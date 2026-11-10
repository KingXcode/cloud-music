/// JavaScript bitwise operations are 32-bit: `1 << 53` becomes zero on Web.
/// Keep this decimal bound and conversion shared by playback and lyric clocks.
const maxSafeTimeInteger = 9007199254740991;

int nonNegativeMilliseconds(Object? value) => value is num && value.isFinite
    ? value.clamp(0, maxSafeTimeInteger).toInt()
    : 0;
