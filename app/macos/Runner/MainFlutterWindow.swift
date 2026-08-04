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

    self.title = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleDisplayName"
    ) as? String ?? "Golem"
    self.contentMinSize = Self.minimumContentSize

    // Restore the user's last frame when one was saved; otherwise open at
    // the iPad-class default. setFrameUsingName returns false on first run.
    if !self.setFrameUsingName(Self.frameAutosaveKey) {
      self.setContentSize(Self.clampedDefaultContentSize(for: self.screen))
      self.center()
    }
    self.setFrameAutosaveName(Self.frameAutosaveKey)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
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
