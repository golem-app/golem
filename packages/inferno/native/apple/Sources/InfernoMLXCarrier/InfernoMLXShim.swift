import Darwin
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

private let infernoMlxABI: UInt32 = 1

private enum EventKind {
    static let textDelta: Int32 = 1
    static let metrics: Int32 = 2
    static let completed: Int32 = 3
    static let error: Int32 = 4
    static let operationCompleted: Int32 = 5
    static let tokenIDs: Int32 = 6
}

public typealias InfernoMlxEventCallback = @convention(c) (
    UInt64,
    Int32,
    UnsafePointer<UInt8>?,
    Int,
    UnsafeMutableRawPointer?
) -> Void

private struct EventSink: @unchecked Sendable {
    let operationID: UInt64
    let callback: InfernoMlxEventCallback
    let userData: UnsafeMutableRawPointer?

    func emit(_ kind: Int32, bytes: [UInt8] = []) {
        guard !bytes.isEmpty else {
            callback(operationID, kind, nil, 0, userData)
            return
        }
        guard let storage = malloc(bytes.count) else { return }
        _ = bytes.withUnsafeBytes { source in
            memcpy(storage, source.baseAddress, bytes.count)
        }
        callback(
            operationID,
            kind,
            UnsafePointer(storage.assumingMemoryBound(to: UInt8.self)),
            bytes.count,
            userData
        )
    }

    func emit(_ kind: Int32, text: String) {
        emit(kind, bytes: Array(text.utf8))
    }

    func emitJSON(_ kind: Int32, _ object: Any) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        emit(kind, bytes: Array(data))
    }

    func fail(code: String, message: String) {
        emitJSON(EventKind.error, ["code": code, "message": message])
    }
}

private struct GenerationRequest: Decodable, Sendable {
    let prompt: String
    let maxTokens: Int
    let temperature: Float
    let topP: Float
    let seed: Int64?
    let stopSequences: [String]
    let stopTokenIds: [Int]
}

private final class InfernoMlxEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var operation: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var model: ModelContainer?

    func start(
        _ body: @escaping @Sendable (InfernoMlxEngine) async -> Void
    ) -> Int32 {
        lock.lock()
        guard !busy else {
            lock.unlock()
            return -1
        }
        busy = true
        let task = Task.detached(priority: .userInitiated) { [self] in
            await body(self)
            finishOperation()
        }
        operation = task
        lock.unlock()
        return 0
    }

    private func finishOperation() {
        lock.lock()
        busy = false
        operation = nil
        generationTask = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let activeOperation = operation
        let activeGeneration = generationTask
        lock.unlock()
        activeGeneration?.cancel()
        activeOperation?.cancel()
    }

    func setGenerationTask(_ task: Task<Void, Never>?) {
        lock.lock()
        generationTask = task
        lock.unlock()
    }

    func container() -> ModelContainer? {
        lock.lock()
        defer { lock.unlock() }
        return model
    }

    func setContainer(_ container: ModelContainer?) {
        lock.lock()
        model = container
        lock.unlock()
    }
}

private func engine(
    from pointer: UnsafeMutableRawPointer?
) -> InfernoMlxEngine? {
    guard let pointer else { return nil }
    return Unmanaged<InfernoMlxEngine>
        .fromOpaque(pointer)
        .takeUnretainedValue()
}

private func modelDirectoryError(_ path: String) -> (String, String)? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
        atPath: path,
        isDirectory: &isDirectory
    ) else {
        return ("invalid_model_path", "The MLX model directory does not exist.")
    }
    guard isDirectory.boolValue else {
        return ("invalid_model_path", "The MLX model path is not a directory.")
    }
    // Text-only v0: the pinned MLX artifact deliberately ships without vision
    // or audio processor files, so only the text-side inputs are required.
    for file in ["config.json", "tokenizer.json"] {
        guard FileManager.default.fileExists(atPath: "\(path)/\(file)") else {
            return ("corrupt_model", "The MLX model directory is missing \(file).")
        }
    }
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    guard contents.contains(where: { $0.hasSuffix(".safetensors") }) else {
        return ("corrupt_model", "The MLX model directory has no safetensors weights.")
    }
    return nil
}

