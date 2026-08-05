import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// The default content size is the iPad Pro 11" logical portrait viewport,
  /// because this target's first job is previewing tablet-proportioned layout
  /// without an iPad. It is clamped to the screen's visible frame (preserving
  /// the aspect ratio) so the window never opens taller than the display.
  private static let defaultContentSize = NSSize(width: 834, height: 1194)
  private static let minimumContentSize = NSSize(width: 480, height: 640)
  private static let frameAutosaveKey = "GolemMainWindow"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let displayName = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleDisplayName"
    ) as? String
    self.title = displayName?.isEmpty == false ? displayName! : "Golem"
    self.contentMinSize = Self.minimumContentSize

    // Restore the user's last frame when one was saved; otherwise open at
    // the iPad-class default. setFrameUsingName returns false on first run.
    // The window has no screen before it is ordered front, so fall back to
    // the main screen — otherwise the clamp silently no-ops on small
    // displays, which is exactly what it exists to prevent.
    if !self.setFrameUsingName(Self.frameAutosaveKey) {
      self.setContentSize(
        Self.clampedDefaultContentSize(for: self.screen ?? NSScreen.main)
      )
      self.center()
    }
    self.setFrameAutosaveName(Self.frameAutosaveKey)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let storageChannel = FlutterMethodChannel(
      name: "app.golem.flutter/storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    storageChannel.setMethodCallHandler(Self.handleStorageCall)

    super.awakeFromNib()
  }

  private static func handleStorageCall(
    _ call: FlutterMethodCall, result: @escaping FlutterResult
  ) {
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

  private static func clampedDefaultContentSize(for screen: NSScreen?) -> NSSize {
    let target = defaultContentSize
    guard let visible = screen?.visibleFrame else { return target }
    // Leave breathing room for the title bar and Dock; scale down uniformly.
    let scale = min(
      1,
      (visible.width - 40) / target.width,
      (visible.height - 60) / target.height
    )
    return NSSize(
      width: max(minimumContentSize.width, target.width * scale),
      height: max(minimumContentSize.height, target.height * scale)
    )
  }
}
