import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

const driveReadOnlyScope = 'https://www.googleapis.com/auth/drive.readonly';
const _folderMime = 'application/vnd.google-apps.folder';
const _audioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'flac',
  'wav',
  'aif',
  'aiff',
  'ogg',
  'opus',
  'alac',
  'wma',
};

class DriveException implements Exception {
  const DriveException(this.message, {this.requiresAuthorization = false});
  final String message;
  final bool requiresAuthorization;
  @override
  String toString() => message;
}

class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    this.size = 0,
    this.canDownload = true,
  });
  final String id, name, mimeType;
  final int size;
  final bool canDownload;
  bool get isFolder => mimeType == _folderMime;
  bool get isAudio =>
      !isFolder &&
      (mimeType.startsWith('audio/') ||
          _audioExtensions.contains(name.split('.').last.toLowerCase()));

  factory DriveFile.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? '';
    if (!validDriveId(id)) {
      throw const DriveException('Google Drive 返回了无效文件编号。');
    }
    return DriveFile(
      id: id,
      name: map['name'] as String? ?? '未命名',
      mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
      size: int.tryParse('${map['size'] ?? 0}') ?? 0,
      canDownload: (map['capabilities'] as Map?)?['canDownload'] != false,
    );
  }

  Track toTrack(String path) => Track.fromMap({
    'id': 'gdrive:$id',
    'title': '',
    'relativePath': path,
    'status': canDownload ? 'cloud' : 'unsupported',
  });
}

bool validDriveId(String id) => RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(id);

class DriveScan {
  const DriveScan(this.tracks, this.files);
  final List<Track> tracks;
  final Map<String, DriveFile> files;
}

/// 只读官方 API。每次请求重新获取会话令牌，错误中不包含服务器响应或凭据。
class DriveApi {
  DriveApi({
    required Future<String> Function() accessToken,
    http.Client? client,
    // 公开注入参数与私有字段刻意保留不同名称。
    // ignore: prefer_initializing_formals
  }) : _accessToken = accessToken,
       _client = client ?? http.Client();
  final Future<String> Function() _accessToken;
  final http.Client _client;

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final token = await _accessToken();
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.https('www.googleapis.com', '/drive/v3/$path', query),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const DriveException('Google Drive 请求超时，请检查网络后重试。');
    } on http.ClientException {
      throw const DriveException('无法连接 Google Drive，请检查网络。');
    }
    if (response.statusCode == 401) {
      throw const DriveException(
        'Google 授权已过期，请重新连接。',
        requiresAuthorization: true,
      );
    }
    if (response.statusCode == 403) {
      throw const DriveException('Google Drive 拒绝读取。请检查只读授权、文件下载权限、API 配置或配额。');
    }
    if (response.statusCode == 404) {
      throw const DriveException('找不到 Google Drive 文件夹或文件，或已失去访问权限。原曲库未清空。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const DriveException('Google Drive 暂时不可用，请稍后重试。');
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const DriveException('Google Drive 返回的数据无法读取。');
    } on TypeError {
      throw const DriveException('Google Drive 返回的数据格式不正确。');
    }
  }

  Future<String> accountIdentity() async {
    final data = await _get('about', {'fields': 'user(permissionId)'});
    final id = (data['user'] as Map?)?['permissionId'];
    if (id is! String || id.isEmpty) {
      throw const DriveException('无法确认当前 Google Drive 账户，请重新连接。');
    }
    return id;
  }

  Future<List<DriveFile>> listFolder(
    String folderId, {
    bool Function()? cancelled,
  }) async {
    if (!validDriveId(folderId)) throw const DriveException('文件夹编号无效。');
    final files = <String, DriveFile>{};
    final seenPages = <String>{};
    String? page;
    do {
      if (cancelled?.call() == true) throw const DriveException('已取消读取。');
      final data = await _get('files', {
        'q': "'$folderId' in parents and trashed = false",
        'fields': 'nextPageToken,incompleteSearch,files(id,name,mimeType,size,capabilities(canDownload))',
        'pageSize': '1000',
        'orderBy': 'folder,name_natural',
        'spaces': 'drive',
        'supportsAllDrives': 'true',
        'includeItemsFromAllDrives': 'true',
        'pageToken': ?page,
      });
      if (cancelled?.call() == true) throw const DriveException('已取消读取。');
      if (data['incompleteSearch'] == true) {
        throw const DriveException('Google Drive 未返回完整目录，已保留原曲库，请重试。');
      }
      for (final raw in (data['files'] as List? ?? const [])) {
        final file = DriveFile.fromMap(Map<String, dynamic>.from(raw as Map));
        if (file.isFolder || file.isAudio) files[file.id] = file;
      }
      page = data['nextPageToken'] as String?;
      if (page != null && (!seenPages.add(page) || seenPages.length > 100)) {
        throw const DriveException('目录分页异常或过大，请选择较小的音乐文件夹。');
      }
    } while (page != null && page.isNotEmpty);
    return files.values.toList(growable: false);
  }

  Future<DriveScan> scanFolder(
    String folderId, {
    bool Function()? cancelled,
  }) async {
    final pending = <({String id, String path, int depth})>[
      (id: folderId, path: '', depth: 0),
    ];
    final visited = <String>{};
    final files = <String, DriveFile>{};
    final tracks = <Track>[];
    while (pending.isNotEmpty) {
      final folder = pending.removeLast();
      if (!visited.add(folder.id)) continue;
      if (visited.length > 500 || folder.depth > 20) {
        throw const DriveException('文件夹层级或数量过多，请选择较小的音乐目录。原曲库未替换。');
      }
      for (final file in await listFolder(folder.id, cancelled: cancelled)) {
        final path = folder.path.isEmpty
            ? file.name
            : '${folder.path}/${file.name}';
        if (file.isFolder) {
          pending.add((id: file.id, path: path, depth: folder.depth + 1));
        } else if (file.isAudio && !files.containsKey('gdrive:${file.id}')) {
          final track = file.toTrack(path);
          tracks.add(track);
          files[track.id] = file;
          if (tracks.length > 10000) {
            throw const DriveException('歌曲超过 10000 首，请选择较小的音乐目录。原曲库未替换。');
          }
        }
      }
    }
    tracks.sort(
      (a, b) =>
          a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()),
    );
    return DriveScan(tracks, files);
  }

  static String mediaUrl(String fileId) {
    if (!validDriveId(fileId)) throw const DriveException('歌曲编号无效。');
    return Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
      'alt': 'media',
      'supportsAllDrives': 'true',
    }).toString();
  }

  void dispose() => _client.close();
}
