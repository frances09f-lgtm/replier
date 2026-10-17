package com.replier.replier.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import com.replier.replier.MainActivity
import com.replier.replier.R

/**
 * Foreground service that keeps the app process alive in the background.
 * Without this, Android kills the process and the NotificationListenerService
 * loses its connection to the RuleEngine and cannot auto-reply.
 */
class AutoReplyForegroundService : Service() {

    companion object {
        private const val TAG = "ForegroundService"
        private const val CHANNEL_ID = "auto_reply_foreground"
        private const val NOTIFICATION_ID = 1001

        fun start(context: Context) {
            val intent = Intent(context, AutoReplyForegroundService::class.java)
            if(RuleEngine(context).isMasterEnabled()) context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, AutoReplyForegroundService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Foreground service created")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        // Warm the local model in the background so the first reply is fast
        PhiLocalService.getInstance(this).preloadModel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Foreground service started")
        // START_STICKY: Android will restart this service if it gets killed
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Foreground service destroyed — restarting")
        // Restart self if destroyed
        val restartIntent = Intent(applicationContext, AutoReplyForegroundService::class.java)
        if(RuleEngine(this).isMasterEnabled()) startForegroundService(restartIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Auto Reply Service",
            NotificationManager.IMPORTANCE_LOW // Low = no sound, minimised in tray
        ).apply {
            description = "Keeps Auto Reply running in the background"
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openAppIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Auto Reply is active")
            .setContentText("Monitoring WhatsApp & Instagram notifications")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(openAppIntent)
            .setOngoing(true)   // Cannot be swiped away
            .build()
    }
}
