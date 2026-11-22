package com.isg32.idris

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Bundle
import com.isg32.idris.youtube.YouTubeChannel
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's activity. It extends audio_service's activity so the playback
 * media service and the app share one Flutter engine.
 */
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        CrashFiles.installCrashHandler(this)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        YouTubeChannel.register(messenger)
        CrashFiles.register(this, messenger)
        // Over-the-air updates from GitHub Releases (lib/platform/updater.dart).
        Updater.register(this, messenger)
        // Music from folders on the phone (lib/platform/local_music.dart).
        LocalMusic.register(this, messenger)
        // A volume-key tap while Idris holds the keys to skip
        // (lib/platform/volume_keys.dart): change the media volume as Android
        // would, with its volume panel.
        val audio = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        MethodChannel(messenger, "idris/volume").setMethodCallHandler { call, result ->
            if (call.method == "step") {
                val up = (call.argument<Int>("direction") ?: 0) > 0
                audio.adjustStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                    AudioManager.FLAG_SHOW_UI,
                )
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    @Deprecated("Flutter's FlutterActivity still routes results through this")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (LocalMusic.onActivityResult(this, requestCode, resultCode, data)) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
