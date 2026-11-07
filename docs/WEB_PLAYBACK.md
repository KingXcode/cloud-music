# Browser playback and privacy

The production browser adapter is `lib/gateway/web_music_gateway.dart`, backed by `web/music_gateway.js`. `web/index.html` loads the helper before Flutter. No audio is uploaded, copied into app storage, cached in IndexedDB, or transcoded. The selected original `File` is handed to an HTML audio element by a temporary Blob URL. URLs are revoked on source replacement, cancellation and disposal.

## Folder persistence

- Chromium browsers with File System Access support (secure HTTPS / localhost) save the read-only `FileSystemDirectoryHandle` in IndexedDB. Track metadata and player preferences are saved separately in localStorage.
- Startup returns saved metadata immediately, retrieves the handle, and calls **queryPermission only**. A valid grant restores and scans the original folder without requiring selection again. A prompt/denied grant shows a Chinese action message. Clicking Refresh calls requestPermission in the user gesture and scans when granted.
- The browser, privacy mode and site-data clearing may prevent persisted grants or storage. If there is no usable saved handle, reselection is needed. A mounted folder handle does not prove that all underlying cloud file bytes are downloaded.
- Browsers without the directory picker use `input[webkitdirectory]`. File references live for the tab session only; reload/refresh requires selecting the folder again. Cancellation preserves the current library. Very old browsers without the input `cancel` event may require a reload after cancelling the fallback picker; current Chrome/Firefox/Safari support it.

## Conservative scanning and playback

Only file paths/handles are enumerated during a handle-based scan; audio is read lazily by `getFile()` for the chosen track. A discovered file is marked `unknown` until successful retrieval, not misleadingly cloud-ready/offline. Startup marks corroborated absent paths missing. Explicit refresh removes paths only after error-free enumeration, repeated direct parent lookup returning NotFound, a granted root permission, and successful reopening of another listed sibling in the same parent. Empty folders, absent parent folders, disconnected providers and any enumeration error retain unknown entries, since the browser offers no definitive mount-health API. A playback NotFound alone is unknown, not evidence of deletion. Failed subtrees retain their old entries. A root failure preserves the entire prior library. Decoder errors are retained as unsupported songs rather than deleted.

The browser supports queue advance/previous, seek, volume, repeat one/all/off and shuffle with history. Shuffle visits each eligible song once and stops with repeat off; repeat all begins a fresh cycle; repeat one affects automatic completion only. New play, pause, cancel and dispose invalidate pending file reads. Browser autoplay and codec restrictions remain applicable and are reported to the user. Embedded artist, album and artwork tags are not parsed by this browser adapter; filenames provide titles.

## Validation

`node --test test/web/music_gateway_test.cjs` exercises eighteen deterministic adapter cases: persisted handle restore without prompts, permission denial, startup/refresh missing references, failed subtree preservation, picker cancellation, cancellation during file retrieval, Blob URL cleanup playback settings, corroborated deletion/provider failure, gesture timing, fallback cancellation, shuffle exhaustion/cycling stale preparation suppression, synchronous picker invocation and distinct security-policy errors. These use controlled browser API doubles, not real cloud downloads or manual permission dialogs.

`flutter analyze lib/gateway/web_music_gateway.dart` verifies the Dart JS interop wrapper.

Manual browser acceptance checklist:

1. Serve the release build at HTTPS or localhost. Choose a folder with two real playable files and nested subfolders. Check playback, previous/next, seeking and volume.
2. In supported Chromium, grant persistent access if offered; reload and confirm the library restores with no picker. Revoke the grant in browser settings, reload, then click Refresh and grant access.
3. Cancel a fresh picker and confirm existing songs/current playback remain. In Firefox/Safari confirm the fallback folder selection and honest reselection prompt after reload.
4. Remove one file and reload: it should appear missing. With a healthy sibling still present, explicit Refresh should remove that entry. If the folder is completely empty, the browser conservatively retains unknown references. Disconnect a whole disk and refresh: retain the library with a warning.
5. Play a large/cloud-placeholder file, cancel while loading, then select a different track. No stale playback should begin. Confirm unsupported codecs report a recoverable error.
6. Inspect network/storage: no audio requests to a server, no stored audio blobs, only folder handle plus text metadata/preferences. Browser/OS providers may independently fetch cloud originals outside this app.

### Picker diagnostics

The UI/controller/interop path invokes `showDirectoryPicker` without an earlier await. The adapter tests assert synchronous picker invocation. A `SecurityError` is presented distinctly from `NotAllowedError`: it can reflect missing transient activation, a restricted origin/embedding context or browser policy, and must not be described as the user refusing file permission. Remote/automated browser behavior is not proof of ordinary desktop Chrome behavior. No automatic alternate picker is attempted after a security denial.
