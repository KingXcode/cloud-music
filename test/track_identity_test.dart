import 'package:cloud_music/models.dart';
import 'package:cloud_music/track_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('本地文件名识别', () {
    final cases = <(String, String, String)>[
      ('S0015 张靓颖 - 天下无双', '天下无双', '张靓颖'),
      ('01. 张靓颖 - 天下无双.flac', '天下无双', '张靓颖'),
      ('001 - 张靓颖 - 天下无双.mp3', '天下无双', '张靓颖'),
      ('01 张靓颖 - 天下无双.mp3', '天下无双', '张靓颖'),
      ('张靓颖–天下无双', '天下无双', '张靓颖'),
      ('张靓颖—天下无双', '天下无双', '张靓颖'),
      ('张靓颖－天下无双', '天下无双', '张靓颖'),
      ('张靓颖-天下无双', '天下无双', '张靓颖'),
      ('张靓颖_天下无双', '天下无双', '张靓颖'),
      ('Artist feat. Guest - Song.mp3', 'Song', 'Artist feat. Guest'),
      ('Artist - Song (feat. Guest).mp3', 'Song (feat. Guest)', 'Artist'),
      ('Artist - Song (Live).flac', 'Song (Live)', 'Artist'),
      ('Artist - Song - Remix.mp3', 'Song - Remix', 'Artist'),
      ('Artist - Song (2024 Version).mp3', 'Song (2024 Version)', 'Artist'),
      ('AC-DC - Thunderstruck.mp3', 'Thunderstruck', 'AC-DC'),
      ('Artist - 1979.mp3', '1979', 'Artist'),
      ('Artist - Song [FLAC] [320kbps].flac', 'Song', 'Artist'),
      ('Artist - Song【无损】.mp3', 'Song', 'Artist'),
      ('Artist - Song (24bit 96kHz).flac', 'Song', 'Artist'),
      ('Artist - Song_SQ.mp3', 'Song', 'Artist'),
      ('1979.mp3', '1979', ''),
      ('99 Luftballons.mp3', '99 Luftballons', ''),
      ('AC-DC.mp3', 'AC-DC', ''),
      ('Love-Hate.mp3', 'Love-Hate', ''),
      ('some_song_name.mp3', 'some_song_name', ''),
      ('普通歌曲.mp3', '普通歌曲', ''),
    ];
    for (final (filename, title, artist) in cases) {
      test(filename, () {
        final identity = normalizeTrackIdentity(relativePath: '音乐/$filename');
        expect(identity.title, title);
        expect(identity.artist, artist);
      });
    }
    test('文件名标题回退与未知歌手', () {
      final identity = normalizeTrackIdentity(
        title: 'S0015 张靓颖 - 天下无双',
        artist: '未知歌手',
      );
      expect(identity.title, '天下无双');
      expect(identity.artist, '张靓颖');
    });
    test('Windows 路径与大写扩展名', () {
      final identity = normalizeTrackIdentity(
        relativePath: r'音乐\Artist - Song.FLAC',
      );
      expect(identity.title, 'Song');
      expect(identity.artist, 'Artist');
    });
    test('没有路径的文件扩展名回退', () {
      expect(normalizeTrackIdentity(title: '1979.mp3').title, '1979');
    });
    test('保留有效内嵌标签与专辑', () {
      final track = Track.fromMap({
        'id': '1',
        'title': '真实标题 (Live)',
        'artist': '真实歌手',
        'album': '真实专辑',
        'relativePath': '其他歌手 - 其他标题.mp3',
        'durationMs': 1234,
        'status': 'ready',
      });
      expect(track.title, '真实标题 (Live)');
      expect(track.artist, '真实歌手');
      expect(track.album, '真实专辑');
      expect(track.duration.inMilliseconds, 1234);
      expect(track.availability, TrackAvailability.ready);
    });
    test('不拆开有歌手标签的有效标题', () {
      final identity = normalizeTrackIdentity(
        title: 'Song - Part II',
        artist: 'Artist',
      );
      expect(identity.title, 'Song - Part II');
      expect(identity.artist, 'Artist');
    });
    test('同名文件不覆盖有效的内嵌标题', () {
      final identity = normalizeTrackIdentity(
        title: 'Song - Part II',
        artist: 'Artist',
        relativePath: 'Song - Part II.mp3',
      );
      expect(identity.title, 'Song - Part II');
      expect(identity.artist, 'Artist');
    });
    test('标题吻合时补全缺失歌手', () {
      final identity = normalizeTrackIdentity(
        title: '天下无双',
        artist: '<unknown>',
        relativePath: 'S0015 张靓颖 - 天下无双.flac',
      );
      expect(identity.title, '天下无双');
      expect(identity.artist, '张靓颖');
    });
    test('标题不吻合时不猜测歌手', () {
      final identity = normalizeTrackIdentity(
        title: '真实标题',
        relativePath: '假歌手 - 假标题.mp3',
      );
      expect(identity.title, '真实标题');
      expect(identity.artist, '');
    });
    test('从快照映射修正标题且不猜测专辑', () {
      final track = Track.fromMap({
        'title': 'S0015 张靓颖 - 天下无双',
        'relativePath': '目录/S0015 张靓颖 - 天下无双.mp3',
      });
      expect(track.title, '天下无双');
      expect(track.artist, '张靓颖');
      expect(track.album, '');
    });
    test('未知字段与空文件名安全回退', () {
      final track = Track.fromMap({
        'title': '未命名音频',
        'artist': 'Unknown Artist',
      });
      expect(track.title, '未命名音频');
      expect(track.artist, '');
    });
    test('不根据目录名称推测歌手或专辑', () {
      final track = Track.fromMap({'relativePath': '歌手/专辑/1979.mp3'});
      expect(track.title, '1979');
      expect(track.artist, '');
      expect(track.album, '');
    });
  });
}
