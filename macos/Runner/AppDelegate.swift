import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Shared Flutter engine for the Spotlight panel.
  let flutterEngine = FlutterEngine(name: "spotlight-engine")

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Keep the app running even when the main window closes, so the
    // Spotlight panel can be summoned with the keyboard shortcut.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Pre-warm the spotlight Flutter engine
    flutterEngine.run(withEntrypoint: "spotlightMain")
  }

  /// Show a menu bar item for quick access to Spotlight.
  func setupStatusBarItem() {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "THOX"
    statusItem.button?.action = #selector(statusBarClicked(_:))

    let menu = NSMenu()
    menu.addItem(withTitle: "Open Spotlight", action: #selector(openSpotlight), keyEquivalent: "i")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    statusItem.menu = menu
  }

  @objc func statusBarClicked(_ sender: Any) {
    SpotlightPanelController.shared.handleMethodCall(
      FlutterMethodCall(channel: "", method: "toggleSpotlight", arguments: nil)
    ) { _ in }
  }

  @objc func openSpotlight() {
    SpotlightPanelController.shared.handleMethodCall(
      FlutterMethodCall(channel: "", method: "showSpotlight", arguments: nil)
    ) { _ in }
  }

  @objc func quitApp() {
    NSApp.terminate(nil)
  }
}