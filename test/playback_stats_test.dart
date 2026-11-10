import 'dart:async';
import 'dart:convert';

import 'package:cloud_music/models.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:cloud_music/playback_stats/playback_stats.dart';
import 'package:cloud_music/playback_stats/playback_stats_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show FakeGateway;

class MemoryPlaybackStatsStore implements PlaybackStatsStore {
  String? value;
  String device = 'this-device';
  String location = 'icloud';
  bool failRead = false, failWrite = false;
  Completer<String?>? pendingRead;
  Completer<void>? pendingWrite;
  int writes = 0;

  @override
  Future<String> deviceId() async => device;
  @override
  Future<String> storageLocation() async => location;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Cannot read stats');
    return pendingRead?.future ?? value;
  }

  @override
  Future<void> write(String next) async {
    writes++;
    if (failWrite) throw StateError('Cannot write stats');
    if (pendingWrite != null) await pendingWrite!.future;
    value = next;
  }
}

class MemoryFolderPlaybackStatsStore extends MemoryPlaybackStatsStore
    implements PlaybackStatsFolderStore {
  @override
  bool canPickFolder = true;
  bool selection = true, failPick = false;
  int picks = 0;
  String? folderValue;
  Completer<bool>? pendingPick;

  @override
  Future<bool> pickFolder() async {
    picks++;
    if (failPick) throw StateError('Cannot select folder');
    final selected = await (pendingPick?.future ?? Future.value(selection));
    if (selected) {
      value = folderValue;
      location = 'folder';
    }
    return selected;
  }
}

const song = Track(
  id: 'encoded-id',
  title: 'Song',
  relativePath: 'Artist/Song.mp3',
);

