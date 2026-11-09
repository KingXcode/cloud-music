package dev.cloudmusic.cloud_music

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var appUpdates: AppUpdateBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdates = AppUpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        appUpdates?.close()
        appUpdates = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
