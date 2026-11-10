import 'package:flutter/foundation.dart';

import 'generated/chinese_dictionary.dart';

export 'lyrics_text_conversion.dart';

bool _licenseRegistered = false;

void registerLyricsConversionLicense() {
  if (_licenseRegistered) return;
  _licenseRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['OpenCC dictionaries'],
      'OpenCC 1.1.9 · Copyright 2010–2024 BYVoid and contributors.\n'
      'Dictionary data adapted to a bundled Dart lookup table.\n\n'
      '$openCcLicense',
    );
  });
}
