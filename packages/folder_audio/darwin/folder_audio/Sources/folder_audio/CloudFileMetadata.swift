import Foundation

// 只描述系统确认的可用状态；缺少属性不等于已经下载。
// 与播放器分离，使状态规则可在 macOS CI 中独立验证。
enum CloudFileMetadata {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "flac", "alac", "caf", "ogg", "oga", "opus", "wma", "mp4"]

    static func availability(isUbiquitous: Bool?, downloadingStatus: URLUbiquitousItemDownloadingStatus?, hasDownloadError: Bool,
                             isLocal: Bool?, isRegularFile: Bool?, isDirectory: Bool?) -> String {
        if hasDownloadError { return "offline" }
        if isUbiquitous == true {
            if downloadingStatus == .notDownloaded { return "cloud" }
            if downloadingStatus == .current || downloadingStatus == .downloaded { return "ready" }
            return "unknown"
        }
        if isUbiquitous == false && isLocal == true && (isRegularFile == true || isDirectory == true) { return "ready" }
        return "unknown"
    }

    static func status(_ value: URLResourceValues) -> String {
        availability(isUbiquitous: value.isUbiquitousItem, downloadingStatus: value.ubiquitousItemDownloadingStatus,
                     hasDownloadError: value.ubiquitousItemDownloadingError != nil, isLocal: value.volumeIsLocal,
                     isRegularFile: value.isRegularFile, isDirectory: value.isDirectory)
    }

    static func promisedValues(_ url: URL, keys: Set<URLResourceKey>) throws -> URLResourceValues {
        // 必须在 immediatelyAvailableMetadataOnly 协调闭包内使用 promised API。
        var fresh = url
        fresh.removeAllCachedResourceValues()
        return try fresh.promisedItemResourceValues(forKeys: keys)
    }

    static func audioName(_ filename: String) -> (name: String, placeholder: Bool)? {
        let placeholder = filename.hasPrefix(".") && (filename as NSString).pathExtension.lowercased() == "icloud"
        let name = placeholder ? String((filename as NSString).deletingPathExtension.dropFirst()) : filename
        guard audioExtensions.contains((name as NSString).pathExtension.lowercased()) else { return nil }
        return (name, placeholder)
    }
}