private func physicalFootprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(
            to: integer_t.self,
            capacity: Int(count)
        ) { rebound in
            task_info(
                mach_task_self_,
                task_flavor_t(TASK_VM_INFO),
                rebound,
                &count
            )
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
}

private func firstStopRange(
    in bytes: [UInt8],
    stops: [[UInt8]]
) -> Range<Int>? {
    var earliest: Range<Int>?
    for stop in stops where !stop.isEmpty && stop.count <= bytes.count {
        for start in 0 ... bytes.count - stop.count
        where bytes[start ..< start + stop.count].elementsEqual(stop) {
            let candidate = start ..< start + stop.count
            if earliest == nil || candidate.lowerBound < earliest!.lowerBound {
                earliest = candidate
            }
            break
        }
    }
    return earliest
}

private func heldStopPrefix(_ bytes: [UInt8], stops: [[UInt8]]) -> Int {
    var held = 0
    for stop in stops where stop.count > 1 {
        let maximum = min(bytes.count, stop.count - 1)
        guard maximum > held else { continue }
        for length in stride(from: maximum, through: held + 1, by: -1)
        where bytes.suffix(length).elementsEqual(stop.prefix(length)) {
            held = length
            break
        }
    }
    return held
}

private func emitVisibleBytes(
    pending: inout [UInt8],
    piece: [UInt8],
    stops: [[UInt8]],
    sink: EventSink
) -> Bool {
    pending.append(contentsOf: piece)
    if let range = firstStopRange(in: pending, stops: stops) {
        if range.lowerBound > 0 {
            sink.emit(EventKind.textDelta, bytes: Array(pending[..<range.lowerBound]))
        }
        pending.removeAll(keepingCapacity: false)
        return true
    }
    let held = heldStopPrefix(pending, stops: stops)
    let visibleCount = pending.count - held
    if visibleCount > 0 {
        sink.emit(EventKind.textDelta, bytes: Array(pending[..<visibleCount]))
        pending.removeFirst(visibleCount)
    }
    return false
}

@_cdecl("inferno_mlx_abi_version")
public func infernoMlxABIVersion() -> UInt32 {
    infernoMlxABI
}

