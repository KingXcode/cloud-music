import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'update_backend.dart';

typedef FetchUpdateBytes = Future<List<int>> Function(Uri url, int limit);

const updateRepository = 'KingXcode/cloud-music';
final releaseApiUrl = Uri.https(
  'api.github.com',
  '/repos/$updateRepository/releases',
  {'per_page': '30'},
);

bool isOfficialAssetUrl(Uri uri, String tag, String name) =>
    uri.scheme == 'https' &&
    uri.host == 'github.com' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    uri.query.isEmpty &&
    uri.fragment.isEmpty &&
    uri.pathSegments.join('/') ==
        '$updateRepository/releases/download/$tag/$name';

/// Public GitHub HTTPS metadata pins repository, release, names, size and digest.
/// SHA-256 is integrity protection, not a replacement for OS publisher signing.
class ReleaseApi {
  ReleaseApi(this.fetch);
  final FetchUpdateBytes fetch;

  Future<UpdateRelease?> check(InstalledVersion current) async {
    final raw = jsonDecode(
      utf8.decode(await fetch(releaseApiUrl, 2 * 1024 * 1024)),
    );
    if (raw is! List) throw const UpdateException('版本服务返回了无效数据。');
    final candidates = <UpdateRelease>[];
    for (final item in raw) {
      if (item is! Map || item['draft'] != false) continue;
      final tag = item['tag_name'];
      if (tag is! String ||
          !RegExp(r'^v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$').hasMatch(tag)) {
        continue;
      }
      if (compareVersions(tag, current.version) < 0) continue;
      final assets = item['assets'];
      if (assets is! List) continue;
      Map? findAsset(String name) {
        final found = assets
            .whereType<Map>()
            .where((a) => a['name'] == name && a['state'] == 'uploaded')
            .toList();
        return found.length == 1 ? found.single : null;
      }

      final manifestAsset = findAsset('update-manifest.json');
      // Older releases do not contain the secure updater contract.
      if (manifestAsset == null) continue;
      final manifestMeta = _asset(manifestAsset, tag, maxSize: 128 * 1024);
      final bytes = await fetch(manifestMeta.url, 128 * 1024);
      _verify(bytes, manifestMeta);
      final manifest = jsonDecode(utf8.decode(bytes));
      if (manifest is! Map || manifest['schema'] != 1) {
        throw const UpdateException('更新清单格式不受支持。');
      }
      final version = manifest['version'], build = manifest['build'];
      if (version is! String ||
          !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
          build is! String ||
          !RegExp(r'^[1-9]\d{0,8}$').hasMatch(build) ||
          compareVersions(tag, version) != 0) {
        throw const UpdateException('更新清单的版本与发布标签不一致。');
      }
      if (compareVersions(version, current.version) < 0 ||
          int.parse(build) <= (int.tryParse(current.build) ?? 0)) {
        continue;
      }
      final artifacts = manifest['artifacts'];
      final artifact = artifacts is Map ? artifacts[current.platform] : null;
      if (artifact is! Map) continue;
      final architectures = artifact['architectures'];
      if (architectures is! List ||
          !architectures.contains(current.architecture)) {
        continue;
      }
      final expectedName = current.platform == 'android'
          ? 'cloud-music-android-test-signed.apk'
          : 'cloud-music-macos-unsigned.dmg';
      if (artifact['name'] != expectedName) {
        throw const UpdateException('发布包名称不受信任。');
      }
      final metadata = findAsset(expectedName);
      if (metadata == null) throw const UpdateException('新版本尚未发布完整，请稍后检查。');
      final asset = _asset(metadata, tag);
      if (artifact['sha256'] != asset.sha256 ||
          artifact['size'] != asset.size) {
        throw const UpdateException('发布包与校验清单不一致，已停止更新。');
      }
      candidates.add(
        UpdateRelease(
          version: version,
          build: build,
          notes: '${item['body'] ?? ''}'.substring(
            0,
            '${item['body'] ?? ''}'.length.clamp(0, 4000),
          ),
          releasePage: Uri.https(
            'github.com',
            '/$updateRepository/releases/tag/$tag',
          ),
          asset: asset,
        ),
      );
    }
    candidates.sort((a, b) {
      final version = compareVersions(b.version, a.version);
      return version == 0
          ? int.parse(b.build).compareTo(int.parse(a.build))
          : version;
    });
    return candidates.firstOrNull;
  }

  UpdateAsset _asset(Map raw, String tag, {int maxSize = 600 * 1024 * 1024}) {
    final name = raw['name'],
        size = raw['size'],
        digest = raw['digest'],
        url = raw['browser_download_url'];
    if (name is! String ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name) ||
        size is! int ||
        size <= 0 ||
        size > maxSize ||
        digest is! String ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest) ||
        url is! String) {
      throw const UpdateException('发布包缺少可信校验信息，不能自动下载。');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !isOfficialAssetUrl(uri, tag, name)) {
      throw const UpdateException('更新地址不属于官方仓库。');
    }
    return UpdateAsset(
      name: name,
      url: uri,
      size: size,
      sha256: digest.substring(7),
    );
  }

  void _verify(List<int> bytes, UpdateAsset asset) {
    if (bytes.length != asset.size ||
        sha256.convert(bytes).toString() != asset.sha256) {
      throw const UpdateException('更新清单校验失败，已停止更新。');
    }
  }
}
