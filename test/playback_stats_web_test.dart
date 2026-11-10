@TestOn('browser')
library;

import 'dart:convert';

import 'package:cloud_music/playback_stats/playback_stats_store_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  final saved = <String, String>{};
  final storage = web.window.localStorage;
  bool relevant(String key) =>
      key == WebPlaybackStatsStore.key ||
      key == WebPlaybackStatsStore.deviceKey ||
      key.startsWith(WebPlaybackStatsStore.writerPrefix);

  setUp(() {
    saved.clear();
    for (var i = 0; i < storage.length; i++) {
      final key = storage.key(i)!;
      if (relevant(key)) saved[key] = storage.getItem(key)!;
    }
    for (final key in saved.keys) {
      storage.removeItem(key);
    }
  });
  tearDown(() {
    final keys = [for (var i = 0; i < storage.length; i++) storage.key(i)!];
    for (final key in keys.where(relevant)) {
      storage.removeItem(key);
    }
    for (final entry in saved.entries) {
      storage.setItem(entry.key, entry.value);
    }
  });

  String document(Map<String, int> counts) => jsonEncode({
    'version': 1,
    'counts': {'song': counts},
  });

  test('independent tabs retain own counters and merge legacy data without overwrites', () async {
    final first = WebPlaybackStatsStore(writerId: 'first-tab');
    final second = WebPlaybackStatsStore(writerId: 'second-tab');
    final firstId = await first.deviceId();
    final secondId = await second.deviceId();
    expect(firstId, isNot(secondId));
    storage.setItem(WebPlaybackStatsStore.key, document({'legacy-device': 3}));
    // Both writers start from independently prepared, stale aggregate snapshots.
    await Future.wait([
      first.write(document({firstId: 5, secondId: 0})),
      second.write(document({firstId: 0, secondId: 2})),
    ]);
    final read = jsonDecode((await first.read())!)['counts']['song'];
    expect(read, {firstId: 5, secondId: 2, 'legacy-device': 3});
    final own = jsonDecode(
      storage.getItem('${WebPlaybackStatsStore.writerPrefix}first-tab')!,
    );
    expect(own['counts']['song'], {firstId: 5});
    expect(
      jsonDecode(storage.getItem(WebPlaybackStatsStore.key)!)['counts']['song'],
      {'legacy-device': 3},
    );
    await first.write(document({firstId: 1}));
    expect(jsonDecode((await second.read())!)['counts']['song'][firstId], 5);
  });

  test('corrupt browser snapshots are preserved and reported', () async {
    final store = WebPlaybackStatsStore(writerId: 'broken-tab');
    final name = '${WebPlaybackStatsStore.writerPrefix}broken-tab';
    storage.setItem(name, 'broken');
    await expectLater(store.read(), throwsFormatException);
    await expectLater(
      store.write(document({await store.deviceId(): 1})),
      throwsFormatException,
    );
    expect(storage.getItem(name), 'broken');
  });
}
