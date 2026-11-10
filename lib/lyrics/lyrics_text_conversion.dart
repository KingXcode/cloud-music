import 'generated/chinese_dictionary.dart';

// Entirely offline. Never overwrite source lyrics: conversion is a display or
// search aid, not a translation, a catalog match or an authoritative correction.
String simplifyChinese(String text) => _simplifier.convert(text);

// Deliberately character-only, used to broaden a search, never for display.
String traditionalChinese(String text) => _traditionalizer.convert(text);

final _simplifier = _DictionaryConverter([
  traditionalToSimplifiedCharacters,
  traditionalToSimplifiedPhrases,
]);
final _traditionalizer = _DictionaryConverter([
  simplifiedToTraditionalCharacters,
]);

class _Node {
  final children = <int, _Node>{};
  String? value;
}

class _DictionaryConverter {
  _DictionaryConverter(List<String> dictionaries) {
    for (final dictionary in dictionaries) {
      for (final row in dictionary.split('\n')) {
        final tab = row.indexOf('\t');
        if (tab < 1) continue;
        var node = _root;
        for (final rune in row.substring(0, tab).runes) {
          node = node.children.putIfAbsent(rune, _Node.new);
        }
        node.value = row.substring(tab + 1);
      }
    }
  }

  final _root = _Node();

  String convert(String text) {
    final runes = text.runes.toList(growable: false);
    final output = StringBuffer();
    var offset = 0;
    while (offset < runes.length) {
      var node = _root;
      String? replacement;
      var end = offset;
      for (var index = offset; index < runes.length; index++) {
        final next = node.children[runes[index]];
        if (next == null) break;
        node = next;
        if (node.value != null) {
          replacement = node.value;
          end = index + 1;
        }
      }
      if (replacement != null) {
        output.write(replacement);
        offset = end;
      } else {
        output.writeCharCode(runes[offset++]);
      }
    }
    return output.toString();
  }
}
