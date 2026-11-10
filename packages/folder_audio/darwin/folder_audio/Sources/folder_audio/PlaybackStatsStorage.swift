import Foundation

/// 每台设备只递增自己的计数，合并时取各设备的最大值，避免离线同步相互覆盖。
struct PlaybackStatsDocument: Codable, Equatable {
    var version = 1
    var counts: [String: [String: Int]] = [:]
    static let limit = 8 * 1024 * 1024
    private static let largestExactInteger = 9_007_199_254_740_991

    init() {}

    init(data: Data) throws {
        guard data.count <= Self.limit else { throw PlaybackStatsStorageError.invalidDocument }
        do { self = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw PlaybackStatsStorageError.invalidDocument }
        guard version == 1, counts.allSatisfy({ track, devices in
            !track.isEmpty && devices.allSatisfy { device, count in
                !device.isEmpty && count >= 0 && count <= Self.largestExactInteger
            }
        }) else { throw PlaybackStatsStorageError.invalidDocument }
    }

    mutating func merge(_ other: Self) {
        for (track, devices) in other.counts {
            var merged = counts[track] ?? [:]
            for (device, count) in devices { merged[device] = max(merged[device] ?? 0, count) }
            counts[track] = merged
        }
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.limit else { throw PlaybackStatsStorageError.invalidDocument }
        return data
    }
}

enum PlaybackStatsStorageError: Error {
    case invalidDocument, invalidDevice, coordinationFailed, unavailableFolder
}

private final class PlaybackStatsFolderAccess {
    let url: URL
    private let started: Bool
    init(_ url: URL) { self.url = url; started = url.startAccessingSecurityScopedResource() }
    deinit { if started { url.stopAccessingSecurityScopedResource() } }
}

/// 必须在插件的串行持久化队列调用；iCloud API 和文件协调不能占用主线程。
final class PlaybackStatsStorage {
    private let localDirectory: URL
    private let cloudDirectory: () -> URL?
    private(set) var storageLocation = "local"
    private var localURL: URL { localDirectory.appendingPathComponent("playback-stats.json") }
    private var folderBookmarkURL: URL { localDirectory.appendingPathComponent("playback-stats-folder.bookmark") }

    init(localDirectory: URL? = nil, cloudDirectory: (() -> URL?)? = nil) {
        self.localDirectory = localDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudMusic", isDirectory: true)
        // 生产构建只使用用户明确选择的文件夹，不查询或注册开发者 iCloud 容器。
        // 注入目录仅用于原生文件协调测试。
        self.cloudDirectory = cloudDirectory ?? { nil }
    }

