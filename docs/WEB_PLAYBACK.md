# Browser playback and privacy

The production browser adapter is `lib/gateway/web_music_gateway.dart`, backed by `web/music_gateway.js`. `web/index.html` loads the helper before Flutter. No audio is uploaded, copied into app storage, cached in IndexedDB, or transcoded. The selected original `File` is handed to an HTML audio element by a temporary Blob URL. URLs are revoked on source replacement, cancellation and disposal.

## Folder persistence

- Chromium browsers with File System Access support (secure HTTPS / localhost) save the read-only `FileSystemDirectoryHandle` in IndexedDB. Track metadata and player preferences are saved separately in localStorage.
- Startup returns saved metadata immediately, retrieves the handle, and calls **queryPermission only**. A valid grant restores and scans the original folder without requiring selection again. A prompt/denied grant shows a Chinese action message. Clicking Refresh calls requestPermission in the user gesture and scans when granted.
- The browser, privacy mode and site-data clearing may prevent persisted grants or storage. If there is no usable saved handle, reselection is needed. A mounted folder handle does not prove that all underlying cloud file bytes are downloaded.
- iPhone/iPad use a multiple-file input by default. Open the music folder inside the system Files picker and select the audio files. This works around differences between iOS versions and file providers; it is not a claim that every recent iOS browser lacks directory-input support. Browsers without either directory API/input also use this route.
- Other browsers without the directory picker use `input[webkitdirectory]`. File references live for the tab session only; reload requires reselection. The app does not gain persistent iCloud directory access through either fallback.
- The fallback command returns immediately after opening the system picker. `change`/`cancel` are handled separately: an absent event can no longer leave the Flutter buttons permanently disabled. Another explicit click replaces an abandoned input; stale results are ignored. Cancel, empty selection and selection without recognized audio preserve the current library/playback. No automatic alternate picker is opened after a security denial.
- A successful selection updates the library without waiting for IndexedDB; failed/unresponsive storage cannot freeze the file-selection flow. The operating system may first download cloud originals. If the provider returns no files, retry and check availability in the Files app.

## Conservative scanning and playback

Only file paths/handles are enumerated during a handle-based scan; audio is read lazily by `getFile()` for the chosen track. A discovered file is marked `unknown` until successful retrieval, not misleadingly cloud-ready/offline. Startup marks corroborated absent paths missing. Explicit refresh removes paths only after error-free enumeration, repeated direct parent lookup returning NotFound, a granted root permission, and successful reopening of another listed sibling in the same parent. Empty folders, absent parent folders, disconnected providers and any enumeration error retain unknown entries, since the browser offers no definitive mount-health API. A playback NotFound alone is unknown, not evidence of deletion. Failed subtrees retain their old entries. A root failure preserves the entire prior library. Decoder errors are retained as unsupported songs rather than deleted.

The browser supports queue advance/previous, seek, volume, repeat one/all/off and shuffle with history. Shuffle visits each eligible song once and stops with repeat off; repeat all begins a fresh cycle; repeat one affects automatic completion only. New play, pause, cancel and dispose invalidate pending file reads. Browser autoplay and codec restrictions remain applicable and are reported to the user. Embedded artist, album and artwork tags are not parsed by this browser adapter; filenames provide titles.

## Validation

`node --test test/web/music_gateway_test.cjs` exercises twenty-five deterministic adapter cases: persisted handle restore without prompts, permission denial, startup/refresh missing references, failed subtree preservation, picker cancellation, cancellation during file retrieval, Blob URL cleanup playback settings, corroborated deletion/provider failure, gesture timing, fallback cancellation, shuffle exhaustion/cycling stale preparation suppression, synchronous picker invocation distinct security-policy errors, iPhone/iPad multiple-file mode, absent picker events/retry, stale selection suppression, duplicate filenames, unsupported-file preservation and unresponsive storage. These use controlled browser API doubles, not real cloud downloads or manual permission dialogs.

`flutter analyze lib/gateway/web_music_gateway.dart` verifies the Dart JS interop wrapper.

Manual browser acceptance checklist:

1. Serve the release build at HTTPS or localhost. Choose a folder with two real playable files and nested subfolders. Check playback, previous/next, seeking and volume.
2. In supported Chromium, grant persistent access if offered; reload and confirm the library restores with no picker. Revoke the grant in browser settings, reload, then click Refresh and grant access.
3. Cancel a fresh picker and confirm existing songs/current playback remain. On desktop Firefox/Safari confirm the fallback folder selection and honest reselection prompt after reload. On iPhone/iPad confirm “选择音乐文件（可多选）”, open a folder in Files, select multiple real audio files and play them. Dismiss/cancel, retry, select unsupported files and reload: buttons must remain usable, cancellation must preserve songs, and reload must explain reselection. Physical iPhone/iCloud provider verification remains required.
4. Remove one file and reload: it should appear missing. With a healthy sibling still present, explicit Refresh should remove that entry. If the folder is completely empty, the browser conservatively retains unknown references. Disconnect a whole disk and refresh: retain the library with a warning.
5. Play a large/cloud-placeholder file, cancel while loading, then select a different track. No stale playback should begin. Confirm unsupported codecs report a recoverable error.
6. Inspect network/storage: no audio requests to a server, no stored audio blobs, only folder handle plus text metadata/preferences. Browser/OS providers may independently fetch cloud originals outside this app.

### Picker diagnostics

The UI/controller/interop path invokes `showDirectoryPicker` without an earlier await. The adapter tests assert synchronous picker invocation. A `SecurityError` is presented distinctly from `NotAllowedError`: it can reflect missing transient activation, a restricted origin/embedding context or browser policy, and must not be described as the user refusing file permission. Remote/automated browser behavior is not proof of ordinary desktop Chrome behavior. No automatic alternate picker is attempted after a security denial.

### iPhone grey-button correction (0.1.1)

The previous fallback awaited a promise settled only by input `change` or `cancel`. If the browser/provider returned neither event, the controller stayed busy forever, matching the reported disabled main button. The fix removes that dependency and defaults Apple mobile browsers to file multiselect. Automated coverage demonstrates the missing-event recovery and selection lifecycle, not successful interaction with a real iPhone Files sheet or cloud provider.

Relevant platform references: [WebKit iOS directory-input issue](https://bugs.webkit.org/show_bug.cgi?id=271705), [MDN directory inputs](https://developer.mozilla.org/en-US/docs/Web/API/HTMLInputElement/webkitdirectory), and [MDN showDirectoryPicker](https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker). Recent Safari directory-input improvements do not provide persistent `showDirectoryPicker` permissions.
