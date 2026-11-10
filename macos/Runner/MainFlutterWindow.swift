import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var appUpdates: AppUpdateBridge?
  private var windowChrome: FlutterMethodChannel?
  private var contentLayoutObservation: NSKeyValueObservation?
  private var lastPublishedTopInset: Double?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    titlebarSeparatorStyle = .none
    styleMask.insert(.fullSizeContentView)
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    appUpdates = AppUpdateBridge(messenger: flutterViewController.engine.binaryMessenger)
    configureWindowChrome(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func configureWindowChrome(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cloud_music/window_chrome", binaryMessenger: messenger)
    windowChrome = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getTopInset" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.topInset ?? 0)
    }
    contentLayoutObservation = observe(\.contentLayoutRect, options: [.initial, .new]) {
      [weak self] _, _ in self?.publishTopInset()
    }
    for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowChromeDidChange(_:)), name: name, object: self)
    }
  }

  private var topInset: Double {
    guard !styleMask.contains(.fullScreen), let view = contentView else { return 0 }
    // AppKit 的布局区域使用窗口坐标；转换后再计算 Flutter 顶部被标题栏覆盖的高度。
    let layout = view.convert(contentLayoutRect, from: nil)
    let inset = view.isFlipped
      ? layout.minY - view.bounds.minY
      : view.bounds.maxY - layout.maxY
    return Double(max(0, inset))
  }

  @objc private func windowChromeDidChange(_ notification: Notification) {
    publishTopInset()
  }

  private func publishTopInset() {
    let inset = topInset
    guard inset != lastPublishedTopInset else { return }
    lastPublishedTopInset = inset
    windowChrome?.invokeMethod("topInsetChanged", arguments: inset)
  }
}
