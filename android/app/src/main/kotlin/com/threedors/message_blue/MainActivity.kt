package com.threedors.message_blue

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trama/network")
            .setMethodCallHandler { call, result ->
                try {
                    val intent = Intent(this, MeshNetworkService::class.java)
                    when (call.method) {
                        "start" -> {
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent)
                            else startService(intent)
                            result.success(null)
                        }
                        "stop" -> { stopService(intent); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("network_service", error.message, null)
                }
            }
    }
}
