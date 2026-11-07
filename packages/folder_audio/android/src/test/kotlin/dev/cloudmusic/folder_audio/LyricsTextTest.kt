package dev.cloudmusic.folder_audio

import java.io.ByteArrayInputStream
import java.nio.charset.CharacterCodingException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class LyricsTextTest {
    @Test fun readsUtf8AndRemovesOptionalBom() {
        val value = "\uFEFF[00:01.00]你好\nsecond line"
        assertEquals(value.removePrefix("\uFEFF"), readLyricsText(ByteArrayInputStream(value.toByteArray()), 256 * 1024))
    }
    @Test fun allowsExactByteLimit() {
        assertEquals("你", readLyricsText(ByteArrayInputStream("你".toByteArray()), 3))
    }
    @Test fun rejectsOneByteOverLimit() {
        assertFailsWith<IllegalArgumentException> { readLyricsText(ByteArrayInputStream(ByteArray(4)), 3) }
    }
    @Test fun rejectsMalformedUtf8InsteadOfSilentlyReplacingIt() {
        assertFailsWith<CharacterCodingException> { readLyricsText(ByteArrayInputStream(byteArrayOf(0xC3.toByte(), 0x28)), 3) }
    }
    @Test fun allowsEmptyFile() {
        assertEquals("", readLyricsText(ByteArrayInputStream(byteArrayOf()), 3))
    }
}
