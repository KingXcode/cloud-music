import 'music_gateway.dart';
import 'native_factory.dart'
    if (dart.library.js_interop) 'web_factory.dart'
    as platform;

MusicGateway createMusicGateway() => platform.createGateway();
