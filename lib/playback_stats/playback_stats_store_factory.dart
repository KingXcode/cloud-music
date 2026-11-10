import 'playback_stats_store.dart';
import 'playback_stats_store_native.dart'
    if (dart.library.js_interop) 'playback_stats_store_web.dart'
    as platform;

PlaybackStatsStore createPlaybackStatsStore() =>
    platform.createPlaybackStatsStore();
