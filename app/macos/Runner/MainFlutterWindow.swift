import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// The two shapes this window opens in, chosen by the `GolemWindowProfile`
  /// Info.plist key that each build configuration fills from
  /// `GOLEM_WINDOW_PROFILE` (ADR 0021). The consumer flavors open at the iPad
  /// Pro 11" logical portrait viewport, because their first job on a Mac is
  /// previewing tablet-proportioned layout without an iPad. The lab opens
  /// landscape at the size its bench was designed for. Both are clamped to
  /// the screen's visible frame (preserving the aspect ratio) so the window
  /// never opens taller than the display, and each remembers its own frame.
  private struct WindowProfile {
    let defaultContentSize: NSSize
    let minimumContentSize: NSSize
    let frameAutosaveKey: String

    static let tablet = WindowProfile(
      defaultContentSize: NSSize(width: 834, height: 1194),
      minimumContentSize: NSSize(width: 480, height: 640),
      frameAutosaveKey: "GolemMainWindow"
    )
    static let desktop = WindowProfile(
      defaultContentSize: NSSize(width: 1440, height: 900),
      minimumContentSize: NSSize(width: 1000, height: 640),
      frameAutosaveKey: "GolemLabWindow"
    )

    /// An absent or unrecognised key is the consumer window: a flavorless
    /// build carries qa's identity and must carry qa's window too.
    static var current: WindowProfile {
      let profile = Bundle.main.object(forInfoDictionaryKey: "GolemWindowProfile") as? String
      return profile == "desktop" ? .desktop : .tablet
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let displayName = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleDisplayName"
    ) as? String
    self.title = displayName?.isEmpty == false ? displayName! : "Golem"
    let profile = WindowProfile.current
    self.contentMinSize = Self.clampedMinimumContentSize(
      of: profile, for: self.screen ?? NSScreen.main
    )

    // Restore the user's last frame when one was saved; otherwise open at
    // the profile's default. setFrameUsingName returns false on first run.
    // The window has no screen before it is ordered front, so fall back to
    // the main screen — otherwise the clamp silently no-ops on small
    // displays, which is exactly what it exists to prevent.
    if !self.setFrameUsingName(profile.frameAutosaveKey) {
      self.setContentSize(
        Self.clampedDefaultContentSize(
          of: profile, for: self.screen ?? NSScreen.main
        )
      )
      self.center()
    }
    self.setFrameAutosaveName(profile.frameAutosaveKey)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let storageChannel = FlutterMethodChannel(
      name: "app.golem/storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    storageChannel.setMethodCallHandler(Self.handleStorageCall)

    super.awakeFromNib()
  }

  private static func handleStorageCall(
    _ call: FlutterMethodCall, result: @escaping FlutterResult
  ) {
    if call.method == "physicalMemoryBytes" {
      result(Int(ProcessInfo.processInfo.physicalMemory))
      return
    }
    // macOS has no simulator: this build always runs on the metal it names.
    if call.method == "isVirtualDevice" {
      result(false)
      return
    }
    // The bench's live memory reading (#58): the same phys_footprint the
    // engines sample for their peak figure, read for this process now.
    if call.method == "physicalFootprintBytes" {
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
      )
      let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      result(status == KERN_SUCCESS ? Int(info.phys_footprint) : nil)
      return
    }
    // What this machine is, for the provenance every bench measurement
    // carries (#58). Each reading is independent: one that fails stays nil
    // rather than taking the others with it.
    if call.method == "deviceProvenance" {
      let process = ProcessInfo.processInfo
      let thermal: String = switch process.thermalState {
      case .nominal: "nominal"
      case .fair: "fair"
      case .serious: "serious"
      case .critical: "critical"
      @unknown default: "unknown"
      }
      result([
        "model": Self.sysctlString("hw.model") as Any,
        "chip": Self.sysctlString("machdep.cpu.brand_string") as Any,
        "memoryBytes": Int(process.physicalMemory),
        "osVersion": process.operatingSystemVersionString,
        "thermalState": thermal,
      ] as [String: Any])
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

  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
  }

  /// The profile's floor, never wider or taller than the display can show.
  private static func clampedMinimumContentSize(
    of profile: WindowProfile, for screen: NSScreen?
  ) -> NSSize {
    let floor = profile.minimumContentSize
    guard let visible = screen?.visibleFrame else { return floor }
    return NSSize(
      width: min(floor.width, visible.width - 40),
      height: min(floor.height, visible.height - 60)
    )
  }

  private static func clampedDefaultContentSize(
    of profile: WindowProfile, for screen: NSScreen?
  ) -> NSSize {
    let target = profile.defaultContentSize
    guard let visible = screen?.visibleFrame else { return target }
    // Leave breathing room for the title bar and Dock; scale down uniformly.
    // The profile's floor yields to the display: a bench on a small screen
    // opens as large as fits rather than wider than the screen.
    let room = NSSize(width: visible.width - 40, height: visible.height - 60)
    let scale = min(1, room.width / target.width, room.height / target.height)
    let floor = clampedMinimumContentSize(of: profile, for: screen)
    return NSSize(
      width: max(floor.width, target.width * scale),
      height: max(floor.height, target.height * scale)
    )
  }
}
