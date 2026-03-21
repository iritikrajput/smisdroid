package com.example.smisdroid

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.IntentFilter
import android.provider.Telephony
import android.os.Build
import android.util.Log

class MainActivity : FlutterActivity() {
    private val SMS_CHANNEL = "com.example.smisdroid/sms"
    private val SMS_EVENT_CHANNEL = "com.example.smisdroid/sms_events"
    private var smsReceiver: SmsReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // EventChannel: streams incoming SMS to Flutter in real-time
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerSmsReceiver()
                    Log.d("MainActivity", "SMS event channel listening")
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterSmsReceiver()
                    Log.d("MainActivity", "SMS event channel cancelled")
                }
            })

        // MethodChannel: for one-off calls from Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> {
                        registerSmsReceiver()
                        result.success(true)
                    }
                    "stopListening" -> {
                        unregisterSmsReceiver()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerSmsReceiver() {
        if (smsReceiver != null) return

        smsReceiver = SmsReceiver()
        SmsReceiver.onSmsReceived = { sender, body ->
            runOnUiThread {
                eventSink?.success(mapOf("sender" to sender, "body" to body))
            }
        }

        val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
        filter.priority = 999 // High priority to intercept before default SMS app

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(smsReceiver, filter)
        }

        Log.d("MainActivity", "SMS receiver registered with priority 999")
    }

    private fun unregisterSmsReceiver() {
        smsReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            SmsReceiver.onSmsReceived = null
            smsReceiver = null
            Log.d("MainActivity", "SMS receiver unregistered")
        }
    }

    override fun onDestroy() {
        unregisterSmsReceiver()
        super.onDestroy()
    }
}
