import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Start with a large-enough window that the dual-pane transcription
    // screen doesn't clip. Users can still resize smaller; scroll views
    // inside the app handle narrow widths.
    let defaultSize = NSSize(width: 1200, height: 800)
    let screen = NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    let origin = NSPoint(
      x: screen.midX - defaultSize.width / 2,
      y: screen.midY - defaultSize.height / 2
    )
    let windowFrame = NSRect(origin: origin, size: defaultSize)

    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 600, height: 480)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // PLAN §5.1.1 system-audio capture — register before
    // super.awakeFromNib so the channels are live by the time
    // Flutter side first invokes them.
    registerSystemAudioCapture(
      messenger: flutterViewController.engine.binaryMessenger)

    // macOS Open-With / drag-on-dock bridge — bind the channel
    // so the cold-launch buffer in OpenWithReceiver can be
    // drained from Dart, and subsequent file opens live-forward.
    OpenWithReceiver.shared.attachChannel(
      messenger: flutterViewController.engine.binaryMessenger)

    // §5.25.3 — Subtitle overlay window management channel.
    // Allows Dart to toggle always-on-top and window opacity for
    // the teleprompter / subtitle overlay mode.
    registerWindowOverlayChannel(
      window: self,
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// §5.25.3 — Platform channel for subtitle overlay window control.
private func registerWindowOverlayChannel(
  window: NSWindow,
  messenger: FlutterBinaryMessenger
) {
  let channel = FlutterMethodChannel(
    name: "crisperweaver/window_overlay",
    binaryMessenger: messenger)

  channel.setMethodCallHandler { (call, result) in
    switch call.method {
    case "setAlwaysOnTop":
      if let onTop = call.arguments as? Bool {
        DispatchQueue.main.async {
          window.level = onTop ? .floating : .normal
        }
        result(nil)
      } else {
        result(FlutterError(code: "INVALID_ARG",
                           message: "Expected bool", details: nil))
      }

    case "setWindowOpacity":
      if let opacity = call.arguments as? Double {
        DispatchQueue.main.async {
          window.alphaValue = CGFloat(opacity.clamped(to: 0.1...1.0))
        }
        result(nil)
      } else {
        result(FlutterError(code: "INVALID_ARG",
                           message: "Expected double", details: nil))
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    return min(max(self, range.lowerBound), range.upperBound)
  }
}
