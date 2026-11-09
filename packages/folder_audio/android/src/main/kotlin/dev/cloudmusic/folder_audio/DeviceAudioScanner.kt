package dev.cloudmusic.folder_audio

import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.CancellationSignal
import android.provider.MediaStore

/** Only reads Android's existing music index. Never crawls paths or opens audio. */
internal object DeviceAudioScanner {
    fun permission(sdk: Int): String = deviceAudioPermission(sdk)

    fun permitted(context: Context): Boolean = context.checkSelfPermission(permission(Build.VERSION.SDK_INT)) == PackageManager.PERMISSION_GRANTED

    fun scan(context: Context, signal: CancellationSignal): List<Song> {
        if (!permitted(context)) throw SecurityException("Audio permission required")
        val collections = if (Build.VERSION.SDK_INT >= 29) {
            MediaStore.getExternalVolumeNames(context).sorted().map { MediaStore.Audio.Media.getContentUri(it) }
        } else listOf(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI)
        // A disconnected/unavailable provider is not evidence of an empty music library.
        check(collections.isNotEmpty()) { "No mounted media volume" }
        val songs = linkedMapOf<String, Song>()
        for (collection in collections) {
            signal.throwIfCanceled()
            val projection = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.DURATION)
            context.contentResolver.query(collection, projection,
                "${MediaStore.Audio.Media.IS_MUSIC} != 0", null, "${MediaStore.Audio.Media._ID} ASC", signal)?.use { cursor ->
                while (cursor.moveToNext()) {
                    signal.throwIfCanceled()
                    val uri = ContentUris.withAppendedId(collection, cursor.getLong(0)).toString()
                    val name = cursor.getString(1).orEmpty()
                    val title = cleanMediaLabel(cursor.getString(2)).ifBlank { name.substringBeforeLast('.').ifBlank { "未命名" } }
                    songs[uri] = Song(uri, title, cleanMediaLabel(cursor.getString(3)), cleanMediaLabel(cursor.getString(4)),
                        relativePath = name.ifBlank { title }, status = "ready", durationMs = cursor.getLong(5).coerceAtLeast(0))
                }
            } ?: error("No media cursor")
        }
        signal.throwIfCanceled()
        if (!permitted(context)) throw SecurityException("Audio permission revoked")
        return songs.values.toList()
    }
}

