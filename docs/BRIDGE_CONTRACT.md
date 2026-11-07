# Shared platform bridge contract

Method channel: `cloud_music/control`. Event channel: `cloud_music/events`.
All events are complete snapshot maps. All methods may return the current snapshot; Dart ignores mutation return values and consumes events. `initialize` must return a loaded snapshot immediately and then validate existing tracks asynchronously, preserving missing entries on startup. `pickFolder` cancellation retains the previous library. Repeated busy calls must be safe. The Web input fallback completes the picker command after opening the sheet, then publishes a successful selection through snapshot events; callers must not require a selection in the command result. Playback and source changes must invalidate pending asynchronous operations.

Methods: `initialize`, `pickFolder`, `refresh`, `play` (`id`: string), `togglePlayback`, `pause`, `next`, `previous`, `seek` (`positionMs`: int), `setShuffle` (`enabled`: bool), `setRepeat` (`mode`: `off`/`all`/`one`), `setVolume` (`volume`: double 0–1), `cancelLoading`.

Snapshot fields:
- `folderName`: string or null, `sourceKind`: `apple`, `android` or `web`
- `selectionMode`: optional `folder` (default) or `files`; the Web adapter uses `files` for iPhone/iPad and browsers without directory selection
- `tracks`: array of maps, each with `id`: stable string, `title`: string, `artist`: string (empty allowed), `album`: string (empty allowed), `relativePath`: display string, `status`: `ready`/`cloud`/`offline`/`missing`/`unsupported`/`unknown`, `durationMs`: nonnegative int (0 when unknown)
- `currentTrackId`: string or null
- `isPlaying`, `isLoading`, `isScanning`, `shuffle`: bool
- `positionMs`, `durationMs`: nonnegative int
- `repeatMode`: `off`/`all`/`one`, `volume`: double 0–1
- `artwork`: optional platform typed bytes (FlutterStandardTypedData / byte[]) for current track; keep it reasonably sized
- `message`: string or null. Human-readable Chinese preferred; actionable/recoverable problems surfaced here.

Defaults: false booleans, 0 times, volume 1, repeat off, empty track list.

Only persist metadata, bookmark/tree URI and preferences, never audio. Root selection is explicit; never delete/move/write/copy source files. Startup validates and marks; explicit refresh discovers new songs and removes confirmed-missing references. Unmounted USB, permission errors, iCloud placeholders/offline and incomplete scans are not deletion evidence. Child directories with errors retain their old entries. A root folder error retains all old entries. Initial selection scans recursively. Use audio MIME/type/extension for discovery, then player errors for codec validation, without deleting unsupported entries.


## Optional lyrics bridge (0.2)

Snapshots also expose `sourceIdentity`: a persisted opaque Apple root UUID,
Android tree URI, or browser root UUID. It is used only for local cache isolation,
never sent to the lyrics provider. Distinct same-named folders must not share it.
Apple folder reselection and browser file-input reselection create a new identity.

Native `cloud_music/control` additionally supports:

- `readLyricsCache` (no arguments) -> nullable UTF-8 JSON string.
- `writeLyricsCache` (`value`: string) -> null. Atomic app-owned write, max 2 MiB.
- `importLyrics` (no arguments) -> selected UTF-8 LRC/TXT string, or null on cancel.
  Max 256 KiB. No write/delete permission to the selected original is requested.

These return their own values rather than a library snapshot. Errors are
`lyrics_error`, `invalid_arguments`, `picker_busy` or `no_activity`.
See [LYRICS.md](LYRICS.md) for the explicit-consent provider flow and limits.
