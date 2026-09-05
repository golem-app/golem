import Darwin
import CoreImage
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXVLM
import Tokenizers

private let infernoMlxABI: UInt32 = 5
private let infernoTimingSemanticsVersion: Int = 2

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
        guard let storage = malloc(bytes.count) else {
            // Allocation failed under memory exhaustion — a dropped
            // terminal event would hang the Dart completer forever, so
            // deliver the event with an empty payload; the Dart side maps
            // a payloadless error to its out-of-memory code.
            callback(operationID, kind, nil, 0, userData)
            return
        }
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

    /// Types a thrown error: the shim's own context-budget error keeps its
    /// dedicated code, and allocation-flavored failures are memory
    /// exhaustion rather than the [fallback] (an OOM reported as "damaged
    /// model" sends users deleting healthy downloads).
    func fail(error: Error, fallback: String) {
        let nsError = error as NSError
        if nsError.domain == "InfernoMLX", nsError.code == 3 {
            fail(code: "context_exhausted", message: nsError.localizedDescription)
            return
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("memory") || text.contains("alloc")
            || text.contains("metal buffer") {
            fail(code: "out_of_memory", message: error.localizedDescription)
            return
        }
        fail(code: fallback, message: error.localizedDescription)
    }
}

private struct GenerationRequest: Decodable, Sendable {
    let prompt: String
    let maxTokens: Int
    let temperature: Float
    let topP: Float
    // Absent-or-null when unset: nil keeps top-k filtering off, leaves the
    // context unbudgeted, and keeps the presence penalty out of the chain,
    // preserving pre-existing behavior.
    let topK: Int?
    let contextLength: Int?
    let presencePenalty: Float?
    let seed: Int64?
    let stopSequences: [String]
    let stopTokenIds: [Int]
}

/// Swift mirror of ABI-3's borrowed `inferno_image_input`.
private struct InfernoImageInput {
    let bytes: UnsafePointer<UInt8>?
    let length: Int
}

private enum VisionAdapter: Sendable {
    case gemma4(Gemma4ProcessorConfiguration)
    case qwen35(Qwen3VLProcessorConfiguration)
}

private final class InfernoMlxEngine: @unchecked Sendable {
    private let condition = NSCondition()
    private var busy = false
    private var operation: Task<Void, Never>?
    private var model: ModelContainer?
    private var visionAdapter: VisionAdapter?

    /// KV-cache bits from the ABI-2 load options (nil = unquantized).
    /// Written by the load worker before the container publishes, read by
    /// generate when building GenerateParameters.
    var kvBits: Int?

    func start(
        _ body: @escaping @Sendable (InfernoMlxEngine) async -> Void
    ) -> Int32 {
        condition.lock()
        // Terminal events are emitted before the operation task finishes
        // unwinding, so a caller reacting to one can arrive while busy is
        // still set. Give the outgoing operation a moment to clear instead
        // of rejecting the follow-on call; only genuinely concurrent use
        // still fails.
        let deadline = Date().addingTimeInterval(2)
        while busy, condition.wait(until: deadline) {}
        guard !busy else {
            condition.unlock()
            return -1
        }
        busy = true
        let task = Task.detached(priority: .userInitiated) { [self] in
            await body(self)
            finishOperation()
        }
        operation = task
        condition.unlock()
        return 0
    }

    private func finishOperation() {
        condition.lock()
        busy = false
        operation = nil
        condition.broadcast()
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        let activeOperation = operation
        condition.unlock()
        activeOperation?.cancel()
    }

    /// Blocks until the current operation task has fully unwound. Task
    /// cancellation is cooperative, so destroy must wait here — the caller
    /// frees the event trampoline right after, and a straggling task would
    /// otherwise call into freed memory.
    func awaitIdle() {
        condition.lock()
        while busy { condition.wait() }
        condition.unlock()
    }

    func container() -> ModelContainer? {
        condition.lock()
        defer { condition.unlock() }
        return model
    }

    func adapter() -> VisionAdapter? {
        condition.lock()
        defer { condition.unlock() }
        return visionAdapter
    }

