package com.example.electrowave_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home screen widget: current track plus previous / play-pause / next.
 *
 * Track data is written from Dart through home_widget (see
 * lib/features/player/services/widget_service.dart). Buttons broadcast
 * standard ACTION_MEDIA_BUTTON key events to audio_service's receiver, so the
 * widget drives the same session as the notification and needs no extra
 * plumbing on the Dart side.
 */
class ElectrowaveWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("track_title", null)
        val artist = widgetData.getString("track_artist", null)
        val artPath = widgetData.getString("track_art", null)
        val playing = widgetData.getBoolean("is_playing", false)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.electrowave_widget).apply {
                setTextViewText(R.id.widget_title, title ?: "Nothing playing")
                setTextViewText(R.id.widget_artist, artist ?: "Electrowave")

                setImageViewResource(
                    R.id.widget_play_pause,
                    if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
                )

                // Decoded here rather than passed as a Uri: the launcher runs in
                // another process and would not be able to read our files.
                val art = artPath?.let { decodeArt(it) }
                if (art != null) {
                    setImageViewBitmap(R.id.widget_art, art)
                    setViewPadding(R.id.widget_art, 0, 0, 0, 0)
                } else {
                    setImageViewResource(R.id.widget_art, R.drawable.ic_stat_electrowave)
                    // centerCrop would blow the logo up to fill the square, so
                    // inset it instead and let the art background show around it.
                    val inset = (FALLBACK_INSET_DP * context.resources.displayMetrics.density).toInt()
                    setViewPadding(R.id.widget_art, inset, inset, inset, inset)
                }

                setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
                setOnClickPendingIntent(
                    R.id.widget_previous,
                    mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS),
                )
                setOnClickPendingIntent(
                    R.id.widget_play_pause,
                    mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE),
                )
                setOnClickPendingIntent(
                    R.id.widget_next,
                    mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Album art is downscaled before it crosses into the launcher process:
     * RemoteViews bitmaps travel over a Binder transaction with a hard size
     * limit, and embedded art is often far larger than the widget needs.
     */
    private fun decodeArt(path: String) = try {
        val file = File(path)
        if (!file.exists()) {
            null
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var scale = 1
            while (bounds.outWidth / (scale * 2) >= TARGET_ART_PX) {
                scale *= 2
            }
            BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply { inSampleSize = scale },
            )
        }
    } catch (e: Exception) {
        null
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun mediaButtonIntent(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(
                context,
                "com.ryanheise.audioservice.MediaButtonReceiver",
            )
            putExtra(
                Intent.EXTRA_KEY_EVENT,
                KeyEvent(KeyEvent.ACTION_DOWN, keyCode),
            )
        }
        return PendingIntent.getBroadcast(
            context,
            // Distinct request codes, otherwise the three buttons would share
            // one PendingIntent and all send the same key event.
            keyCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private companion object {
        const val TARGET_ART_PX = 192
        const val FALLBACK_INSET_DP = 14
    }
}
