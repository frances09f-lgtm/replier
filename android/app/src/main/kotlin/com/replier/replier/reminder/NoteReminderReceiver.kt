package com.replier.replier.reminder

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.replier.replier.MainActivity

/**
 * Fires the notification when a note reminder alarm goes off.
 *
 * Receives the note payload that was attached at scheduling time, so it works
 * even after a reboot or when the Flutter engine is not running.
 */
class NoteReminderReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "NoteReminderReceiver"
        private const val CHANNEL_ID = "note_reminders"
        private const val NOTIFICATION_ID_BASE = 12000

        const val EXTRA_NOTE_ID = "note_id"
        const val EXTRA_TITLE = "note_title"
        const val EXTRA_BODY = "note_body"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val noteId = intent.getStringExtra(EXTRA_NOTE_ID) ?: return
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Reminder"
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""

        createChannel(context)
        showNotification(context, noteId, title, body)
        Log.d(TAG, "Note reminder fired for '$noteId': $title")
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                CHANNEL_ID,
                "Note Reminders",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Reminders for meetings, calls, and deadlines captured from your messages"
                enableVibration(true)
            }
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun showNotification(context: Context, noteId: String, title: String, body: String) {
        val contentIntent = PendingIntent.getActivity(
            context,
            noteId.hashCode(),
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body.ifBlank { title })
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setPriority(Notification.PRIORITY_HIGH)

        if (body.isNotBlank() && body != title) {
            notificationBuilder.setStyle(Notification.BigTextStyle().bigText(body))
        }

        val notification = notificationBuilder.build()

        val notificationId = NOTIFICATION_ID_BASE + noteId.hashCode()
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.notify(notificationId, notification)
    }
}
