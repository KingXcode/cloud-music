import 'dart:async';
import 'dart:convert';

import 'package:cloud_music/drive/drive_gateway.dart';
import 'package:cloud_music/drive/drive_platform.dart';
import 'package:cloud_music/gateway/music_gateway.dart';
import 'package:cloud_music/gateway/source_music_gateway.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeDrivePlatform implements DrivePlatform {
  final events = StreamController<DrivePlayback>.broadcast(sync: true);
  final played = <DriveAudioRequest>[];
  bool enabled = true;
  bool authorized = false;
  int interactiveCount = 0, cancelCount = 0, stopCount = 0, resumes = 0;
  Completer<DriveAuthorization?>? pendingAuthorization;
  Completer<void>? pendingPlay;
  @override
  bool get configured => enabled;
  @override
  String get setupMessage => '未配置';
  @override
  String get playbackNotice => '测试';
  @override
  Stream<DrivePlayback> get playback => events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<DriveAuthorization?> authorize({bool interactive = false}) async {
    if (pendingAuthorization != null) return pendingAuthorization!.future;
    if (interactive) {
      interactiveCount++;
      authorized = true;
    }
    return authorized ? const DriveAuthorization('memory-token') : null;
  }

  @override
  void cancelAuthorization() {
    cancelCount++;
  }

  @override
  Future<void> disconnect() async {
    authorized = false;
  }

  @override
  Future<void> play(DriveAudioRequest request) async {
    played.add(request);
    if (pendingPlay != null) await pendingPlay!.future;
    events.add(DrivePlayback(id: request.id, playing: true));
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {
    resumes++;
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() => events.close();
}

class FakeLocalGateway implements MusicGateway {
  final events = StreamController<LibrarySnapshot>.broadcast(sync: true);
  final commands = <String>[];
  Completer<void>? pausePending;
  Object? commandFailure;
  @override
  Stream<LibrarySnapshot> get snapshots => events.stream;
  @override
  Future<LibrarySnapshot> initialize() async => const LibrarySnapshot(
    folderName: 'Local',
    canScanDevice: true,
    canPickFiles: true,
  );
  @override
  Future<void> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    commands.add(method);
    if (commandFailure != null) throw commandFailure!;
    if (method == 'pause' && pausePending != null) await pausePending!.future;
  }

  @override
  Future<void> dispose() => events.close();
}

MockClient apiClient({Future<http.Response> Function(http.Request)? list}) =>
    MockClient((request) async {
      if (request.url.path.endsWith('/about')) {
        return http.Response('{"user":{"permissionId":"account"}}', 200);
      }
      if (list != null) return list(request);
      return http.Response(
        jsonEncode({
          'files': [
            {
              'id': 'one',
              'name': 'Artist - One.mp3',
              'mimeType': 'audio/mpeg',
              'size': '1024',
            },
            {
              'id': 'two',
              'name': 'Artist - Two.mp3',
              'mimeType': 'audio/mpeg',
              'size': '2048',
            },
          ],
        }),
        200,
      );
    });

