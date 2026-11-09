import 'filter_store.dart';
import 'filter_store_native.dart'
    if (dart.library.js_interop) 'filter_store_web.dart'
    as platform;

FilterStore createFilterStore() => platform.createFilterStore();
