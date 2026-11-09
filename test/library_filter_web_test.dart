@TestOn('browser')
library;

import 'package:cloud_music/library_filter/filter_store_web.dart';
import 'package:cloud_music/library_filter/library_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('web settings persist across controller reload without altering library cache', () async {
    final old = web.window.localStorage.getItem(WebFilterStore.key);
    final filter = LibraryFilter(store: WebFilterStore());
    final restored = LibraryFilter(store: WebFilterStore());
    try {
      await filter.update(enabled: false, minimumSeconds: 45);
      await restored.initialize();
      expect(restored.enabled, false);
      expect(restored.minimumSeconds, 45);
    } finally {
      filter.dispose();
      restored.dispose();
      if (old == null) {
        web.window.localStorage.removeItem(WebFilterStore.key);
      } else {
        web.window.localStorage.setItem(WebFilterStore.key, old);
      }
    }
  });
}
