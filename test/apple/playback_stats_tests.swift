import Foundation

@main
struct PlaybackStatsTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
            checks += 1
            let passed = try condition()
            precondition(passed, message)
        }
        func document(_ text: String) throws -> PlaybackStatsDocument {
            try PlaybackStatsDocument(data: Data(text.utf8))
        }
        func rejected(_ action: () throws -> Void) -> Bool {
            do { try action(); return false } catch { return true }
        }
        var merged = try document(#"{"version":1,"counts":{"song":{"mac":4,"phone":2}}}"#)
        let newer = try document(#"{"version":1,"counts":{"song":{"mac":3,"phone":6},"another":{"mac":1}}}"#)
        merged.merge(newer)
        check(merged.counts["song"] == ["mac": 4, "phone": 6], "Merge device counters using maximum")
        check(merged.counts["another"] == ["mac": 1], "Merge distinct tracks")
        merged.merge(newer)
        check(merged.counts["song"] == ["mac": 4, "phone": 6], "Merge is idempotent")
        try check(document(String(data: merged.data(), encoding: .utf8)!) == merged, "Round trip preserves counters")
        for invalid in ["garbage", #"{"version":2,"counts":{}}"#, #"{"version":1,"counts":{"song":{"mac":-1}}}"#,
                        #"{"version":1,"counts":{"song":{"mac":1.5}}}"#, #"{"version":1,"counts":{"song":{"mac":true}}}"#,
                        #"{"version":1,"counts":{"song":{"mac":9007199254740992}}}"#, #"{"version":1,"counts":{"":{"mac":1}}}"#] {
            check(rejected { _ = try document(invalid) }, "Reject invalid or unsupported documents")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("local", isDirectory: true)
        let cloud = root.appendingPathComponent("cloud-fixture", isDirectory: true)
        var cloudEnabled = false
        let store = PlaybackStatsStorage(localDirectory: local, cloudDirectory: { cloudEnabled ? cloud : nil })
        try check(store.read() == nil, "Missing store is absent")
        let device = try store.deviceId()
        try check(store.deviceId() == device, "Device identifier remains stable")
        try check(PlaybackStatsStorage(localDirectory: local, cloudDirectory: { nil }).deviceId() == device, "Device identifier survives new instance")
        let initial = #"{"version":1,"counts":{"song":{"mac":4}}}"#
        try store.write(initial)
        check(store.storageLocation == "local", "Offline playback remains local")
        try check(document(store.read()!) == document(initial), "Offline playback persists")
        cloudEnabled = true
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        let cloudFile = cloud.appendingPathComponent("playback-stats.json")
        try Data(#"{"version":1,"counts":{"song":{"phone":2}}}"#.utf8).write(to: cloudFile)
        let synchronized = try document(store.read()!)
        check(synchronized.counts["song"] == ["mac": 4, "phone": 2], "Reconnect merges cloud and local counters")
        check(store.storageLocation == "icloud", "Successful coordination reports cloud location")
        try check(PlaybackStatsDocument(data: Data(contentsOf: cloudFile)) == synchronized, "Merged result is saved in cloud fixture")
        try store.write(#"{"version":1,"counts":{"song":{"mac":1}}}"#)
        try check(document(store.read()!).counts["song"] == ["mac": 4, "phone": 2], "Older writes never reduce cached counts")

        let corrupt = Data("invalid cloud data".utf8)
        try corrupt.write(to: cloudFile)
        check(rejected { _ = try store.read() }, "Corrupt cloud document is reported")
        check(rejected { try store.write(#"{"version":1,"counts":{"song":{"mac":5}}}"#) }, "Corrupt cloud blocks replacement")
        try check(Data(contentsOf: cloudFile) == corrupt, "Corrupt cloud content is preserved")
        let localFile = local.appendingPathComponent("playback-stats.json")
        try check(PlaybackStatsDocument(data: Data(contentsOf: localFile)).counts["song"]?["mac"] == 5, "Cloud error retains new local play")
        cloudEnabled = false
        let blockedCloud = root.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: blockedCloud)
        let disconnected = PlaybackStatsStorage(localDirectory: local, cloudDirectory: { blockedCloud })
        try check(document(disconnected.read()!).counts["song"]?["mac"] == 5, "Transient cloud failure falls back to local read")
        try disconnected.write(#"{"version":1,"counts":{"song":{"mac":6}}}"#)
        try check(document(disconnected.read()!).counts["song"]?["mac"] == 6, "Transient cloud failure retains new local writes")
        check(disconnected.storageLocation == "local", "Transient failure reports local location")
        let firstOffline = PlaybackStatsStorage(localDirectory: root.appendingPathComponent("first-offline"), cloudDirectory: { blockedCloud })
        try check(firstOffline.read() == nil, "First offline read is an absent local baseline")
        try firstOffline.write(initial)
        try check(document(firstOffline.read()!) == document(initial), "First offline play is durably saved")
        try corrupt.write(to: localFile)
        check(rejected { try store.write(initial) }, "Corrupt local document blocks replacement")
        try check(Data(contentsOf: localFile) == corrupt, "Corrupt local content is preserved")

        let personalLocal = root.appendingPathComponent("personal-local", isDirectory: true)
        let personalFolder = root.appendingPathComponent("personal-icloud-fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: personalFolder, withIntermediateDirectories: true)
        let personalFile = personalFolder.appendingPathComponent("playback-stats.json")
        let personalStore = PlaybackStatsStorage(localDirectory: personalLocal)
        try check(personalStore.read() == nil, "Default personal setup stays local without a selected folder")
        try check(personalStore.selectFolder(personalFolder), "Confirming a personal folder succeeds without developer container")
        check(personalStore.storageLocation == "folder", "Personal folder reports distinct storage location")
        try check(PlaybackStatsDocument(data: Data(contentsOf: personalFile)).counts.isEmpty, "Connecting an empty folder immediately validates a writable statistics file")
        try personalStore.write(initial)
        try check(PlaybackStatsDocument(data: Data(contentsOf: personalFile)).counts["song"]?["mac"] == 4, "Personal folder receives playback counters")
        let bookmarkURL = personalLocal.appendingPathComponent("playback-stats-folder.bookmark")
        let savedBookmark = try Data(contentsOf: bookmarkURL)
        try check(!personalStore.selectFolder(nil), "Cancelled folder selection reports false")
        try check(Data(contentsOf: bookmarkURL) == savedBookmark, "Cancelled selection preserves folder authorization")
        let restored = PlaybackStatsStorage(localDirectory: personalLocal)
        try check(document(restored.read()!).counts["song"]?["mac"] == 4, "Selected folder authorization restores after restart")
        check(restored.storageLocation == "folder", "Restored selection keeps personal-folder location")
        try Data(#"{"version":1,"counts":{"song":{"phone":3}}}"#.utf8).write(to: personalFile)
        try check(document(restored.read()!).counts["song"] == ["mac": 4, "phone": 3], "Personal folder merges incoming device changes")

        let invalidFolder = root.appendingPathComponent("invalid-personal-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidFolder, withIntermediateDirectories: true)
        let invalidFile = invalidFolder.appendingPathComponent("playback-stats.json")
        try corrupt.write(to: invalidFile)
        check(rejected { try restored.selectFolder(invalidFolder) }, "Invalid new folder fails without changing selected folder")
        try check(Data(contentsOf: bookmarkURL) == savedBookmark, "Failed selection keeps prior bookmark")
        try check(Data(contentsOf: invalidFile) == corrupt, "Failed selection preserves invalid remote contents")
        try FileManager.default.removeItem(at: personalFolder)
        try check(document(restored.read()!).counts["song"] == ["mac": 4, "phone": 3], "Unavailable selected folder falls back to durable local counters")
        check(restored.storageLocation == "local", "Unavailable selected folder reports local fallback")
        try restored.write(#"{"version":1,"counts":{"song":{"mac":5}}}"#)
        try check(document(restored.read()!).counts["song"]?["mac"] == 5, "New plays remain durable while selected folder is unavailable")
        check(!FileManager.default.fileExists(atPath: personalFolder.path), "Unavailable selected folder is never silently recreated")
        try FileManager.default.createDirectory(at: personalFolder, withIntermediateDirectories: true)
        try Data(#"{"version":1,"counts":{"song":{"phone":5}}}"#.utf8).write(to: personalFile)
        try check(document(restored.read()!).counts["song"] == ["mac": 5, "phone": 5], "Selected folder reconnect merges offline counters")
        check(restored.storageLocation == "folder", "Reconnected personal folder resumes saving")
        try check(FileManager.default.contentsOfDirectory(atPath: personalFolder.path) == ["playback-stats.json"], "Only playback statistics are placed in the selected folder")
        print("Passed \(checks) playback statistics checks (local fixtures; no iCloud account).")
    }
}
