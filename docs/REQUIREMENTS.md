# Cloud Music: implementation brief

Working title only. Flutter is confirmed by the user. Android local/USB access and Web playback are included.

## Requested experience

- iPhone, iPad and macOS music player.
- At first use, select a folder in iCloud Drive using Apple's system folder picker.
- Remember the permission using a security-scoped folder bookmark. Do not import/copy audio into the app sandbox.
- List supported audio candidates recursively. Tapping a row starts that exact track.
- On launch, verify previously indexed tracks and mark unavailable/missing references without silently deleting the list.
- Manual Refresh rescans, adds newly discovered tracks and removes confirmed-missing references only. Never remove source files.
- Keep cloud placeholders, download failures, offline files, permission failures and incomplete scans distinct from deleted files.
- Persistent bottom mini-player opens a dedicated now-playing screen: artwork, title/artist, playback progress/seeking, previous/next, play/pause, shuffle and repeat.
- Responsive iPhone, iPad and Mac layouts.
- Future vehicle target is a normal Android head unit installing an APK, not Android Auto. Plan for landscape and large touch targets, with an independent Android file source. Direct Android iCloud access is not promised.

## Proposed portable architecture

A Flutter presentation layer can use a typed library/playback gateway. The Apple gateway owns folder picking, bookmark persistence, security scope lifetimes, coordinated scanning, iCloud download preparation and AVFoundation playback. A future Android implementation replaces that gateway instead of trying to reinterpret an Apple bookmark.

Only index metadata, bookmark credentials and preferences belong in application support. User songs remain at their selected URLs. iCloud downloads use Apple's managed storage and therefore still consume device disk space.

## Conservative refresh policy

1. Resolve the folder bookmark and renew it if stale.
2. Acquire scoped access before scanning. If permission or folder access fails, retain the complete prior list and offer re-selection.
3. Enumerate with coordinated metadata-only reads on a background queue; recognize undownloaded placeholders without forcing every song to download.
4. Record coverage and errors per parent directory. A failed/incomplete directory does not prove any previous child was deleted.
5. Preserve existing tracks with transient, cloud-only, download or codec errors. Mark their availability separately.
6. Only treat an old path as missing after a successful coordinated parent listing and an explicit not-found check, with no known cloud/provider uncertainty affecting that parent.
7. On startup, mark missing entries. On explicit Refresh, remove only those confirmed-missing entries from the index.
8. Reconcile playback if the current reference disappears. Never call delete, move, copy or write APIs on the source folder.

## Required device checks

- Pick iCloud folder, nested folder, Unicode filenames and duplicate basenames.
- Cancel initial picker; cancel replacement picker; change folder while playing.
- Relaunch app and reboot device; renew stale bookmark; revoke access and reselect.
- Tap track B while track A is still downloading; only B may become active.
- Download cloud-only song; show waiting/error and allow cancellation.
- Offline launch/refresh must not clear a populated library.
- Incomplete listing and provider error must retain affected entries.
- Move/rename/delete song externally during playback and between launches.
- Startup marks missing; explicit refresh removes references but does not delete songs.
- Unsupported/damaged audio remains distinguishable from missing source.
- Background audio, interruption, unplug headphones and route changes on iOS.
- Full player and mini-player stay synchronized; seek and repeated controls do not produce stale state.
- iPhone compact width, iPad split screen, wide and narrow Mac window.
- Confirm application support contains only index/bookmark/settings, not copied audio.

## Current verification environment

The user's Mac is reported offline. Cloud workspace has Flutter 3.47.5 / Dart 3.13.4, verified using its existing isolated toolchain activation with BOT=true and analytics suppressed. No Xcode or Swift executable is available. Dart/static/widget checks are possible; Apple compilation, code signing, iCloud access and real audio-device tests require a Mac and physical signed-in Apple devices.

## Delivery requested

Create a new GitHub repository after visibility is confirmed, publish a test-signed Android APK and unsigned/non-notarized macOS DMG to Releases, and deploy Web to GitHub Pages. Browser should remember the last folder when supported and ask for permission/reselection only when needed. A GitHub-hosted macOS runner can perform Apple compilation even while the local Mac is offline.
