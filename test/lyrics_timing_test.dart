import 'package:flutter_test/flutter_test.dart';

import 'dart2js/lyrics_timing_probe.dart' as probe;

void main() {
  test('production playback and lyric timestamp parsing', probe.main);
}
