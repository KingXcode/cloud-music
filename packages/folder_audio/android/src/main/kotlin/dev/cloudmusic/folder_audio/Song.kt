package dev.cloudmusic.folder_audio

internal data class Song(val id: String, var title: String, var artist: String = "", var album: String = "",
    val relativePath: String, var status: String = "ready", var durationMs: Long = 0) {
    fun map(): Map<String, Any> = mapOf("id" to id, "title" to title, "artist" to artist,
        "album" to album, "relativePath" to relativePath, "status" to status, "durationMs" to durationMs)
}