LibrarySnapshot playing({
  String? session = 'session-1',
  bool isPlaying = true,
  bool isLoading = false,
  String folder = 'Music',
  String sourceIdentity = 'folder-bookmark-1',
  String sourceKind = 'apple',
  Track track = song,
}) => LibrarySnapshot(
  folderName: folder,
  sourceKind: sourceKind,
  sourceIdentity: sourceIdentity,
  tracks: [track],
  currentTrackId: track.id,
  playbackSessionId: session,
  isPlaying: isPlaying,
  isLoading: isLoading,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'connect a personal folder and merge its counts with existing plays',
    () async {
      final store = MemoryFolderPlaybackStatsStore()..location = 'local';
      final stats = PlaybackStats(store: store);
      stats.observe(playing());
      await stats.flush();
      final key = PlaybackStats.trackKey(playing(), song);
      store.folderValue = jsonEncode({
        'version': 1,
        'counts': {
          key: {'other-device': 4},
        },
      });
      await stats.pickFolder();
      expect(stats.storageLocation, 'folder');
      expect(stats.count(playing(), song), 5);
      expect(stats.choosingFolder, false);
      expect(stats.notice, isNull);
      final restored = PlaybackStats(store: store);
      await restored.initialize();
      expect(restored.count(playing(), song), 5);
      stats.dispose();
      restored.dispose();
    },
  );

  test(
    'cancelled or failed folder selection retains existing statistics',
    () async {
      final store = MemoryFolderPlaybackStatsStore()
        ..location = 'local'
        ..selection = false;
      final stats = PlaybackStats(store: store);
      stats.observe(playing());
      await stats.flush();
      final original = store.value;
      await stats.pickFolder();
      expect(stats.storageLocation, 'local');
      expect(stats.count(playing(), song), 1);
      expect(store.value, original);
      store.failPick = true;
      await stats.pickFolder();
      expect(stats.notice, isNotNull);
      expect(stats.storageLocation, 'local');
      expect(store.value, original);
      stats.dispose();
    },
  );

  test('only one folder picker opens while selection is pending', () async {
    final store = MemoryFolderPlaybackStatsStore()..pendingPick = Completer();
    final stats = PlaybackStats(store: store);
    await stats.initialize();
    final first = stats.pickFolder();
    await stats.flush();
    await Future<void>.value();
    await stats.pickFolder();
    expect(stats.choosingFolder, true);
    expect(store.picks, 1);
    store.pendingPick!.complete(false);
    await first;
    expect(stats.choosingFolder, false);
    stats.dispose();
  });

  test(
    'merge the latest same-device baseline before applying a new play',
    () async {
      final store = MemoryPlaybackStatsStore();
      final first = PlaybackStats(store: store);
      final second = PlaybackStats(store: store);
      await first.initialize();
      await second.initialize();
      first.observe(playing());
      await first.flush();
      second.observe(playing(session: 'second-instance'));
      // The queued increment remains visible before disk I/O completes.
      expect(second.count(playing(), song), 1);
      await second.flush();
      final restored = PlaybackStats(store: store);
      await restored.initialize();
      expect(restored.count(playing(), song), 2);
      first.dispose();
      second.dispose();
      restored.dispose();
    },
  );

  test('reload and plays serialize behind an unfinished write without losing increments', () async {
    final store = MemoryPlaybackStatsStore()..pendingWrite = Completer<void>();
    final stats = PlaybackStats(store: store);
    await stats.initialize();
    stats.observe(playing());
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    final reload = stats.reload();
    stats.observe(playing(session: 'during-write'));
    expect(stats.count(playing(), song), 2);
    store.pendingWrite!.complete();
    await reload;
    await stats.flush();
    final restored = PlaybackStats(store: store);
    await restored.initialize();
    expect(restored.count(playing(), song), 2);
    stats.dispose();
    restored.dispose();
  });

  test(
    'Android file IDs and browser source handles isolate same-named tracks',
    () async {
      final stats = PlaybackStats(store: MemoryPlaybackStatsStore());
      final other = Track(
        id: 'different-uri',
        title: song.title,
        relativePath: song.relativePath,
      );
      stats.observe(playing(sourceKind: 'android'));
      stats.observe(playing(sourceKind: 'web', session: 'web-play'));
      await stats.flush();
      expect(stats.count(playing(sourceKind: 'android'), other), 0);
      expect(
        stats.count(
          playing(sourceKind: 'web', sourceIdentity: 'another-folder-handle'),
          song,
        ),
        0,
      );
      stats.dispose();
    },
  );

  test(
    'count actual sessions once across progress, pause, seek and resume',
    () async {
      final store = MemoryPlaybackStatsStore();
      final stats = PlaybackStats(store: store);
      await stats.initialize();
      stats.observe(playing(isPlaying: false, isLoading: true, session: null));
      stats.observe(playing(session: null));
      await stats.flush();
      expect(stats.count(playing(), song), 0);

      stats.observe(playing());
      stats.observe(playing());
      stats.observe(playing(isPlaying: false));
      stats.observe(playing());
      await stats.flush();
      expect(stats.count(playing(), song), 1);

      stats.observe(playing(session: 'repeat-one-2'));
      await stats.flush();
      expect(stats.count(playing(), song), 2);
      final restored = PlaybackStats(store: store);
      await restored.initialize();
      expect(restored.count(playing(), song), 2);
      stats.dispose();
      restored.dispose();
    },
  );

  test(
    'ignore failed loading and sessions without a matching current track',
    () async {
      final stats = PlaybackStats(store: MemoryPlaybackStatsStore());
      stats.observe(playing(isPlaying: false, session: 'failed-attempt'));
      stats.observe(
        const LibrarySnapshot(
          playbackSessionId: 'orphan-session',
          isPlaying: true,
          currentTrackId: 'missing',
        ),
      );
      await stats.flush();
      expect(stats.count(playing(), song), 0);
      stats.dispose();
    },
  );

  test(
    'pending initialization preserves plays and serializes rapid writes',
    () async {
      final key = PlaybackStats.trackKey(playing(), song);
      final store = MemoryPlaybackStatsStore()..pendingRead = Completer();
      final stats = PlaybackStats(store: store);
      stats.observe(playing());
      stats.observe(playing(session: 'second'));
      store.pendingRead!.complete(
        jsonEncode({
          'version': 1,
          'counts': {
            key: {'this-device': 4, 'other-device': 6},
          },
        }),
      );
      await stats.flush();
      expect(stats.count(playing(), song), 12);
      expect(jsonDecode(store.value!)['counts'][key]['this-device'], 6);
      stats.dispose();
    },
  );

  test(
    'merge device maxima without multiplying previously synced counts',
    () async {
      final key = PlaybackStats.trackKey(playing(), song);
      final store = MemoryPlaybackStatsStore()
        ..value = jsonEncode({
          'version': 1,
          'counts': {
            key: {'this-device': 2, 'other-device': 3},
          },
        });
      final stats = PlaybackStats(store: store);
      await stats.initialize();
      expect(stats.count(playing(), song), 5);
      store.value = jsonEncode({
        'version': 1,
        'counts': {
          key: {'this-device': 1, 'other-device': 5},
        },
      });
      await stats.reload();
      await stats.reload();
      expect(stats.count(playing(), song), 7);
      stats.observe(playing());
      await stats.flush();
      expect(stats.count(playing(), song), 8);
      stats.dispose();
    },
  );

  test(
    'reselected folders and metadata updates retain counts; sources isolate',
    () async {
      final stats = PlaybackStats(store: MemoryPlaybackStatsStore());
      stats.observe(playing());
      await stats.flush();
      final updated = song.copyWith(title: 'Correct title', artist: 'Artist');
      expect(stats.count(playing(sourceIdentity: 'new-bookmark'), updated), 1);
      expect(stats.count(playing(folder: 'Other Music'), song), 0);
      expect(
        stats.count(
          playing(sourceKind: 'googleDrive', sourceIdentity: 'a'),
          song,
        ),
        0,
      );
      stats.observe(
        playing(
          sourceKind: 'googleDrive',
          sourceIdentity: 'a',
          session: 'drive',
        ),
      );
      await stats.flush();
      expect(
        stats.count(
          playing(sourceKind: 'googleDrive', sourceIdentity: 'a'),
          song,
        ),
        1,
      );
      expect(
        stats.count(
          playing(sourceKind: 'googleDrive', sourceIdentity: 'b'),
          song,
        ),
        0,
      );
      stats.dispose();
    },
  );

  test('corrupt or unreadable cache never gets overwritten', () async {
    for (final raw in [
      'broken-json',
      '{"version":9,"counts":{}}',
      '{"version":1,"counts":{"bad":{"device":-1}}}',
    ]) {
      final store = MemoryPlaybackStatsStore()..value = raw;
      final stats = PlaybackStats(store: store);
      stats.observe(playing());
      await stats.flush();
      expect(stats.count(playing(), song), 1);
      expect(stats.notice, isNotNull);
      expect(store.writes, 0);
      expect(store.value, raw);
      stats.dispose();
    }
  });

  test(
    'failed write retains count and retries all increments on next play',
    () async {
      final store = MemoryPlaybackStatsStore()..failWrite = true;
      final stats = PlaybackStats(store: store);
      stats.observe(playing());
      await stats.flush();
      expect(stats.count(playing(), song), 1);
      expect(stats.notice, isNotNull);
      store.failWrite = false;
      stats.observe(playing(session: 'after-recovery'));
      await stats.flush();
      expect(stats.count(playing(), song), 2);
      expect(stats.notice, isNull);
      final restored = PlaybackStats(store: store);
      await restored.initialize();
      expect(restored.count(playing(), song), 2);
      stats.dispose();
      restored.dispose();
    },
  );

  test(
    'read recovery adds unsaved plays after the restored baseline',
    () async {
      final key = PlaybackStats.trackKey(playing(), song);
      final store = MemoryPlaybackStatsStore()..failRead = true;
      final stats = PlaybackStats(store: store);
      stats.observe(playing());
      stats.observe(playing(session: 'read-failed-second'));
      await stats.flush();
      expect(stats.count(playing(), song), 2);
      expect(store.writes, 0);
      store.failRead = false;
      store.value = jsonEncode({
        'version': 1,
        'counts': {
          key: {'this-device': 5, 'other-device': 3},
        },
      });
      await stats.reload();
      expect(stats.count(playing(), song), 10);
      expect(jsonDecode(store.value!)['counts'][key]['this-device'], 7);
      stats.dispose();
    },
  );

  test(
    'controller observes initial and stream sessions without command counting',
    () async {
      final gateway = FakeGateway()..initial = playing();
      final stats = PlaybackStats(store: MemoryPlaybackStatsStore());
      final controller = MusicController(
        gateway: gateway,
        playbackStats: stats,
      );
      await controller.initialize();
      await stats.flush();
      expect(controller.playCount(song), 1);
      await controller.play(
        song,
      ); // A command alone is not successful playback.
      expect(controller.playCount(song), 1);
      gateway.events.add(playing());
      gateway.events.add(playing(session: 'automatic-next'));
      await stats.flush();
      expect(controller.playCount(song), 2);
      controller.dispose();
    },
  );
}
