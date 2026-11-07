#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import Cocoa
#endif
import Foundation
import AVFoundation
import MediaPlayer
import Network
import UniformTypeIdentifiers

// 桥接状态由主线程管理，文件 I/O 仅在后台队列执行。
private struct Track: Codable {
    var id: String
    var title: String
    var artist = ""
    var album = ""
    var relativePath: String
    var status = "unknown"
    var durationMs = 0
    var map: [String: Any] {
        ["id": id, "title": title, "artist": artist, "album": album,
         "relativePath": relativePath, "status": status, "durationMs": durationMs]
    }
}
private struct Library: Codable {
    var bookmark: Data?
    var folderName: String?
    var volumeUUID: String?
    var sourceIdentity: String?
    var tracks: [Track] = []
    var shuffle = false
    var repeatMode = "off"
    var volume: Float = 1
}
private final class Cancellation {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    private var coordinators: [ObjectIdentifier: NSFileCoordinator] = [:]
    func attach(_ coordinator: NSFileCoordinator) throws {
        lock.lock(); defer { lock.unlock() }
        guard !value else { throw SourceError.cancelled }
        coordinators[ObjectIdentifier(coordinator)] = coordinator
    }
    func detach(_ coordinator: NSFileCoordinator) {
        lock.lock(); coordinators.removeValue(forKey: ObjectIdentifier(coordinator)); lock.unlock()
    }
    func cancel() {
        lock.lock(); value = true; let pending = Array(coordinators.values); lock.unlock()
        pending.forEach { $0.cancel() }
    }
}
private final class Scope {
    let url: URL
    private let started: Bool
    init(_ url: URL) { self.url = url; started = url.startAccessingSecurityScopedResource() }
    deinit { if started { url.stopAccessingSecurityScopedResource() } }
}
private enum SourceError: Error, Equatable { case unavailable, cancelled, timeout, unsupported }

// AVPlayer 在文件协调结束后仍会异步读取。为实际播放的 URL 注册文件呈现器，
// 在外部写入、移动或删除时暂停播放，本实现不写入源文件。
private final class PlaybackPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 1; return q
    }()
    let changed: () -> Void
    init(url: URL, changed: @escaping () -> Void) { presentedItemURL = url; self.changed = changed }
    func presentedItemDidChange() { DispatchQueue.main.async(execute: changed) }
    func presentedItemDidMove(to newURL: URL) { DispatchQueue.main.async(execute: changed) }
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { self.changed(); completionHandler(nil) }
    }
    func relinquishPresentedItem(toWriter writer: @escaping ((() -> Void)?) -> Void) {
        // 允许其他进程修改正在播放的文件之前，先暂停播放。
        DispatchQueue.main.async { self.changed(); writer({}) }
    }
}

