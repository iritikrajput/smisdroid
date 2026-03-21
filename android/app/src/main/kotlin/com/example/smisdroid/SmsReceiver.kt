package com.example.smisdroid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Native BroadcastReceiver for SMS_RECEIVED.
 * Ensures SMS messages are captured even when the app is killed.
 * Forwards the message to Flutter via a MethodChannel through MainActivity.
 */
class SmsReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "SmsReceiver"
        var onSmsReceived: ((sender: String, body: String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        // Group multi-part SMS by sender
        val grouped = mutableMapOf<String, StringBuilder>()
        for (msg in messages) {
            val sender = msg.originatingAddress ?: "Unknown"
            val body = msg.messageBody ?: ""
            grouped.getOrPut(sender) { StringBuilder() }.append(body)
        }

        for ((sender, body) in grouped) {
            val fullMessage = body.toString()
            Log.d(TAG, "SMS received from: $sender (${fullMessage.length} chars)")

            // Forward to Flutter callback if registered
            onSmsReceived?.invoke(sender, fullMessage)
        }
    }
}
