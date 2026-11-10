import Foundation
import AVFoundation

// 只补充系统已确认驻留本机的文件。此操作不创建播放器、不发起下载。
enum LocalAudioDuration {
    static func needsRead(status: String, durationMs: Int) -> Bool {
        status == "ready" && durationMs <= 0
    }

    private static func resident(_ target: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey, .volumeIsLocalKey, .isRegularFileKey,
            .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? CloudFileMetadata.promisedValues(target, keys: keys) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true && CloudFileMetadata.status(values) == "ready"
    }

    static func read(_ url: URL, cancelled: @escaping () -> Bool,
                     isResident: (URL) -> Bool = resident) -> Int? {
        guard !cancelled() else { return nil }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let timeout = DispatchWorkItem { coordinator.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
        defer { timeout.cancel() }
        var result: Int?
        var error: NSError?
        // 必须先进行纯属性检查；普通读取协调可能使云端文件实体化。
        var ready = false
        coordinator.coordinate(readingItemAt: url, options: .immediatelyAvailableMetadataOnly, error: &error) { target in
            ready = !cancelled() && isResident(target)
        }
        guard ready, error == nil, !cancelled() else { return nil }
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { target in
            // 排队期间文件可能被系统移出本机，再次检查并跳过。
            guard !cancelled(), isResident(target) else { return }
            let asset = AVURLAsset(url: target)
            let loaded = DispatchSemaphore(value: 0)
            // 保持 iOS 15/macOS 12 部署兼容性，与播放流程使用同一加载 API。
            asset.loadValuesAsynchronously(forKeys: ["duration"]) { loaded.signal() }
            defer { asset.cancelLoading() }
            let deadline = Date().addingTimeInterval(8)
            while loaded.wait(timeout: .now() + 0.1) == .timedOut {
                if cancelled() || Date() >= deadline { return }
            }
            guard !cancelled(), asset.statusOfValue(forKey: "duration", error: nil) == .loaded else { return }
            let seconds = asset.duration.seconds
            guard seconds.isFinite, seconds > 0, seconds < Double(Int.max / 1000) else { return }
            result = Int(seconds * 1000)
        }
        return error == nil && !cancelled() ? result : nil
    }
}
