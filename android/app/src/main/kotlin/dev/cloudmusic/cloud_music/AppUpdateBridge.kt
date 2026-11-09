package dev.cloudmusic.cloud_music

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** This channel never downloads, installs silently, or resumes installation on return from Settings. */
internal class AppUpdateBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "dev.cloudmusic/app_updates")
    private val validationExecutor = Executors.newSingleThreadExecutor()
    private val installing = AtomicBoolean(false)
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getInfo" -> {
                    val info = installedPackage()
                    result.success(mapOf(
                        "version" to (info.versionName ?: "0.0.0"),
                        "build" to versionCode(info).toString(),
                        "platform" to "android",
                        "architecture" to architecture(),
                        "automaticInstall" to false,
                    ))
                }
                "getDownloadDirectory" -> result.success(downloadDirectory().path)
                "installDownloaded" -> installDownloaded(call, result)
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            report(error, result)
        }
    }

    private fun downloadDirectory(): File {
        val requested = File(activity.cacheDir.canonicalFile, "app_updates")
        val directory = requested.canonicalFile
        if (requested != directory ||
            (!directory.isDirectory && !directory.mkdirs())
        ) {
            throw UpdateFailure("cache_unavailable", "The private update cache is unavailable.")
        }
        return directory
    }

    private fun installDownloaded(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            throw UpdateFailure("invalid_arguments", "An update file path is required.")
        }
        if (!installing.compareAndSet(false, true)) {
            throw UpdateFailure("install_in_progress", "An update install request is already in progress.")
        }
        // APK inspection may be expensive. Keep the Flutter/platform thread responsive.
        validationExecutor.execute {
            val validated = runCatching { validateApk(path) }
            activity.runOnUiThread {
                try {
                    if (closed || activity.isFinishing || activity.isDestroyed) {
                        throw UpdateFailure("install_unavailable", "The application is no longer active.")
                    }
                    val apk = validated.getOrThrow()
                    // Recheck confinement immediately before granting the read-only URI.
                    UpdatePackagePolicy.validateFile(apk.path, downloadDirectory())
                    result.success(openInstaller(apk))
                } catch (error: Exception) {
                    report(error, result)
                } finally {
                    installing.set(false)
                }
            }
        }
    }

    private fun validateApk(path: String): File {
        val apk = UpdatePackagePolicy.validateFile(path, downloadDirectory())
        val candidate = activity.packageManager.getPackageArchiveInfo(apk.path, signatureFlags())
            ?: throw UpdateFailure("invalid_package", "The downloaded file is not a readable Android package.")
        val installed = installedPackage()
        UpdatePackagePolicy.validateIdentity(
            installedPackage = activity.packageName,
            candidatePackage = candidate.packageName,
            installedVersion = versionCode(installed),
            candidateVersion = versionCode(candidate),
            installedSigners = signingCertificates(installed),
            candidateSigners = signingCertificates(candidate),
        )
        return apk
    }

    private fun openInstaller(apk: File): String {
        // This method is reached ONLY by an explicit Flutter install button action.
        // Do not request this permission during update checks, downloads, or app startup.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            activity.startActivity(Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            ))
            return "permissionRequired"
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.app_updates", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            clipData = ClipData.newRawUri("Cloud Music update", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // Android performs the final cryptographic APK/signature/compatibility checks
        // and asks the user to install. Opening this UI is not installation success.
        activity.startActivity(intent)
        return "opened"
    }

    @Suppress("DEPRECATION")
    private fun installedPackage(): PackageInfo =
        activity.packageManager.getPackageInfo(activity.packageName, signatureFlags())

    @Suppress("DEPRECATION")
    private fun signatureFlags(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        PackageManager.GET_SIGNING_CERTIFICATES
    } else {
        PackageManager.GET_SIGNATURES
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signingCertificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        }?.toSet() ?: emptySet()
    }

    private fun architecture(): String = when (Build.SUPPORTED_ABIS.firstOrNull()) {
        "arm64-v8a" -> "arm64"
        "armeabi-v7a", "armeabi" -> "arm"
        "x86_64" -> "x64"
        "x86" -> "x86"
        else -> "unknown"
    }

    private fun report(error: Exception, result: MethodChannel.Result) {
        when (error) {
            is UpdateFailure -> result.error(error.code, error.message, null)
            is ActivityNotFoundException -> result.error("install_unavailable", "No system package installer or settings screen is available.", null)
            is SecurityException -> result.error("install_unavailable", "Android did not allow the update installer to open.", null)
            else -> result.error("update_failed", "The native update operation could not be completed.", null)
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        validationExecutor.shutdown()
    }
}