@_cdecl("inferno_mlx_probe_json")
public func infernoMlxProbeJSON() -> UnsafePointer<CChar>? {
    let payload: [String: Any] = [
        "operatingSystem": "apple",
        "engines": [[
            "name": "mlx",
            "available": true,
            "detail": "MLX Swift LM 3.31.4 / MLX Swift 0.31.6",
        ]],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let string = String(data: data, encoding: .utf8),
          let copy = strdup(string)
    else { return nil }
    return UnsafePointer(copy)
}

@_cdecl("inferno_mlx_engine_create")
public func infernoMlxEngineCreate(
    _ engineName: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let engineName, String(cString: engineName) == "mlx" else {
        return nil
    }
    return Unmanaged.passRetained(InfernoMlxEngine()).toOpaque()
}

@_cdecl("inferno_mlx_engine_load")
public func infernoMlxEngineLoad(
    _ rawEngine: UnsafeMutableRawPointer?,
    _ modelPath: UnsafePointer<CChar>?,
    _ operationID: UInt64,
    _ callback: InfernoMlxEventCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let engine = engine(from: rawEngine),
          let modelPath,
          let callback,
          engine.container() == nil
    else { return -1 }
    let path = String(cString: modelPath)
    let sink = EventSink(
        operationID: operationID,
        callback: callback,
        userData: userData
    )
    return engine.start { engine in
        if let (code, message) = modelDirectoryError(path) {
            sink.fail(code: code, message: message)
            return
        }
        do {
            MLX.Memory.cacheLimit = 64 * 1024 * 1024
            let container = try await VLMModelFactory.shared.loadContainer(
                from: URL(fileURLWithPath: path, isDirectory: true),
                using: #huggingFaceTokenizerLoader()
            )
            if Task.isCancelled {
                sink.fail(code: "cancelled", message: "Model loading was cancelled.")
                return
            }
            engine.setContainer(container)
            sink.emit(EventKind.operationCompleted)
        } catch {
            sink.fail(code: "incompatible_model", message: error.localizedDescription)
        }
    }
}

@_cdecl("inferno_mlx_engine_tokenize")
public func infernoMlxEngineTokenize(
    _ rawEngine: UnsafeMutableRawPointer?,
    _ prompt: UnsafePointer<CChar>?,
    _ operationID: UInt64,
    _ callback: InfernoMlxEventCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let engine = engine(from: rawEngine),
          let container = engine.container(),
          let prompt,
          let callback
    else { return -1 }
    let text = String(cString: prompt)
    let sink = EventSink(
        operationID: operationID,
        callback: callback,
        userData: userData
    )
    return engine.start { _ in
        let tokenIDs = await container.perform { context in
            context.tokenizer.encode(text: text, addSpecialTokens: false)
        }
        sink.emitJSON(EventKind.tokenIDs, tokenIDs)
        sink.emit(EventKind.operationCompleted)
    }
}

@_cdecl("inferno_mlx_engine_generate")
public func infernoMlxEngineGenerate(
    _ rawEngine: UnsafeMutableRawPointer?,
    _ requestJSON: UnsafePointer<CChar>?,
    _ operationID: UInt64,
    _ callback: InfernoMlxEventCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let engine = engine(from: rawEngine),
          let container = engine.container(),
          let requestJSON,
          let callback
    else { return -1 }
    let encoded = Data(String(cString: requestJSON).utf8)
    let sink = EventSink(
        operationID: operationID,
        callback: callback,
        userData: userData
    )
    let request: GenerationRequest
    do {
        request = try JSONDecoder().decode(GenerationRequest.self, from: encoded)
        guard !request.prompt.isEmpty,
              request.maxTokens > 0,
              request.temperature >= 0,
              request.topP > 0,
              request.topP <= 1
        else {
            sink.fail(code: "generation_failed", message: "The generation request is invalid.")
            return 0
        }
    } catch {
        sink.fail(code: "generation_failed", message: error.localizedDescription)
        return 0
    }

    return engine.start { engine in
        do {
            try await container.perform(values: request) { context, request in
                let promptTokenIDs = context.tokenizer.encode(
                    text: request.prompt,
                    addSpecialTokens: false
                )
                guard !promptTokenIDs.isEmpty else {
                    throw NSError(
                        domain: "InfernoMLX",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The rendered prompt could not be tokenized."]
                    )
                }
                if promptTokenIDs.count > 1,
                   promptTokenIDs[0] == 2,
                   promptTokenIDs[1] == 2 {
                    throw NSError(
                        domain: "InfernoMLX",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "The rendered prompt contains a duplicated BOS token."]
                    )
                }

                let input = LMInput(
                    tokens: MLXArray(promptTokenIDs).expandedDimensions(axis: 0)
                )
                let parameters = GenerateParameters(
                    maxTokens: request.maxTokens,
                    temperature: request.temperature,
                    topP: request.topP,
                    seed: request.seed.map { UInt64(bitPattern: $0) }
                )
                var generationContext = context
                generationContext.configuration.eosTokenIds = Set(request.stopTokenIds)
                generationContext.configuration.stopStrings = []
                let (stream, task) = try generateTokensTask(
                    input: input,
                    parameters: parameters,
                    context: generationContext,
                    includeStopToken: true
                )
                engine.setGenerationTask(task)

                let started = ContinuousClock.now
                var firstTokenAt: ContinuousClock.Instant?
                var peakFootprint = physicalFootprintBytes()
                var generatedTokenIDs: [Int] = []
                var previousDecoded = ""
                var pending: [UInt8] = []
                let stopBytes = request.stopSequences.map { Array($0.utf8) }
                let requestedStopIDs = Set(request.stopTokenIds)
                var stopReason = "max_tokens"
                var completion: GenerateCompletionInfo?

                for await event in stream {
                    if Task.isCancelled {
                        stopReason = "cancelled"
                        task.cancel()
                        break
                    }
                    switch event {
                    case .token(let token):
                        if requestedStopIDs.contains(token) {
                            stopReason = "stop_token"
                            task.cancel()
                            break
                        }
                        generatedTokenIDs.append(token)
                        if firstTokenAt == nil { firstTokenAt = .now }
                        let decoded = context.tokenizer.decode(tokenIds: generatedTokenIDs)
                        let piece: String
                        if decoded.hasPrefix(previousDecoded) {
                            piece = String(decoded.dropFirst(previousDecoded.count))
                        } else {
                            piece = context.tokenizer.decode(tokenIds: [token])
                        }
                        previousDecoded = decoded
                        peakFootprint = max(peakFootprint, physicalFootprintBytes())
                        if emitVisibleBytes(
                            pending: &pending,
                            piece: Array(piece.utf8),
                            stops: stopBytes,
                            sink: sink
                        ) {
                            stopReason = "stop_sequence"
                            task.cancel()
                            break
                        }
                    case .info(let info):
                        completion = info
                        switch info.stopReason {
                        case .cancelled:
                            stopReason = "cancelled"
                        case .length:
                            stopReason = "max_tokens"
                        case .stop:
                            if stopReason == "max_tokens" {
                                stopReason = "end_of_sequence"
                            }
                        }
                    }
                    if stopReason == "stop_token" || stopReason == "stop_sequence" {
                        break
                    }
                }
                await task.value
                if !pending.isEmpty && stopReason != "stop_sequence" {
                    sink.emit(EventKind.textDelta, bytes: pending)
                }
                if Task.isCancelled { stopReason = "cancelled" }

                let elapsed = started.duration(to: .now).components
                let elapsedSeconds = Double(elapsed.seconds)
                    + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
                let promptSeconds = completion?.promptTime ?? 0
                let decodeSeconds = completion?.generateTime ?? 0
                let generatedCount = completion?.generationTokenCount
                    ?? generatedTokenIDs.count
                let firstTokenSeconds: Double? = firstTokenAt.map { first in
                    let duration = started.duration(to: first).components
                    return Double(duration.seconds)
                        + Double(duration.attoseconds) / 1_000_000_000_000_000_000
                }
                sink.emitJSON(EventKind.metrics, [
                    "decodeTokensPerSecond": decodeSeconds > 0
                        ? Double(generatedCount) / decodeSeconds : 0,
                    "promptTokensPerSecond": promptSeconds > 0
                        ? Double(promptTokenIDs.count) / promptSeconds : 0,
                    "generatedTokenCount": generatedCount,
                    "elapsedSeconds": elapsedSeconds,
                    "promptTokenCount": promptTokenIDs.count,
                    "timeToFirstTokenSeconds": firstTokenSeconds.map { $0 as Any } ?? NSNull(),
                    "peakPhysicalFootprintBytes": peakFootprint,
                ])
                sink.emit(EventKind.completed, text: stopReason)
                sink.emit(EventKind.operationCompleted)
            }
        } catch {
            sink.fail(code: "generation_failed", message: error.localizedDescription)
        }
    }
}

