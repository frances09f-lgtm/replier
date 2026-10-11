package com.replier.replier
import android.content.Context
import android.provider.Settings
object LegacyGuard {
 private val packages=setOf("com.example.auto_reply_assistant","com.replier.replier")
 fun blocked(c:Context):Boolean {return listOf("enabled_notification_listeners",Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).any{setting->(Settings.Secure.getString(c.contentResolver,setting)?:"").split(':').any{it.substringBefore('/') in packages}}}
}
