import 'dart:convert';

import 'package:cloud_music/updates/release_api.dart';
import 'package:cloud_music/updates/update_backend.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _current = InstalledVersion(
  version: '0.6.0',
  build: '8',
  platform: 'android',
  architecture: 'arm64-v8a',
);
const _apk = 'cloud-music-android-test-signed.apk';
const _dmg = 'cloud-music-macos-unsigned.dmg';

class _ReleaseFixture {
  _ReleaseFixture({this.tag = 'v0.7.0-preview', String build = '9'}) {
    artifact = {
      'name': _apk,
      'sha256': sha256.convert([1, 2, 3]).toString(),
      'size': 3,
      'architectures': ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
    };
    manifest = {
      'schema': 1,
      'version': '0.7.0',
      'build': build,
      'artifacts': {'android': artifact},
    };
    package = asset(_apk, [1, 2, 3]);
  }

  final String tag;
  late Map<String, dynamic> artifact;
  late Map<String, dynamic> manifest;
  late Map<String, dynamic> package;
  List<int>? manifestBytes;
  void Function(Map<String, dynamic>)? changeManifestAsset;
  void Function(Map<String, dynamic>)? changeRelease;
  final fetched = <Uri>[];

  Uri url(String name) => Uri.https(
    'github.com',
    '/$updateRepository/releases/download/$tag/$name',
  );

  Map<String, dynamic> asset(String name, List<int> bytes) => {
    'name': name,
    'state': 'uploaded',
    'size': bytes.length,
    'digest': 'sha256:${sha256.convert(bytes)}',
    'browser_download_url': url(name).toString(),
  };

  Future<UpdateRelease?> check([InstalledVersion current = _current]) {
    final expected = utf8.encode(jsonEncode(manifest));
    final manifestAsset = asset('update-manifest.json', expected);
    changeManifestAsset?.call(manifestAsset);
    final release = <String, dynamic>{
      'tag_name': tag,
      'draft': false,
      'prerelease': true,
      'body': '修复并改善更新体验。',
      'assets': [manifestAsset, package],
    };
    changeRelease?.call(release);
    return ReleaseApi((uri, limit) async {
      fetched.add(uri);
      if (uri == releaseApiUrl) {
        expect(limit, 2 * 1024 * 1024);
        return utf8.encode(jsonEncode([release]));
      }
      expect(uri, url('update-manifest.json'));
      expect(limit, 128 * 1024);
      return manifestBytes ?? expected;
    }).check(current);
  }
}