    func deviceId() throws -> String {
        let url = localDirectory.appendingPathComponent("playback-device-id.txt")
        if let data = try readData(url) {
            guard data.count <= 128, let value = String(data: data, encoding: .utf8), UUID(uuidString: value) != nil else {
                throw PlaybackStatsStorageError.invalidDevice
            }
            return value
        }
        let value = UUID().uuidString
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url, options: .atomic)
        return value
    }

    /// 只在系统选择器确认后调用；取消选择不改变原授权或已保存的统计。
    @discardableResult
    func selectFolder(_ url: URL?) throws -> Bool {
        guard let url = url else { return false }
        let access = PlaybackStatsFolderAccess(url)
        defer { withExtendedLifetime(access) {} }
        let previousLocation = storageLocation
        do {
            try Self.validateFolder(url)
            let bookmark = try Self.folderBookmark(url)
            // 连接时立即写入一个有效文件，确认目标可写后才保存新授权。
            let local = try readDocument(localURL) ?? PlaybackStatsDocument()
            _ = try synchronizeDirectory(url, local: local, location: "folder", createDirectory: false)
            try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
            try bookmark.write(to: folderBookmarkURL, options: .atomic)
            return true
        } catch {
            storageLocation = previousLocation
            throw error
        }
    }

    private static func folderBookmark(_ url: URL) throws -> Data {
        #if os(macOS)
        // 统计文件使用独立的读写书签；音乐目录仍通过原来的只读书签访问。
        return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private static func validateFolder(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw PlaybackStatsStorageError.unavailableFolder }
    }

    func read() throws -> String? {
        let local = try readDocument(localURL)
        let merged: PlaybackStatsDocument?
        do { merged = try synchronize(local) }
        catch PlaybackStatsStorageError.invalidDocument { throw PlaybackStatsStorageError.invalidDocument }
        catch {
            // iCloud 离线、不可访问或超时时沿用本地记录；下次读取/播放再重试。
            storageLocation = "local"
            merged = local
        }
        guard let merged = merged else { return nil }
        return String(data: try merged.data(), encoding: .utf8)
    }

    func write(_ value: String) throws {
        var document = try PlaybackStatsDocument(data: Data(value.utf8))
        if let local = try readDocument(localURL) { document.merge(local) }
        // 先原子保存本地副本；iCloud 不可用或协调失败也不丢掉本次播放。
        try writeLocal(document)
        do { _ = try synchronize(document) }
        catch PlaybackStatsStorageError.invalidDocument { throw PlaybackStatsStorageError.invalidDocument }
        catch { storageLocation = "local" }
    }

    private func synchronize(_ local: PlaybackStatsDocument?) throws -> PlaybackStatsDocument? {
        storageLocation = "local"
        if let bookmark = try readData(folderBookmarkURL) {
            var stale = false
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
            #else
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            #endif
            let access = PlaybackStatsFolderAccess(url)
            defer { withExtendedLifetime(access) {} }
            try Self.validateFolder(url)
            let output = try synchronizeDirectory(url, local: local, location: "folder", createDirectory: false)
            if stale { try Self.folderBookmark(url).write(to: folderBookmarkURL, options: .atomic) }
            return output
        }
        guard let directory = cloudDirectory() else { return local }
        return try synchronizeDirectory(directory, local: local, location: "icloud", createDirectory: true)
    }

    private func synchronizeDirectory(_ directory: URL, local: PlaybackStatsDocument?, location: String, createDirectory: Bool) throws -> PlaybackStatsDocument? {
        if createDirectory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let url = directory.appendingPathComponent("playback-stats.json")
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let timeout = DispatchWorkItem { coordinator.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeout)
        defer { timeout.cancel() }
        var coordinationError: NSError?
        var operationError: Error?
        var output = local
        var accessed = false
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinatedURL in
            accessed = true
            do {
                var merged = local ?? PlaybackStatsDocument()
                var found = local != nil
                if let current = try readDocument(coordinatedURL) { merged.merge(current); found = true }
                let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinatedURL) ?? []
                for conflict in conflicts {
                    // 冲突版本可能尚未驻留，需单独协调读取其版本 URL。
                    guard let value = try readConflict(conflict.url) else { throw PlaybackStatsStorageError.invalidDocument }
                    merged.merge(value); found = true
                }
                if found {
                    // 损坏或不认识的版本会在读取阶段抛错，绝不被空数据覆盖。
                    try merged.data().write(to: coordinatedURL, options: .atomic)
                    try writeLocal(merged)
                    for conflict in conflicts {
                        conflict.isResolved = true
                        try? conflict.remove()
                    }
                    output = merged
                }
            } catch { operationError = error }
        }
        if let error = operationError { throw error }
        if let error = coordinationError { throw error }
        guard accessed else { throw PlaybackStatsStorageError.coordinationFailed }
        storageLocation = location
        return output
    }

    private func readConflict(_ url: URL) throws -> PlaybackStatsDocument? {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let timeout = DispatchWorkItem { coordinator.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeout)
        defer { timeout.cancel() }
        var coordinationError: NSError?
        var output: PlaybackStatsDocument?
        var operationError: Error?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do { output = try readDocument(coordinatedURL) }
            catch { operationError = error }
        }
        if let error = operationError { throw error }
        if let error = coordinationError { throw error }
        return output
    }

    private func readDocument(_ url: URL) throws -> PlaybackStatsDocument? {
        guard let data = try readData(url) else { return nil }
        return try PlaybackStatsDocument(data: data)
    }

    private func readData(_ url: URL) throws -> Data? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: PlaybackStatsDocument.limit + 1) ?? Data()
            guard data.count <= PlaybackStatsDocument.limit else { throw PlaybackStatsStorageError.invalidDocument }
            return data
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    private func writeLocal(_ document: PlaybackStatsDocument) throws {
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try document.data().write(to: localURL, options: .atomic)
    }
}
