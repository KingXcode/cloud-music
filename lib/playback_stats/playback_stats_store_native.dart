import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'playback_stats_store.dart';

PlaybackStatsStore createPlaybackStatsStore() => NativePlaybackStatsStore();

class NativePlaybackStatsStore
    implements PlaybackStatsStore, PlaybackStatsFolderStore {
  NativePlaybackStatsStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('cloud_music/control');
  final MethodChannel _channel;

  @override
  bool get canPickFolder =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> pickFolder() async =>
      await _channel.invokeMethod<bool>('pickPlaybackStatsFolder') ?? false;

  @override
  Future<String?> read() => _channel.invokeMethod<String>('readPlaybackStats');

  @override
  Future<void> write(String value) =>
      _channel.invokeMethod<void>('writePlaybackStats', {'value': value});

  @override
  Future<String> deviceId() async =>
      (await _channel.invokeMethod<String>('playbackStatsDeviceId'))!;

  @override
  Future<String> storageLocation() async =>
      await _channel.invokeMethod<String>('playbackStatsStorageLocation') ??
      'local';
}
