package com.isg32.idris

import com.isg32.idris.youtube.YouTubeChannel
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The app's activity. It extends audio_service's activity so the playback
 * media service and the app share one Flutter engine.
 */
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        YouTubeChannel.register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