void main() {
  group('version ordering', () {
    test(
      'compares numeric components, not strings, and accepts preview tags',
      () {
        expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
        expect(compareVersions('v0.7.0-preview', '0.7.0'), 0);
        expect(compareVersions('1.0.0', '2.0.0'), lessThan(0));
        expect(() => compareVersions('latest', '0.6.0'), throwsFormatException);
      },
    );
  });

  test(
    'accepts a digest-pinned official preview for this architecture',
    () async {
      final fixture = _ReleaseFixture();
      final release = await fixture.check();
      expect(release!.version, '0.7.0');
      expect(release.build, '9');
      expect(release.asset!.name, _apk);
      expect(release.asset!.size, 3);
      expect(release.asset!.sha256, fixture.artifact['sha256']);
      expect(
        release.releasePage.toString(),
        'https://github.com/KingXcode/cloud-music/releases/tag/v0.7.0-preview',
      );
      expect(fixture.fetched, [
        releaseApiUrl,
        fixture.url('update-manifest.json'),
      ]);
    },
  );

  test(
    'uses the official DMG only for a matching macOS architecture',
    () async {
      final fixture = _ReleaseFixture();
      fixture.artifact['name'] = _dmg;
      fixture.artifact['architectures'] = ['arm64', 'x86_64'];
      fixture.manifest['artifacts'] = {'macos': fixture.artifact};
      fixture.package = fixture.asset(_dmg, [1, 2, 3]);
      final release = await fixture.check(
        const InstalledVersion(
          version: '0.6.0',
          build: '8',
          platform: 'macos',
          architecture: 'arm64',
        ),
      );
      expect(release!.asset!.name, _dmg);
    },
  );

  for (final url in [
    'http://github.com/KingXcode/cloud-music/releases/download/v0.7.0-preview/$_apk',
    'https://github.com.evil.example/KingXcode/cloud-music/releases/download/v0.7.0-preview/$_apk',
    'https://github.com/OtherOwner/cloud-music/releases/download/v0.7.0-preview/$_apk',
    'https://github.com/KingXcode/cloud-music/releases/download/v0.6.0/$_apk',
    'https://github.com/KingXcode/cloud-music/releases/download/v0.7.0-preview/other.apk',
    'https://user@github.com/KingXcode/cloud-music/releases/download/v0.7.0-preview/$_apk',
    'https://github.com:8443/KingXcode/cloud-music/releases/download/v0.7.0-preview/$_apk',
    'https://github.com/KingXcode/cloud-music/releases/download/v0.7.0-preview/$_apk?download=1',
    'https://github.com/KingXcode/cloud-music/releases/download/v0.7.0-preview/$_apk#fragment',
    'https://release-assets.githubusercontent.com/$_apk',
  ]) {
    test('rejects a noncanonical asset address: $url', () async {
      final fixture = _ReleaseFixture();
      fixture.package['browser_download_url'] = url;
      await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
    });
  }

  test('rejects untrusted manifest URL before fetching it', () async {
    final fixture = _ReleaseFixture()
      ..changeManifestAsset = (asset) {
        asset['browser_download_url'] = 'https://evil.example/manifest.json';
      };
    await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
    expect(fixture.fetched, [releaseApiUrl]);
  });

  for (final digest in [null, '', 'sha1:1234', 'sha256:ABC', 'a' * 64]) {
    test('rejects absent or malformed GitHub digest $digest', () async {
      final fixture = _ReleaseFixture();
      fixture.package['digest'] = digest;
      await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
    });
  }

  test('rejects a manifest digest mismatch and truncated manifest', () async {
    for (final bytes in [utf8.encode('{"schema":1}'), <int>[]]) {
      final fixture = _ReleaseFixture()..manifestBytes = bytes;
      await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
    }
  });

  test(
    'rejects a wrong digest even when the manifest length matches',
    () async {
      final fixture = _ReleaseFixture()
        ..changeManifestAsset = (asset) =>
            asset['digest'] = 'sha256:${'0' * 64}';
      await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
    },
  );

  for (final size in [0, -1, 600 * 1024 * 1024 + 1, '3']) {
    test('rejects invalid or excessive package size $size', () async {
      final fixture = _ReleaseFixture();
      fixture.package['size'] = size;
      await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
    });
  }

  for (final mutation in <String, void Function(_ReleaseFixture)>{
    'unknown schema': (f) => f.manifest['schema'] = 2,
    'mismatched version': (f) => f.manifest['version'] = '0.8.0',
    'non-numeric version': (f) => f.manifest['version'] = 'latest',
    'missing build': (f) => f.manifest.remove('build'),
    'numeric rather than string build': (f) => f.manifest['build'] = 9,
    'zero build': (f) => f.manifest['build'] = '0',
    'negative build': (f) => f.manifest['build'] = '-9',
    'unbounded build': (f) => f.manifest['build'] = '9999999999',
    'wrong package name': (f) => f.artifact['name'] = 'untrusted.apk',
    'manifest package digest mismatch': (f) => f.artifact['sha256'] = '0' * 64,
    'manifest package size mismatch': (f) => f.artifact['size'] = 4,
  }.entries) {
    test('rejects ${mutation.key}', () async {
      final fixture = _ReleaseFixture();
      mutation.value(fixture);
      await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
    });
  }

  test(
    'skips incompatible architectures and missing platform artifacts',
    () async {
      final fixture = _ReleaseFixture();
      fixture.artifact['architectures'] = ['x86_64'];
      expect(await fixture.check(), isNull);
      fixture.manifest['artifacts'] = {};
      expect(await fixture.check(), isNull);
    },
  );

  test(
    'requires a higher build even when the display version is higher',
    () async {
      expect(await _ReleaseFixture(build: '8').check(), isNull);
      expect(await _ReleaseFixture(build: '7').check(), isNull);
    },
  );

  test('accepts a higher build of the same display version', () async {
    final fixture = _ReleaseFixture(tag: 'v0.6.0-preview');
    fixture.manifest['version'] = '0.6.0';
    expect((await fixture.check())!.build, '9');
  });

  test('does not offer downgrades, drafts or invalid tags', () async {
    final old = _ReleaseFixture(tag: 'v0.5.0-preview');
    old.manifest['version'] = '0.5.0';
    expect(await old.check(), isNull);
    expect(
      await (_ReleaseFixture()..changeRelease = (r) => r['draft'] = true)
          .check(),
      isNull,
    );
    expect(await _ReleaseFixture(tag: 'latest').check(), isNull);
  });

  test(
    'legacy releases without a manifest are not silently auto-installed',
    () async {
      final fixture = _ReleaseFixture()
        ..changeRelease = (r) => (r['assets'] as List).removeAt(0);
      expect(await fixture.check(), isNull);
    },
  );

  test(
    'rejects a partial release with a missing or unfinished package',
    () async {
      for (final state in ['missing', 'starter']) {
        final fixture = _ReleaseFixture();
        if (state == 'missing') {
          fixture.changeRelease = (r) => (r['assets'] as List).removeLast();
        } else {
          fixture.package['state'] = state;
        }
        await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
      }
    },
  );

  test(
    'rejects duplicate package assets instead of choosing arbitrarily',
    () async {
      final fixture = _ReleaseFixture()
        ..changeRelease = (r) =>
            (r['assets'] as List).add((r['assets'] as List).last);
      await expectLater(fixture.check(), throwsA(isA<UpdateException>()));
    },
  );

  test('bounds release notes and rejects a malformed API response', () async {
    final fixture = _ReleaseFixture()
      ..changeRelease = (r) => r['body'] = 'x' * 5000;
    expect((await fixture.check())!.notes.length, 4000);
    await expectLater(
      ReleaseApi((_, _) async => utf8.encode('{}')).check(_current),
      throwsA(isA<UpdateException>()),
    );
  });
}
