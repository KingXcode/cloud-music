# Lyrics: optional download and offline display

## Usage

Open the full player and tap the top-right **查看歌词** icon, or scroll to **歌词** in either player layout.

- **搜索下载** opens an editable title/artist/album form. Only **同意并搜索** sends a request. Playback, opening the player, typing, canceling and library scans never query a lyrics service.
- Check the returned artist, album, duration and synchronized/plain/instrumental label. Tap the correct version to download it into this app's local cache. There is no automatic selection or replacement; a >2-second duration difference is flagged.
- UTF-8 **.lrc / .txt import** and **paste** work without the online provider. Importing replaces only this app's lyrics for that track, never the original file.
- Synchronized LRC follows playback and highlights the current line. Tap a line to seek, or disable follow to browse. Plain lyrics remain scrollable; instrumental records explicitly say there are no lyrics.
- No match, invalid metadata, rate limits, connectivity/CORS problems and storage failures have distinct recovery guidance. Search failure retains previously saved lyrics.

Downloaded lyrics are **in-app offline cache**, not sidecar files written next to your music. The cache is bounded to approximately 2 MiB / 100 songs, with the oldest saved items evicted first. Large collections may need re-download; browser storage can be cleared or evicted by the browser. A failed persistence operation is explicitly labeled session-only. Clearing app/site data removes this cache, not source audio. Re-importing a track under a new location/metadata identity can require selecting lyrics again. Apple folder reselection and browser file-input reselection conservatively create a new source identity, so their old cached lyrics require a fresh selection; normal retained-folder refresh and restart preserve identity.

## Privacy and source

The only provider is HTTPS `lrclib.net`, using its public `/api/search` endpoint. Each user-confirmed search sends **only the entered title, artist and nonempty album**. It does not send duration, local file paths, folder names, audio, artwork or the library index. LRCLIB necessarily receives the connection's IP address and client identification. Browser fetch omits credentials and referrer; both adapters reject redirects. The project does not proxy requests or retain server-side search history.

Cached lyrics and a local track identity are kept in app-private storage on native platforms and origin-local browser storage on Web. This is ordinary local storage, not encrypted secret storage. No API key or account is required. Imports read only the explicitly chosen file; no automatic directory scan or embedded-lyrics extraction is implemented.

### Provider contract and rights review

Primary references checked for this implementation:

- [LRCLIB official API documentation](https://lrclib.net/docs.txt): structured search, at most 20 records, nullable synced/plain lyrics and instrumental marker, CORS, client identification, rate limits and Retry-After.
- [LRCLIB source repository](https://github.com/tranxuanthang/lrclib): MIT license covers server software. It does **not** establish copyright permission for the underlying lyrics.
- [Official LRCGET client](https://github.com/tranxuanthang/lrcget): local lyrics downloading is an intended API use, but this is not a blanket content-rights license.

No authoritative blanket lyrics-content license or applicable full provider terms/privacy policy was verified. Do not advertise the catalog as rights-cleared. The UI attributes LRCLIB, explains possible inaccuracies, and asks users to download only when permitted. Commercial redistribution or app-store distribution requires a separate content-rights/terms review. No lyrics corpus or copyrighted song fixture is included in this repository; tests use invented text.

## Engineering

- `lib/lyrics/lyrics_models.dart`: bounded UTF-8/plain/LRC parsing, multiple timestamps, fractional seconds, hour timestamps, metadata, offset and simultaneous-line grouping. Colon fractions such as `[03:24:45]` mean 3:24.45; the hour form requires a decimal fraction, such as `[01:02:03.250]`, to avoid ambiguity. A positive LRC offset advances display relative to audio. Empty cues remain timing boundaries.
- `lib/lyrics/lyrics_controller.dart`: per-track state, explicit user search, candidate selection, bounded versioned cache, stale-result protection and serialized persistence. Provider errors cannot clear accepted lyrics. No background retries; `429`/`503` respects Retry-After with a conservative fallback when the header cannot be read through CORS.
- `lib/lyrics/lyrics_native.dart`: HTTPS Dart client, identifiable User-Agent, timeouts, bounded response, native cache/import bridge.
- `lib/lyrics/lyrics_web.dart`: browser fetch with Lrclib-Client, CORS enforcement, timeout/abort, localStorage and browser file input. No CORS proxy or security bypass.
- `lib/ui/lyrics_panel.dart`: consent, candidate selection, synchronized highlighting/scroll/seek and offline fallback.
- Native `cloud_music/control`: `readLyricsCache` -> nullable JSON string; `writeLyricsCache({value: String})` -> null; `importLyrics` -> nullable UTF-8 string (null means cancellation). Cache is atomically replaced in app-owned storage; input limits are 2 MiB cache / 256 KiB imported lyrics.

Android INTERNET and macOS client-network entitlements permit the user-initiated HTTPS lookup. Apple file access remains read-only. File picker cancellation, duplicate requests and detach are handled separately from the music picker.

## Verification and remaining device checks

Automated parser/controller/widget checks cover invented LRC, offset and duplicate timestamps, plain/instrumental fallback, consent/cancel/back/typing, track-switch races, explicit candidate acceptance, offline persistence, invalid cache, failed writes, rate limits, responsive layouts and seeking. Native parser unit tests cover UTF-8/BOM and limits. Run:

```sh
flutter analyze
flutter test
node --test test/web/music_gateway_test.cjs
flutter build web --release --base-href /cloud-music/
```

Native test sources are included, but Linux source checks do not prove Android/iOS/macOS compilation or system-picker behavior. Use actual release CI and devices to verify native builds, picker Cancel/reopen, provider cloud-file access and offline restart. Live LRCLIB requests with actual user songs were deliberately not made. A metadata-free OPTIONS preflight confirmed `Access-Control-Allow-Origin: *` and `lrclib-client` in allowed headers for the production origin. Full end-to-end search remains a manual check; use an authorized query and confirm the disclosure before sending.

Final source verification in the Linux development workspace: Flutter analyzer and 48 unit/widget tests passed, including colon-fraction timestamp ambiguity, source isolation, consent and stale-result regressions. The existing 27 JavaScript browser-gateway tests, JavaScript syntax check and final Web release build (including Wasm compatibility dry-run) also passed. Visual capture checks passed before the final parser/picker fixes and phone lyrics / landscape player images were inspected.

The new real-browser abandoned-picker regression could compile, but local Chromium could not launch because this workspace blocks its process socket. It is now a required GitHub Actions check for Web deployment and Android builds. Inspect the actual workflow result before treating that check as passed. Native Android parser tests/build and Apple builds/device picker behavior require their respective build/device environments.
