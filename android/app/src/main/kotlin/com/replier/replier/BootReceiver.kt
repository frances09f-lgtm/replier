package com.replier.replier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.replier.replier.reminder.NoteReminderScheduler
import com.replier.replier.service.AutoReplyForegroundService

/**
 * Starts the foreground service automatically after the device reboots and
 * re-arms any note-reminder alarms that were lost with the reboot.
 * Requires RECEIVE_BOOT_COMPLETED permission.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            Log.d(TAG, "Boot completed — starting AutoReplyForegroundService")
            if(com.replier.replier.service.RuleEngine(context).isMasterEnabled()) AutoReplyForegroundService.start(context)

            Log.d(TAG, "Boot completed — re-arming note reminder alarms")
            NoteReminderScheduler.getInstance(context).rescheduleDueToBoot()
        }
    }
}
