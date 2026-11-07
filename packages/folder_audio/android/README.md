# Android native bridge

This is an ordinary Android application/head-unit plugin (minimum API 24), not an Android Auto application. The app uses the Flutter-generated AGP 9.1/Kotlin 2.4 project configuration and JDK 17 bytecode. The release variant currently uses the scaffold debug signing configuration: distribution must call this a test-signed APK, not a production-signed build.

## Source access and preservation

`ACTION_OPEN_DOCUMENT_TREE` requests persistent **read-only** permission. The library stores JSON metadata, preferences and original document URIs in SharedPreferences. Audio is opened through a read-only provider file descriptor; the plugin never copies, moves, deletes or writes source audio. Android does not reinterpret an Apple bookmark or provide built-in iCloud access.

Initialization returns persisted metadata immediately and validates asynchronously. Startup never drops references. Explicit refresh recursively discovers songs but only removes missing references after a wholly successful traversal and independent absence proof. Any incomplete/error cursor or inaccessible subtree disables pruning for the entire scan, deliberately retaining more than necessary. External-storage providers additionally require a mounted StorageManager volume, valid persistent grant and healthy root before and after traversal. A null/error remote provider result is never deletion evidence. Cancellation signals and generations prevent stale scans from publishing after cancellation or source replacement.

The picker reports its result asynchronously. Canceling the system picker leaves the previous library and playback untouched. Activity reattachment keeps the pending picker result listener; no outstanding Flutter method result is retained across lifecycle changes.

## Playback

The process-level engine survives activity recreation. MediaPlayer streams original source descriptors; metadata/artwork is fetched lazily on a separate executor. Generation checks prevent old song preparation and artwork from replacing a newer selection. Provider descriptor acquisition uses CancellationSignal. A poorly behaved third-party provider may ignore cancellation; its late result is still discarded.

The native media foreground service exposes notification previous/play/pause/next actions, seekable MediaSession state and lock-screen metadata. It remains foreground while preparing the next song. Audio focus handles interruption/ducking and the noisy-route receiver pauses when wired audio is disconnected. Playback resumes after a transient focus loss only when it had been playing. Pausing stops the foreground service; transport controls are available again after playback resumes in the app. The application does not automatically play after process death or reboot.

## Validation status

Source review completed; Kotlin/Android compilation and physical-device behavior require CI/device validation. No Android SDK was available in the authoring workspace. JVM tests cover bridge unknown-method handling and track snapshot fields; they are not substitutes for provider/player instrumentation.

Before shipping, test: nested/Unicode/duplicate-named files; picker cancel and replacement; persisted access after restart; revoked permission; USB unplug during scan and playback; empty/incomplete/error provider results; external removal and explicit refresh; damaged/unsupported tracks; rapid A/B selection and cancellation; seek/shuffle/repeat; incoming call/focus loss; unplugged headphones; screen-off and background playback; Android 15+ foreground restrictions; landscape head-unit touch controls. Check that only metadata is stored in app support data.

Official API references reviewed:
- https://developer.android.com/reference/android/provider/DocumentsContract
- https://developer.android.com/reference/android/provider/DocumentsProvider
- https://developer.android.com/media/optimize/audio-focus
