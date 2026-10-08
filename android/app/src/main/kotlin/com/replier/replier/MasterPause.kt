package com.replier.replier
import android.content.Context
object MasterPause {
    fun enabled(context: Context): Boolean =
        context.getSharedPreferences("replier_master", Context.MODE_PRIVATE).getBoolean("enabled", true)
    fun set(context: Context, enabled: Boolean): Boolean {
        val saved = context.getSharedPreferences("replier_master", Context.MODE_PRIVATE)
            .edit().putBoolean("enabled", enabled).commit()
        if (!enabled) {
            ReplierNotificationListener.clearBuffer()
            ReplierAccessibilityService.clearQueue()
        }
        return saved
    }
}