    func setContainer(
        _ container: ModelContainer?,
        visionAdapter: VisionAdapter? = nil
    ) {
        condition.lock()
        model = container
        self.visionAdapter = visionAdapter
        condition.unlock()
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

private func visionAdapter(at path: String) throws -> VisionAdapter? {
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    let configData = try Data(contentsOf: directory.appendingPathComponent("config.json"))
    guard let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any],
          let modelType = config["model_type"] as? String
    else { return nil }

    let preprocessor = directory.appendingPathComponent("preprocessor_config.json")
    let processor = directory.appendingPathComponent("processor_config.json")
    let processorURL = FileManager.default.fileExists(atPath: preprocessor.path)
        ? preprocessor : processor
    guard FileManager.default.fileExists(atPath: processorURL.path) else { return nil }
    let processorData = try Data(contentsOf: processorURL)
    switch modelType {
    case "gemma4":
        return .gemma4(try JSONDecoder().decode(
            Gemma4ProcessorConfiguration.self,
            from: processorData
        ))
    case "qwen3_5":
        return .qwen35(try JSONDecoder().decode(
            Qwen3VLProcessorConfiguration.self,
            from: processorData
        ))
    default:
        return nil
    }
}

private let mediaMarker = "<__media__>"

private func markerCount(in prompt: String) -> Int {
    prompt.components(separatedBy: mediaMarker).count - 1
}

private func tokenRanges(of needle: [Int], in haystack: [Int]) -> [Range<Int>] {
    guard !needle.isEmpty, needle.count <= haystack.count else { return [] }
    var ranges: [Range<Int>] = []
    var start = 0
    while start <= haystack.count - needle.count {
        let end = start + needle.count
        if haystack[start ..< end].elementsEqual(needle) {
            ranges.append(start ..< end)
            start = end
        } else {
            start += 1
        }
    }
    return ranges
}

private func replaceQwenPaddingTokens(
    in promptTokens: [Int],
    frames: [THW],
    mergeSize: Int,
    tokenizer: any MLXLMCommon.Tokenizer
) throws -> [Int] {
    let placeholder = tokenizer.encode(
        text: "<|vision_start|><|image_pad|><|vision_end|>",
        addSpecialTokens: false
    )
    let ranges = tokenRanges(of: placeholder, in: promptTokens)
    guard ranges.count == frames.count else {
        throw NSError(
            domain: "InfernoMLX",
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The rendered prompt's image markers do not match its images."
            ]
        )
    }
    let mergeLength = mergeSize * mergeSize
    let replacements = frames.map { frame in
        tokenizer.encode(
            text: "<|vision_start|>"
                + String(repeating: "<|image_pad|>", count: frame.product / mergeLength)
                + "<|vision_end|>",
            addSpecialTokens: false
        )
    }
    var result: [Int] = []
    var current = 0
    for (range, replacement) in zip(ranges, replacements) {
        result.append(contentsOf: promptTokens[current ..< range.lowerBound])
        result.append(contentsOf: replacement)
        current = range.upperBound
    }
    result.append(contentsOf: promptTokens[current...])
    return result
}

