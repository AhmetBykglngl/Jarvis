package com.jarvis.jarvis

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarvis/arkaplan")
            .setMethodCallHandler { call, result ->
                val servis = Intent(this, JarvisService::class.java)
                when (call.method) {
                    "baslat" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(servis)
                            else startService(servis)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "durdur" -> {
                        stopService(servis)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
