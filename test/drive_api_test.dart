import 'dart:convert';

import 'package:cloud_music/drive/drive_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('官方只读列表分页、音频过滤和 Authorization 请求头', () async {
    final requests = <http.Request>[];
    final api = DriveApi(
      accessToken: () async => 'private-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(
            request.url.queryParameters.containsKey('pageToken')
                ? {
                    'files': [
                      {
                        'id': 'song2',
                        'name': 'Two.FLAC',
                        'mimeType': 'application/octet-stream',
                      },
                    ],
                  }
                : {
                    'files': [
                      {
                        'id': 'folder',
                        'name': 'Album',
                        'mimeType': 'application/vnd.google-apps.folder',
                      },
                      {
                        'id': 'song1',
                        'name': 'One.mp3',
                        'mimeType': 'audio/mpeg',
                        'size': '42',
                      },
                      {
                        'id': 'other',
                        'name': 'document.txt',
                        'mimeType': 'text/plain',
                      },
                    ],
                    'nextPageToken': 'next-page',
                  },
          ),
          200,
        );
      }),
    );
    addTearDown(api.dispose);
    final files = await api.listFolder('root');
    expect(files.map((f) => f.id), ['folder', 'song1', 'song2']);
    expect(requests, hasLength(2));
    expect(requests.last.url.queryParameters['pageToken'], 'next-page');
    for (final request in requests) {
      expect(request.method, 'GET');
      expect(request.url.host, 'www.googleapis.com');
      expect(request.headers['Authorization'], 'Bearer private-token');
      expect(request.url.toString(), isNot(contains('private-token')));
      expect(
        request.url.queryParameters['q'],
        "'root' in parents and trashed = false",
      );
    }
  });

  test('递归扫描保留稳定 ID、歌曲路径和不可下载标记', () async {
    final api = DriveApi(
      accessToken: () async => 'token',
      client: MockClient((request) async {
        final root = request.url.queryParameters['q']!.startsWith("'root'");
        return http.Response(
          jsonEncode({
            'files': root
                ? [
                    {
                      'id': 'album',
                      'name': 'Album',
                      'mimeType': 'application/vnd.google-apps.folder',
                    },
                  ]
                : [
                    {
                      'id': 'song',
                      'name': 'Singer - Title.mp3',
                      'mimeType': 'audio/mpeg',
                      'capabilities': {'canDownload': false},
                    },
                    {
                      'id': 'shortcut',
                      'name': 'Shortcut',
                      'mimeType': 'application/vnd.google-apps.shortcut',
                    },
                  ],
          }),
          200,
        );
      }),
    );
    addTearDown(api.dispose);
    final scan = await api.scanFolder('root');
    expect(scan.tracks.single.id, 'gdrive:song');
    expect(scan.tracks.single.relativePath, 'Album/Singer - Title.mp3');
    expect(scan.tracks.single.artist, 'Singer');
    expect(scan.files['gdrive:song']!.canDownload, isFalse);
  });

  test('401 要求重新授权且错误不回显令牌或服务端内容', () async {
    final api = DriveApi(
      accessToken: () async => 'secret',
      client: MockClient((_) async => http.Response('secret server data', 401)),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.listFolder('root'),
      throwsA(
        isA<DriveException>()
            .having((e) => e.requiresAuthorization, 'reauth', true)
            .having((e) => e.message, 'message', isNot(contains('secret'))),
      ),
    );
  });

  test('不完整/重复分页不能作为空目录成功提交', () async {
    var incomplete = true;
    final api = DriveApi(
      accessToken: () async => 'token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(
            incomplete
                ? {'incompleteSearch': true}
                : {'nextPageToken': 'repeated', 'files': []},
          ),
          200,
        ),
      ),
    );
    addTearDown(api.dispose);
    await expectLater(api.listFolder('root'), throwsA(isA<DriveException>()));
    incomplete = false;
    await expectLater(api.listFolder('root'), throwsA(isA<DriveException>()));
  });

  test('非法 ID/取消不发送请求，媒体地址不包含令牌', () async {
    var count = 0;
    final api = DriveApi(
      accessToken: () async => 'token',
      client: MockClient((_) async {
        count++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.listFolder("x' or trashed = true"),
      throwsA(isA<DriveException>()),
    );
    await expectLater(
      api.listFolder('root', cancelled: () => true),
      throwsA(isA<DriveException>()),
    );
    expect(count, 0);
    expect(
      DriveApi.mediaUrl('song-id'),
      'https://www.googleapis.com/drive/v3/files/song-id?alt=media&supportsAllDrives=true',
    );
    expect(() => DriveApi.mediaUrl('../bad'), throwsA(isA<DriveException>()));
  });
}
