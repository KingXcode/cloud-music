import 'package:cloud_music/lyrics/lyrics_models.dart';
import 'package:cloud_music/lyrics/lyrics_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline phrase conversion preserves non-Chinese text and emoji', () {
    expect(
      simplifyChinese('音樂與夢想，頭髮乾燥。😀 café Live 2026'),
      '音乐与梦想，头发干燥。😀 café Live 2026',
    );
    expect(simplifyChinese('乾坤'), '乾坤');
    expect(traditionalChinese('音乐与梦想'), '音樂與夢想');
    expect(simplifyChinese('𠮷野家 🎼'), '𠮷野家 🎼');
  });

  test(
    'display conversion preserves offsets and duplicate timestamps exactly',
    () {
      final original = LyricsDocument.parse(
        '[offset:250]\n[ar:虛構樂隊]\n[00:01.50][00:03.00]紙船遠航\n[00:03]風繼續吹拂',
        source: '测试导入',
      );
      final display = original.simplified();
      expect(display.source, original.source);
      expect(
        display.lines.map((l) => l.time),
        original.lines.map((l) => l.time),
      );
      expect(display.lines.first.text, '纸船远航');
      expect(display.lines.last.text, '纸船远航\n风继续吹拂');
      expect(original.lines.first.text, '紙船遠航');
      expect(display.text, contains('[00:01.50][00:03.00]'));
      expect(display.activeLineIndex(const Duration(milliseconds: 1250)), 0);
    },
  );

  test('conversion preserves instrumental and plain document semantics', () {
    final instrumental = LyricsDocument.parse(
      '',
      instrumental: true,
    ).simplified();
    expect(instrumental.instrumental, isTrue);
    expect(instrumental.isSynced, isFalse);
    expect(instrumental.isEmpty, isFalse);
    final plain = LyricsDocument.parse('虛構的島嶼\n沒有時間軸').simplified();
    expect(plain.text, '虚构的岛屿\n没有时间轴');
    expect(plain.isSynced, isFalse);
  });
}
