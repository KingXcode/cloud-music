package dev.cloudmusic.folder_audio

internal fun deviceAudioPermission(sdk: Int): String = if (sdk >= 33)
    "android.permission.READ_MEDIA_AUDIO" else "android.permission.READ_EXTERNAL_STORAGE"

internal fun cleanMediaLabel(value: String?): String = value?.trim()?.takeUnless { it.equals("<unknown>", ignoreCase = true) }.orEmpty()

/** Missing rows may mean an unmounted SD card. Keep their references, never delete files. */
internal fun mergeDeviceSongs(found: List<Song>, previous: List<Song>): MutableList<Song> {
    val old = previous.associateBy { it.id }
    val merged = found.associateByTo(linkedMapOf()) { it.id }
    for ((id, song) in merged.toMap()) {
        val prior = old[id] ?: continue
        merged[id] = song.copy(title = song.title.ifBlank { prior.title },
            artist = song.artist.ifBlank { prior.artist }, album = song.album.ifBlank { prior.album },
            durationMs = if (song.durationMs > 0) song.durationMs else prior.durationMs,
            status = if (prior.status == "unsupported") "unsupported" else song.status)
    }
    for (song in previous) if (song.id !in merged) merged[song.id] = song.copy(status = "offline")
    return merged.values.sortedBy { it.relativePath.lowercase() }.toMutableList()
}
