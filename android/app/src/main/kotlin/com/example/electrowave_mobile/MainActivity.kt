package com.example.electrowave_mobile

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Reports and repairs the *real* state of the playback notification.
 *
 * POST_NOTIFICATIONS being granted is not enough: the media channel can be
 * turned off on its own (a swipe-away + "block", or the system's notification
 * management), which hides the playback notification while every permission
 * check still answers "granted". Neither state is reachable from
 * permission_handler, so it is read here and linked straight to the system
 * page that fixes it.
 */
class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(notificationStatus())
                    "openSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun notificationStatus(): Map<String, Any> {
        val appEnabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
        var channelExists = false
        var channelBlocked = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Created by audio_service when its foreground service first
            // starts, so a missing channel means playback has never run.
            val channel = manager.getNotificationChannel(PLAYBACK_CHANNEL_ID)
            channelExists = channel != null
            channelBlocked = channel?.importance == NotificationManager.IMPORTANCE_NONE
        }

        return mapOf(
            "appEnabled" to appEnabled,
            "channelExists" to channelExists,
            "channelBlocked" to channelBlocked,
        )
    }

    private fun openNotificationSettings() {
        val appSettings = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", packageName, null))

        val intent = when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O -> appSettings
            // Deep link to the channel itself when it exists — the app-level
            // page does not show a channel's own on/off switch.
            hasPlaybackChannel() ->
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, PLAYBACK_CHANNEL_ID)
            else ->
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }

        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Some OEM builds ship without the deep-linked screens.
            startActivity(appSettings)
        }
    }

    private fun hasPlaybackChannel(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.getNotificationChannel(PLAYBACK_CHANNEL_ID) != null
    }

    private companion object {
        const val CHANNEL = "electrowave/notifications"

        /** Must match `androidNotificationChannelId` in `main.dart`. */
        const val PLAYBACK_CHANNEL_ID = "com.example.electrowave.playback"
    }
}
