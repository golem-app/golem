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
    self.contentMinSize = profile.minimumContentSize

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

  private static func clampedDefaultContentSize(
    of profile: WindowProfile, for screen: NSScreen?
  ) -> NSSize {
    let target = profile.defaultContentSize
    guard let visible = screen?.visibleFrame else { return target }
    // Leave breathing room for the title bar and Dock; scale down uniformly.
    let scale = min(
      1,
      (visible.width - 40) / target.width,
      (visible.height - 60) / target.height
    )
    return NSSize(
      width: max(profile.minimumContentSize.width, target.width * scale),
      height: max(profile.minimumContentSize.height, target.height * scale)
    )
  }
}
