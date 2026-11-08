import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:just_audio/just_audio.dart';

import 'drive_platform.dart';

DrivePlatform createDrivePlatform() => NativeDrivePlatform();

/// 携带令牌的请求只允许访问 Drive 媒体端点，以及网关使用的共享云端硬盘参数。
/// 不接受用户自定义的播放地址。
@visibleForTesting
bool isAllowedNativeDriveMediaUrl(String url) => RegExp(
  r'^https://www\.googleapis\.com/drive/v3/files/[A-Za-z0-9_-]+\?alt=media(?:&supportsAllDrives=true)?$',
).hasMatch(url);

/// 应用只在内存中使用令牌；操作系统中的登录会话由官方 Google SDK 管理。
class NativeDrivePlatform implements DrivePlatform {
  static const _scope = 'https://www.googleapis.com/auth/drive.readonly';
  static const _android = String.fromEnvironment(
    'GOOGLE_DRIVE_SERVER_CLIENT_ID',
  );
  static const _ios = String.fromEnvironment('GOOGLE_DRIVE_IOS_CLIENT_ID');
  static const _macos = String.fromEnvironment('GOOGLE_DRIVE_MACOS_CLIENT_ID');
  final _events = StreamController<DrivePlayback>.broadcast();
  final _signIn = GoogleSignIn.instance;
  GoogleSignInAccount? _account;
  String? _lastAccessToken;
  Future<void>? _initialization;
  AudioPlayer? _player;
  String? _playingId;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _generation = 0;
  int _authGeneration = 0;
  bool _disposed = false;
  double _volume = 1;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  String get _clientId => switch (defaultTargetPlatform) {
    TargetPlatform.android => _android,
    TargetPlatform.iOS => _ios,
    TargetPlatform.macOS => _macos,
    _ => '',
  };

  @override
  bool get configured =>
      _supported &&
      _clientId.endsWith('.apps.googleusercontent.com') &&
      !_clientId.contains(RegExp(r'\s'));

  @override
  String get setupMessage => !_supported
      ? '此系统暂不支持 Google Drive 原生登录，请使用浏览器版本。'
      : '需配置本平台的 Google OAuth 客户端 ID；Apple 平台还需回调 URL Scheme 和签名配置。详见 docs/GOOGLE_DRIVE_NATIVE.md。';

  @override
  String get playbackNotice =>
      '从 Google Drive 直接串流，不下载完整文件；需保持联网。Apple 平台的带授权请求播放仍需真机验证。';

  @override
  Stream<DrivePlayback> get playback => _events.stream;

