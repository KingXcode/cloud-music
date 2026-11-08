import 'music_gateway.dart';
import 'source_music_gateway.dart';
import '../drive/drive_factory.dart';
import 'native_factory.dart'
    if (dart.library.js_interop) 'web_factory.dart'
    as platform;

MusicGateway createMusicGateway() => SourceMusicGateway(
  local: platform.createGateway(),
  drive: createDriveGateway(),
);