private func preparedInput(
    prompt: String,
    imageData: [Data],
    adapter: VisionAdapter?,
    context: ModelContext
) throws -> (LMInput, [Int]) {
    guard markerCount(in: prompt) == imageData.count else {
        throw NSError(
            domain: "InfernoMLX",
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The rendered prompt's image markers do not match its images."
            ]
        )
    }
    guard !imageData.isEmpty else {
        let tokens = context.tokenizer.encode(text: prompt, addSpecialTokens: false)
        if adapter == nil {
            return (LMInput(tokens: MLXArray(tokens)), tokens)
        }
        let array = MLXArray(tokens).expandedDimensions(axis: 0)
        return (
            LMInput(text: .init(tokens: array, mask: ones(like: array).asType(.int8))),
            tokens
        )
    }
    guard let adapter else {
        throw NSError(
            domain: "InfernoMLX",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "This MLX model has no image processor."]
        )
    }
    // Image decode and preprocessing are the one long stretch of CPU work
    // before the library's prefill, and the library polls nothing until its
    // first token — so a cancel, or a teardown waiting on it, is honoured at
    // every image boundary here rather than after the whole batch (#154).
    let images = try imageData.map { data -> CIImage in
        try Task.checkCancellation()
        guard let image = CIImage(data: data), !image.extent.isEmpty else {
            throw NSError(
                domain: "InfernoMLX",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "An attached image could not be decoded."]
            )
        }
        return image
    }

    let promptTokens: [Int]
    let processedImage: LMInput.ProcessedImage
    switch adapter {
    case .gemma4(let config):
        guard let processor = context.processor as? Gemma4Processor else {
            throw NSError(
                domain: "InfernoMLX",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The Gemma image processor is unavailable."]
            )
        }
        let prepared = try images.map {
            try Task.checkCancellation()
            return try processor.preprocess(image: $0, processing: nil)
        }
        let frames = prepared.map { $0.1 }
        let maxHeight = frames.map(\.h).max() ?? 0
        let maxWidth = frames.map(\.w).max() ?? 0
        let paddedPixels = prepared.map { pixels, frame in
            frame.h == maxHeight && frame.w == maxWidth
                ? pixels
                : MLX.padded(
                    pixels,
                    widths: [
                        0, 0,
                        .init((0, maxHeight - frame.h)),
                        .init((0, maxWidth - frame.w)),
                    ]
                )
        }
        processedImage = .init(
            pixels: concatenated(paddedPixels),
            frames: frames
        )
        var tokens = context.tokenizer.encode(
            text: prompt.replacingOccurrences(of: mediaMarker, with: "<|image|>"),
            addSpecialTokens: false
        )
        guard tokens.filter({ $0 == config.imageTokenId }).count == images.count else {
            throw NSError(
                domain: "InfernoMLX",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The Gemma image tokens do not match the attached images."
                ]
            )
        }
        var expanded: [Int] = []
        var imageIndex = 0
        for token in tokens {
            guard token == config.imageTokenId else {
                expanded.append(token)
                continue
            }
            expanded.append(config.boiTokenId)
            expanded.append(contentsOf: Array(
                repeating: config.imageTokenId,
                count: config.softTokenCount(
                    height: frames[imageIndex].h,
                    width: frames[imageIndex].w
                )
            ))
            if let eoiTokenId = config.eoiTokenId {
                expanded.append(eoiTokenId)
            }
            imageIndex += 1
        }
        tokens = expanded
        promptTokens = tokens
    case .qwen35(let config):
        guard let processor = context.processor as? Qwen3VLProcessor else {
            throw NSError(
                domain: "InfernoMLX",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The Qwen image processor is unavailable."]
            )
        }
        // A one-megapixel Qwen frame is correct but pushes the 4B path past
        // iOS's foreground memory budget during vision prefill. 512² keeps
        // the documented aspect-preserving processor path while bounding
        // visual activations; the app's one-megapixel intake cap remains the
        // broader cross-engine decode boundary.
        let processing = UserInput.Processing(maxPixels: 262_144)
        let prepared = try images.map {
            try Task.checkCancellation()
            return try processor.preprocess(images: [$0], processing: processing)
        }
        let frames = prepared.map { $0.1 }
        processedImage = .init(
            pixels: concatenated(prepared.map { $0.0 }),
            frames: frames
        )
        let tokens = context.tokenizer.encode(
            text: prompt.replacingOccurrences(
                of: mediaMarker,
                with: "<|vision_start|><|image_pad|><|vision_end|>"
            ),
            addSpecialTokens: false
        )
        promptTokens = try replaceQwenPaddingTokens(
            in: tokens,
            frames: frames,
            mergeSize: config.mergeSize,
            tokenizer: context.tokenizer
        )
    }
    let promptArray = MLXArray(promptTokens).expandedDimensions(axis: 0)
    let mask = ones(like: promptArray).asType(.int8)
    return (
        LMInput(text: .init(tokens: promptArray, mask: mask), image: processedImage),
        promptTokens
    )
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