  @override
  Future<void> initialize() async {
    if (!configured || _disposed) return;
    await (_initialization ??= _signIn.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.android
          ? null
          : _clientId,
      serverClientId: defaultTargetPlatform == TargetPlatform.android
          ? _clientId
          : null,
    ));
  }

  @override
  Future<DriveAuthorization?> authorize({bool interactive = false}) async {
    if (!configured || _disposed) return null;
    final generation = _authGeneration;
    try {
      await initialize();
      if (_disposed || generation != _authGeneration) return null;
      var account = _account;
      account ??= interactive
          ? await _signIn.authenticate(scopeHint: const [_scope])
          : await _signIn.attemptLightweightAuthentication();
      if (account == null || _disposed || generation != _authGeneration) {
        return null;
      }
      final previousToken = _lastAccessToken;
      if (interactive && previousToken != null) {
        // 显式重新连接时清除 SDK 缓存，避免外部撤销授权后反复拿到失效令牌。
        // Apple 插件此调用为空操作，令牌失效由其底层 SDK 自行处理。
        await account.authorizationClient.clearAuthorizationToken(
          accessToken: previousToken,
        );
        if (_disposed || generation != _authGeneration) return null;
        if (_lastAccessToken == previousToken) _lastAccessToken = null;
      }
      var authorization = await account.authorizationClient
          .authorizationForScopes(const [_scope]);
      if (_disposed || generation != _authGeneration) return null;
      if (authorization == null && interactive) {
        authorization = await account.authorizationClient.authorizeScopes(
          const [_scope],
        );
      }
      if (_disposed || generation != _authGeneration || authorization == null) {
        return null;
      }
      _account = account;
      _lastAccessToken = authorization.accessToken;
      // 由 SDK 刷新访问令牌，不推测有效期，也不持久化令牌。
      return DriveAuthorization(authorization.accessToken);
    } on GoogleSignInException catch (error) {
      if (_disposed || generation != _authGeneration) return null;
      if (!interactive || error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw StateError('Google 登录或只读授权失败，请检查客户端配置后重试。');
    } catch (_) {
      if (_disposed || generation != _authGeneration) return null;
      if (!interactive) return null;
      throw StateError('Google 登录暂不可用，请检查客户端配置后重试。');
    }
  }

  @override
  void cancelAuthorization() {
    // 只丢弃尚未完成的授权结果，保留已有会话，不发起新的授权或撤销请求。
    ++_authGeneration;
  }

  @override
  Future<void> disconnect() async {
    ++_authGeneration;
    _account = null;
    _lastAccessToken = null;
    await stop();
    if (_initialization != null) {
      try {
        await _initialization;
        // 用户明确选择断开并撤销授权时，调用官方 SDK 撤销应用授权。
        await _signIn.disconnect();
      } catch (_) {
        throw StateError('本地播放已停止；Google 授权撤销失败，请重试。');
      }
    }
  }

  bool _current(int generation, AudioPlayer player) =>
      !_disposed && generation == _generation && identical(_player, player);

  void _emit(DrivePlayback event) {
    if (!_disposed) _events.add(event);
  }

  void _publish(AudioPlayer player, String id, int generation) {
    if (!_current(generation, player)) return;
    final state = player.processingState;
    _emit(
      DrivePlayback(
        id: id,
        playing: player.playing && state != ProcessingState.completed,
        loading:
            state == ProcessingState.loading ||
            state == ProcessingState.buffering,
        completed: state == ProcessingState.completed,
        position: player.position,
        duration: player.duration ?? Duration.zero,
      ),
    );
  }

  void _playbackError(String id, int generation, AudioPlayer player) {
    if (!_current(generation, player)) return;
    // 不转发 SDK 原始异常、播放地址或请求头。
    _emit(
      DrivePlayback(
        id: id,
        error: '云端播放失败，请重新连接 Google Drive 后重试；也请检查网络及音频格式。',
      ),
    );
  }

  Future<void> _releasePlayer() async {
    final old = _player;
    _player = null;
    _playingId = null;
    final subscriptions = List<StreamSubscription<dynamic>>.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await old?.dispose();
  }

  @override
  Future<void> play(DriveAudioRequest request) async {
    if (_disposed) return;
    final generation = ++_generation;
    await _releasePlayer();
    if (_disposed || generation != _generation) return;
    if (!isAllowedNativeDriveMediaUrl(request.url) ||
        request.accessToken.isEmpty) {
      _emit(DrivePlayback(id: request.id, error: '无效的 Google Drive 音频地址。'));
      return;
    }
    final player = AudioPlayer(useProxyForRequestHeaders: false);
    _player = player;
    _playingId = request.id;
    _emit(DrivePlayback(id: request.id, loading: true));
    _subscriptions.add(
      player.playerStateStream.listen(
        (_) => _publish(player, request.id, generation),
      ),
    );
    _subscriptions.add(
      player.positionStream.listen(
        (_) => _publish(player, request.id, generation),
      ),
    );
    _subscriptions.add(
      player.durationStream.listen(
        (_) => _publish(player, request.id, generation),
      ),
    );
    _subscriptions.add(
      player.errorStream.listen(
        (_) => _playbackError(request.id, generation, player),
      ),
    );
    try {
      await player.setVolume(_volume);
      if (!_current(generation, player)) return;
      await player.setUrl(
        request.url,
        headers: {'Authorization': 'Bearer ${request.accessToken}'},
      );
      if (!_current(generation, player)) return;
      unawaited(
        player.play().catchError(
          (Object _) => _playbackError(request.id, generation, player),
        ),
      );
    } catch (_) {
      _playbackError(request.id, generation, player);
    }
  }

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> resume() async {
    final player = _player;
    final generation = _generation;
    if (player == null) return;
    if (player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero);
    }
    if (!_current(generation, player)) return;
    // play() 在歌曲播放结束时才完成，不是在开始播放时完成。
    final id = _playingId;
    if (id == null) return;
    unawaited(
      player.play().catchError(
        (Object _) => _playbackError(id, generation, player),
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 1);
    await _player?.setVolume(_volume);
  }

  @override
  Future<void> stop() async {
    final generation = ++_generation;
    await _releasePlayer();
    if (generation == _generation) _emit(const DrivePlayback());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    ++_authGeneration;
    _account = null;
    _lastAccessToken = null;
    await _releasePlayer();
    await _events.close();
  }
}
