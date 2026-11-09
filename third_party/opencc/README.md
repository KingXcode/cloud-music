# OpenCC dictionary attribution

These dictionary files are copied unchanged from [OpenCC 1.1.9](https://github.com/BYVoid/OpenCC/tree/ver.1.1.9), commit `556ed22496d650bd0b13b6c163be9814637970ae`.

Copyright 2010-2024 BYVoid and the OpenCC contributors. Licensed under Apache-2.0; the complete license is included in `LICENSE`.

`TSCharacters.txt` and `TSPhrases.txt` support offline traditional-to-simplified display, with longest phrase matches before character fallback. `STCharacters.txt` provides a character-only traditional search variant, not a full context-sensitive simplified-to-traditional translator. Ambiguous character conversion cannot identify song versions and must never replace artist/version/duration checks.

Run `python3 scripts/generate_lyrics_dictionary.py` to produce `lib/lyrics/generated/chinese_dictionary.dart`. Generated data selects the first preferred alternative from each dictionary entry. The original dictionaries remain unmodified here for provenance and reproducibility. No OpenCC native binaries or network services are used.
