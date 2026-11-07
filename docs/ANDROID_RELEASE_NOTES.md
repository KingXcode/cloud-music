## Cloud Music 0.2.0 (build 3) · Android-only preview

### Lyrics download and display

- Search LRCLIB after reviewing and confirming the song title, artist and optional album. No automatic searches or audio uploads.
- Select the matching version before saving lyrics locally. Artist, album, duration and synchronized/plain/instrumental status are shown; duration mismatches are flagged.
- Synchronized LRC highlighting and follow-scroll, tap a line to seek, and plain-text/instrumental fallback.
- Import UTF-8 `.lrc` / `.txt` through the system picker, or paste text. Accepted lyrics remain available offline in app-owned cache; originals are never changed.
- Open the full player and tap the top-right lyrics icon. Errors and cancellations preserve existing lyrics; stale responses cannot attach to another song or source.

Downloaded lyrics use a bounded **in-app cache**, not files written next to your music. The cache keeps up to approximately 2 MiB / 100 songs. Lyrics may be inaccurate and copyrighted; download only when permitted. The LRCLIB server's software license does not establish a blanket lyric-content license. See [lyrics usage, privacy and rights limits](https://github.com/KingXcode/cloud-music/blob/main/docs/LYRICS.md).

Download `cloud-music-android-test-signed.apk` below. The universal APK includes ARM64, ARM32 and x86_64 and requires Android 7.0 / API 24 or later. It is intended for phones/tablets and ordinary Android APK head units, not Android Auto.

- Pick a local or USB directory and play originals without copying a music library into the app.
- Persistent mini-player, full-screen player, artwork/metadata, seeking, shuffle/repeat, responsive landscape layout and refresh.
- Disconnected USB or uncertain provider failures retain existing entries. Refresh never deletes original files.

This package is **debug/test-signed**, not signed with a production identity. A future preview may require uninstall/reinstall. The publishing workflow requires Flutter checks, Android bridge JVM tests, APK signature verification and package/architecture checks to pass before releasing the APK. Physical USB/head-unit playback, lyrics picker and background behavior still need device testing. Do not interact with the app while driving.

This release contains **only the Android APK**, not a macOS DMG or an iOS package. macOS packaging remains pending. The Web preview is at https://kingxcode.github.io/cloud-music/ .

Verify the APK against `SHA256SUMS.txt`. `android-signature.txt` and `android-package.txt` record build verification results. Codec availability depends on the device.
