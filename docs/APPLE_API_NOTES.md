# Apple API decisions and limitations

Verified against Apple sources, 2026-11-07.

## Folder access

Use `UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)` on iOS/iPadOS. Native macOS can use `NSOpenPanel` with directory-only selection. The folder grant covers descendants.

- https://developer.apple.com/documentation/uikit/providing-access-to-directories
- https://developer.apple.com/videos/play/wwdc2019/719/

Create iOS bookmarks with `.minimalBookmark` and resolve with ordinary options. macOS uses `[.withSecurityScope, .securityScopeAllowOnlyReadAccess]` and resolves with `.withSecurityScope`. The macOS flag must not be compiled into the iOS branch. Start security-scoped access before creating/using the bookmark; balance successful starts/stops and keep access active during playback. Renew stale bookmarks. Failure must offer re-selection rather than assume permanent access.

- https://developer.apple.com/documentation/Foundation/NSURL/BookmarkCreationOptions/withSecurityScope
- https://developer.apple.com/forums/thread/797469

Native macOS entitlements: App Sandbox, user-selected read-only files, app-scoped bookmarks. Avoid read-write and broad Music folder access. No app-owned iCloud container is required by this design, but the minimal signed device target must be validated because older archived picker setup guidance is inconsistent with modern user-selected folder access.

- https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html

## Scanning and download

Use background coordinated access (`NSFileCoordinator`), including metadata/traversal. A remote provider may block. Metadata-only reads should avoid materializing all songs. A download request is not download completion; inspect ubiquitous status and playback readiness.

- https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system
- https://developer.apple.com/documentation/foundation/nsfilecoordinator
- https://developer.apple.com/documentation/foundation/filemanager/startdownloadingubiquitousitem(at:)
- https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/DocumentPickerProgrammingGuide/CreatinganOutstandingUserExperience/CreatinganOutstandingUserExperience.html

Coordinate availability preparation, retain scope and handle later player errors. Merely creating AVPlayerItem inside a coordinator closure does not prove that AVPlayer's subsequent asynchronous reads remain coordinated. Use a file presenter/change handling and validate external mutation scenarios.

## Playback

Use AVURLAsset/AVPlayerItem/AVPlayer against the original URL. Extension recognition identifies candidates, not guaranteed supported codecs. Check playability and item status; report unsupported/corrupt separately from missing. Load embedded metadata/artwork lazily after the selected song is available to avoid downloading every song during indexing.

- https://developer.apple.com/documentation/avfoundation/avplayer
- https://developer.apple.com/documentation/avfoundation/avurlasset/audiovisualcontenttypes
- https://developer.apple.com/documentation/avfoundation/avpartialasyncproperty/isplayable-45h5v

iOS: audio-session playback category, background audio mode, interruptions and route changes. macOS does not use AVAudioSession in the same manner.

- https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback

## Flutter boundary

Flutter platform channels can call Swift code on iOS and macOS. A plain file path is not a persistent permission and must not replace the native folder bookmark layer.

- https://docs.flutter.dev/platform-integration/platform-channels
- https://docs.flutter.dev/platform-integration/ios/apple-frameworks
- https://docs.flutter.dev/platform-integration

Compiling iOS or macOS targets requires macOS/Xcode, including with Flutter.
