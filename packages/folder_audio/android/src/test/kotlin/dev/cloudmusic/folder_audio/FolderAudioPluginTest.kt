package dev.cloudmusic.folder_audio

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertEquals

/** JVM checks for the bridge schema; SAF and playback require the documented device matrix. */
internal class FolderAudioPluginTest {
    private class RecordingResult : MethodChannel.Result {
        var successCount = 0
        var errorCount = 0
        var notImplementedCount = 0
        override fun success(result: Any?) { successCount++ }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { errorCount++ }
        override fun notImplemented() { notImplementedCount++ }
    }

    @Test
    fun unknownMethodIsNotImplemented() {
        val plugin = FolderAudioPlugin()
        val result = RecordingResult()
        plugin.onMethodCall(MethodCall("unknownMethod", null), result)
        assertEquals(1, result.notImplementedCount)
        assertEquals(0, result.successCount)
        assertEquals(0, result.errorCount)
    }
    @Test
    fun songUsesStableOriginalUriAndCompleteSnapshotFields() {
        val uri = "content://provider/tree/root/document/song"
        val song = Song(uri, "音乐", relativePath = "子目录/音乐.flac")
        assertEquals(uri, song.map()["id"])
        assertEquals("ready", song.map()["status"])
        assertEquals(0L, song.map()["durationMs"])
        assertEquals("子目录/音乐.flac", song.map()["relativePath"])
    }
}