public final class FolderAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var library = Library()
    private var sink: FlutterEventSink?
    private let io = DispatchQueue(label: "cloud_music.index", qos: .utility, attributes: .concurrent)
    private let playbackIO = DispatchQueue(label: "cloud_music.prepare", qos: .userInitiated, attributes: .concurrent)
    private let persistence = DispatchQueue(label: "cloud_music.persistence", qos: .utility)
    private var loaded = false
    private let networkMonitor = NWPathMonitor()
    private var networkAvailable = false
    private var generation = UUID()
    private var scanToken: Cancellation?
    private var playToken: Cancellation?
    private var scope: Scope?
    private var presenter: PlaybackPresenter?
    private let player = AVPlayer()
    private var itemObservation: NSKeyValueObservation?
    private var timeObservation: NSKeyValueObservation?
    private var periodic: Any?
    private var observers: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var currentID: String?
    private var artwork: Data?
    private var loading = false
    private var scanning = false
    private var picking = false
    private var lyricsResult: FlutterResult?
    private var lyricsRequest: UUID?
    #if os(iOS)
    private var lyricsPicker: UIDocumentPickerViewController?
    #else
    private var lyricsPanel: NSOpenPanel?
    #endif
    private var message: String?
    private var wantsPlayback = false
    private var audioInterrupted = false
    private var shuffleCycleStarted = false
    private var history: [String] = []
    private var shuffleBag: [String] = []
    private var asset: AVURLAsset?
    private static var store: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudMusic", isDirectory: true).appendingPathComponent("library.json")
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #else
        let messenger = registrar.messenger
        #endif
        let instance = FolderAudioPlugin()
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "cloud_music/control", binaryMessenger: messenger))
        FlutterEventChannel(name: "cloud_music/events", binaryMessenger: messenger).setStreamHandler(instance)
        instance.configurePlayback()
    }
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events; emit(); return nil
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
    private func snapshot() -> [String: Any] {
        let duration = player.currentItem?.duration.seconds ?? 0
        let position = player.currentTime().seconds
        var result: [String: Any] = ["folderName": library.folderName as Any? ?? NSNull(), "sourceKind": "apple",
            "sourceIdentity": library.sourceIdentity as Any? ?? NSNull(),
            "tracks": library.tracks.map { $0.map }, "currentTrackId": currentID as Any? ?? NSNull(),
            "isPlaying": player.timeControlStatus == .playing, "isLoading": loading || (wantsPlayback && player.timeControlStatus == .waitingToPlayAtSpecifiedRate),
            "isScanning": scanning, "shuffle": library.shuffle,
            "positionMs": position.isFinite ? max(0, Int(position * 1000)) : 0,
            "durationMs": duration.isFinite ? max(0, Int(duration * 1000)) : 0,
            "repeatMode": library.repeatMode, "volume": Double(library.volume), "message": message as Any? ?? NSNull()]
        if let artwork = artwork { result["artwork"] = FlutterStandardTypedData(bytes: artwork) }
        return result
    }
    private func emit() { sink?(snapshot()); updateNowPlaying() }
    private func save() {
        let value = library
        persistence.async {
            do {
                let url = Self.store
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(value).write(to: url, options: .atomic)
            } catch {
                DispatchQueue.main.async { [weak self] in self?.message = "无法保存曲库，下次启动可能需要重新选择文件夹。"; self?.emit() }
            }
        }
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "readLyricsCache":
            persistence.async {
                do {
                    let url = Self.lyricsStore
                    let value = FileManager.default.fileExists(atPath: url.path)
                        ? try Self.readLyrics(url, limit: 2 * 1024 * 1024) : nil
                    DispatchQueue.main.async { result(value) }
                } catch {
                    DispatchQueue.main.async { result(FlutterError(code: "lyrics_error", message: "无法读取歌词缓存。", details: nil)) }
                }
            }
            return
        case "writeLyricsCache":
            guard let value = args["value"] as? String else {
                result(FlutterError(code: "invalid_arguments", message: "缺少歌词缓存内容。", details: nil)); return
            }
            persistence.async {
                do {
                    let data = Data(value.utf8)
                    guard data.count <= 2 * 1024 * 1024 else { throw SourceError.unsupported }
                    let url = Self.lyricsStore
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async { result(FlutterError(code: "lyrics_error", message: "无法保存歌词缓存（上限 2 MiB）。", details: nil)) }
                }
            }
            return
        case "importLyrics": importLyrics(result); return
        case "initialize":
            if !loaded {
                loaded = true
                // initialize 返回前加载体积较小的本地元数据索引，
                // 云端访问和校验始终异步执行。
                if let data = try? Data(contentsOf: Self.store), let saved = try? JSONDecoder().decode(Library.self, from: data) { library = saved }
                // 旧索引仅迁移一次，刷新和书签更新均保留该标识。
                if library.bookmark != nil, library.sourceIdentity == nil {
                    library.sourceIdentity = UUID().uuidString; save()
                }
                player.volume = library.volume
                scan(removeMissing: false, discover: false)
            }
        case "pickFolder": pickFolder()
        case "refresh": scan(removeMissing: true, discover: true)
        case "play": if let id = args["id"] as? String { play(id) }
        case "togglePlayback":
            if wantsPlayback || player.timeControlStatus == .playing { pause() }
            else if player.currentItem != nil { resume() }
            else if let id = currentID ?? library.tracks.first?.id { play(id) }
        case "pause": pause()
        case "next": advance(back: false)
        case "previous": advance(back: true)
        case "seek":
            if let ms = args["positionMs"] as? NSNumber {
                let duration = player.currentItem?.duration.seconds ?? .infinity
                let seconds = min(max(0, ms.doubleValue / 1000), duration.isFinite ? max(0, duration) : .infinity)
                player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            }
        case "setShuffle": library.shuffle = args["enabled"] as? Bool ?? false; shuffleBag = []; shuffleCycleStarted = false; save()
        case "setRepeat":
            let mode = args["mode"] as? String ?? "off"
            if ["off", "all", "one"].contains(mode) { library.repeatMode = mode; save() }
        case "setVolume":
            if let number = args["volume"] as? NSNumber, number.doubleValue.isFinite {
                library.volume = Float(min(1, max(0, number.doubleValue))); player.volume = library.volume; save()
            }
        case "cancelLoading": cancelPlayback(); message = "已取消等待；系统可能继续管理 iCloud 下载。"
        default: result(FlutterMethodNotImplemented); return
        }
        emit(); result(snapshot())
    }

    private static var lyricsStore: URL {
        store.deletingLastPathComponent().appendingPathComponent("lyrics-cache.json")
    }
    // 即使文件提供器报告的文件大小错误或缺失，也要限制读取量。
    private static func readLyrics(_ url: URL, limit: Int) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var bytes = Data()
        while bytes.count <= limit {
            let chunk = try file.read(upToCount: min(8192, limit + 1 - bytes.count)) ?? Data()
            if chunk.isEmpty { break }
            bytes.append(chunk)
        }
        guard bytes.count <= limit, var value = String(data: bytes, encoding: .utf8) else { throw SourceError.unsupported }
        if value.hasPrefix("\u{FEFF}") { value.removeFirst() }
        return value
    }
    private func finishLyrics(_ value: Any?) {
        let result = lyricsResult
        lyricsResult = nil; lyricsRequest = nil
        #if os(iOS)
        lyricsPicker = nil
        #else
        lyricsPanel = nil
        #endif
        result?(value)
    }
    private func importLyrics(_ result: @escaping FlutterResult) {
        guard lyricsResult == nil, !picking else {
            result(FlutterError(code: "picker_busy", message: "请先关闭当前文件选择器。", details: nil)); return
        }
        lyricsResult = result; lyricsRequest = UUID()
        #if os(iOS)
        let types: [UTType] = [.plainText, UTType(filenameExtension: "lrc") ?? .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self; picker.allowsMultipleSelection = false
        var controller = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let host = controller, host.viewIfLoaded?.window != nil, !host.isBeingDismissed else {
            finishLyrics(FlutterError(code: "no_activity", message: "请返回应用后导入歌词。", details: nil)); return
        }
        lyricsPicker = picker
        host.present(picker, animated: true)
        picker.presentationController?.delegate = self
        #else
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "lrc") ?? .data]
        panel.prompt = "导入歌词"; lyricsPanel = panel
        panel.begin { [weak self] response in
            guard let self = self, self.lyricsPanel === panel else { return }
            if response == .OK, let url = panel.url { self.loadImportedLyrics(url) }
            else { self.finishLyrics(nil) }
        }
        #endif
    }
    private func loadImportedLyrics(_ url: URL) {
        guard let request = lyricsRequest else { return }
        io.async { [weak self] in
            let selectedScope = Scope(url)
            let outcome: Result<String, Error> = Result {
                guard ["lrc", "txt"].contains(url.pathExtension.lowercased()) else { throw SourceError.unsupported }
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var error: NSError?
                var text: Result<String, Error>?
                coordinator.coordinate(readingItemAt: url, options: [], error: &error) { target in
                    text = Result { try Self.readLyrics(target, limit: 256 * 1024) }
                }
                if let error = error { throw error }
                guard let text = text else { throw SourceError.unavailable }
                return try text.get()
            }
            withExtendedLifetime(selectedScope) {}
            DispatchQueue.main.async {
                guard let self = self, self.lyricsRequest == request else { return }
                switch outcome {
                case .success(let text): self.finishLyrics(text)
                case .failure: self.finishLyrics(FlutterError(code: "lyrics_error", message: "请选择不超过 256 KiB 的 UTF-8 .lrc 或 .txt 文件。", details: nil))
                }
            }
        }
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        lyricsPicker?.dismiss(animated: false)
        #else
        lyricsPanel?.cancel(nil)
        #endif
        finishLyrics(FlutterError(code: "lyrics_error", message: "应用已关闭，请重试导入。", details: nil))
    }

    private static func bookmark(_ url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }
    private static func resolve(_ data: Data) throws -> (Scope, Data?) {
        var stale = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        let scope = Scope(url)
        return (scope, stale ? try bookmark(url) : nil)
    }
    private func pickFolder() {
        guard !picking, lyricsResult == nil else { return }; picking = true
        #if os(iOS)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self; picker.allowsMultipleSelection = false
        var controller = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let host = controller else { picking = false; message = "无法打开文件夹选择器。"; return }
        host.present(picker, animated: true)
        #else
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "选择音乐文件夹"
        panel.begin { [weak self] response in
            guard let self = self else { return }; self.picking = false
            if response == .OK, let url = panel.url { self.select(url) }
        }
        #endif
    }
    private func select(_ url: URL) {
        // 确认新书签能够保存之前，不丢弃旧来源。
        let request = UUID(); generation = request
        scanToken?.cancel(); scanning = false
        cancelPlayback()
        io.async { [weak self] in
            let selectedScope = Scope(url)
            do {
                let data = try Self.bookmark(url)
                let volumeUUID = try Self.metadata(url, token: Cancellation()) { try $0.resourceValues(forKeys: Self.keys).volumeUUIDString }
                DispatchQueue.main.async {
                    guard let self = self, self.generation == request else { return }
                    withExtendedLifetime(selectedScope) {
                        self.library.bookmark = data; self.library.folderName = url.lastPathComponent; self.library.volumeUUID = volumeUUID
                        // 用户主动重新选择时，即使是同一文件夹，也创建新来源。
                        self.library.sourceIdentity = UUID().uuidString
                        self.library.tracks = []; self.currentID = nil; self.history = []; self.shuffleBag = []; self.shuffleCycleStarted = false
                        self.save(); self.scan(removeMissing: false, discover: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self, self.generation == request else { return }
                    self.message = "无法保存文件夹授权，请重新选择文件夹。"; self.emit()
                }
            }
        }
    }

    // 此选项可避免文件提供器将内容实体化，.withoutChanges 不具备这一作用。
    // 闭包中只允许读取元数据或枚举名称，不得读取音频内容。
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey,
        .contentTypeKey, .volumeUUIDStringKey, .volumeIsLocalKey, .fileResourceIdentifierKey]
    private static func metadata<T>(_ url: URL, token: Cancellation, _ body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        try token.attach(coordinator)
        defer { token.detach(coordinator) }
        // 取消对文件呈现器的等待，但无法保证中断访问闭包中已开始的
        // 文件提供器系统调用。界面超时机制独立运行。
        let timeout = DispatchWorkItem { coordinator.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeout)
        defer { timeout.cancel() }
        var coordinationError: NSError?
        var outcome: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: .immediatelyAvailableMetadataOnly, error: &coordinationError) { target in
            outcome = Result {
                guard !token.cancelled else { throw SourceError.cancelled }
                var fresh = target
                fresh.removeAllCachedResourceValues()
                return try body(fresh)
            }
        }
        guard !token.cancelled else { throw SourceError.cancelled }
        if let error = coordinationError { throw error }
        guard let outcome = outcome else { throw SourceError.unavailable }
        return try outcome.get()
    }
    // 仅针对所选歌曲的可用性协调，有意允许文件提供器将内容实体化。
    // 绝不在索引扫描中调用。
    private static func availableURL(_ url: URL, token: Cancellation) throws -> URL {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        try token.attach(coordinator)
        defer { token.detach(coordinator) }
        var error: NSError?
        var available: URL?
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { target in
            if !token.cancelled { available = target }
        }
        guard !token.cancelled else { throw SourceError.cancelled }
        if let error = error { throw error }
        guard let available = available else { throw SourceError.unavailable }
        return available
    }
    private static func status(_ value: URLResourceValues) -> String {
        if value.ubiquitousItemDownloadingError != nil { return "offline" }
        if value.isUbiquitousItem == true && value.ubiquitousItemDownloadingStatus != .current && value.ubiquitousItemDownloadingStatus != .downloaded { return "cloud" }
        return "ready"
    }
    private static func missingError(_ error: Error) -> Bool {
        let e = error as NSError
        // 不得将文件提供器或网络错误解包后重新解释为文件已删除。
        return e.domain == NSCocoaErrorDomain && (e.code == NSFileReadNoSuchFileError || e.code == NSFileNoSuchFileError)
    }
    private func scan(removeMissing: Bool, discover: Bool) {
        guard let bookmark = library.bookmark else { return }
        scanToken?.cancel()
        let token = Cancellation(); scanToken = token
        let request = generation; let previous = library.tracks
        let online = networkAvailable
        let expectedVolume = library.volumeUUID
        scanning = true; message = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
            guard let self = self, self.generation == request, !token.cancelled, self.scanning else { return }
            token.cancel(); self.scanning = false
            self.message = "文件服务响应超时，已保留曲库。请检查连接后重试。"; self.emit()
        }
        io.async { [weak self] in
            do {
                let (scope, renewed) = try Self.resolve(bookmark)
                let root = scope.url.standardizedFileURL
                var found: [String: Track] = [:]
                var covered: [String: Set<String>] = [:]
                var uncertain = Set<String>()
                var issues = false
                let rootValues = try Self.metadata(root, token: token) { try $0.resourceValues(forKeys: Self.keys) }
                guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw SourceError.unavailable }
                if let expectedVolume = expectedVolume, rootValues.volumeUUIDString != expectedVolume { throw SourceError.unavailable }
                if rootValues.volumeUUIDString == nil || expectedVolume == nil || rootValues.volumeIsLocal != true || rootValues.fileResourceIdentifier == nil || !online {
                    // 来源标识未经验证、远程卷或网络路径不可用时，均不能确认删除。
                    // 旧索引首次运行时只补充卷标识，
                    // 不清理条目。
                    uncertain.insert(""); issues = true
                }
                let old = Dictionary(previous.map { ($0.relativePath, $0) }, uniquingKeysWith: { a, _ in a })
                func walk(_ directory: URL, _ relative: String) throws {
                    if token.cancelled { throw SourceError.cancelled }
                    do {
                        let listing: ([URL], Bool) = try Self.metadata(directory, token: token) { target in
                            let values = try target.resourceValues(forKeys: Self.keys)
                            guard values.isDirectory == true, values.isSymbolicLink != true else { throw SourceError.unavailable }
                            let children = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: Array(Self.keys), options: [])
                            return (children, Self.status(values) == "ready")
                        }
                        // 文件提供器或存储卷视图意外为空，
                        // 不足以作为清空已有子树的证据。
                        let prefix = relative.isEmpty ? "" : relative + "/"
                        if listing.0.isEmpty && previous.contains(where: { $0.relativePath.hasPrefix(prefix) }) {
                            uncertain.insert(relative); issues = true
                        }
                        if listing.1 { covered[relative] = Set(listing.0.map { $0.lastPathComponent }) }
                        else { uncertain.insert(relative); issues = true }
                        for child in listing.0 {
                            if token.cancelled { throw SourceError.cancelled }
                            let path = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                            // 旧版 iCloud 占位文件可能显示为 .name.ext.icloud。
                            // 绝不将占位文件的名称形式作为删除证据。
                            if child.lastPathComponent.hasPrefix(".") && child.pathExtension.lowercased() == "icloud" {
                                uncertain.insert(relative); issues = true
                                let name = String(child.deletingPathExtension().lastPathComponent.dropFirst())
                                let logicalPath = relative.isEmpty ? name : relative + "/" + name
                                let ext = (name as NSString).pathExtension.lowercased()
                                if ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "alac", "caf", "ogg", "opus", "wma"].contains(ext), discover || old[logicalPath] != nil {
                                    var t = old[logicalPath] ?? Track(id: Data(logicalPath.utf8).base64EncodedString(), title: (name as NSString).deletingPathExtension, relativePath: logicalPath)
                                    t.status = "cloud"; found[logicalPath] = t
                                }
                                continue
                            }
                            do {
                                let value = try Self.metadata(child, token: token) { try $0.resourceValues(forKeys: Self.keys) }
                                if value.isSymbolicLink == true { continue }
                                if value.isDirectory == true { try walk(child, path); continue }
                                let ext = child.pathExtension.lowercased()
                                let candidate = value.contentType?.conforms(to: .audio) == true || ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "alac", "caf", "ogg", "opus", "wma"].contains(ext)
                                guard candidate, discover || old[path] != nil else { continue }
                                var track = old[path] ?? Track(id: Data(path.utf8).base64EncodedString(), title: child.deletingPathExtension().lastPathComponent, relativePath: path)
                                let availability = Self.status(value)
                                if track.status != "unsupported" || availability != "ready" { track.status = availability }
                                found[path] = track
                            } catch {
                                issues = true; uncertain.insert(path)
                            }
                        }
                    } catch {
                        if token.cancelled { throw SourceError.cancelled }
                        if relative.isEmpty { throw error }
                        uncertain.insert(relative); issues = true
                    }
                }
                try walk(root, "")
                for var track in previous where found[track.relativePath] == nil {
                    if token.cancelled { throw SourceError.cancelled }
                    let path = track.relativePath
                    let components = path.split(separator: "/").map(String.init)
                    var parent = ""
                    var confirmed = false
                    for component in components {
                        if uncertain.contains(parent) { break }
                        if let names = covered[parent], !names.contains(component) {
                            let absent = parent.isEmpty ? component : parent + "/" + component
                            do {
                                _ = try Self.metadata(root.appendingPathComponent(absent), token: token) { try $0.resourceValues(forKeys: Self.keys) }
                            } catch {
                                if Self.missingError(error) {
                                    // 在父目录的协调读取仍有效时重新检查，
                                    // 仅凭缓存名称不足以作出判断。
                                    do {
                                        let parentURL = parent.isEmpty ? root : root.appendingPathComponent(parent)
                                        confirmed = try Self.metadata(parentURL, token: token) { target in
                                            let values = try target.resourceValues(forKeys: Self.keys)
                                            guard values.isDirectory == true, Self.status(values) == "ready",
                                                  values.volumeUUIDString == rootValues.volumeUUIDString else { return false }
                                            let namesNow = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).map { $0.lastPathComponent }
                                            return !namesNow.isEmpty && Set(namesNow) == names && !namesNow.contains(component)
                                        }
                                    } catch { issues = true }
                                }
                            }
                            break
                        }
                        parent = parent.isEmpty ? component : parent + "/" + component
                    }
                    if confirmed { track.status = "missing" }
                    else if track.status != "cloud" && track.status != "unsupported" { track.status = "offline" }
                    if !confirmed || !removeMissing { found[path] = track }
                }
                // 枚举及移除判定完成后，重新校验来源标识。
                // 扫描期间若发生弹出、卸载或替换，则保留旧索引。
                let finalRoot = try Self.metadata(root, token: token) { try $0.resourceValues(forKeys: Self.keys) }
                guard finalRoot.isDirectory == true, finalRoot.volumeUUIDString == rootValues.volumeUUIDString else { throw SourceError.unavailable }
                if let beforeID = rootValues.fileResourceIdentifier as? NSObject {
                    guard let afterID = finalRoot.fileResourceIdentifier as? NSObject, beforeID.isEqual(afterID) else { throw SourceError.unavailable }
                }
                if Self.status(rootValues) == "ready" && Self.status(finalRoot) != "ready" { throw SourceError.unavailable }
                let tracks = found.values.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
                withExtendedLifetime(scope) {
                    DispatchQueue.main.async {
                        guard let self = self, self.generation == request, !token.cancelled else { return }
                        // 扫描期间断网会使所有待执行的移除判定失效，
                        // 此时保留之前的快照。
                        if online && !self.networkAvailable {
                            self.scanning = false; self.message = "网络状态已变化，已保留曲库，请联网后刷新。"; self.emit(); return
                        }
                        // 保留扫描运行期间新获取的元数据。
                        let live = Dictionary(self.library.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                        if self.library.volumeUUID == nil { self.library.volumeUUID = rootValues.volumeUUIDString }
                        self.library.tracks = tracks.map { candidate in
                            var t = candidate
                            if let existing = live[t.id] { t.title = existing.title; t.artist = existing.artist; t.album = existing.album; t.durationMs = existing.durationMs }
                            return t
                        }
                        if let renewed = renewed { self.library.bookmark = renewed }
                        if let id = self.currentID, !tracks.contains(where: { $0.id == id }) { self.cancelPlayback(); self.currentID = nil }
                        self.scanning = false; self.message = issues ? "部分文件暂时无法访问，已保留原有记录。" : nil
                        self.save(); self.emit()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self, self.generation == request, !token.cancelled else { return }
                    self.scanning = false
                    self.message = "文件夹暂时无法访问，已保留曲库。请检查网络、云盘或重新选择文件夹。"
                    self.emit()
                }
            }
        }
    }

    private func cancelPlayback() {
        playToken?.cancel(); playToken = nil
        asset?.cancelLoading(); asset = nil
        wantsPlayback = false; loading = false; player.pause()
        itemObservation = nil; player.replaceCurrentItem(with: nil)
        if let presenter = presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil; scope = nil; artwork = nil
    }
    private func pause() {
        wantsPlayback = false
        if loading { cancelPlayback() } else { player.pause() }
        emit()
    }
    private func resume() {
        guard !audioInterrupted else { return }
        guard player.currentItem?.status != .failed else {
            if let id = currentID { play(id) }; return
        }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            wantsPlayback = true
            let duration = player.currentItem?.duration.seconds ?? 0
            if duration.isFinite && duration > 0 && player.currentTime().seconds >= duration - 0.1 {
                let item = player.currentItem
                player.seek(to: .zero) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self, self.wantsPlayback, self.player.currentItem === item else { return }
                        self.player.play()
                    }
                }
            } else { player.play() }
        } catch { message = "无法启动音频输出，请稍后重试。"; wantsPlayback = false }
        emit()
    }
    private func play(_ id: String, remember: Bool = true) {
        guard let track = library.tracks.first(where: { $0.id == id }), let bookmark = library.bookmark else { return }
        // 相对路径虽来自本应用的元数据，仍须校验，
        // 防止损坏的索引越出用户选择的目录。
        let pieces = track.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, !pieces.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            message = "文件路径无效，请刷新曲库。"; emit(); return
        }
        if remember, let current = currentID, current != id { history.append(current) }
        shuffleBag.removeAll { $0 == id }
        cancelPlayback(); currentID = id; loading = true; wantsPlayback = true; message = "正在准备歌曲…"
        let token = Cancellation(); playToken = token
        let request = generation
        emit()
        // 超时覆盖书签解析、文件提供器等待和媒体资源加载，不仅限于轮询。
        // 取消时使结果失效，并取消协调器。
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            guard let self = self, !token.cancelled, self.generation == request, self.loading else { return }
            self.failPlayback(SourceError.timeout, id: id)
        }
        playbackIO.async { [weak self] in
            do {
                let (scope, renewed) = try Self.resolve(bookmark)
                let url = scope.url.appendingPathComponent(track.relativePath)
                let rootPath = scope.url.resolvingSymlinksInPath().standardizedFileURL.path
                guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else { throw SourceError.unavailable }
                let deadline = Date().addingTimeInterval(90)
                var requested = false
                while true {
                    if token.cancelled { throw SourceError.cancelled }
                    let value = try Self.metadata(url, token: token) { try $0.resourceValues(forKeys: Self.keys) }
                    if value.isSymbolicLink == true { throw SourceError.unavailable }
                    if let error = value.ubiquitousItemDownloadingError { throw error }
                    if Self.status(value) != "cloud" { break }
                    if !requested {
                        // 显式发起下载与元数据协调相互独立，
                        // 此处只请求内容，不读取内容。
                        guard !token.cancelled else { throw SourceError.cancelled }
                        try FileManager.default.startDownloadingUbiquitousItem(at: url)
                        requested = true
                        DispatchQueue.main.async {
                            guard let self = self, !token.cancelled, self.generation == request else { return }
                            self.message = "正在等待 iCloud 下载，可随时取消。"; self.emit()
                        }
                    }
                    if Date() >= deadline { throw SourceError.timeout }
                    Thread.sleep(forTimeInterval: 0.3)
                }
                if token.cancelled { throw SourceError.cancelled }
                let readyURL = try Self.availableURL(url, token: token)
                let asset = AVURLAsset(url: readyURL)
                DispatchQueue.main.async {
                    guard let self = self, !token.cancelled, self.generation == request else { return }
                    self.scope = scope; self.asset = asset
                    if let renewed = renewed { self.library.bookmark = renewed; self.save() }
                    let presenter = PlaybackPresenter(url: readyURL) { [weak self] in
                        guard let self = self, !token.cancelled, self.generation == request else { return }
                        self.pause()
                        self.message = "源文件发生变化，播放已暂停。请刷新曲库后重新播放。"; self.emit()
                    }
                    self.presenter = presenter; NSFileCoordinator.addFilePresenter(presenter)
                    self.loadAsset(asset, id: id, token: token, request: request)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self, !token.cancelled, self.generation == request else { return }
                    self.failPlayback(error, id: id)
                }
            }
        }
    }
    private func loadAsset(_ asset: AVURLAsset, id: String, token: Cancellation, request: UUID) {
        // 使用旧式异步键加载，以保持对 iOS 15/macOS 12 的部署兼容性。
        // 不为未选中的歌曲加载元数据。
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration", "commonMetadata"]) { [weak self] in
            var error: NSError?
            let state = asset.statusOfValue(forKey: "playable", error: &error)
            DispatchQueue.main.async {
                guard let self = self, !token.cancelled, self.generation == request else { return }
                guard state == .loaded else { self.failPlayback(error ?? NSError(domain: "CloudMusic", code: 1), id: id); return }
                guard asset.isPlayable else { self.failPlayback(SourceError.unsupported, id: id); return }
                let item = AVPlayerItem(asset: asset)
                self.itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    DispatchQueue.main.async {
                        guard let self = self, !token.cancelled, self.generation == request, self.player.currentItem === item else { return }
                        if item.status == .readyToPlay {
                            self.loading = false; self.message = nil
                            if let i = self.library.tracks.firstIndex(where: { $0.id == id }) { self.library.tracks[i].status = "ready" }
                            if self.wantsPlayback { self.resume() }
                            self.save(); self.emit()
                        } else if item.status == .failed {
                            self.failPlayback(item.error ?? SourceError.unavailable, id: id)
                        }
                    }
                }
                self.player.replaceCurrentItem(with: item)
                self.loadMetadata(asset, id: id, token: token)
                // AVPlayerItem 就绪可能需要异步读取文件提供器内容。
                DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
                    guard let self = self, !token.cancelled, self.loading, self.player.currentItem === item else { return }
                    self.failPlayback(SourceError.timeout, id: id)
                }
            }
        }
    }
    private func loadMetadata(_ asset: AVURLAsset, id: String, token: Cancellation) {
        playbackIO.async { [weak self] in
            guard !token.cancelled else { return }
            var title: String?; var artist: String?; var album: String?; var art: Data?
            if asset.statusOfValue(forKey: "commonMetadata", error: nil) == .loaded {
                for metadata in asset.commonMetadata {
                    switch metadata.commonKey {
                    case .commonKeyTitle: title = metadata.stringValue
                    case .commonKeyArtist: artist = metadata.stringValue
                    case .commonKeyAlbumName: album = metadata.stringValue
                    case .commonKeyArtwork:
                        // 限制桥接数据大小，忽略过大的内嵌封面，
                        // 避免造成过高的内存或 IPC 压力。
                        if let bytes = metadata.dataValue, bytes.count <= 2_000_000 { art = bytes }
                    default: break
                    }
                }
            }
            let seconds = asset.statusOfValue(forKey: "duration", error: nil) == .loaded ? asset.duration.seconds : 0
            DispatchQueue.main.async {
                guard let self = self, !token.cancelled, let i = self.library.tracks.firstIndex(where: { $0.id == id }) else { return }
                if let title = title, !title.isEmpty { self.library.tracks[i].title = title }
                if let artist = artist { self.library.tracks[i].artist = artist }
                if let album = album { self.library.tracks[i].album = album }
                self.library.tracks[i].durationMs = seconds.isFinite ? max(0, Int(seconds * 1000)) : 0
                self.artwork = art; self.save(); self.emit()
            }
        }
    }
    private func failPlayback(_ error: Error, id: String) {
        let e = error as NSError
        // 仅凭播放错误不能证明删除。只有保守扫描才能标记或移除缺失条目，
        // 解码失败的歌曲仍保留在索引中。
        let unsupported = (error as? SourceError) == .unsupported ||
            (e.domain == AVFoundationErrorDomain && [AVError.Code.fileFormatNotRecognized.rawValue, AVError.Code.fileFailedToParse.rawValue, AVError.Code.decoderNotFound.rawValue].contains(e.code))
        cancelPlayback()
        if let i = library.tracks.firstIndex(where: { $0.id == id }) {
            if library.tracks[i].status != "missing" { library.tracks[i].status = unsupported ? "unsupported" : "offline" }
        }
        message = unsupported ? "无法解码此音频，可能是格式不支持或文件损坏。原文件和记录均已保留。" : "歌曲暂时无法播放。请检查网络、iCloud 下载或文件夹授权后重试。"
        save(); emit()
    }
    private func advance(back: Bool, automatic: Bool = false) {
        guard !library.tracks.isEmpty else { return }
        if back && player.currentTime().seconds > 3 { player.seek(to: .zero); emit(); return }
        if automatic && library.repeatMode == "one", let id = currentID { play(id, remember: false); return }
        if back {
            while let id = history.popLast() {
                if library.tracks.contains(where: { $0.id == id }) { play(id, remember: false); return }
            }
        }
        let playable = library.tracks.filter { $0.status != "missing" && $0.status != "unsupported" }
        guard !playable.isEmpty else { pause(); return }
        if library.shuffle && !back {
            shuffleBag.removeAll { id in !playable.contains(where: { $0.id == id }) }
            if shuffleBag.isEmpty {
                if automatic && library.repeatMode == "off" && shuffleCycleStarted { pause(); return }
                shuffleCycleStarted = true
                shuffleBag = playable.map { $0.id }.filter { $0 != currentID }.shuffled()
            }
            if let id = shuffleBag.popLast() { play(id); return }
            if library.repeatMode == "all", let id = currentID { play(id, remember: false) } else { pause() }
            return
        }
        let current = playable.firstIndex(where: { $0.id == currentID }) ?? (back ? playable.count : -1)
        let next = current + (back ? -1 : 1)
        if next >= 0 && next < playable.count { play(playable[next].id) }
        else if library.repeatMode == "all" || !automatic { play(playable[back ? playable.count - 1 : 0].id) }
        else { pause() }
    }
    private func configurePlayback() {
        networkMonitor.pathUpdateHandler = { [weak self] path in self?.networkAvailable = path.status == .satisfied }
        networkMonitor.start(queue: .main)
        #if os(iOS)
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default) }
        catch { message = "后台音频设置失败，请重试。" }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began { self.audioInterrupted = true; self.player.pause() }
            else {
                self.audioInterrupted = false
                let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                if options.contains(.shouldResume) && self.wantsPlayback { self.resume() }
                else { self.wantsPlayback = false }
            }
            self.emit()
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { self?.pause() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelPlayback()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            self?.message = "音频服务已重置，请重新播放。"; self?.emit()
        })
        #endif
        timeObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.emit() }
        }
        periodic = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in self?.emit() }
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
            self.advance(back: false, automatic: true)
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let item = note.object as? AVPlayerItem, item === self.player.currentItem, let id = self.currentID else { return }
            self.failPlayback(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error ?? SourceError.unavailable, id: id)
        })
        let commands = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, _ action: @escaping (MPRemoteCommandEvent) -> Void) {
            command.isEnabled = true
            let target = command.addTarget { event in DispatchQueue.main.async { action(event) }; return .success }
            remoteTargets.append((command, target))
        }
        bind(commands.playCommand) { [weak self] _ in
            guard let self = self else { return }
            if self.player.currentItem != nil { self.resume() }
            else if let id = self.currentID ?? self.library.tracks.first?.id { self.play(id) }
        }
        bind(commands.pauseCommand) { [weak self] _ in self?.pause() }
        bind(commands.togglePlayPauseCommand) { [weak self] _ in
            guard let self = self else { return }
            if self.wantsPlayback { self.pause() } else if self.player.currentItem != nil { self.resume() }
            else if let id = self.currentID ?? self.library.tracks.first?.id { self.play(id) }
        }
        bind(commands.nextTrackCommand) { [weak self] _ in self?.advance(back: false) }
        bind(commands.previousTrackCommand) { [weak self] _ in self?.advance(back: true) }
        bind(commands.changePlaybackPositionCommand) { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent, event.positionTime.isFinite {
                self?.player.seek(to: CMTime(seconds: max(0, event.positionTime), preferredTimescale: 600))
            }
        }
    }
    private func updateNowPlaying() {
        guard let track = library.tracks.first(where: { $0.id == currentID }) else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return
        }
        let seconds = player.currentTime().seconds
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: Double(track.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: seconds.isFinite ? max(0, seconds) : 0,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate]
        if let bytes = artwork {
            #if os(iOS)
            if let image = UIImage(data: bytes) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
            #else
            if let image = NSImage(data: bytes) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
            #endif
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = player.timeControlStatus == .playing ? .playing : .paused
        #endif
    }
    deinit {
        networkMonitor.cancel()
        scanToken?.cancel(); playToken?.cancel(); asset?.cancelLoading()
        if let periodic = periodic { player.removeTimeObserver(periodic) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
        if let presenter = presenter { NSFileCoordinator.removeFilePresenter(presenter) }
    }
}
#if os(iOS)
extension FolderAudioPlugin: UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if controller === lyricsPicker {
            if let url = urls.first { loadImportedLyrics(url) } else { finishLyrics(nil) }
            return
        }
        picking = false
        if let url = urls.first { select(url) }
    }
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if controller === lyricsPicker { finishLyrics(nil) } else { picking = false }
    }
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if presentationController.presentedViewController === lyricsPicker { finishLyrics(nil) }
    }
}
#endif
