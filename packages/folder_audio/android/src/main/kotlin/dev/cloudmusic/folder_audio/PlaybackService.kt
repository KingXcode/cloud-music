package dev.cloudmusic.folder_audio

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.*

/** Standard phone/head-unit media session. No Android Auto requirement or audio cache. */
class PlaybackService : Service() {
    companion object {
        private var running: PlaybackService? = null
        fun start(context: Context) {
            val intent = Intent(context, PlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }
        fun stop(context: Context) { context.stopService(Intent(context, PlaybackService::class.java)) }
        fun refresh() { running?.update() }
    }
    private lateinit var session: MediaSession
    private lateinit var engine: AudioEngine
    override fun onCreate() {
        super.onCreate(); running = this; engine = AudioEngine.get(this)
        if (Build.VERSION.SDK_INT >= 26) (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(NotificationChannel("music", "音乐播放", NotificationManager.IMPORTANCE_LOW))
        session = MediaSession(this, "CloudMusic").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { if (!engine.isPlaying()) engine.toggle() }
                override fun onPause() { engine.pause() }
                override fun onStop() { engine.pause() }
                override fun onSkipToNext() { engine.step(1) }
                override fun onSkipToPrevious() { engine.step(-1) }
                override fun onSeekTo(pos: Long) { engine.seek(pos) }
            }, Handler(Looper.getMainLooper()))
            isActive = true
        }
        val notification = notification()
        if (Build.VERSION.SDK_INT >= 29) startForeground(23, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        else startForeground(23, notification)
        update()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) { "previous" -> engine.step(-1); "toggle" -> engine.toggle(); "next" -> engine.step(1); "pause" -> engine.pause() }
        update(); return START_NOT_STICKY
    }
    private fun action(name: String, icon: Int, label: String): Notification.Action {
        val pending = PendingIntent.getService(this, name.hashCode(), Intent(this, PlaybackService::class.java).setAction(name), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Action.Builder(icon, label, pending).build()
    }
    private fun notification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "music") else @Suppress("DEPRECATION") Notification.Builder(this)
        builder.setContentTitle(engine.title()).setContentText(engine.artist()).setSmallIcon(android.R.drawable.ic_media_play)
            .setVisibility(Notification.VISIBILITY_PUBLIC).setOnlyAlertOnce(true).setOngoing(engine.isPlaying())
            .addAction(action("previous", android.R.drawable.ic_media_previous, "上一首"))
            .addAction(action("toggle", if (engine.isPlaying()) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, if (engine.isPlaying()) "暂停" else "播放"))
            .addAction(action("next", android.R.drawable.ic_media_next, "下一首"))
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            builder.setContentIntent(PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        return builder.build()
    }
    fun update() {
        if (!::session.isInitialized) return
        session.setMetadata(MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, engine.title())
            .putString(MediaMetadata.METADATA_KEY_ARTIST, engine.artist()).putLong(MediaMetadata.METADATA_KEY_DURATION, engine.duration()).build())
        session.setPlaybackState(PlaybackState.Builder().setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_STOP)
            .setState(if (engine.isPlaying()) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, engine.position(), if (engine.isPlaying()) 1f else 0f).build())
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(23, notification())
    }
    override fun onDestroy() { running = null; session.release(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
