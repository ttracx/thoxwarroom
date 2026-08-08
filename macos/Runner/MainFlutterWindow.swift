import Cocoa
import FlutterMacOS
import IOKit
import AVFoundation

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // Desktop-sized window — wide enough for the adaptive drawer layout
    let contentRect = NSMakeRect(0, 0, 1200, 800)
    self.setContentSize(contentRect.size)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Register a method channel for the Spotlight floating chat bar
    let spotlightChannel = FlutterMethodChannel(
      name: "ai.thox.warroom/spotlight",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    spotlightChannel.setMethodCallHandler({ [weak self] (call, result) in
      SpotlightPanelController.shared.handleMethodCall(call, result: result)
    })

    // Register global keyboard shortcut for spotlight (Shift+Cmd+I)
    SpotlightPanelController.shared.registerGlobalShortcut()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

/// Manages a floating, always-on-top panel for the Spotlight chat bar.
/// The panel is a borderless NSPanel that floats above other windows.
class SpotlightPanelController: NSObject {
  static let shared = SpotlightPanelController()

  private var panel: NSPanel?
  private var flutterViewController: FlutterViewController?
  private var isPanelVisible = false
  private var globalMonitor: Any?

  private let panelWidth: CGFloat = 640
  private let panelHeightCollapsed: CGFloat = 56
  private let panelHeightExpanded: CGFloat = 420

  func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showSpotlight":
      showPanel()
      result(true)
    case "hideSpotlight":
      hidePanel()
      result(true)
    case "toggleSpotlight":
      togglePanel()
      result(true)
    case "isSpotlightVisible":
      result(isPanelVisible)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func registerGlobalShortcut() {
    // Register Shift+Cmd+I as a global shortcut within the app
    globalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      // Shift+Cmd+I (keyCode 34 = 'i')
      if event.modifierFlags.contains([.shift, .command]) && event.keyCode == 34 {
        self?.togglePanel()
        return nil
      }
      // Escape closes the spotlight
      if event.keyCode == 53 && self?.isPanelVisible == true {
        self?.hidePanel()
        return nil
      }
      return event
    }
  }

  private func showPanel() {
    if panel == nil {
      createPanel()
    }
    guard let panel = panel else { return }

    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    let panelX = (screenFrame.width - panelWidth) / 2 + screenFrame.minX
    let panelY = screenFrame.maxY - panelHeightCollapsed - 80

    panel.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeightCollapsed), display: true)
    panel.orderFrontRegardless()
    isPanelVisible = true

    // Make the app active so the panel receives keyboard focus
    NSApp.activate(ignoringOtherApps: true)
  }

  private func hidePanel() {
    panel?.orderOut(nil)
    isPanelVisible = false
  }

  private func togglePanel() {
    if isPanelVisible {
      hidePanel()
    } else {
      showPanel()
    }
  }

  private func createPanel() {
    let styleMask: NSWindow.StyleMask = [
      .borderless,
      .nonactivatingPanel,
    ]

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeightCollapsed),
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.level = .floating
    panel.backgroundColor = NSColor.black.withAlphaComponent(0.95)
    panel.isOpaque = false
    panel.hasShadow = true
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    // Create a FlutterViewController for the spotlight content
    let flutterVC = FlutterViewController(
      engine: (NSApp.delegate as? AppDelegate)?.flutterEngine
        ?? FlutterEngine(name: "spotlight", project: nil),
      nibName: nil,
      bundle: nil
    )
    panel.contentViewController = flutterVC
    self.flutterViewController = flutterVC

    self.panel = panel
  }

  func expandPanel() {
    guard let panel = panel, isPanelVisible else { return }
    var frame = panel.frame
    frame.size.height = panelHeightExpanded
    panel.setFrame(frame, display: true, animate: true)
  }

  func collapsePanel() {
    guard let panel = panel, isPanelVisible else { return }
    var frame = panel.frame
    frame.size.height = panelHeightCollapsed
    panel.setFrame(frame, display: true, animate: true)
  }
}
