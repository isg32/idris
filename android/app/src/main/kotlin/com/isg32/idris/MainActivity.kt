package com.isg32.idris

import android.content.Intent
import android.os.Bundle
import com.isg32.idris.youtube.YouTubeChannel
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

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
    }

    @Deprecated("Flutter's FlutterActivity still routes results through this")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (LocalMusic.onActivityResult(this, requestCode, resultCode, data)) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
