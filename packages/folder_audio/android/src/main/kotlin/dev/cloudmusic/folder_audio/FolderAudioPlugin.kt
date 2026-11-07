package dev.cloudmusic.folder_audio

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.AtomicFile
import java.io.File
import java.util.concurrent.Executors
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*

/** 仅负责 Flutter 适配；进程级引擎在 Activity 重建后仍可继续存在。 */
class FolderAudioPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.ActivityResultListener {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var engine: AudioEngine
    private var binding: ActivityPluginBinding? = null
    private var picking = false
    private var lyricsResult: MethodChannel.Result? = null
    private var lyricsIO = Executors.newSingleThreadExecutor()
    @Volatile private var engineGeneration = 0
    private companion object {
        // 重新附着时，旧执行器可能仍在完成原子写入。
        val lyricsCacheLock = Any()
    }
    private val main by lazy { Handler(Looper.getMainLooper()) }
    private val lyricsCache get() = AtomicFile(File(engine.context.filesDir, "lyrics-cache.json"))

    private fun finishLyrics(value: String? = null, error: String? = null) {
        val result = lyricsResult ?: return
        lyricsResult = null
        if (error == null) result.success(value) else result.error("lyrics_error", error, null)
    }
    private fun lyricsOperation(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "readLyricsCache", "writeLyricsCache" -> {
                val value = (call.arguments as? Map<*, *>)?.get("value") as? String
                if (call.method == "writeLyricsCache" && value == null) {
                    result.error("invalid_arguments", "缺少歌词缓存内容。", null); return true
                }
                val generation = engineGeneration
                val cache = lyricsCache
                lyricsIO.execute {
                    try {
                        val output: String? = synchronized(lyricsCacheLock) {
                            check(generation == engineGeneration) { "Engine detached" }
                            if (call.method == "readLyricsCache") {
                                try { cache.openRead().use { readLyricsText(it, 2 * 1024 * 1024) } }
                                catch (_: java.io.FileNotFoundException) { null }
                            } else {
                                val bytes = value!!.toByteArray(Charsets.UTF_8)
                                require(bytes.size <= 2 * 1024 * 1024) { "歌词缓存过大。" }
                                val stream = cache.startWrite()
                                try { stream.write(bytes); cache.finishWrite(stream) }
                                catch (e: Exception) { cache.failWrite(stream); throw e }
                                null
                            }
                        }
                        main.post { result.success(output) }
                    } catch (_: Exception) {
                        main.post { result.error("lyrics_error", "无法读取或保存歌词缓存。", null) }
                    }
                }
                return true
            }
            "importLyrics" -> {
                val activity = binding?.activity
                if (lyricsResult != null || picking) result.error("picker_busy", "请先关闭当前文件选择器。", null)
                else if (activity == null) result.error("no_activity", "请返回应用后导入歌词。", null)
                else {
                    lyricsResult = result
                    try {
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            // LRC 没有统一注册的 MIME 类型，选择完成后再校验扩展名。
                            type = "*/*"
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }, 7413)
                    } catch (_: Exception) { finishLyrics(error = "无法打开歌词选择器。") }
                }
                return true
            }
        }
        return false
    }
    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        if (lyricsIO.isShutdown) lyricsIO = Executors.newSingleThreadExecutor()
        engine = AudioEngine.get(b.applicationContext)
        methods = MethodChannel(b.binaryMessenger, "cloud_music/control")
        events = EventChannel(b.binaryMessenger, "cloud_music/events")
        methods.setMethodCallHandler(this); events.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        finishLyrics(error = "应用已关闭，请重试导入。")
        engineGeneration++
        // 等待任务执行完毕，不中断正在进行的原子写入；队列中过期的缓存操作
        // 无法通过代次检查，工作线程在队列清空后退出。
        lyricsIO.shutdown()
        methods.setMethodCallHandler(null); events.setStreamHandler(null); engine.sink = null
    }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { engine.sink = sink; engine.emit() }
    override fun onCancel(arguments: Any?) { engine.sink = null }
    override fun onAttachedToActivity(b: ActivityPluginBinding) { binding = b; b.addActivityResultListener(this) }
    override fun onDetachedFromActivityForConfigChanges() { detach() }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) { onAttachedToActivity(b) }
    override fun onDetachedFromActivity() { detach(); picking = false; finishLyrics(error = "页面已关闭，请重试导入。") }
    private fun detach() { binding?.removeActivityResultListener(this); binding = null }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == 7413) {
            val pending = lyricsResult ?: return true
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { finishLyrics(); return true }
            val generation = engineGeneration
            val resolver = engine.context.contentResolver
            lyricsIO.execute {
                try {
                    check(generation == engineGeneration) { "Engine detached" }
                    val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        if (it.moveToFirst()) it.getString(0) else null
                    } ?: uri.lastPathSegment.orEmpty()
                    require(name.substringAfterLast('.', "").lowercase() in listOf("lrc", "txt"))
                    val text = resolver.openInputStream(uri)?.use { readLyricsText(it, 256 * 1024) }
                        ?: throw java.io.IOException("无法读取文件")
                    main.post { if (lyricsResult === pending) finishLyrics(text) }
                } catch (_: Exception) {
                    main.post { if (lyricsResult === pending) finishLyrics(error = "请选择不超过 256 KiB 的 UTF-8 .lrc 或 .txt 文件。") }
                }
            }
            return true
        }
        if (requestCode != 7412) return false
        picking = false
        if (resultCode == Activity.RESULT_OK && data?.data != null) {
            try {
                val uri = data.data!!
                engine.context.contentResolver.takePersistableUriPermission(uri,
                    data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
                engine.select(uri)
            } catch (_: Exception) { engine.notice("无法保留文件夹读取权限，请重新选择文件夹。") }
        }
        return true
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (lyricsOperation(call, result)) return
        try {
            when (call.method) {
                "initialize" -> { result.success(engine.snapshot()); engine.scan(false); return }
                "pickFolder" -> if (!picking && lyricsResult == null) {
                    val activity = binding?.activity
                    if (activity == null) engine.notice("请返回应用后选择文件夹。") else {
                        picking = true
                        try { activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                        }, 7412) } catch (e: Exception) { picking = false; throw e }
                    }
                }
                "refresh" -> engine.scan(true)
                "play" -> engine.play(call.argument<String>("id") ?: "")
                "togglePlayback" -> engine.toggle()
                "pause" -> engine.pause()
                "next" -> engine.step(1)
                "previous" -> engine.step(-1)
                "seek" -> engine.seek((call.argument<Number>("positionMs")?.toLong() ?: 0))
                "setShuffle" -> engine.setShuffle(call.argument<Boolean>("enabled") ?: false)
                "setRepeat" -> engine.setRepeat(call.argument<String>("mode") ?: "off")
                "setVolume" -> engine.setVolume(call.argument<Number>("volume")?.toDouble() ?: 1.0)
                "cancelLoading" -> engine.cancel()
                else -> { result.notImplemented(); return }
            }
            result.success(engine.snapshot())
        } catch (_: Exception) { engine.notice("操作未完成，请检查文件夹权限后重试。"); result.success(engine.snapshot()) }
    }
}
