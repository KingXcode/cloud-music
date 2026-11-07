# Apple bridge verification notes

Implemented against the app's `docs/BRIDGE_CONTRACT.md`, targeting iOS 15 and macOS 12. Flutter channels are `cloud_music/control` and `cloud_music/events`.

## Storage and access

- System directory picker opens the original folder, without importing/copying songs.
- iOS uses minimal bookmarks; macOS uses read-only security-scoped bookmarks. Successful security-scope starts are balanced and scope stays alive during preparation/playback.
- The only persisted file is the app-owned Application Support/CloudMusic/library.json (bookmark, metadata, preferences). No audio is persisted by this code.
- Background coordinated listings use `.immediatelyAvailableMetadataOnly` (not `.withoutChanges`); symlink directories are not traversed. Startup retains missing entries. Refresh removes references only after a successful parent listing plus a direct Cocoa not-found result. Errors/cloud placeholders retain old entries. Known-offline ubiquitous roots cannot establish deletion.
- iCloud downloads are system-managed and still use device storage. Cancel stops waiting and invalidates pending player operations, but does not delete/cancel Apple's cached download.
- Provider coordination itself may block. Concurrent background work and generation tokens let new playback/source requests proceed without accepting stale results.

## Playback

AVPlayer uses original URLs with a file presenter for external writes/moves/deletions. Metadata and bounded artwork are loaded only for selected songs. Queue controls, shuffle, repeat, seek, volume, iOS background audio, interruption/route handling and system media commands are implemented. Decode failures are not treated as file deletions.

## Packaging

SwiftPM processes PrivacyInfo.xcprivacy; CocoaPods includes it as a resource bundle. This implementation does not use UserDefaults, file timestamps, disk-space APIs or other required-reason APIs; the manifest declares no collected data or tracking. Reassess if additional SDKs/APIs are added. macOS Runner has app sandbox, user-selected read-only and app-scoped bookmark entitlements. iOS Runner has audio background mode, with no app-owned iCloud container entitlement.

## Verification status

Static source review and XML/plist parsing completed in Linux. No Swift compiler, Apple SDK, Xcode, code signing or physical device was available in this workspace. This is **not yet a verified Apple build**. Run hosted macOS CI and then the complete device matrix in `docs/REQUIREMENTS.md`, particularly third-party provider/offline enumeration, stale/revoked grants, externally renamed playing files, interruption during download, cancellation/reselection and real iCloud placeholder behavior. A successful unsigned CI build cannot establish signed iCloud access or audio-route correctness.

Known boundaries: artwork larger than 2 MB is omitted; no crossfade/equalizer; paused files retain their grant until playback/source replacement; bookmarks/index are local to this app installation, not synced across devices. No downloaded binary is code-signed or notarized by this source alone.

## Coordination correction and deletion safeguards

Apple explicitly documents [immediatelyAvailableMetadataOnly](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/immediatelyavailablemetadataonly) as avoiding download/materialization. [withoutChanges](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/withoutchanges) only suppresses presenter-save requests and must not be used as a substitute. All indexing, absence checks and download-status polling now use the former, clear cached URL metadata, and register their coordinator with the operation's cancellation token. Explicit iCloud download initiation is separate from metadata-only coordination; A separate selected-song-only normal coordinated read intentionally permits provider materialization (important for non-iCloud providers). AVPlayer still reads the coordinator-provided original URL with the registered presenter; the preparation deadline cancels this coordinator too.

Cancellation calls [NSFileCoordinator.cancel](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel()), and a 15-second per-coordination timer cancels presenter waits. Independent main-thread deadlines end playback preparation after 90 seconds and scans after 180 seconds, retain the old index, and ignore late completions. Apple documents that cancellation cannot abort an already-executing accessor. A stuck provider syscall may therefore retain a background worker/scope until it returns, but cannot keep the UI loading indefinitely or install a stale player. The application does not claim to forcibly interrupt arbitrary OS provider calls.

Refresh now persists/checks source volume UUID, uses macOS bookmark resolution without remounting, compares root identity before/after scanning, re-lists an unchanged nonempty parent before confirming an absent child, and refuses pruning on unknown identity, unavailable network, remote volume, any uncertain ancestor or unexpectedly empty subtree. Network loss during a scan discards pending reconciliation. This deliberately retains a final removed song when its formerly populated subtree becomes completely empty; that case is indistinguishable from an incomplete provider view at this layer. Reselecting the folder rebuilds the list explicitly. Legacy indexes first learn volume identity without pruning. Provider/device tests are still required.
