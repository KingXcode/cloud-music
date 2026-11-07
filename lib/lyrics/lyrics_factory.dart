import 'lyrics_native.dart'
    if (dart.library.js_interop) 'lyrics_web.dart'
    as platform;
import 'lyrics_platform.dart';

LyricsPlatform createLyricsPlatform() => platform.createLyricsPlatform();