@_cdecl("inferno_mlx_engine_cancel")
public func infernoMlxEngineCancel(
    _ rawEngine: UnsafeMutableRawPointer?
) -> Int32 {
    guard let engine = engine(from: rawEngine) else { return -1 }
    engine.cancel()
    return 0
}

@_cdecl("inferno_mlx_engine_unload")
public func infernoMlxEngineUnload(
    _ rawEngine: UnsafeMutableRawPointer?,
    _ operationID: UInt64,
    _ callback: InfernoMlxEventCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let engine = engine(from: rawEngine), let callback else { return -1 }
    let sink = EventSink(
        operationID: operationID,
        callback: callback,
        userData: userData
    )
    return engine.start { engine in
        engine.setContainer(nil)
        MLX.Memory.clearCache()
        sink.emit(EventKind.operationCompleted)
    }
}

@_cdecl("inferno_mlx_engine_destroy")
public func infernoMlxEngineDestroy(
    _ rawEngine: UnsafeMutableRawPointer?
) {
    guard let rawEngine else { return }
    let retained = Unmanaged<InfernoMlxEngine>.fromOpaque(rawEngine)
    retained.takeUnretainedValue().cancel()
    retained.release()
}

@_cdecl("inferno_mlx_string_free")
public func infernoMlxStringFree(_ value: UnsafePointer<CChar>?) {
    guard let value else { return }
    free(UnsafeMutableRawPointer(mutating: value))
}
