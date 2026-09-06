import Darwin
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GolemStorage") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.golem/storage",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler(Self.handleStorageCall)
  }

  private static func handleStorageCall(
    _ call: FlutterMethodCall, result: @escaping FlutterResult
  ) {
    if call.method == "physicalMemoryBytes" {
      result(Int(ProcessInfo.processInfo.physicalMemory))
      return
    }
    if call.method == "isVirtualDevice" {
      #if targetEnvironment(simulator)
        result(true)
      #else
        result(false)
      #endif
      return
    }
    // The bench's readings (#58) are the Mac's; a phone says "unknown", the
    // null the Dart contract promises, rather than refusing the call.
    if call.method == "physicalFootprintBytes" || call.method == "deviceProvenance" {
      result(nil)
      return
    }
    if call.method == "availableMemoryBytes" {
      // The jetsam headroom: what this process can still allocate before
      // iOS terminates it. The increased-memory-limit entitlement raises
      // it on supported devices.
      result(Int(os_proc_available_memory()))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      result(FlutterError(code: "bad-args", message: "Expected a path argument", details: nil))
      return
    }
    switch call.method {
    case "freeBytes":
      do {
        let values = try URL(fileURLWithPath: path).resourceValues(
          forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        // nil capacity means "unknown", which must not read as zero free.
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
          result(Int(capacity))
        } else {
          result(nil)
        }
      } catch {
        result(FlutterError(code: "free-bytes", message: error.localizedDescription, details: nil))
      }
    case "totalBytes":
      do {
        let values = try URL(fileURLWithPath: path).resourceValues(
          forKeys: [.volumeTotalCapacityKey]
        )
        if let capacity = values.volumeTotalCapacity {
          result(Int(capacity))
        } else {
          result(nil)
        }
      } catch {
        result(FlutterError(code: "total-bytes", message: error.localizedDescription, details: nil))
      }
    case "excludeFromBackup":
      do {
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "exclude-backup", message: error.localizedDescription, details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
