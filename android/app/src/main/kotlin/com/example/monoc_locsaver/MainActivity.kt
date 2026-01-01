package com.example.monoc_locsaver

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var uwbPlugin: UwbPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // UWBプラグインを登録
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UwbPlugin.CHANNEL_NAME
        )
        
        uwbPlugin = UwbPlugin(this).apply {
            setMethodChannel(channel)
            channel.setMethodCallHandler(this)
        }
    }

    override fun onDestroy() {
        uwbPlugin?.cleanup()
        super.onDestroy()
    }
}
