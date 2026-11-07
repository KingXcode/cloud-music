package dev.cloudmusic.folder_audio

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

internal fun readLyricsText(input: InputStream, limit: Int): String {
    val bytes = ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (true) {
        val n = input.read(buffer, 0, minOf(buffer.size, limit + 1 - bytes.size()))
        if (n < 0) break
        bytes.write(buffer, 0, n)
        require(bytes.size() <= limit) { "文件过大。" }
    }
    return Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(bytes.toByteArray())).toString().removePrefix("\uFEFF")
}