void main() {
  test(
    'file picking and device scanning always route to the local source',
    () async {
      final p = FakeDrivePlatform();
      final d = DriveGateway(platform: p, client: apiClient());
      final local = FakeLocalGateway();
      final source = SourceMusicGateway(local: local, drive: d);
      addTearDown(source.dispose);
      await source.initialize();
      expect(source.localSnapshot.canScanDevice, true);
      var revision = 0;
      for (final command in ['pickFolder', 'pickFiles', 'scanDevice']) {
        await d.connect();
        await source.command('driveUseFolder');
        expect(source.usingDrive, true);
        await source.command(command);
        expect(source.usingDrive, true);
        local.events.add(
          LibrarySnapshot(
            importRevision: ++revision,
            canPickFiles: true,
            canScanDevice: true,
            tracks: const [Track(id: 'local', title: 'Local')],
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(source.usingDrive, false);
        expect(local.commands.last, command);
        expect(source.localSnapshot.canPickFiles, true);
      }
    },
  );

  for (final command in ['pickFolder', 'pickFiles', 'scanDevice']) {
    for (final outcome in ['cancel', 'denied', 'empty', 'failed', 'thrown']) {
      test('$command $outcome preserves active Drive source and playback', () async {
        final p = FakeDrivePlatform();
        final d = DriveGateway(platform: p, client: apiClient());
        final local = FakeLocalGateway();
        final source = SourceMusicGateway(local: local, drive: d);
        addTearDown(source.dispose);
        await source.initialize();
        await d.connect();
        await source.command('driveUseFolder');
        await source.command('play', {'id': 'gdrive:one'});
        final stops = p.stopCount;
        final snapshots = <LibrarySnapshot>[];
        final sub = source.snapshots.listen(snapshots.add);
        addTearDown(sub.cancel);
        if (outcome == 'thrown') {
          local.commandFailure = StateError('import failure');
        }
        final pending = source.command(command);
        // No await, including drive.stop(), may precede the local picker call.
        expect(local.commands.last, command);
        if (outcome == 'thrown') {
          await expectLater(pending, throwsStateError);
        } else {
          await pending;
          if (outcome != 'cancel') {
            local.events.add(
              LibrarySnapshot(
                sourceKind: 'android',
                message: outcome,
                // Even an incorrect success marker cannot switch to an empty source.
                importRevision: outcome == 'empty' ? 1 : 0,
              ),
            );
          }
        }
        await Future<void>.delayed(Duration.zero);
        expect(source.usingDrive, true);
        expect(d.snapshot.isPlaying, true);
        expect(d.snapshot.currentTrackId, 'gdrive:one');
        expect(p.stopCount, stops);
        expect(snapshots.every((s) => s.sourceKind == 'googleDrive'), true);
      });
    }
  }

  test('staged Android scan exposes progress and cancels local work without stopping Drive', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    final local = FakeLocalGateway();
    final source = SourceMusicGateway(local: local, drive: d);
    final c = MusicController(gateway: source);
    addTearDown(c.dispose);
    await c.initialize();
    await d.connect();
    await c.useDriveFolder();
    await c.play(c.snapshot.tracks.first);
    final stops = p.stopCount;
    await c.scanDevice();
    local.events.add(
      const LibrarySnapshot(
        sourceKind: 'android',
        isScanning: true,
        message: '正在扫描本机音乐…',
      ),
    );
    expect(c.usingDrive, true);
    expect(c.snapshot.isPlaying, true);
    expect(c.isLocalImportScanning, true);
    expect(c.isBusy, true);
    expect(c.localImportMessage, '正在扫描本机音乐…');
    expect(c.error, null);
    final calls = local.commands.length;
    await c.pickFolder();
    expect(local.commands.length, calls);
    await c.cancelLocalImport();
    expect(local.commands.last, 'cancelImport');
    expect(c.isLocalImportScanning, false);
    expect(c.isBusy, false);
    expect(c.snapshot.isPlaying, true);
    expect(p.stopCount, stops);
    // A late success after cancellation is not authorization to switch sources.
    local.events.add(
      const LibrarySnapshot(
        importRevision: 1,
        tracks: [Track(id: 'late', title: 'Late')],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.usingDrive, true);
    expect(p.stopCount, stops);
  });

  test(
    'failed staged scan is visible and dismissible while Drive keeps playing',
    () async {
      final p = FakeDrivePlatform();
      final d = DriveGateway(platform: p, client: apiClient());
      final local = FakeLocalGateway();
      final source = SourceMusicGateway(local: local, drive: d);
      final c = MusicController(gateway: source);
      addTearDown(c.dispose);
      await c.initialize();
      await d.connect();
      await c.useDriveFolder();
      await c.play(c.snapshot.tracks.first);
      await c.scanDevice();
      local.events.add(
        const LibrarySnapshot(
          sourceKind: 'android',
          message: '未授予音乐读取权限，原资料库已保留。',
        ),
      );
      expect(c.error, contains('未授予'));
      expect(c.snapshot.isPlaying, true);
      expect(c.isBusy, false);
      expect(c.usingDrive, true);
      c.clearError();
      expect(c.error, null);
    },
  );

  test('only completed nonempty import commits, and stale success cannot override newer Drive selection', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    final local = FakeLocalGateway();
    final source = SourceMusicGateway(local: local, drive: d);
    addTearDown(source.dispose);
    await source.initialize();
    await d.connect();
    await source.command('driveUseFolder');
    await source.command('play', {'id': 'gdrive:one'});
    final stops = p.stopCount;
    await source.command('pickFolder');
    local.events.add(
      const LibrarySnapshot(
        isScanning: true,
        tracks: [Track(id: 'part', title: 'Partial')],
      ),
    );
    expect(source.usingDrive, true);
    expect(p.stopCount, stops);
    local.events.add(
      const LibrarySnapshot(
        importRevision: 1,
        tracks: [Track(id: 'done', title: 'Done')],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(source.usingDrive, false);
    expect(p.stopCount, stops + 1);
    await source.command('driveUseFolder');
    await source.command('pickFiles');
    await source.command('driveUseFolder');
    final newerStops = p.stopCount;
    local.events.add(
      const LibrarySnapshot(
        importRevision: 2,
        tracks: [Track(id: 'late', title: 'Late')],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(source.usingDrive, true);
    expect(p.stopCount, newerStops);
  });
  test('未配置与初始化不会请求 Google 授权', () async {
    final p = FakeDrivePlatform()..enabled = false;
    final d = DriveGateway(platform: p, client: apiClient());
    addTearDown(d.dispose);
    await d.initialize();
    await d.connect();
    expect(p.interactiveCount, 0);
    expect(d.connected, isFalse);
    expect(d.error, '未配置');
  });

  test('连接只读索引、播放头令牌不进入歌曲 ID，断开清除会话', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    addTearDown(d.dispose);
    await d.connect();
    expect(d.connected, isTrue);
    expect(d.entries, hasLength(2));
    expect(await d.selectFolder(), isTrue);
    await d.command('play', {'id': 'gdrive:one'});
    expect(p.played.single.accessToken, 'memory-token');
    expect(p.played.single.url, isNot(contains('memory-token')));
    expect(d.snapshot.currentTrackId, 'gdrive:one');
    expect(d.snapshot.sourceIdentity, 'account');
    await d.disconnect();
    expect(d.snapshot.tracks, isEmpty);
    expect(d.connected, isFalse);
  });

  test('刷新失败保留已有曲库，不将权限错误当成歌曲删除', () async {
    var fail = false;
    final p = FakeDrivePlatform();
    final d = DriveGateway(
      platform: p,
      client: apiClient(
        list: (_) async => fail
            ? http.Response('private error body', 403)
            : http.Response(
                '{"files":[{"id":"one","name":"One.mp3","mimeType":"audio/mpeg"}]}',
                200,
              ),
      ),
    );
    addTearDown(d.dispose);
    await d.connect();
    await d.selectFolder();
    fail = true;
    await d.command('refresh');
    expect(d.snapshot.tracks.single.id, 'gdrive:one');
    expect(d.error, isNotNull);
  });

  test('取消待完成扫描不替换曲库', () async {
    var wait = false;
    final pending = Completer<http.Response>();
    final p = FakeDrivePlatform();
    final d = DriveGateway(
      platform: p,
      client: apiClient(
        list: (_) async =>
            wait ? pending.future : http.Response('{"files":[]}', 200),
      ),
    );
    addTearDown(d.dispose);
    await d.connect();
    wait = true;
    final scan = d.selectFolder();
    await Future<void>.delayed(Duration.zero);
    d.cancelBrowse();
    pending.complete(http.Response('{"files":[]}', 200));
    expect(await scan, isFalse);
    expect(d.snapshot.folderName, isNull);
    expect(d.busy, isFalse);
  });

  test('恢复浏览器缓冲播放不重新下载，暂停加载取消迟到播放', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    addTearDown(d.dispose);
    await d.connect();
    await d.selectFolder();
    await d.command('play', {'id': 'gdrive:one'});
    p.events.add(
      const DrivePlayback(id: 'gdrive:one', resumable: true, error: '点击播放继续'),
    );
    await d.command('togglePlayback');
    expect(p.resumes, 1);
    expect(p.played, hasLength(1));
    p.pendingAuthorization = Completer<DriveAuthorization?>();
    final play = d.command('play', {'id': 'gdrive:two'});
    await Future<void>.delayed(Duration.zero);
    await d.command('pause');
    p.pendingAuthorization!.complete(const DriveAuthorization('token'));
    await play;
    expect(p.played, hasLength(1));
    expect(d.snapshot.isPlaying, isFalse);
  });

  test('重复完成事件只推进一次，旧曲事件不会覆盖新曲', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    addTearDown(d.dispose);
    await d.connect();
    await d.selectFolder();
    await d.command('play', {'id': 'gdrive:one'});
    p.events.add(const DrivePlayback(id: 'gdrive:one', completed: true));
    p.events.add(const DrivePlayback(id: 'gdrive:one', completed: true));
    await Future<void>.delayed(Duration.zero);
    expect(p.played.map((r) => r.id), ['gdrive:one', 'gdrive:two']);
    p.events.add(const DrivePlayback(id: 'gdrive:one', playing: true));
    expect(d.snapshot.currentTrackId, 'gdrive:two');
  });

  test('随机且关闭循环时，完成全部曲目就停止', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    addTearDown(d.dispose);
    await d.connect();
    await d.selectFolder();
    await d.command('setShuffle', {'enabled': true});
    await d.command('play', {'id': 'gdrive:one'});
    p.events.add(const DrivePlayback(id: 'gdrive:one', completed: true));
    await Future<void>.delayed(Duration.zero);
    p.events.add(const DrivePlayback(id: 'gdrive:two', completed: true));
    await Future<void>.delayed(Duration.zero);
    expect(p.played, hasLength(2));
    expect(d.snapshot.isPlaying, isFalse);
  });

  test('迟到的来源切换不能覆盖返回系统文件的操作', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    final local = FakeLocalGateway()..pausePending = Completer<void>();
    final source = SourceMusicGateway(local: local, drive: d);
    addTearDown(source.dispose);
    await source.initialize();
    await d.connect();
    final switchToDrive = source.command('driveUseFolder');
    await Future<void>.delayed(Duration.zero);
    await source.command('useLocal');
    local.pausePending!.complete();
    await switchToDrive;
    expect(source.usingDrive, isFalse);
  });
  test('结束后重新播放仍能继续单曲循环', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    addTearDown(d.dispose);
    await d.connect();
    await d.selectFolder();
    await d.command('play', {'id': 'gdrive:two'});
    p.events.add(const DrivePlayback(id: 'gdrive:two', completed: true));
    await Future<void>.delayed(Duration.zero);
    await d.command('setRepeat', {'mode': 'one'});
    await d.command('togglePlayback');
    p.events.add(const DrivePlayback(id: 'gdrive:two', completed: true));
    p.events.add(const DrivePlayback(id: 'gdrive:two', completed: true));
    await Future<void>.delayed(Duration.zero);
    expect(p.played, hasLength(3));
  });

  test('关闭面板取消等待本地暂停的网盘来源切换', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    final local = FakeLocalGateway()..pausePending = Completer<void>();
    final source = SourceMusicGateway(local: local, drive: d);
    addTearDown(source.dispose);
    await source.initialize();
    await d.connect();
    final change = source.command('driveUseFolder');
    await Future<void>.delayed(Duration.zero);
    d.cancelBrowse();
    local.pausePending!.complete();
    await change;
    expect(source.usingDrive, isFalse);
  });

  test('取消重新连接保留原先已连接的会话状态', () async {
    final p = FakeDrivePlatform();
    final d = DriveGateway(platform: p, client: apiClient());
    addTearDown(d.dispose);
    await d.connect();
    p.pendingAuthorization = Completer<DriveAuthorization?>();
    final reconnect = d.connect();
    await Future<void>.delayed(Duration.zero);
    d.cancelBrowse();
    p.pendingAuthorization!.complete(null);
    await reconnect;
    expect(d.connected, isTrue);
    expect(p.authorized, isTrue);
  });
}
