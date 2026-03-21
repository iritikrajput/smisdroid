package com.example.smisdroid

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.IntentFilter
import android.provider.Telephony
import android.os.Build
import android.util.Log
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : FlutterActivity() {
    private val SMS_CHANNEL = "com.example.smisdroid/sms"
    private val SMS_EVENT_CHANNEL = "com.example.smisdroid/sms_events"
    private var smsReceiver: SmsReceiver? = null
    private var eventSink: EventChannel.EventSink? = null
    private val SMS_PERMISSION_CODE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Request SMS permission early
        requestSmsPermission()

        // EventChannel: streams incoming SMS to Flutter in real-time
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerSmsReceiver()
                    Log.d("SMISDroid", "SMS event channel LISTENING")
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterSmsReceiver()
                    Log.d("SMISDroid", "SMS event channel cancelled")
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

    private fun requestSmsPermission() {
        val permissions = arrayOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS
        )
        val needed = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), SMS_PERMISSION_CODE)
        }
    }

    private fun registerSmsReceiver() {
        if (smsReceiver != null) return

        smsReceiver = SmsReceiver()
        SmsReceiver.onSmsReceived = { sender, body ->
            Log.d("SMISDroid", ">>> SMS captured: from=$sender, len=${body.length}")
            runOnUiThread {
                eventSink?.success(mapOf("sender" to sender, "body" to body))
                    ?: Log.w("SMISDroid", "EventSink is null — Flutter not listening")
            }
        }

        val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
        filter.priority = 999

        // SMS_RECEIVED is a system broadcast — must use RECEIVER_EXPORTED on Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsReceiver, filter, RECEIVER_EXPORTED)
        } else {
            registerReceiver(smsReceiver, filter)
        }

        Log.d("SMISDroid", "SMS receiver registered (API ${Build.VERSION.SDK_INT})")
    }

    private fun unregisterSmsReceiver() {
        smsReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            SmsReceiver.onSmsReceived = null
            smsReceiver = null
            Log.d("SMISDroid", "SMS receiver unregistered")
        }
    }

    override fun onDestroy() {
        unregisterSmsReceiver()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_CODE) {
            if (grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                Log.d("SMISDroid", "SMS permissions granted — registering receiver")
                registerSmsReceiver()
            } else {
                Log.w("SMISDroid", "SMS permissions DENIED")
            }
        }
    }
}
