import 'dart:async';
import 'dart:io';

import 'package:cloud_music/updates/update_backend.dart';
import 'package:cloud_music/updates/update_native.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Headers implements HttpHeaders {
  _Headers([this.values = const {}]);
  final Map<String, String> values;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => values[name];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.body, {
    this.statusCode = 200,
    this.contentLength = -1,
    Map<String, String> headers = const {},
  }) : headers = _Headers(headers);
  final Stream<List<int>> body;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final HttpClientResponse response;
  @override
  final HttpHeaders headers = _Headers();
  @override
  bool followRedirects = false;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.respond);
  final HttpClientResponse Function(Uri) respond;
  final requests = <Uri>[];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return _Request(respond(url));
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UpdateRelease _release(List<int> payload, {Uri? url}) => UpdateRelease(
  version: '0.7.0',
  build: '9',
  releasePage: Uri.parse(
    'https://github.com/KingXcode/cloud-music/releases/tag/v0.7.0-preview',
  ),
  asset: UpdateAsset(
    name: 'cloud-music-macos-unsigned.dmg',
    url:
        url ??
        Uri.parse(
          'https://github.com/KingXcode/cloud-music/releases/download/v0.7.0-preview/cloud-music-macos-unsigned.dmg',
        ),
    size: payload.length,
    sha256: sha256.convert(payload).toString(),
  ),
);

