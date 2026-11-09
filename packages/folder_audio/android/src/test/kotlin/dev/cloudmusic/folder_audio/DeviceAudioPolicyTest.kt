package dev.cloudmusic.folder_audio

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotSame

internal class DeviceAudioPolicyTest {
    @Test
    fun onlyAudioPermissionOnAndroid13AndLater() {
        for (sdk in 24..32) assertEquals("android.permission.READ_EXTERNAL_STORAGE", deviceAudioPermission(sdk))
        for (sdk in 33..40) assertEquals("android.permission.READ_MEDIA_AUDIO", deviceAudioPermission(sdk))
    }

    @Test
    fun blankAndUnknownSystemLabelsDoNotHideFilenameFallback() {
        assertEquals("", cleanMediaLabel(null))
        assertEquals("", cleanMediaLabel(" <unknown> "))
        assertEquals("", cleanMediaLabel("<UNKNOWN>"))
        assertEquals("歌手", cleanMediaLabel(" 歌手 "))
    }

    @Test
    fun rescanDeduplicatesUrisButKeepsSameNamedSongsOnDifferentVolumes() {
        val a = Song("content://media/external_primary/audio/media/1", "A", relativePath = "same.mp3")
        val b = Song("content://media/0123-4567/audio/media/1", "B", relativePath = "same.mp3")
        val result = mergeDeviceSongs(listOf(a, a, b), listOf(a))
        assertEquals(listOf(a.id, b.id), result.map { it.id })
    }

    @Test
    fun emptyScanAndDisconnectedVolumeKeepPreviousReferencesWithoutMutatingThem() {
        val song = Song("content://media/sd/audio/media/1", "A", relativePath = "A.mp3")
        val result = mergeDeviceSongs(emptyList(), listOf(song))
        assertEquals(song.id, result.single().id)
        assertEquals("offline", result.single().status)
        assertEquals("ready", song.status)
        assertNotSame(song, result.single())
    }

    @Test
    fun returningSongRestoresAvailabilityAndKeepsKnownTagsAndDuration() {
        val old = Song("one", "A", "Artist", "Album", "A.mp3", "offline", 45000)
        val fresh = Song("one", "A", relativePath = "A.mp3")
        val result = mergeDeviceSongs(listOf(fresh), listOf(old)).single()
        assertEquals("ready", result.status)
        assertEquals("Artist", result.artist)
        assertEquals("Album", result.album)
        assertEquals(45000L, result.durationMs)
        assertEquals("unsupported", mergeDeviceSongs(listOf(fresh), listOf(old.copy(status = "unsupported"))).single().status)
        assertEquals(60000L, mergeDeviceSongs(listOf(fresh.copy(durationMs = 60000)), listOf(old)).single().durationMs)
    }
}
