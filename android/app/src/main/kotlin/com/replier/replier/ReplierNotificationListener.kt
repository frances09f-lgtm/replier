package com.replier.replier

import android.app.Notification
import android.app.Person
import android.os.Build
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ConcurrentLinkedQueue

/// Watches every posted notification, extracts message-shaped content, and
/// hands it to Dart. Pure detection: no app-specific hacks, no sending.
/// Sending lives in replyInline (the notification's own reply action) and
/// the accessibility service (last resort, user-approved only).
class ReplierNotificationListener : NotificationListenerService() {

    companion object {
        @Volatile var sink: EventChannel.EventSink? = null
        private val buffer = ConcurrentLinkedQueue<Map<String, Any>>()

        fun clearBuffer() { buffer.clear() }

        fun warm() { /* touch the class so the buffer exists */ }

        fun flushToSink() {
            if (instance?.let { !MasterPause.enabled(it) } == true) { buffer.clear(); return }
            val s = sink ?: return
            while (true) {
                val e = buffer.poll() ?: break
                s.success(e)
            }
        }

        fun drainBuffer(): List<Map<String, Any>> {
            if (instance?.let { !MasterPause.enabled(it) } == true) { buffer.clear(); return emptyList() }
            val out = mutableListOf<Map<String, Any>>()
            while (true) {
                out.add(buffer.poll() ?: break)
            }
            return out
        }

        private fun emit(event: Map<String, Any>) {
            if (instance?.let { !MasterPause.enabled(it) } == true) return
            val s = sink
            if (s != null) s.success(event) else buffer.add(event)
        }

        private fun active(context: Context, key: String): StatusBarNotification? {
            val svc = instance ?: return null
            return try {
                svc.activeNotifications?.firstOrNull { it.key == key }
            } catch (e: Exception) {
                null
            }
        }

        /// Send through the notification's own inline-reply action.
        /// submitted | no_inline | gone | error
        fun replyInline(context: Context, key: String, text: String): String {
            if (!MasterPause.enabled(context)) return "paused"
            if (LegacyMigration.blocked(context)) return "old_access_active"
            if (text.isBlank()) return "error"
            val sbn = active(context, key) ?: return "gone"
            val actions = sbn.notification.actions ?: return "no_inline"
            for (action in actions) {
                val inputs = action.remoteInputs ?: continue
                if (inputs.isEmpty()) continue
                return try {
                    val fill = Intent()
                    val bundle = Bundle()
                    for (ri in inputs) {
                        bundle.putCharSequence(ri.resultKey, text)
                    }
                    RemoteInput.addResultsToIntent(inputs, fill, bundle)
                    if (!MasterPause.enabled(context)) return "paused"
                    action.actionIntent.send(context, 0, fill)
                    "submitted"
                } catch (e: PendingIntent.CanceledException) {
                    "gone"
                } catch (e: Exception) {
                    "error"
                }
            }
            return "no_inline"
        }

        /// No inline action: open the chat, queue the text for the
        /// accessibility service to type + send. opened | gone | error
        fun openChatAndQueueSend(context: Context, key: String, text: String): String {
            if (!MasterPause.enabled(context)) return "paused"
            if (LegacyMigration.blocked(context)) return "old_access_active"
            val sbn = active(context, key) ?: return "gone"
            val pi = sbn.notification.contentIntent ?: return "error"
            return try {
                ReplierAccessibilityService.queueSend(text)
                if (!MasterPause.enabled(context)) { ReplierAccessibilityService.clearQueue(); return "paused" }
                pi.send()
                "opened"
            } catch (e: Exception) {
                ReplierAccessibilityService.clearQueue()
                "error"
            }
        }

        @Volatile var instance: ReplierNotificationListener? = null
    }

    override fun onListenerConnected() {
        instance = this
    }

    override fun onListenerDisconnected() {
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            if (!MasterPause.enabled(this)) return
            if (LegacyMigration.blocked(this)) return
            if (sbn.packageName == packageName) return // never process our own
            val n = sbn.notification ?: return
            if(sbn.packageName in setOf("com.ambi.gold_paper_trading","com.ambi.lookout","com.friday.assistant"))return
            if(n.flags and Notification.FLAG_ONGOING_EVENT != 0 || n.flags and Notification.FLAG_GROUP_SUMMARY != 0)return
            val extras = n.extras ?: return

            var sender = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            var messageAt = sbn.postTime
            var text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

            // MessagingStyle notifications (WhatsApp, Telegram, ...) carry
            // the real sender per message and let us skip the user's OWN
            // outgoing messages.
            // Framework-only MessagingStyle parsing (no androidx dep):
            // EXTRA_MESSAGES holds Message bundles, EXTRA_MESSAGING_PERSON
            // holds the phone owner's own Person (used to skip outgoing).
            val msgBundles = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (msgBundles != null && msgBundles.isNotEmpty()) {
                val lastBundle = msgBundles[msgBundles.size - 1] as? Bundle
                if (lastBundle != null) {
                    messageAt = lastBundle.getLong("time", sbn.postTime)
                    // Parse the Message bundle directly (stable framework keys
                    // "text"/"sender"/"sender_person") - no hidden API calls.
                    val senderP: Person? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                            lastBundle.getParcelable("sender_person", Person::class.java)
                        else
                            @Suppress("DEPRECATION") lastBundle.getParcelable("sender_person") as? Person
                    val userPerson: Person? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                            extras.getParcelable(Notification.EXTRA_MESSAGING_PERSON, Person::class.java)
                        else
                            @Suppress("DEPRECATION") extras.getParcelable(Notification.EXTRA_MESSAGING_PERSON) as? Person
                    val userName = userPerson?.name?.toString()
                    val msgSender = senderP?.name?.toString()
                        ?: lastBundle.getCharSequence("sender")?.toString() ?: ""
                    if (!userName.isNullOrEmpty() && msgSender == userName) return
                    if (msgSender.isNotEmpty()) sender = msgSender
                    val msgText = lastBundle.getCharSequence("text")?.toString() ?: ""
                    if (msgText.isNotEmpty()) text = msgText
                }
            }

            if (text.isBlank()) return // nothing readable: skip safely
            if(Regex("^(?:[^:]+: )?(?:Reacted .+ to |You reacted |Reaction to )",RegexOption.IGNORE_CASE).containsMatchIn(text))return
            if (sender.isBlank()) sender = sbn.packageName

            val label = try {
                packageManager.getApplicationLabel(
                    packageManager.getApplicationInfo(sbn.packageName, 0)
                ).toString()
            } catch (e: Exception) {
                sbn.packageName
            }

            emit(
                mapOf(
                    "notifKey" to sbn.key,
                    "package" to sbn.packageName,
                    "appLabel" to label,
                    "sender" to sender,
                    "text" to text,
                    "at" to messageAt
                )
            )
        } catch (e: Exception) {
            // A malformed notification must never kill the listener.
        }
    }
}
