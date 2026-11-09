import 'package:flutter/services.dart';

import 'filter_store.dart';

FilterStore createFilterStore() => NativeFilterStore();

class NativeFilterStore implements FilterStore {
  NativeFilterStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('cloud_music/control');
  final MethodChannel _channel;

  @override
  Future<String?> read() => _channel.invokeMethod<String>('readLibraryFilter');
  @override
  Future<void> write(String value) =>
      _channel.invokeMethod<void>('writeLibraryFilter', {'value': value});
}
