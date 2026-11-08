import 'package:cloud_music/drive/drive_native.dart';
import 'package:cloud_music/drive/drive_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'unsupported desktop explains browser fallback without invoking SDK',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final platform = NativeDrivePlatform();
      expect(platform.configured, isFalse);
      expect(platform.setupMessage, contains('浏览器'));
      await platform.initialize();
      expect(await platform.authorize(), isNull);
      expect(await platform.authorize(interactive: true), isNull);
      await platform.disconnect();
      await platform.dispose();
    },
  );

  test('unconfigured native builds do not start interactive login', () async {
    for (final target in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = target;
      final platform = NativeDrivePlatform();
      expect(platform.configured, isFalse);
      expect(await platform.authorize(interactive: true), isNull);
      await platform.dispose();
    }
  });

  test(
    'untrusted audio URLs are rejected before constructing a player',
    () async {
      final platform = NativeDrivePlatform();
      final events = <DrivePlayback>[];
      final subscription = platform.playback.listen(events.add);
      for (final url in [
        'http://www.googleapis.com/drive/v3/files/id?alt=media',
        'https://evil.example/drive/v3/files/id?alt=media',
        'https://www.googleapis.com.evil.example/drive/v3/files/id?alt=media',
        'https://www.googleapis.com/drive/v3/files/id?alt=media&access_token=secret',
        'https://www.googleapis.com/drive/v3/files/id?alt=media#fragment',
        'https://user@www.googleapis.com/drive/v3/files/id?alt=media',
        'https://www.googleapis.com:443/drive/v3/files/id?alt=media',
        'https://www.googleapis.com/other?alt=media',
      ]) {
        await platform.play(
          DriveAudioRequest(
            id: 'track',
            url: url,
            accessToken: 'never-log-token',
            mimeType: 'audio/mpeg',
            size: 1,
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(8));
      expect(
        events.every((event) => event.id == 'track' && event.error != null),
        isTrue,
      );
      expect(
        events.every((event) => !event.error!.contains('never-log-token')),
        isTrue,
      );
      await platform.stop();
      await subscription.cancel();
      await platform.dispose();
      await platform.dispose();
    },
  );
}
