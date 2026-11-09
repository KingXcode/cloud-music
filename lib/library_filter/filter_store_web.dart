import 'package:web/web.dart' as web;

import 'filter_store.dart';

FilterStore createFilterStore() => WebFilterStore();

class WebFilterStore implements FilterStore {
  static const key = 'cloud-music-library-filter-v1';

  @override
  Future<String?> read() async => web.window.localStorage.getItem(key);
  @override
  Future<void> write(String value) async =>
      web.window.localStorage.setItem(key, value);
}
