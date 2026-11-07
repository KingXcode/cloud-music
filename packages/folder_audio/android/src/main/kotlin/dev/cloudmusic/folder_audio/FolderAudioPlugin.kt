package dev.cloudmusic.folder_audio

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*

/** Flutter adapter only: the process-level engine survives activity recreation. */
class FolderAudioPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.ActivityResultListener {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var engine: AudioEngine
    private var binding: ActivityPluginBinding? = null
    private var picking = false
    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        engine = AudioEngine.get(b.applicationContext)
        methods = MethodChannel(b.binaryMessenger, "cloud_music/control")
        events = EventChannel(b.binaryMessenger, "cloud_music/events")
        methods.setMethodCallHandler(this); events.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null); events.setStreamHandler(null); engine.sink = null
    }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { engine.sink = sink; engine.emit() }
    override fun onCancel(arguments: Any?) { engine.sink = null }
    override fun onAttachedToActivity(b: ActivityPluginBinding) { binding = b; b.addActivityResultListener(this) }
    override fun onDetachedFromActivityForConfigChanges() { detach() }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) { onAttachedToActivity(b) }
    override fun onDetachedFromActivity() { detach(); picking = false }
    private fun detach() { binding?.removeActivityResultListener(this); binding = null }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
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
        try {
            when (call.method) {
                "initialize" -> { result.success(engine.snapshot()); engine.scan(false); return }
                "pickFolder" -> if (!picking) {
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
