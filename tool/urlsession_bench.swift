// URLSession throughput bench for spike #36.
//
// Measures the two URLSession paths the app's iOS downloader could take:
//   --mode default     in-process URLSession(.default) — the fast-foreground
//                      candidate transport
//   --mode background  URLSessionConfiguration.background — the nsurlsessiond
//                      daemon path background_downloader always uses on iOS
//
// Validity caveat: macOS's nsurlsessiond is not iOS's discretionary
// scheduler. This prototypes the mechanism difference (in-process vs
// daemon); the on-device matrix rows are the real evidence.
//
// Usage: swift tool/urlsession_bench.swift <url> [--mode default|background]
//        [--window 45] [--repeat 3]
//
// Emits DOWNLOAD_BENCH lines in the same key=value grammar as
// tool/bench_host_download.dart. rate_mbs is the whole-window average
// (curl convention); steady_mbs excludes the first 5 s of ramp.

import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: swift tool/urlsession_bench.swift <url> [--mode default|background] [--window 45] [--repeat 3]")
    exit(64)
}
let url = URL(string: args[1])!

func flag(_ name: String, default def: String) -> String {
    if let i = args.firstIndex(of: name), i + 1 < args.count { return args[i + 1] }
    return def
}
let mode = flag("--mode", default: "default")
let windowSeconds = Double(flag("--window", default: "45"))!
let repeats = Int(flag("--repeat", default: "3"))!
let rampSeconds = 5.0

final class WindowDelegate: NSObject, URLSessionDownloadDelegate {
    let done = DispatchSemaphore(value: 0)
    var startedAt: Date?
    var bytesTotal: Int64 = 0
    var bytesAtRampEnd: Int64 = -1

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if startedAt == nil { startedAt = Date() }
        bytesTotal = totalBytesWritten
        if bytesAtRampEnd < 0, let start = startedAt,
           Date().timeIntervalSince(start) >= rampSeconds {
            bytesAtRampEnd = totalBytesWritten
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        try? FileManager.default.removeItem(at: location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        done.signal()
    }
}

for round in 0..<repeats {
    let delegate = WindowDelegate()
    let config = mode == "background"
        ? URLSessionConfiguration.background(withIdentifier: "golem-bench-\(round)-\(UUID().uuidString)")
        : URLSessionConfiguration.default
    let session = URLSession(configuration: config, delegate: delegate,
                             delegateQueue: nil)
    let task = session.downloadTask(with: url)
    let ts = ISO8601DateFormatter().string(from: Date())
    let launched = Date()
    task.resume()

    DispatchQueue.global().asyncAfter(deadline: .now() + windowSeconds) {
        task.cancel()
    }
    // Background sessions can defer the first byte well past the window;
    // wait for the cancel to surface, with a hard cap so the CLI never hangs.
    _ = delegate.done.wait(timeout: .now() + windowSeconds * 3)

    let firstByteDelay = delegate.startedAt.map { $0.timeIntervalSince(launched) } ?? -1
    let elapsed = delegate.startedAt.map { min(Date().timeIntervalSince($0), windowSeconds) } ?? windowSeconds
    let rate = Double(delegate.bytesTotal) / elapsed / 1e6
    let steady = delegate.bytesAtRampEnd >= 0 && elapsed > rampSeconds
        ? Double(delegate.bytesTotal - delegate.bytesAtRampEnd) / (elapsed - rampSeconds) / 1e6
        : rate
    print("DOWNLOAD_BENCH client=urlsession-\(mode) round=\(round) " +
          "window_s=\(Int(windowSeconds)) bytes=\(delegate.bytesTotal) " +
          String(format: "rate_mbs=%.2f steady_mbs=%.2f first_byte_s=%.2f ",
                 rate, steady, firstByteDelay) +
          "url_host=\(url.host ?? "?") ts=\(ts)")
    session.invalidateAndCancel()
}
