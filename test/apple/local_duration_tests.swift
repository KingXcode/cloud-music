import Foundation

@main
struct LocalDurationTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        check(LocalAudioDuration.needsRead(status: "ready", durationMs: 0), "Resident unplayed song needs duration")
        check(!LocalAudioDuration.needsRead(status: "ready", durationMs: 1234), "Keep cached duration")
        for status in ["cloud", "unknown", "offline", "missing", "unsupported", "loading"] {
            check(!LocalAudioDuration.needsRead(status: status, durationMs: 0), "Do not read \(status) files")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // 真实 PCM WAV：单声道、8 kHz、16 bit、1.25 秒，无需创建 AVPlayer。
        var wav = Data()
        func text(_ value: String) { wav.append(contentsOf: value.utf8) }
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        text("RIFF"); word(UInt32(20036)); text("WAVEfmt "); word(UInt32(16))
        word(UInt16(1)); word(UInt16(1)); word(UInt32(8000)); word(UInt32(16000))
        word(UInt16(2)); word(UInt16(16)); text("data"); word(UInt32(20000))
        wav.append(Data(count: 20000))
        let file = root.appendingPathComponent("unplayed.wav")
        try wav.write(to: file)
        // 模拟文件提供器明确报告已驻留（macOS 本地卷可能省略云端属性）；
        // 音频仍由真实文件协调和 AVFoundation 读取。
        let duration = LocalAudioDuration.read(file, cancelled: { false }, isResident: { _ in true })
        check(duration.map { abs($0 - 1250) <= 1 } == true, "Read actual unplayed WAV duration: \(String(describing: duration))")
        for download in [URLUbiquitousItemDownloadingStatus.notDownloaded, nil] {
            let value = LocalAudioDuration.read(file, cancelled: { false }, isResident: { _ in
                CloudFileMetadata.availability(isUbiquitous: true, downloadingStatus: download,
                    hasDownloadError: false, isLocal: true, isRegularFile: true, isDirectory: false) == "ready"
            })
            check(value == nil, "Skip cloud/unknown residency even for parseable audio")
        }
        check(LocalAudioDuration.read(file, cancelled: { true }) == nil, "Cancelled batch does not read")
        var residencyChecks = 0
        let evicted = LocalAudioDuration.read(file, cancelled: { false }, isResident: { _ in
            residencyChecks += 1
            return residencyChecks == 1
        })
        check(evicted == nil && residencyChecks == 2, "Recheck and skip a file evicted after admission")
        let invalid = root.appendingPathComponent("invalid.mp3")
        try Data("not audio".utf8).write(to: invalid)
        check(LocalAudioDuration.read(invalid, cancelled: { false }, isResident: { _ in true }) == nil, "Corrupt audio remains unknown")
        check(LocalAudioDuration.read(root, cancelled: { false }) == nil, "Do not parse directories")
        check(LocalAudioDuration.read(root.appendingPathComponent("missing.mp3"), cancelled: { false }) == nil, "Missing file is harmless")
        let link = root.appendingPathComponent("link.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        check(LocalAudioDuration.read(link, cancelled: { false }) == nil, "Do not follow symbolic links")
        print("Passed \(checks) local duration checks (real WAV; no playback or iCloud account).")
    }
}
