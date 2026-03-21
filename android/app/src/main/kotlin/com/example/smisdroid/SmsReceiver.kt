package com.example.smisdroid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Native BroadcastReceiver for SMS_RECEIVED.
 * Registered both in AndroidManifest (for background) and at runtime (for foreground).
 */
class SmsReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "SMISDroid"
        var onSmsReceived: ((sender: String, body: String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "BroadcastReceiver.onReceive triggered: action=${intent.action}")

        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            Log.w(TAG, "Ignoring non-SMS intent: ${intent.action}")
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) {
            Log.w(TAG, "No messages in SMS intent")
            return
        }

        Log.d(TAG, "Received ${messages.size} SMS PDU(s)")

        // Group multi-part SMS by sender
        val grouped = mutableMapOf<String, StringBuilder>()
        for (msg in messages) {
            val sender = msg.originatingAddress ?: "Unknown"
            val body = msg.messageBody ?: ""
            grouped.getOrPut(sender) { StringBuilder() }.append(body)
        }

        for ((sender, body) in grouped) {
            val fullMessage = body.toString()
            Log.d(TAG, "SMS from: $sender | length: ${fullMessage.length} | preview: ${fullMessage.take(50)}")

            if (onSmsReceived != null) {
                onSmsReceived?.invoke(sender, fullMessage)
                Log.d(TAG, "SMS forwarded to Flutter via callback")
            } else {
                Log.w(TAG, "onSmsReceived callback is NULL — Flutter not connected")
            }
        }
    }
}
