package com.replier.replier.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.util.Log
import com.replier.replier.MainActivity
import com.replier.replier.R

/**
 * Foreground service that keeps the app process alive in the background.
 * Without this, Android kills the process and the NotificationListenerService
 * loses its connection to the RuleEngine and cannot auto-reply.
 *
 * It also runs a light watchdog: if the user still has notification access
 * enabled but the listener service object is gone while the process lives,
 * it asks Android to rebind the listener.
 */
class AutoReplyForegroundService : Service() {

    companion object {
        private const val TAG = "ForegroundService"
        private const val CHANNEL_ID = "auto_reply_foreground"
        private const val NOTIFICATION_ID = 1001
        private const val WATCHDOG_INTERVAL_MS = 60_000L

        fun start(context: Context) {
            val intent = Intent(context, AutoReplyForegroundService::class.java)
            if(RuleEngine(context).isMasterEnabled()) context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, AutoReplyForegroundService::class.java)
            context.stopService(intent)
        }
    }

    private val watchdogHandler = Handler(Looper.getMainLooper())
    private val listenerWatchdog = object : Runnable {
        override fun run() {
            checkListenerBound()
            watchdogHandler.postDelayed(this, WATCHDOG_INTERVAL_MS)
        }
    }

    private fun checkListenerBound() {
        try {
            val enabled = Settings.Secure.getString(
                contentResolver, "enabled_notification_listeners"
            ) ?: ""
            if (enabled.contains(packageName) &&
                AppNotificationListenerService.getInstance() == null
            ) {
                Log.w(TAG, "Notification listener not running, requesting rebind")
                NotificationListenerService.requestRebind(
                    ComponentName(this, AppNotificationListenerService::class.java)
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Listener watchdog check failed: ${e.message}")
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
        watchdogHandler.removeCallbacks(listenerWatchdog)
        watchdogHandler.postDelayed(listenerWatchdog, WATCHDOG_INTERVAL_MS)
        // START_STICKY: Android will restart this service if it gets killed
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        watchdogHandler.removeCallbacks(listenerWatchdog)
        Log.d(TAG, "Foreground service destroyed — restarting")
        // Restart self if destroyed. On Android 12+ starting a foreground
        // service from the background can throw; do not crash the process
        // that also hosts the notification listener.
        try {
            val restartIntent = Intent(applicationContext, AutoReplyForegroundService::class.java)
            if(RuleEngine(this).isMasterEnabled()) startForegroundService(restartIntent)
        } catch (e: Exception) {
            Log.w(TAG, "Could not restart foreground service: ${e.message}")
        }
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
