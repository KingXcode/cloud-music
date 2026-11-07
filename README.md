# 云听 · Cloud Music

A Flutter original-file music player for iPhone, iPad, macOS, Android (including ordinary APK-based head units), and the browser.

## What it does

- Choose an iCloud Drive folder on Apple devices, or a local/USB directory through Android's system picker.
- Keep permission and a metadata index; play original URLs/URIs instead of copying songs into the app's sandbox.
- Restore folder bookmarks / persisted Android SAF permission. Browser directory handles are remembered when supported and permitted; other browsers request reselection when necessary.
- Library with search, availability labels and explicit refresh.
- Persistent mini-player and a full player with artwork fallback, metadata, seek, previous/next, play/pause, shuffle, repeat and volume.
- Adaptive compact/landscape/wide layouts and larger touch targets. This is **not Android Auto**. Do not interact with the app while driving.
- Startup validates known tracks; refresh discovers new songs and removes only confirmed-missing references. Offline iCloud, provider errors, revoked permissions and disconnected USB do not clear the library. Source files are never deleted.

## Important boundaries

Audio is never uploaded. Browser audio is played through temporary Blob URLs. Apple iCloud/File Provider can download originals into system-managed device storage, so playback is not zero-storage streaming. The app stores metadata and access credentials only.

Supported formats depend on AVFoundation, Android codecs and the browser. Filename extensions are discovery hints, not codec guarantees. Native artwork/metadata is loaded lazily for the selected song; the Web version currently uses filenames and fallback artwork.

This repository is an early working implementation. Automated tests do not replace physical iCloud/USB/head-unit/background audio tests. See platform implementation notes and `docs/REQUIREMENTS.md` for acceptance checks.

## Run locally

Use Flutter **3.47.5** (Dart 3.13.4), then:

```sh
flutter pub get
flutter analyze
flutter test
node --test test/web/music_gateway_test.cjs
flutter run -d chrome
```

For a local browser folder picker, serve through localhost or HTTPS. Chrome/Edge desktop have the most complete persistent File System Access support. A folder-input fallback is available in other compatible browsers. See `docs/WEB_PLAYBACK.md`.

```sh
flutter run -d macos       # macOS + Xcode required
flutter run -d ios         # choose a signed iPhone/iPad or simulator device ID
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
flutter build macos --release
bash scripts/package_macos.sh
```

Android minimum API 24. Apple plugin targets iOS 15 / macOS 12 or later. Physical Apple testing requires the appropriate signing setup and an iCloud account. iOS source is included; no signed iOS package is provided.

The release Android configuration currently uses the standard debug/test signing key. It is deliberately labeled test-signed; replace with a properly managed production key before public production distribution. New CI runs may use a different key and require reinstalling this preview.

## GitHub delivery

- `Deploy Web to GitHub Pages`: validates, builds and deploys the browser app when main is pushed or manually dispatched. The Pages base path follows the repository name. The repository must support Pages and allow the workflow permissions.
- `Build APK and macOS DMG`: manually dispatch with a new preview tag. Linux builds the universal APK; hosted macOS compiles the app and creates the DMG. It verifies APK signatures/package contents, checks the app executable/signature, verifies the DMG, writes SHA-256 checksums and publishes a prerelease only after both native jobs succeed.
- The macOS DMG is unsigned and the app is not Developer ID signed/notarized. A local ad-hoc signature may be present. The release reports actual CPU architectures.

No certificates, production signing keys or user music are stored in this repository.

## Code map

- `lib/ui/`: responsive Flutter library and player.
- `lib/music_controller.dart`, `lib/models.dart`: typed presentation state and command handling.
- `lib/gateway/`: native channel adapter and browser bridge.
- `packages/folder_audio/darwin/`: shared Swift bookmark, coordination, iCloud and AVPlayer implementation.
- `packages/folder_audio/android/`: SAF scanner, original-URI player and foreground media service.
- `web/music_gateway.js`: browser handle persistence and local audio playback.
- `docs/BRIDGE_CONTRACT.md`: platform interface.

## Validation status at source delivery

Passed in the cloud workspace: Flutter analyzer, 16 unit/widget tests (including compact/landscape/wide and large-text layouts), 16 browser logic tests, JavaScript syntax check and Web release build. Native Android/macOS builds and package checks are performed by the GitHub release workflow; inspect its actual result rather than assuming a source-only pass proves compilation. Real-device access/playback tests remain separate.
