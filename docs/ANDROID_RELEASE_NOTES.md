## Cloud Music 0.1.1 (build 2) · Android-only preview

### Changes in 0.1.1

- Fix the Web picker lifecycle so an iPhone browser/provider that returns no selection or cancellation event cannot leave the page buttons permanently grey.
- Default iPhone/iPad Web to selecting multiple music files, with accurate reselection guidance. Desktop folder selection remains available where supported.
- Preserve existing songs/playback on cancellation or unsupported selections, and ignore stale picker results.
- Android is rebuilt from the same corrected source at version 0.1.1+2. Its native folder picker behavior is unchanged.

Download `cloud-music-android-test-signed.apk` below. The universal APK includes ARM64, ARM32 and x86_64 and requires Android 7.0 / API 24 or later. It is intended for phones/tablets and ordinary Android APK head units, not Android Auto.

- Pick a local or USB directory with Android's system picker and play original files without copying a music library into the app.
- Persistent mini-player, full-screen player, artwork/metadata, seeking, shuffle/repeat, responsive landscape layout and refresh.
- Disconnected USB or uncertain provider failures retain existing entries. Refresh never deletes original files.

This package is **debug/test-signed**, not signed with a production identity. A future preview may require uninstall/reinstall. The publishing workflow requires Flutter checks, Android bridge JVM tests, APK signature verification and package/architecture checks to pass before releasing the APK. Physical USB/head-unit playback and background behavior still need device testing. Do not interact with the app while driving.

This release contains **only the Android APK**, not a macOS DMG or an iOS package. macOS packaging is still pending. The Web preview is at https://kingxcode.github.io/cloud-music/ .

Verify the APK against `SHA256SUMS.txt`. `android-signature.txt` and `android-package.txt` record build verification results. Codec availability depends on the device.
