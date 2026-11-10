package dev.cloudmusic.folder_audio

import android.content.*
import android.os.storage.StorageManager
import java.io.FileNotFoundException
import android.graphics.BitmapFactory
import android.media.*
import android.net.Uri
import android.os.*
import android.provider.DocumentsContract
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.UUID

internal class AudioEngine private constructor(val context: Context) {
    companion object {
        @Volatile private var instance: AudioEngine? = null
        fun get(context: Context): AudioEngine = instance ?: synchronized(this) {
            instance ?: AudioEngine(context.applicationContext).also { instance = it }
        }
    }
    var sink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val io = Executors.newFixedThreadPool(2)
    private val metadataIO = Executors.newSingleThreadExecutor()
    private var playbackSignal: CancellationSignal? = null
    private var scanSignal: CancellationSignal? = null
    private val scanGeneration = AtomicInteger()
    @Volatile private var playGeneration = 0
    private val prefs = context.getSharedPreferences("folder_audio_index", Context.MODE_PRIVATE)
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private var resumeAfterFocus = false
    private var duck = 1f
    private var player: MediaPlayer? = null
    private var prepared = false
    private var deviceLibrary = prefs.getBoolean("deviceLibrary", false)
    private var tree: Uri? = prefs.getString("tree", null)?.let(Uri::parse)
    private var folderName: String? = prefs.getString("folder", null)
    private var tracks = mutableListOf<Song>()
    private var current: String? = null
    private var playbackSessionId: String? = null
    private var playbackCompleted = false
    private var loading = false
    private var scanning = false
    private var importRevision = 0
    private var pendingFolderImport = false
    private var message: String? = null
    private var artwork: ByteArray? = null
    private var shuffle = prefs.getBoolean("shuffle", false)
    private var repeat = prefs.getString("repeat", "off") ?: "off"
    private var volume = prefs.getFloat("volume", 1f)
    private val history = mutableListOf<String>()
    private val shuffledPlayed = mutableSetOf<String>()
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change -> handler.post {
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> { pause(); resumeAfterFocus = false }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> { resumeAfterFocus = isPlaying(); if (prepared) try { player?.pause() } catch (_: Exception) {}; emit() }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> { duck = .2f; applyVolume() }
            AudioManager.AUDIOFOCUS_GAIN -> { duck = 1f; applyVolume(); if (resumeAfterFocus) { resumeAfterFocus = false; resume() } }
        }
    } }
    init {
        try {
            val saved = JSONArray(prefs.getString("tracks", "[]"))
            for (i in 0 until saved.length()) { val s = saved.getJSONObject(i)
                tracks.add(Song(s.getString("id"), s.getString("title"), s.optString("artist"), s.optString("album"),
                    s.getString("relativePath"), s.optString("status", "unknown"), s.optLong("durationMs")))
            }
        } catch (_: Exception) { message = "索引无法读取，请重新刷新文件夹。" }
        val receiver = object : BroadcastReceiver() { override fun onReceive(c: Context?, i: Intent?) { pause() } }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") context.registerReceiver(receiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        handler.post(object : Runnable { override fun run() { if (isPlaying()) emit(); handler.postDelayed(this, 750) } })
    }
    fun snapshot(): Map<String, Any?> = mapOf("folderName" to folderName, "sourceKind" to "android",
        "sourceIdentity" to if (deviceLibrary) "mediastore:audio" else tree?.toString(),
        "canScanDevice" to true, "importRevision" to importRevision,
        "tracks" to tracks.map { it.map() }, "currentTrackId" to current, "isPlaying" to isPlaying(),
        "playbackSessionId" to playbackSessionId,
        "isLoading" to loading, "isScanning" to scanning, "shuffle" to shuffle,
        "positionMs" to position(), "durationMs" to duration(), "repeatMode" to repeat,
        "volume" to volume.toDouble(), "artwork" to artwork, "message" to message)
    fun emit() { sink?.success(snapshot()); PlaybackService.refresh() }
    fun notice(text: String) { message = text; emit() }
    fun title() = tracks.find { it.id == current }?.title ?: "弦泊"
    fun artist() = tracks.find { it.id == current }?.artist ?: ""
    fun isPlaying() = try { prepared && player?.isPlaying == true } catch (_: Exception) { false }
    fun position(): Long = try { if (prepared) player?.currentPosition?.toLong() ?: 0 else 0 } catch (_: Exception) { 0 }
    fun duration(): Long = try { if (prepared) player?.duration?.toLong()?.coerceAtLeast(0) ?: 0 else 0 } catch (_: Exception) { 0 }
    private fun save() {
        prefs.edit().putBoolean("deviceLibrary", deviceLibrary).putString("tree", tree?.toString()).putString("folder", folderName)
            .putString("tracks", JSONArray(tracks.map { JSONObject(it.map()) }).toString())
            .putBoolean("shuffle", shuffle).putString("repeat", repeat).putFloat("volume", volume).apply()
    }
    fun select(uri: Uri) {
        cancel(); stopPlayer(); current = null; artwork = null; history.clear(); shuffledPlayed.clear()
        pendingFolderImport = true; deviceLibrary = false; tree = uri; folderName = "所选文件夹"; tracks.clear(); save(); scan(true)
    }
    fun cancel() { scanSignal?.cancel(); scanGeneration.incrementAndGet(); scanning = false; if (loading) { stopPlayer(); loading = false }; message = "已取消加载。"; emit() }
    private data class Scan(val songs: MutableList<Song> = mutableListOf(), var complete: Boolean = true, var name: String? = null)
    private fun document(uri: Uri, signal: CancellationSignal): Boolean {
        context.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null, signal)?.use {
            if (it.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false) || it.extras.containsKey(DocumentsContract.EXTRA_ERROR)) throw IllegalStateException("Provider incomplete")
            return it.moveToFirst()
        }
        throw IllegalStateException("No provider cursor")
    }
    private fun verifySource(source: Uri) {
        if (context.contentResolver.persistedUriPermissions.none { it.uri == source && it.isReadPermission })
            throw SecurityException("Folder grant revoked")
        if (source.authority == "com.android.externalstorage.documents") {
            val volumeId = DocumentsContract.getTreeDocumentId(source).substringBefore(':')
            val storage = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
            val volume = storage.storageVolumes.find {
                if (volumeId == "primary") it.isPrimary else it.uuid.equals(volumeId, ignoreCase = true)
            } ?: throw IllegalStateException("Storage volume unavailable")
            if (volume.state != Environment.MEDIA_MOUNTED && volume.state != Environment.MEDIA_MOUNTED_READ_ONLY)
                throw IllegalStateException("Storage volume unmounted")
        }
    }
    private fun confirmedAbsent(source: Uri, uri: Uri, signal: CancellationSignal): Boolean {
        try { return !document(uri, signal) } catch (e: SecurityException) { throw e }
        catch (e: Exception) {
            // 仅对已完整扫描且已挂载的 Android 存储卷，才用只读文件描述符的
            // 文件不存在结果佐证目录条目缺失。远程文件提供器错误仍视为状态未知。
            if (source.authority != "com.android.externalstorage.documents") throw e
            verifySource(source)
            try { context.contentResolver.openAssetFileDescriptor(uri, "r", signal)?.use { return false }; throw e }
            catch (_: FileNotFoundException) { verifySource(source); return true }
        }
    }
    fun scan(refresh: Boolean) {
        if (deviceLibrary) { scanDevice(); return }
        val source = tree ?: return
        if (scanning) return
        val importing = pendingFolderImport; pendingFolderImport = false
        val token = scanGeneration.incrementAndGet(); val signal = CancellationSignal(); scanSignal = signal; scanning = true; message = "正在检查文件夹…"; emit()
        val old = tracks.map { it.copy() }
        io.execute {
            val result = Scan()
            val missing = mutableSetOf<String>()
            var failure = false
            try {
                verifySource(source)
                val rootId = DocumentsContract.getTreeDocumentId(source)
                val root = DocumentsContract.buildDocumentUriUsingTree(source, rootId)
                if (!document(root, signal)) throw IllegalStateException("Root unavailable")
                context.contentResolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null, signal)?.use {
                    if (it.moveToFirst()) result.name = it.getString(0)
                }
                val visited = mutableSetOf<String>()
                fun walk(id: String, prefix: String, depth: Int) {
                    if (scanGeneration.get() != token) throw InterruptedException()
                    if (depth > 64 || !visited.add(id)) { result.complete = false; return }
                    val children = DocumentsContract.buildChildDocumentsUriUsingTree(source, id)
                    try {
                        context.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null, signal)?.use { cursor ->
                            if (cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false) || cursor.extras.containsKey(DocumentsContract.EXTRA_ERROR)) result.complete = false
                            while (cursor.moveToNext()) {
                                if (scanGeneration.get() != token) throw InterruptedException()
                                val childId = cursor.getString(0); val name = cursor.getString(1) ?: "未命名"
                                val mime = cursor.getString(2) ?: ""; val path = prefix + name
                                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) walk(childId, "$path/", depth + 1)
                                else if (mime.startsWith("audio/") || name.substringAfterLast('.', "").lowercase() in setOf("mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff", "aif", "alac", "wma", "amr")) {
                                    val uri = DocumentsContract.buildDocumentUriUsingTree(source, childId).toString()
                                    result.songs.add(Song(uri, name.substringBeforeLast('.'), relativePath = path))
                                }
                            }
                        } ?: run { result.complete = false }
                    } catch (e: InterruptedException) { throw e } catch (_: Exception) { result.complete = false }
                }
                walk(rootId, "", 0)
                // 仅在目录列表中缺失不能证明文件已删除，必须再次查询文档，
                // 并确保完整遍历成功、根目录重新校验通过。文件提供器失败时保留全部条目。
                if (result.complete && document(root, signal)) {
                    val found = result.songs.map { it.id }.toSet()
                    for (song in old.filter { it.id !in found }) {
                        try { if (confirmedAbsent(source, Uri.parse(song.id), signal)) missing.add(song.id) }
                        catch (_: Exception) { result.complete = false; missing.clear(); break }
                    }
                }
                verifySource(source)
                if (!document(root, signal)) throw IllegalStateException("Root disappeared")
            } catch (_: InterruptedException) { return@execute } catch (_: Exception) { failure = true; result.complete = false }
            handler.post {
                if (token != scanGeneration.get()) return@post
                scanning = false
                if (!failure) {
                    val discovered = result.songs.associateBy { it.id }
                    val previous = tracks.associateBy { it.id }
                    val merged = result.songs.map { fresh -> previous[fresh.id]?.copy(relativePath = fresh.relativePath,
                        status = if (previous[fresh.id]?.status == "unsupported") "unsupported" else "ready") ?: fresh }.toMutableList()
                    for (song in old) if (song.id !in discovered && !(refresh && result.complete && song.id in missing)) {
                        merged.add(song.copy(status = if (song.id in missing) "missing" else "offline"))
                    }
                    tracks = merged.sortedBy { it.relativePath.lowercase() }.toMutableList()
                    folderName = result.name ?: folderName
                    if (importing && result.songs.isNotEmpty()) importRevision++
                    if (current != null && tracks.none { it.id == current }) { stopPlayer(); current = null; artwork = null }
                    message = if (result.complete) "文件夹检查完成，共 ${tracks.size} 首。" else "文件夹暂时无法完整读取，已保留原有歌曲；请检查 U 盘或权限后刷新。"
                    save()
                } else { tracks.forEach { it.status = "offline" }; message = "文件夹无法访问，已保留音乐库。请连接 U 盘或重新选择文件夹。"; save() }
                emit()
            }
        }
    }
    fun scanDevice(fromImport: Boolean = false) {
        if (scanning) return
        if (!DeviceAudioScanner.permitted(context)) {
            if (deviceLibrary) tracks.forEach { it.status = "accessRequired" }
            notice("未获得音乐读取权限。可点击扫描重新授权，或直接选择文件夹；原资料库已保留。")
            return
        }
        val wasDeviceLibrary = deviceLibrary
        val token = scanGeneration.incrementAndGet()
        val signal = CancellationSignal(); scanSignal = signal
        scanning = true; message = "正在扫描本机音乐…"; emit()
        io.execute {
            try {
                val found = DeviceAudioScanner.scan(context, signal)
                handler.post {
                    if (token != scanGeneration.get()) return@post
                    scanning = false
                    // An empty first scan must not replace the user's existing folder library.
                    if (!wasDeviceLibrary && found.isEmpty()) {
                        notice("系统媒体库未找到音乐，已保留原资料库。未被系统收录的文件或 U 盘音乐，请选择文件夹。")
                        return@post
                    }
                    if (!wasDeviceLibrary) {
                        stopPlayer(); current = null; artwork = null; history.clear(); shuffledPlayed.clear()
                    }
                    tracks = mergeDeviceSongs(found, if (wasDeviceLibrary) tracks else emptyList())
                    deviceLibrary = true; tree = null; folderName = "本机音乐"
                    if (fromImport && found.isNotEmpty()) importRevision++
                    val unseen = tracks.size - found.size
                    message = "扫描完成，找到 ${found.size} 首本机音乐。" +
                        if (unseen > 0) "另有 $unseen 首暂时无法确认，已保留；请检查存储卡或权限。" else "未收录的音乐或 U 盘目录可通过选择文件夹导入。"
                    save(); emit()
                }
            } catch (_: OperationCanceledException) { /* cancel/source change owns the state. */ }
            catch (error: Exception) {
                handler.post {
                    if (token != scanGeneration.get()) return@post
                    scanning = false
                    if (wasDeviceLibrary) tracks.forEach { it.status = if (error is SecurityException) "accessRequired" else "offline" }
                    notice(if (error is SecurityException) "音乐读取权限已撤销，已保留原资料库。请重新点击扫描授权，或选择文件夹。"
                        else "本机音乐暂时无法完整扫描，已保留原资料库。请检查存储卡后重试，或选择文件夹。")
                }
            }
        }
    }
    private fun stopPlayer(stopService: Boolean = true) { playbackSessionId = null; playbackCompleted = false; playbackSignal?.cancel(); playGeneration++; prepared = false; loading = false; player?.release(); player = null; resumeAfterFocus = false; abandonFocus(); if (stopService) PlaybackService.stop(context) }
    private fun requestFocus(): Boolean {
        return if (Build.VERSION.SDK_INT >= 26) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener, handler).build().also { focusRequest = it }
            audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else @Suppress("DEPRECATION") (audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
    }
    private fun abandonFocus() { if (Build.VERSION.SDK_INT >= 26) focusRequest?.let { audio.abandonAudioFocusRequest(it) } else @Suppress("DEPRECATION") audio.abandonAudioFocus(focusListener) }
    fun play(id: String, remember: Boolean = true) {
        val song = tracks.find { it.id == id } ?: return
        if (remember) current?.takeIf { it != id }?.let { history.add(it) }
        shuffledPlayed.add(id)
        stopPlayer(false); current = id; artwork = null; loading = true; message = "正在加载…"
        try { PlaybackService.start(context) } catch (_: Exception) { loading = false; notice("请返回应用后开始播放。"); return }
        val token = playGeneration
        val signal = CancellationSignal(); playbackSignal = signal
        val p = MediaPlayer(); player = p; p.setAudioAttributes(attributes); p.setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
        p.setOnPreparedListener { ready ->
            if (token != playGeneration || player !== ready) return@setOnPreparedListener
            prepared = true; loading = false; song.durationMs = duration(); song.status = "ready"
            resume(); save(); emit()
        }
        p.setOnCompletionListener {
            if (token == playGeneration) {
                playbackCompleted = true
                if (repeat == "one") { seek(0); resume() }
                else if (!shuffle && tracks.lastOrNull { it.status !in setOf("missing", "unsupported") }?.id == current && repeat == "off") { pause(); seek(0) }
                else step(1, automatic = true)
            }
        }
        p.setOnErrorListener { _, what, extra ->
            if (token == playGeneration) {
                song.status = if (what == MediaPlayer.MEDIA_ERROR_SERVER_DIED || extra == MediaPlayer.MEDIA_ERROR_IO || extra == MediaPlayer.MEDIA_ERROR_TIMED_OUT) "offline" else "unsupported"
                stopPlayer(); message = if (song.status == "unsupported") "无法播放此音频格式或文件已损坏。" else "音频无法读取，请检查 U 盘、网络或文件夹权限。"; save(); emit()
            }; true
        }
        emit()
        // 打开远程 DocumentsProvider URI 可能阻塞，应在界面线程之外获取只读描述符。
        io.execute {
            try {
                val descriptor = context.contentResolver.openAssetFileDescriptor(Uri.parse(id), "r", signal)
                    ?: throw IllegalStateException("No audio descriptor")
                handler.post {
                    descriptor.use { fd ->
                        if (token == playGeneration && player === p) try {
                            if (fd.declaredLength < 0) p.setDataSource(fd.fileDescriptor)
                            else p.setDataSource(fd.fileDescriptor, fd.startOffset, fd.declaredLength)
                            p.prepareAsync()
                        } catch (_: Exception) { stopPlayer(); notice("无法准备音频，请重试。") }
                    }
                }
                metadataIO.execute metadataTask@{
                    if (token != playGeneration) return@metadataTask
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(context, Uri.parse(id))
                    val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                    val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                    val album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                    val raw = retriever.embeddedPicture
                    var cover: ByteArray? = null
                    if (raw != null && raw.size <= 16 * 1024 * 1024) {
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
                        val options = BitmapFactory.Options().apply { inSampleSize = (maxOf(bounds.outWidth, bounds.outHeight) / 512).coerceAtLeast(1) }
                        BitmapFactory.decodeByteArray(raw, 0, raw.size, options)?.let { bitmap ->
                            cover = ByteArrayOutputStream().use { out -> bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, out); out.toByteArray() }; bitmap.recycle()
                        }
                    }
                    handler.post { if (token == playGeneration && current == id) { if (!title.isNullOrBlank()) song.title = title; song.artist = artist ?: ""; song.album = album ?: ""; artwork = cover; save(); emit() } }
                } catch (_: Exception) { /* 元数据为可选项，获取失败仍继续播放。 */ }
                finally { retriever.release() }
                }
            } catch (_: Exception) { handler.post { if (token == playGeneration && !prepared) { song.status = "offline"; stopPlayer(); save(); notice("音频无法读取，请连接 U 盘或重新授权文件夹。") } } }
        }
    }
    private fun resume() {
        if (!prepared) return
        try {
            // 先启动媒体前台服务再申请音频焦点，以满足目标 API 35 及以上版本的后台焦点要求。
            PlaybackService.start(context)
            if (!requestFocus()) { message = "其他应用正在使用音频，请稍后重试。"; PlaybackService.stop(context); emit(); return }
            applyVolume(); player?.start()
            if (isPlaying() && (playbackSessionId == null || playbackCompleted)) {
                playbackSessionId = UUID.randomUUID().toString(); playbackCompleted = false
            }
            message = null; emit()
        } catch (_: Exception) { notice("无法开始后台播放，请返回应用重试。"); PlaybackService.stop(context) }
    }
    fun toggle() { if (isPlaying()) pause() else if (prepared) resume() else (current ?: tracks.firstOrNull()?.id)?.let { play(it) } }
    fun pause() { resumeAfterFocus = false; if (loading) { stopPlayer() } else if (prepared) try { player?.pause() } catch (_: Exception) {}; abandonFocus(); emit(); PlaybackService.stop(context) }
    fun seek(ms: Long) { if (prepared) { val target = ms.coerceIn(0, duration()); if (Build.VERSION.SDK_INT >= 26) player?.seekTo(target, MediaPlayer.SEEK_CLOSEST) else @Suppress("DEPRECATION") player?.seekTo(target.toInt()); emit() } }
    fun step(direction: Int, automatic: Boolean = false) {
        if (tracks.isEmpty()) return
        if (direction < 0 && position() > 3000) { seek(0); return }
        if (shuffle && direction < 0 && history.isNotEmpty()) { val id = history.removeAt(history.lastIndex); play(id, remember = false); return }
        val playable = tracks.filter { it.status !in setOf("missing", "unsupported") }
        if (playable.isEmpty()) { pause(); return }
        val index = playable.indexOfFirst { it.id == current }
        if (shuffle && automatic) {
            var remaining = playable.filter { it.id !in shuffledPlayed }
            if (remaining.isEmpty()) {
                if (repeat != "all") { pause(); seek(0); return }
                shuffledPlayed.clear(); remaining = playable.filter { it.id != current }.ifEmpty { playable }
            }
            play(remaining.random().id); return
        }
        val next = if (shuffle && playable.size > 1) playable.filter { it.id != current }.random()
            else playable[Math.floorMod(index + direction, playable.size)]
        play(next.id)
    }
    fun setShuffle(enabled: Boolean) { shuffle = enabled; shuffledPlayed.clear(); current?.let { shuffledPlayed.add(it) }; save(); emit() }
    fun setRepeat(mode: String) { repeat = mode.takeIf { it in setOf("off", "all", "one") } ?: "off"; save(); emit() }
    fun setVolume(value: Double) { volume = if (value.isFinite()) value.coerceIn(0.0, 1.0).toFloat() else 1f; applyVolume(); save(); emit() }
    private fun applyVolume() { try { player?.setVolume(volume * duck, volume * duck) } catch (_: Exception) {} }
}
