import Cocoa
import CoreServices
import FlutterMacOS

struct AppUpdateFailure: Error {
  let code: String
  let message: String
}

/// File checks are kept separate so tests never mount a disk image or install an app.
enum AppUpdateFilePolicy {
  static func validatedReleasePage(_ text: String) throws -> URL {
    guard let url = URL(string: text), url.scheme == "https", url.host == "github.com",
          url.port == nil || url.port == 443,
          url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
          url.path.range(of: #"^/KingXcode/cloud-music/releases/tag/v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$"#,
                         options: .regularExpression) != nil else {
      throw AppUpdateFailure(code: "invalid_url", message: "Only official release pages can be opened.")
    }
    return url
  }

  static func validatedDMG(path: String, directory: URL) throws -> URL {
    guard (path as NSString).isAbsolutePath else {
      throw invalidPackage()
    }
    let requested = URL(fileURLWithPath: path)
    let candidate = requested.standardizedFileURL.resolvingSymlinksInPath()
    let cache = directory.standardizedFileURL.resolvingSymlinksInPath()
    guard path == candidate.path,
          candidate.deletingLastPathComponent().path == cache.path,
          candidate.pathExtension.lowercased() == "dmg" else {
      throw invalidPackage()
    }
    let values = try candidate.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true,
          values.isSymbolicLink != true,
          (values.fileSize ?? 0) > 0,
          FileManager.default.isReadableFile(atPath: candidate.path) else {
      throw invalidPackage()
    }
    return candidate
  }

  private static func invalidPackage() -> AppUpdateFailure {
    AppUpdateFailure(
      code: "invalid_package",
      message: "The update must be a completed DMG in the private update cache."
    )
  }

  static func quarantineDownload(_ url: URL) throws {
    // Dart's HTTP client does not add browser download quarantine. Preserve any
    // existing metadata, or add it through Launch Services before opening the DMG.
    if let properties = try url.resourceValues(forKeys: [.quarantinePropertiesKey])
      .quarantineProperties, !properties.isEmpty {
      return
    }
    let properties: [String: Any] = [
      kLSQuarantineAgentNameKey as String: "Xianbo",
      kLSQuarantineAgentBundleIdentifierKey as String:
        Bundle.main.bundleIdentifier ?? "dev.cloudmusic.cloudMusic",
      kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
      kLSQuarantineTimeStampKey as String: Date(),
    ]
    try (url as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey)
    // Some unsupported resource setters silently succeed. Fail closed unless a
    // fresh resource read confirms quarantine exists. Never strip quarantine.
    let freshURL = URL(fileURLWithPath: url.path)
    guard let saved = try freshURL.resourceValues(forKeys: [.quarantinePropertiesKey])
      .quarantineProperties, !saved.isEmpty else {
      throw AppUpdateFailure(
        code: "quarantine_failed",
        message: "macOS could not apply download security checks to this update."
      )
    }
  }
}

final class AppUpdateBridge {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "dev.cloudmusic/app_updates", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "open_failed", message: "The update bridge is unavailable.", details: nil))
        return
      }
      self.handle(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "getInfo":
        let info: [String: Any] = [
          "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
          "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
          "platform": "macos",
          "architecture": Self.architecture,
          // This build has no signed Sparkle feed or production signing identity.
          // Opening a DMG is NOT automatic installation, replacement, or relaunch.
          "automaticInstall": false,
        ]
        result(info)
      case "getDownloadDirectory":
        result(try downloadDirectory().path)
      case "openReleasePage":
        let arguments = call.arguments as? [String: Any]
        let page = try AppUpdateFilePolicy.validatedReleasePage(arguments?["url"] as? String ?? "")
        guard NSWorkspace.shared.open(page) else {
          throw AppUpdateFailure(code: "open_failed", message: "The browser could not open the release page.")
        }
        result(nil)
      case "installDownloaded":
        guard let arguments = call.arguments as? [String: Any],
              let path = arguments["path"] as? String, !path.isEmpty else {
          throw AppUpdateFailure(code: "invalid_arguments", message: "An update file path is required.")
        }
        let dmg = try AppUpdateFilePolicy.validatedDMG(path: path, directory: downloadDirectory())
        try AppUpdateFilePolicy.quarantineDownload(dmg)
        // The shared Dart controller verifies the release SHA-256 before invoking
        // this explicit user action. NSWorkspace preserves normal macOS security.
        guard NSWorkspace.shared.open(dmg) else {
          throw AppUpdateFailure(code: "open_failed", message: "macOS could not open the downloaded disk image.")
        }
        result("opened")
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch let error as AppUpdateFailure {
      result(FlutterError(code: error.code, message: error.message, details: nil))
    } catch {
      result(FlutterError(code: "update_failed", message: "The native update operation could not be completed.", details: nil))
    }
  }

  private func downloadDirectory() throws -> URL {
    let manager = FileManager.default
    // In sandboxed builds this resolves inside the app's own container. No new
    // entitlements, user-selected directory access, or external storage are needed.
    let cache = try manager.url(for: .cachesDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)
      .standardizedFileURL.resolvingSymlinksInPath()
    let requested = cache.appendingPathComponent("app_updates", isDirectory: true)
    let directory = requested.standardizedFileURL.resolvingSymlinksInPath()
    guard requested.path == directory.path else {
      throw AppUpdateFailure(code: "cache_unavailable", message: "The private update cache is unavailable.")
    }
    try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
    return directory
  }

  private static var architecture: String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x64"
    #else
    return "unknown"
    #endif
  }
}
