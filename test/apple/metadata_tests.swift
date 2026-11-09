import Foundation

@main
struct MetadataTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        func status(_ ubiquitous: Bool?, _ download: URLUbiquitousItemDownloadingStatus?, error: Bool = false,
                    local: Bool? = true, file: Bool? = true, directory: Bool? = false) -> String {
            CloudFileMetadata.availability(isUbiquitous: ubiquitous, downloadingStatus: download, hasDownloadError: error,
                                           isLocal: local, isRegularFile: file, isDirectory: directory)
        }
        check(status(true, .notDownloaded) == "cloud", "Undownloaded iCloud item")
        check(status(true, .current) == "ready", "Current iCloud item")
        check(status(true, .downloaded) == "ready", "Resident iCloud item")
        check(status(true, nil) == "unknown", "Missing download status is not proof of download")
        check(status(nil, nil) == "unknown", "Missing provider identity is unknown")
        check(status(false, nil) == "ready", "Confirmed local regular file")
        check(status(false, nil, local: nil) == "unknown", "Missing volume info")
        check(status(false, nil, local: false) == "unknown", "Remote provider")
        check(status(true, .current, error: true) == "offline", "Download error wins")
        check(status(false, nil, file: nil, directory: nil) == "unknown", "Unknown item type")
        check(CloudFileMetadata.audioName(".Song.mp3.icloud")?.name == "Song.mp3", "Legacy placeholder name")
        check(CloudFileMetadata.audioName(".Song.mp3.icloud")?.placeholder == true, "Legacy placeholder status")
        check(CloudFileMetadata.audioName("Song.M4A")?.placeholder == false, "Case-insensitive extension")
        check(CloudFileMetadata.audioName(".Notes.txt.icloud") == nil, "Non-audio placeholder")
        check(CloudFileMetadata.audioName("Song.mp3.icloud") == nil, "Do not invent a legacy placeholder")
        // Real Foundation metadata-only API on an ordinary local file. This does not simulate iCloud.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Song.mp3")
        try Data().write(to: file)
        var coordinationError: NSError?
        var result: Result<URLResourceValues, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: file, options: .immediatelyAvailableMetadataOnly, error: &coordinationError) { target in
            result = Result { try CloudFileMetadata.promisedValues(target, keys: [.isRegularFileKey]) }
        }
        if let error = coordinationError { throw error }
        let values = try result!.get()
        check(values.isRegularFile == true, "Promised metadata API in coordinated accessor")
        print("Passed \(checks) Apple metadata checks (local file only; no iCloud account).")
    }
}
