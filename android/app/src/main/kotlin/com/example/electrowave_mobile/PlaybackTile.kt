package com.example.electrowave_mobile

import android.service.quicksettings.TileService
import android.service.quicksettings.Tile
import android.content.ComponentName
import android.content.Intent
import android.content.SharedPreferences
import android.view.KeyEvent

class PlaybackTile:TileService(),SharedPreferences.OnSharedPreferenceChangeListener {
    private val preferences by lazy {getSharedPreferences("HomeWidgetPreferences",0)}
    override fun onStartListening() {
        super.onStartListening();preferences.registerOnSharedPreferenceChangeListener(this);refresh()
    }
    override fun onStopListening() {
        preferences.unregisterOnSharedPreferenceChangeListener(this);super.onStopListening()
    }
    override fun onSharedPreferenceChanged(prefs:SharedPreferences?,key:String?) {if(key=="is_playing") refresh()}
    private fun refresh() {
        val playing=preferences.getBoolean("is_playing",false)
        qsTile?.apply {state=if(playing) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE;label=if(playing) "Pause Electrowave" else "Play Electrowave";updateTile()}
    }
    override fun onClick() {
        super.onClick()
        sendBroadcast(Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component=ComponentName(this@PlaybackTile,"com.ryanheise.audioservice.MediaButtonReceiver")
            putExtra(Intent.EXTRA_KEY_EVENT,KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        })
        android.os.Handler(mainLooper).postDelayed({refresh()},700)
    }
}
