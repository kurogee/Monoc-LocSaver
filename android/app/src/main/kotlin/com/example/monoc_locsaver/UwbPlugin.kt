package com.example.monoc_locsaver

import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.UwbManager
import androidx.core.uwb.rxjava3.UwbManagerRx
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.rx3.await
import kotlinx.coroutines.rx3.collect
import java.nio.ByteBuffer

class UwbPlugin(private val context: Context) : MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "uwb_service"
    }

    private var uwbManager: UwbManager? = null
    private var rangingJob: Job? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    private var methodChannel: MethodChannel? = null

    fun setMethodChannel(channel: MethodChannel) {
        methodChannel = channel
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "checkUwbSupport" -> checkUwbSupport(result)
            "startRanging" -> {
                val targetId = call.argument<String>("targetId")
                if (targetId != null) {
                    startRanging(targetId, result)
                } else {
                    result.error("INVALID_ARGUMENT", "targetId is required", null)
                }
            }
            "stopRanging" -> stopRanging(result)
            else -> result.notImplemented()
        }
    }

    private fun checkUwbSupport(result: Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                uwbManager = UwbManager.createInstance(context)
                val isSupported = uwbManager != null
                val isAvailable = isSupported && checkUwbAvailability()
                
                result.success(mapOf(
                    "isSupported" to isSupported,
                    "isAvailable" to isAvailable
                ))
            } catch (e: Exception) {
                result.success(mapOf(
                    "isSupported" to false,
                    "isAvailable" to false
                ))
            }
        } else {
            result.success(mapOf(
                "isSupported" to false,
                "isAvailable" to false
            ))
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun checkUwbAvailability(): Boolean {
        return try {
            val manager = uwbManager ?: return false
            // UWB機能が利用可能かチェック
            true
        } catch (e: Exception) {
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun startRanging(targetId: String, result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.error("UNSUPPORTED", "UWB requires Android 12+", null)
            return
        }

        val manager = uwbManager
        if (manager == null) {
            result.error("UWB_NOT_AVAILABLE", "UWB manager not initialized", null)
            return
        }

        try {
            rangingJob?.cancel()
            val uwbManagerRx = UwbManagerRx.createInstance(context)

            rangingJob = coroutineScope.launch {
                try {
                    val controllerScope = uwbManagerRx.controllerSessionScope

                    // targetIdを8バイトのUWBアドレスへ（例: "0102030405060708"）
                    val peerAddress = UwbAddress(hexToBytes(targetId))

                    val params = RangingParameters(
                        sessionId = (System.currentTimeMillis() % 65535).toInt(),
                        deviceRole = RangingParameters.DEVICE_ROLE_CONTROLLER,
                        rangingUpdateRate = RangingParameters.RANGING_UPDATE_RATE_FREQUENT,
                        uwbConfigType = RangingParameters.UWB_CONFIG_ID_1,
                        peerDevices = listOf(RangingParameters.PeerDevice(peerAddress))
                    )

                    // セッション開始
                    val session = controllerScope.prepareSession(params).await()
                    session.start(params)

                    result.success(true)

                    // 測距フローを受信
                    session.rangingResults.collect { rangingResult ->
                        when (rangingResult) {
                            is RangingResult.Position -> {
                                val distance = rangingResult.distance?.value
                                val azimuth = rangingResult.azimuth?.value
                                val elevation = rangingResult.elevation?.value

                                val payload = mapOf(
                                    "targetId" to targetId,
                                    "distance" to (distance ?: -1.0),
                                    "azimuth" to azimuth,
                                    "elevation" to elevation,
                                )
                                methodChannel?.invokeMethod("onRangingResult", payload)
                            }
                            is RangingResult.RangingError -> {
                                methodChannel?.invokeMethod("onRangingError", rangingResult.error.toString())
                            }
                        }
                    }
                } catch (e: Exception) {
                    methodChannel?.invokeMethod("onRangingError", e.message)
                }
            }
        } catch (e: Exception) {
            result.error("RANGING_ERROR", e.message, null)
        }
    }

    private fun stopRanging(result: Result) {
        rangingJob?.cancel()
        rangingJob = null
        result.success(null)
    }

    fun cleanup() {
        rangingJob?.cancel()
        uwbManager = null
    }

    private fun hexToBytes(hex: String): ByteArray {
        val clean = hex.replace(Regex("[^0-9A-Fa-f]"), "")
        if (clean.isEmpty()) return ByteArray(8) { 0x00 }
        val buffer = ByteBuffer.allocate((clean.length + 1) / 2)
        var i = 0
        while (i < clean.length) {
            val end = (i + 2).coerceAtMost(clean.length)
            buffer.put(clean.substring(i, end).toInt(16).toByte())
            i += 2
        }
        // UWBアドレスは8バイト推奨、足りない場合は0でパディング
        val arr = buffer.array()
        return if (arr.size >= 8) arr.copyOfRange(0, 8) else arr + ByteArray(8 - arr.size)
    }
}