Future<T> _withClient<T>(_Client client, Future<T> Function() body) =>
    HttpOverrides.runZoned(body, createHttpClient: (_) => client);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.cloudmusic/updates');
  late Directory directory;
  late NativeUpdateBackend backend;
  late List<MethodCall> calls;
  const payload = [1, 2, 3, 4];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'cloud-music-update-test-',
    );
    backend = NativeUpdateBackend(channel: channel);
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getDownloadDirectory') return directory.path;
          if (call.method == 'installDownloaded') return 'opened';
          if (call.method == 'openReleasePage') return null;
          throw PlatformException(code: 'unexpected_method');
        });
  });
  tearDown(() async {
    backend.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('opens only official HTTPS release pages without downloading files', () async {
    await backend.openReleasePage(_release(payload));
    expect(calls.single.method, 'openReleasePage');
    expect(directory.listSync(), isEmpty);
    calls.clear();
    for (final url in [
      'file:///tmp/update.dmg',
      'https://github.com.evil.test/KingXcode/cloud-music/releases/tag/v0.7.6',
      'https://github.com/Other/project/releases/tag/v0.7.6',
      'https://github.com/KingXcode/cloud-music/releases/tag/v0.7.6?redirect=other',
    ]) {
      await expectLater(
        backend.openReleasePage(
          UpdateRelease(
            version: '0.7.6',
            build: '18',
            releasePage: Uri.parse(url),
          ),
        ),
        throwsA(isA<UpdateException>()),
      );
    }
    expect(calls, isEmpty);
  });

  test(
    'verifies complete bytes, removes partial file and never auto-installs',
    () async {
      final client = _Client(
        (_) => _Response(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          contentLength: 4,
        ),
      );
      final progress = <int>[];
      await _withClient(
        client,
        () => backend.download(_release(payload), (received, total) {
          expect(total, 4);
          progress.add(received);
        }),
      );
      expect(progress, [0, 2, 4]);
      final files = directory.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(files.single.path, isNot(endsWith('.part')));
      expect(await files.single.readAsBytes(), payload);
      expect(
        calls.where((call) => call.method == 'installDownloaded'),
        isEmpty,
      );
      expect(await backend.install(_release(payload)), 'opened');
      expect(
        calls.where((call) => call.method == 'installDownloaded'),
        hasLength(1),
      );
    },
  );

  test(
    'rechecks the verified file before handing it to the installer',
    () async {
      final client = _Client(
        (_) => _Response(Stream.value(payload), contentLength: 4),
      );
      await _withClient(
        client,
        () => backend.download(_release(payload), (_, _) {}),
      );
      final file = directory.listSync().whereType<File>().single;
      await file.writeAsBytes([9, 9, 9, 9]);
      await expectLater(
        backend.install(_release(payload)),
        throwsA(isA<UpdateException>()),
      );
      expect(
        calls.where((call) => call.method == 'installDownloaded'),
        isEmpty,
      );
    },
  );

  test(
    'does not invoke an installer without a successfully verified download',
    () async {
      await expectLater(
        backend.install(_release(payload)),
        throwsA(isA<UpdateException>()),
      );
      expect(calls, isEmpty);
    },
  );

  for (final bytes in [
    <int>[9, 9, 9, 9],
    <int>[1, 2],
    <int>[1, 2, 3, 4, 5],
  ]) {
    test(
      'rejects corrupt, truncated or oversized download $bytes and cleans partials',
      () async {
        final client = _Client((_) => _Response(Stream.value(bytes)));
        await expectLater(
          _withClient(
            client,
            () => backend.download(_release(payload), (_, _) {}),
          ),
          throwsA(isA<UpdateException>()),
        );
        expect(directory.listSync(), isEmpty);
        await expectLater(
          backend.install(_release(payload)),
          throwsA(isA<UpdateException>()),
        );
        expect(
          calls.where((call) => call.method == 'installDownloaded'),
          isEmpty,
        );
      },
    );
  }

  test(
    'rejects mismatching Content-Length before committing a package',
    () async {
      final client = _Client(
        (_) => _Response(Stream.value(payload), contentLength: 5),
      );
      await expectLater(
        _withClient(
          client,
          () => backend.download(_release(payload), (_, _) {}),
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(directory.listSync(), isEmpty);
    },
  );

  for (final target in [
    'https://evil.example/package.dmg',
    'http://github.com/KingXcode/cloud-music/releases/download/v0.7.0-preview/package.dmg',
    'https://release-assets.githubusercontent.com.evil.example/package.dmg',
    'https://user@release-assets.githubusercontent.com/package.dmg',
    'https://release-assets.githubusercontent.com:444/package.dmg',
  ]) {
    test('stops an untrusted redirect before requesting $target', () async {
      final client = _Client(
        (_) => _Response(
          const Stream.empty(),
          statusCode: 302,
          headers: {HttpHeaders.locationHeader: target},
        ),
      );
      await expectLater(
        _withClient(
          client,
          () => backend.download(_release(payload), (_, _) {}),
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(client.requests, hasLength(1));
      expect(directory.listSync(), isEmpty);
    });
  }

  test(
    'accepts the GitHub asset CDN redirect and validates the final bytes',
    () async {
      final client = _Client(
        (uri) => uri.host == 'github.com'
            ? _Response(
                const Stream.empty(),
                statusCode: 302,
                headers: {
                  HttpHeaders.locationHeader: 'https://release-assets.githubusercontent.com/github-production-release-asset/123?signature=test',
                },
              )
            : _Response(Stream.value(payload), contentLength: 4),
      );
      await _withClient(
        client,
        () => backend.download(_release(payload), (_, _) {}),
      );
      expect(client.requests, hasLength(2));
      expect(directory.listSync(), hasLength(1));
    },
  );

  test('limits redirect loops and cleans cache on HTTP failures', () async {
    for (final status in [302, 403, 429, 500]) {
      final client = _Client(
        (_) => _Response(
          const Stream.empty(),
          statusCode: status,
          headers: {
            HttpHeaders.locationHeader: _release(payload).asset!.url.toString(),
          },
        ),
      );
      await expectLater(
        _withClient(
          client,
          () => backend.download(_release(payload), (_, _) {}),
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(client.requests.length, lessThanOrEqualTo(6));
      expect(directory.listSync(), isEmpty);
    }
  });

  test(
    'cancelling a queued restart cannot start a transfer after cancellation',
    () async {
      final body = StreamController<List<int>>();
      final requested = Completer<void>();
      final client = _Client((_) {
        if (!requested.isCompleted) requested.complete();
        return _Response(body.stream);
      });
      await _withClient(client, () async {
        final first = backend.download(_release(payload), (_, _) {});
        final firstResult = expectLater(first, throwsA(isA<UpdateCancelled>()));
        await requested.future;
        backend.cancel();
        final queued = backend.download(_release(payload), (_, _) {});
        final queuedResult = expectLater(
          queued,
          throwsA(isA<UpdateCancelled>()),
        );
        backend.cancel();
        await body.close();
        await firstResult;
        await queuedResult;
        expect(client.requests, hasLength(1));
        expect(directory.listSync(), isEmpty);
      });
    },
  );

  test('cache cleanup preserves unrelated user files', () async {
    final unrelated = File('${directory.path}/music.mp3');
    await unrelated.writeAsBytes([7, 8, 9]);
    await File('${directory.path}/update-${'0' * 64}.dmg.part')
        .writeAsBytes([0]);
    final client = _Client(
      (_) => _Response(Stream.value(payload), contentLength: 4),
    );
    await _withClient(
      client,
      () => backend.download(_release(payload), (_, _) {}),
    );
    expect(await unrelated.readAsBytes(), [7, 8, 9]);
    expect(directory.listSync(), hasLength(2));
    expect(
      directory.listSync().any((file) => file.path.endsWith('.part')),
      isFalse,
    );
  });
}
