## Cloud Music preview

Original-file folder music player with a library, persistent mini-player and dedicated now-playing screen.

- Android: select local or USB folders with the system picker; permission is persisted when the provider supports it. The APK uses standard debug/test signing, not a production signing identity. Future builds may require uninstalling this preview before installation.
- macOS: select a folder, including iCloud Drive, with scoped bookmark access. The DMG is unsigned and the app is not Developer ID signed/notarized. A local ad-hoc signature may be present. See macos-architectures.txt for actual build architectures.
- Web: local playback without uploading audio. Supported browsers can remember a directory handle; browsers without that capability ask for a folder when needed. Access permission can expire or be revoked.
- iOS/iPadOS source is included. No signed iOS install package is supplied.

The application stores folder permission and metadata, not a copied audio library. iCloud/File Provider may download originals into system-managed storage. Refresh never deletes source files. Offline/provider errors and disconnected USB devices are not treated as confirmed deletions.

This is a preview, not a device-certified production release. Passing CI establishes compilation, automated tests and package checks; it does not establish real iCloud account access, USB behavior on every head unit, hardware audio output or uninterrupted background playback on all devices. Do not use the UI while driving.

APK and DMG SHA-256 hashes are in SHA256SUMS.txt. Audio format support depends on each platform's codecs.
