import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var appUpdates: AppUpdateBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    appUpdates = AppUpdateBridge(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
