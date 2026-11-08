import 'dart:async';

/// OAuth 凭据仅在当前会话内使用，不写入曲库、日志或播放 URL。
class DriveAuthorization {
  const DriveAuthorization(this.accessToken, {this.expiresAt});
  final String accessToken;
  final DateTime? expiresAt;
}

class DriveAudioRequest {
  const DriveAudioRequest({
    required this.id,
    required this.url,
    required this.accessToken,
    required this.mimeType,
    required this.size,
  });
  final String id, url, accessToken, mimeType;
  final int size;
}

class DrivePlayback {
  const DrivePlayback({
    this.id,
    this.playing = false,
    this.loading = false,
    this.completed = false,
    this.resumable = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
  });
  final String? id, error;
  final bool playing, loading, completed, resumable;
  final Duration position, duration;
}

abstract interface class DrivePlatform {
  bool get configured;
  String get setupMessage;
  String get playbackNotice;
  Stream<DrivePlayback> get playback;
  Future<void> initialize();
  // 交互式授权只能由明确的用户操作触发。
  Future<DriveAuthorization?> authorize({bool interactive = false});
  void cancelAuthorization();
  Future<void> disconnect();
  Future<void> play(DriveAudioRequest request);
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> setVolume(double value);
  Future<void> stop();
  Future<void> dispose();
}