private func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
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
            "detail": "MLX Swift LM 3.31.4+31.g60bd0d78 / MLX Swift 0.31.6",
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
    // ABI 2: one JSON payload carries the path and the load options.
    // llama-only fields (checkTensors, threadCount, gpuLayers, swaFull)
    // are ignored here; kvCacheType q8_0 maps to an 8-bit quantized KV
    // cache at generate time.
    let encoded = String(cString: modelPath)
    let path: String
    if let data = encoded.data(using: .utf8),
       let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let modelPathValue = request["modelPath"] as? String {
        path = modelPathValue
        engine.kvBits = (request["kvCacheType"] as? String) == "q8_0" ? 8 : nil
    } else {
        return -1
    }
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
            let adapter = try visionAdapter(at: path)
            // The container load itself cannot be interrupted — the library
            // polls nothing while mapping weights — so the poll before it is
            // the last chance to honour a cancel that arrived during the
            // adapter read, and the one after it the first chance afterwards.
            try Task.checkCancellation()
            let modelURL = URL(fileURLWithPath: path, isDirectory: true)
            let container = if adapter == nil {
                try await LLMModelFactory.shared.loadContainer(
                    from: modelURL,
                    using: #huggingFaceTokenizerLoader()
                )
            } else {
                try await VLMModelFactory.shared.loadContainer(
                    from: modelURL,
                    using: #huggingFaceTokenizerLoader()
                )
            }
            if Task.isCancelled {
                sink.fail(code: "cancelled", message: "Model loading was cancelled.")
                return
            }
            engine.setContainer(container, visionAdapter: adapter)
            sink.emit(EventKind.operationCompleted)
        } catch is CancellationError {
            sink.fail(code: "cancelled", message: "Model loading was cancelled.")
        } catch {
            sink.fail(error: error, fallback: "incompatible_model")
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
    _ images: UnsafeRawPointer?,
    _ imageCount: Int,
    _ operationID: UInt64,
    _ callback: InfernoMlxEventCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let engine = engine(from: rawEngine),
          let container = engine.container(),
          let requestJSON,
          let callback
    else { return -1 }
    // Timing semantics 2: accepted here, so the buffer copy, JSON decoding,
    // the bounded wait for a retiring operation, tokenization and prefill
    // are all inside the interval the caller waited through.
    let requestStart = ContinuousClock.now
    let encoded = Data(String(cString: requestJSON).utf8)
    let sink = EventSink(
        operationID: operationID,
        callback: callback,
        userData: userData
    )
    guard imageCount == 0 || images != nil else { return -1 }
    // ABI-3 buffers are borrowed only for this call; copy them before the
    // detached generation task starts.
    let imageData: [Data]
    if imageCount == 0 {
        imageData = []
    } else {
        let inputs = images!.assumingMemoryBound(to: InfernoImageInput.self)
        var copied: [Data] = []
        copied.reserveCapacity(imageCount)
        for index in 0 ..< imageCount {
            let input = inputs[index]
            guard let bytes = input.bytes, input.length > 0 else { return -1 }
            copied.append(Data(bytes: bytes, count: input.length))
        }
        imageData = copied
    }
    let request: GenerationRequest
    do {
        request = try JSONDecoder().decode(GenerationRequest.self, from: encoded)
        // Zero matches the llama shim: top-k filtering off, context
        // unbudgeted. Only negatives are invalid.
        guard !request.prompt.isEmpty,
              request.maxTokens > 0,
              request.temperature >= 0,
              request.topP > 0,
              request.topP <= 1,
              request.topK ?? 0 >= 0,
              request.contextLength ?? 0 >= 0,
              request.presencePenalty ?? 0 >= 0
        else {
            sink.fail(code: "generation_failed", message: "The generation request is invalid.")
            return 0
        }
    } catch {
        sink.fail(code: "generation_failed", message: error.localizedDescription)
        return 0
    }

    let adapter = engine.adapter()
    return engine.start { engine in
        do {
            try await container.perform(values: request) { context, request in
                let (input, promptTokenIDs) = try preparedInput(
                    prompt: request.prompt,
                    imageData: imageData,
                    adapter: adapter,
                    context: context
                )
                guard !promptTokenIDs.isEmpty else {
                    throw NSError(
                        domain: "InfernoMLX",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The rendered prompt could not be tokenized."]
                    )
                }
                // The tokenizer defines BOS; the shim must stay model-blind.
                // Tokenizers without a BOS token skip the guard entirely.
                if promptTokenIDs.count > 1,
                   let bosToken = context.tokenizer.bosToken,
                   let bosTokenID = context.tokenizer.convertTokenToId(bosToken),
                   promptTokenIDs[0] == bosTokenID,
                   promptTokenIDs[1] == bosTokenID {
                    throw NSError(
                        domain: "InfernoMLX",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "The rendered prompt contains a duplicated BOS token."]
                    )
                }

                // MLX has no trained-context cap of its own — the KV cache
                // grows unbounded — so the caller's context budget is the
                // only bound, checked post-tokenization to fail exactly like
                // the llama shim's pre-allocation check.
                if let contextBudget = request.contextLength,
                   contextBudget > 0,
                   promptTokenIDs.count + request.maxTokens > contextBudget {
                    throw NSError(
                        domain: "InfernoMLX",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "The rendered prompt and max tokens exceed the context budget."
                        ]
                    )
                }

                // The library's prefill polls nothing until its first token;
                // a cancel that arrived during preparation ends here, the way
                // the llama shim's batch loop ends before its next batch.
                try Task.checkCancellation()

                var parameters = GenerateParameters(
                    maxTokens: request.maxTokens,
                    temperature: request.temperature,
                    topP: request.topP,
                    // 0 keeps the library's top-k filter disabled.
                    topK: request.topK ?? 0,
                    presencePenalty: request.presencePenalty,
                    // The library defaults to a 20-token window, which a
                    // budget-length think loop never notices; the penalty
                    // exists to break exactly that loop, so it watches the
                    // whole generation.
                    presenceContextSize: request.maxTokens,
                    seed: request.seed.map { UInt64(bitPattern: $0) }
                )
                // ABI-2 load option: an 8-bit quantized KV cache roughly
                // quarters cache memory versus fp16 on long generations.
                parameters.kvBits = engine.kvBits
                var generationContext = context
                generationContext.configuration.eosTokenIds = Set(request.stopTokenIds)
                generationContext.configuration.stopStrings = []
                // generate() is not lazy: TokenIterator's init runs the
                // prefill windows synchronously, so the library's promptTime
                // is measured from here.
                let generateCallStart = ContinuousClock.now
                // The token-task path miscomputes Gemma 4 per-layer inputs
                // during prefill; this overload is the streaming path proven
                // on device against the pinned artifact. Requested stop-token
                // IDs are enforced by the library via the per-request context
                // copy.
                let stream = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: generationContext
                )

                var firstTokenAt: ContinuousClock.Instant?
                // The summary's arrival: the library yields it right after
                // measuring generateTime and before synchronising its GPU
                // stream, so it anchors both ends of the generation window.
                var summaryAt: ContinuousClock.Instant?
                var peakFootprint = physicalFootprintBytes()
                var generatedChunkCount = 0
                var pending: [UInt8] = []
                let stopBytes = request.stopSequences.map { Array($0.utf8) }
                let requestedStopIDs = Set(request.stopTokenIds)
                var stopReason = "max_tokens"
                var completion: GenerateCompletionInfo?

                for await event in stream {
                    if Task.isCancelled {
                        stopReason = "cancelled"
                        break
                    }
                    switch event {
                    case .chunk(let text):
                        if firstTokenAt == nil { firstTokenAt = .now }
                        generatedChunkCount += 1
                        peakFootprint = max(peakFootprint, physicalFootprintBytes())
                        if emitVisibleBytes(
                            pending: &pending,
                            piece: Array(text.utf8),
                            stops: stopBytes,
                            sink: sink
                        ) {
                            stopReason = "stop_sequence"
                            break
                        }
                    case .info(let info):
                        summaryAt = .now
                        completion = info
                        switch info.stopReason {
                        case .cancelled:
                            stopReason = "cancelled"
                        case .length:
                            stopReason = "max_tokens"
                        case .stop:
                            // The library cannot distinguish the model's own
                            // EOS from a requested stop-token ID; report the
                            // requested kind when the caller supplied IDs.
                            if stopReason == "max_tokens" {
                                stopReason = requestedStopIDs.isEmpty
                                    ? "end_of_sequence" : "stop_token"
                            }
                        }
                    case .toolCall:
                        break
                    }
                    if stopReason == "stop_sequence" || stopReason == "cancelled" {
                        break
                    }
                }
                // A normal completion ends at the summary, which excludes the
                // library's stream teardown; a cancel or a stop sequence ends
                // where the loop was left.
                let generationEnd = summaryAt ?? .now
                if !pending.isEmpty && stopReason != "stop_sequence" {
                    sink.emit(EventKind.textDelta, bytes: pending)
                }
                if Task.isCancelled { stopReason = "cancelled" }

                let elapsedSeconds = seconds(requestStart.duration(to: generationEnd))
                // When the loop broke early the library never summarised;
                // the interval to the first chunk measures the same window
                // its promptTime does (prefill plus the first-token step).
                let promptSeconds = completion?.promptTime
                    ?? firstTokenAt.map { seconds(generateCallStart.duration(to: $0)) }
                    ?? 0
                let generatedCount = completion?.generationTokenCount
                    ?? generatedChunkCount
                // Two measurements of one instant; the earlier wins. The
                // summary's arrival less the library's generateTime lands on
                // the instant the first token was returned — everything
                // before it, iterator setup and task dispatch included, is
                // inside — and does not see the streaming detokenizer hold a
                // token that ends mid-UTF-8, nor the tool-call scanner buffer
                // a reply from its first "{". The wall clock to the first
                // chunk is what remains when the summary never arrives.
                // Clamped because generateTime is the library's wall clock.
                var firstTokenCandidates: [Double] = []
                if let firstTokenAt {
                    firstTokenCandidates.append(seconds(requestStart.duration(to: firstTokenAt)))
                }
                if let completion, let summaryAt, completion.generationTokenCount > 0 {
                    firstTokenCandidates.append(
                        seconds(requestStart.duration(to: summaryAt)) - completion.generateTime
                    )
                }
                let firstTokenSeconds = firstTokenCandidates.min()
                    .map { min(max($0, 0), elapsedSeconds) }
                // One library step per generated token sits in this window,
                // the last being the step that ended the reply.
                let decodeSeconds = firstTokenSeconds.map { elapsedSeconds - $0 } ?? 0
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
                    "timingSemanticsVersion": infernoTimingSemanticsVersion,
                ])
                sink.emit(EventKind.completed, text: stopReason)
                sink.emit(EventKind.operationCompleted)
            }
        } catch is CancellationError {
            // Cancelled before the library produced anything: no token means
            // no first-token time and no decode window, but the request still
            // cost the caller the time it took to get here. The prompt token
            // count is unknown — the cancel can land before tokenization — so
            // it is null rather than a zero that reads like a measurement.
            sink.emitJSON(EventKind.metrics, [
                "decodeTokensPerSecond": 0,
                "promptTokensPerSecond": 0,
                "generatedTokenCount": 0,
                "elapsedSeconds": seconds(requestStart.duration(to: .now)),
                "promptTokenCount": NSNull(),
                "timeToFirstTokenSeconds": NSNull(),
                "peakPhysicalFootprintBytes": physicalFootprintBytes(),
                "timingSemanticsVersion": infernoTimingSemanticsVersion,
            ])
            sink.emit(EventKind.completed, text: "cancelled")
            sink.emit(EventKind.operationCompleted)
        } catch {
            sink.fail(error: error, fallback: "generation_failed")
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
    let engine = retained.takeUnretainedValue()
    engine.cancel()
    engine.awaitIdle()
    retained.release()
}

@_cdecl("inferno_mlx_string_free")
public func infernoMlxStringFree(_ value: UnsafePointer<CChar>?) {
    guard let value else { return }
    free(UnsafeMutableRawPointer(mutating: value))
}
