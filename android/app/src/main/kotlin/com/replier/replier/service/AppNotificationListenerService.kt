package com.replier.replier.service

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import org.json.JSONArray
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class AppNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "AppNotificationListener"
        private const val CONFIRM_NOTIFICATION_CHANNEL_ID = "confirm_reply_channel"
        private const val REPLY_ERROR_CHANNEL_ID = "reply_error_channel"
        private const val REPLY_ERROR_NOTIFICATION_ID = 977
        private const val CONFIRM_NOTIFICATION_ID_BASE = 9000
        private const val CONFIRM_TIMEOUT_MS = 15_000L

        const val ACTION_APPROVE = "com.replier.replier.APPROVE_REPLY"
        const val ACTION_DENY = "com.replier.replier.DENY_REPLY"
        const val EXTRA_CONFIRM_ID = "confirm_id"
        const val EXTRA_NOTIFICATION_KEY = "notification_key"
        const val EXTRA_SENDER = "sender"
        const val EXTRA_REPLY_TEXT = "reply_text"
        const val EXTRA_ORIGINAL_MESSAGE = "original_message"
        const val EXTRA_IS_AI_REPLY = "is_ai_reply"
        const val EXTRA_AI_MODEL_TYPE = "ai_model_type"

        private var methodChannel: MethodChannel? = null
        private var instance: AppNotificationListenerService? = null

        private var chatbotContext: String = ""

        fun setMethodChannel(channel: MethodChannel) {
            methodChannel = channel
        }

        fun getInstance(): AppNotificationListenerService? = instance

        fun setChatbotContext(context: String) {
            chatbotContext = context
            Log.d(TAG, "Chatbot context updated (${context.length} chars)")
        }

        fun getChatbotContext(): String = chatbotContext

        private const val PIPELINE_EVENTS_PREFS = "replier_pipeline_events"
        private const val PIPELINE_EVENTS_KEY = "events"
        private const val PIPELINE_EVENTS_MAX = 60

        fun recordPipelineEvent(reason: String) {
            try {
                val ctx = instance?.applicationContext ?: return
                val event = JSONObject().apply {
                    put("id", "${System.currentTimeMillis()}-${(0..999999).random()}")
                    put("ts", System.currentTimeMillis())
                    put("reason", reason)
                }.toString()
                val prefs = ctx.getSharedPreferences(PIPELINE_EVENTS_PREFS, Context.MODE_PRIVATE)
                val arr = try {
                    JSONArray(prefs.getString(PIPELINE_EVENTS_KEY, "[]") ?: "[]")
                } catch (_: Exception) { JSONArray() }
                arr.put(event)
                while (arr.length() > PIPELINE_EVENTS_MAX) arr.remove(0)
                prefs.edit().putString(PIPELINE_EVENTS_KEY, arr.toString()).apply()
            } catch (_: Exception) {
                Log.w(TAG, "recordPipelineEvent failed")
            }
        }

        fun drainPipelineEvents(): List<String> {
            val out = mutableListOf<String>()
            try {
                val ctx = instance?.applicationContext ?: return out
                val prefs = ctx.getSharedPreferences(PIPELINE_EVENTS_PREFS, Context.MODE_PRIVATE)
                val raw = prefs.getString(PIPELINE_EVENTS_KEY, null)
                if (raw != null) {
                    val arr = JSONArray(raw)
                    for (i in 0 until arr.length()) out.add(arr.getString(i))
                }
                prefs.edit().remove(PIPELINE_EVENTS_KEY).apply()
            } catch (_: Exception) {
                Log.w(TAG, "drainPipelineEvents failed")
            }
            return out
        }
    }

    data class PendingReply(
        val confirmId: String,
        val notificationKey: String,
        val packageName: String,
        val shortcutId: String?,
        val sbnTag: String?,
        val sbnId: Int?,
        val sender: String,
        val replyText: String,
        val originalMessage: String,
        val isAiReply: Boolean,
        val aiModelType: String,
        val createdAt: Long = System.currentTimeMillis(),
    )

    data class ScheduledReply(
        val runnable: Runnable,
        val wakeLock: PowerManager.WakeLock?,
        val scheduledAt: Long,
        val delayMs: Long,
        val replyText: String,
        val originalMessage: String,
        val notificationKey: String,
        val packageName: String?,
        val shortcutId: String?,
        val sbnTag: String?,
        val sbnId: Int?,
    )

    private val pendingReplies = ConcurrentHashMap<String, PendingReply>()
    private var confirmReceiver: BroadcastReceiver? = null

    private val activeScheduledReplies = ConcurrentHashMap<String, ScheduledReply>()

    private val lastHandledIncoming = ConcurrentHashMap<String, Pair<String, Long>>()
    private val incomingDedupeWindowMs = 60_000L

    private val notificationArrivalTimes = ConcurrentHashMap<String, Long>()

    private val maxChatbotContextChars = 600

    private val supportedPackages = listOf(
        "com.whatsapp",
        "com.instagram.android"
    )

    private lateinit var ruleEngine: RuleEngine
    private lateinit var messageBatcher: MessageBatcher
    private val mainHandler = Handler(Looper.getMainLooper())
    private val directChatGate = DirectChatGate()
    private val analysisAttempts = AnalysisAttempts { SystemClock.elapsedRealtime() }
    private val analysisEpoch = UUID.randomUUID().toString()
    private var analysisRevision = 0L
    private val analysisTimers = mutableMapOf<String, Runnable>()

    fun analysisSnapshot(): String {
        val records = analysisAttempts.snapshot()
        return JSONObject().apply {
            put("epoch", analysisEpoch)
            put("revision", ++analysisRevision)
            put("attempts", JSONArray().apply {
                records.forEach { a -> put(JSONObject().apply {
                    put("id", a.id); put("sender", a.sender); put("state", a.state)
                    put("remainingMs", analysisAttempts.remaining(a.id))
                    put("limitMs", AnalysisAttempts.LIMIT_MS)
                    put("terminalRemainingMs", a.finished?.let {
                        (AnalysisAttempts.TERMINAL_DISPLAY_MS - (SystemClock.elapsedRealtime() - it)).coerceAtLeast(0)
                    } ?: 0)
                }) }
            })
        }.toString()
    }

    private fun publishAnalysis() {
        methodChannel?.invokeMethod("onAnalysisStatus", analysisSnapshot())
    }

    private fun failAnalysis(id: String) {
        mainHandler.post {
            analysisAttempts.complete(id, "failed")
            analysisTimers.remove(id)?.let { mainHandler.removeCallbacks(it) }
            publishAnalysis()
        }
    }


    private fun acquireWakeLock(tag: String, timeoutMs: Long): PowerManager.WakeLock? {
        return try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AutoReplier:$tag")?.apply {
                setReferenceCounted(false)
                acquire(timeoutMs)
                Log.d(TAG, "WakeLock acquired for $tag (${timeoutMs}ms)")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire wake lock: ${e.message}")
            null
        }
    }

    private fun cancelScheduledReply(sender: String) {
        val existing = activeScheduledReplies.remove(senderKey(sender)) ?: return
        mainHandler.removeCallbacks(existing.runnable)
        existing.wakeLock?.let { wl ->
            if (wl.isHeld) {
                try { wl.release() } catch (_: Exception) {}
            }
        }
        Log.d(TAG, "Pipeline event")
    }

    private fun scheduleDelayedReply(
        key: String,
        sender: String,
        replyText: String,
        isAiReply: Boolean = false,
        aiModelType: String = "",
        originalMessage: String = "",
        packageName: String? = null,
        shortcutId: String? = null,
        sbnTag: String? = null,
        sbnId: Int? = null,
        onBeforeSend: (() -> Unit)? = null,
    ) {
        if (confirmedDirectTarget(key, packageName, shortcutId, sbnTag, sbnId) == null) {
            notifyUnsafeChatSkipped()
            return
        }
        cancelScheduledReply(sender)

        val resolvedIdentity = resolveConversationIdentity(key, packageName, shortcutId, sbnTag, sbnId)
        val resolvedPackage = resolvedIdentity.first
        val resolvedShortcut = resolvedIdentity.second
        val resolvedTag = resolvedIdentity.third
        val resolvedId = resolvedIdentity.fourth

        val snapshot=activeNotifications?.find{it.key==key}?.notification?.extras?.let{e->e.toString()+e.getCharSequence(Notification.EXTRA_TEXT).toString()+e.getCharSequence(Notification.EXTRA_BIG_TEXT).toString()}
        val delayMs = ruleEngine.getReplyDelayMs()
        notifyReplyScheduled(sender, replyText, delayMs)

        if (delayMs <= 0L) {
            Log.d(TAG, "Pipeline event")
            onBeforeSend?.invoke()
            sendReply(key, sender, replyText, isAiReply, aiModelType, resolvedPackage, resolvedShortcut, resolvedTag, resolvedId)
            return
        }

        val wakeLock = acquireWakeLock("Reply_${sender.hashCode()}", delayMs + 5000L)

        val runnable = Runnable {
            try {
                activeScheduledReplies.remove(senderKey(sender))
                Log.d(TAG, "Pipeline event")
                val current=activeNotifications?.find{it.key==key}?.notification?.extras?.let{e->e.toString()+e.getCharSequence(Notification.EXTRA_TEXT).toString()+e.getCharSequence(Notification.EXTRA_BIG_TEXT).toString()}
                if(snapshot==null || snapshot!=current){mainHandler.post{methodChannel?.invokeMethod("onReplyFailed","Draft replaced by newer notification")};return@Runnable}
                onBeforeSend?.invoke()
                sendReply(key, sender, replyText, isAiReply, aiModelType, resolvedPackage, resolvedShortcut, resolvedTag, resolvedId)
            } finally {
                wakeLock?.let { wl ->
                    if (wl.isHeld) {
                        try { wl.release() } catch (_: Exception) {}
                    }
                }
            }
        }

        activeScheduledReplies[senderKey(sender)] = ScheduledReply(
            runnable = runnable,
            wakeLock = wakeLock,
            scheduledAt = System.currentTimeMillis(),
            delayMs = delayMs,
            replyText = replyText,
            originalMessage = originalMessage,
            notificationKey = key,
            packageName = resolvedPackage,
            shortcutId = resolvedShortcut,
            sbnTag = resolvedTag,
            sbnId = resolvedId,
        )

        mainHandler.postDelayed(runnable, delayMs)
        Log.d(TAG, "Pipeline event")
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        ruleEngine = RuleEngine(applicationContext)
        messageBatcher = MessageBatcher(mainHandler)
        createConfirmNotificationChannel()
        registerConfirmReceiver()
        Log.d(TAG, "AppNotificationListenerService created")
    }

    override fun onDestroy() {
        super.onDestroy()
        activeScheduledReplies.values.forEach { scheduled ->
            mainHandler.removeCallbacks(scheduled.runnable)
            scheduled.wakeLock?.let { wl ->
                if (wl.isHeld) {
                    try { wl.release() } catch (_: Exception) {}
                }
            }
        }
        activeScheduledReplies.clear()
        messageBatcher.cancelAll()
        directChatGate.clear()
        analysisAttempts.cancelAll()
        analysisTimers.values.forEach { mainHandler.removeCallbacks(it) }
        analysisTimers.clear()
        publishAnalysis()
        unregisterConfirmReceiver()
        instance = null
        Log.d(TAG, "AppNotificationListenerService destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        try {
            processNotification(sbn)
        } catch (t: Throwable) {
            Log.e(TAG, "Notification processing crashed", t)
            notifyReplyError("Reply pipeline crashed: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    private fun processNotification(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        if (!supportedPackages.contains(packageName)) return
        recordPipelineEvent("Got a notification from ${getAppName(packageName)}")

        if (isGroupSummary(sbn)) {
            // WhatsApp posts a group-summary notification for the same conversation (same
            // shortcut id) next to every chat notification. Treating it as a non-direct chat
            // revoked the admitted chat and silently cancelled the queued AI reply.
            recordPipelineEvent("Ignored ${getAppName(packageName)} summary notification")
            return
        }

        notificationArrivalTimes[sbn.key] = SystemClock.elapsedRealtime()
        if (notificationArrivalTimes.size > 100) {
            val cutoff = SystemClock.elapsedRealtime() - 10 * 60_000L
            notificationArrivalTimes.entries.removeIf { it.value < cutoff }
        }

        pendingReplies.entries.filter { it.value.notificationKey==sbn.key }.forEach { (id, _)-> pendingReplies.remove(id);getSystemService(NotificationManager::class.java).cancel(CONFIRM_NOTIFICATION_ID_BASE+id.hashCode()) }
        activeScheduledReplies.entries.filter{it.value.notificationKey==sbn.key}.forEach{(sender,_)->cancelScheduledReply(sender)}
        val notification = sbn.notification ?: return
        val extras = notification.extras

        val appName = getAppName(packageName)
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val message = if (bigText.isNotEmpty()) bigText else text
        val chatKind = classifyChat(notification, packageName)
        val target = chatTarget(sbn)
        val revoked = directChatGate.record(target, chatKind)
        revoked.forEach { cancelUnsafeConversation(it) }
        if (chatKind != ChatTypePolicy.Kind.DIRECT || !target.stable) {
            Log.i(TAG, "Skipping auto reply: chat type=$chatKind, stable=${target.stable}")
            recordPipelineEvent("Skipped: chat is not a confirmed one-to-one chat (type=$chatKind, stable=${target.stable})")
            return
        }
        val isGroupChat = false

        val sender = normalizeSenderName(title, packageName)
        Log.d(TAG, "Pipeline event")

        if (isOutgoingMessagingStyleMessage(notification, sender)) {
            Log.d(TAG, "Pipeline event")
            recordPipelineEvent("Skipped: outgoing message echo")
            return
        }

        val now = System.currentTimeMillis()

        val active = activeScheduledReplies[senderKey(sender)]
        if (active != null && active.originalMessage.isNotBlank() && active.originalMessage.trim().equals(message.trim(), ignoreCase = true)) {
            Log.d(TAG, "Pipeline event")
            recordPipelineEvent("Skipped: duplicate of a message already waiting for its reply")
            return
        }

        if (!ruleEngine.isSenderAllowedForAutoReply(sender)) {
            Log.d(TAG, "Pipeline event")
            recordPipelineEvent("Skipped: sender is not allowed by your contact settings")
            return
        }

        val notificationData = JSONObject().apply {
            put("packageName", packageName)
            put("appName", appName)
            put("sender", sender)
            put("message", message)
            put("timestamp", sbn.postTime)
            put("isGroupChat", isGroupChat)
            put("key", sbn.key)
        }
        mainHandler.post {
            methodChannel?.invokeMethod("onNotificationPosted", notificationData.toString())
        }


        if (!ruleEngine.isMasterEnabled()) {
            Log.d(TAG, "Skipping: master switch is OFF")
            recordPipelineEvent("Skipped: master switch is off")
            return
        }


        if (!ruleEngine.isWithinScheduleWindow()) {
            Log.d(TAG, "Skipping: outside schedule window")
            recordPipelineEvent("Skipped: outside the schedule window")
            return
        }

        if (!ruleEngine.isAppEnabled(packageName)) {
            Log.d(TAG, "Skipping: $packageName is disabled in settings")
            recordPipelineEvent("Skipped: this app is disabled in settings")
            return
        }


        if (ruleEngine.isSelfSentMessage(message, sender)) {
            Log.d(TAG, "Skipping: self-sent message detected")
            recordPipelineEvent("Skipped: message looks self-sent")
            return
        }

        val incomingKey = senderKey(sender)
        val normalizedIncoming = message.trim().lowercase()
        val lastIncoming = lastHandledIncoming[incomingKey]
        if (lastIncoming != null &&
            lastIncoming.first == normalizedIncoming &&
            now - lastIncoming.second < incomingDedupeWindowMs
        ) {
            Log.d(TAG, "Pipeline event")
            recordPipelineEvent("Skipped: same message repeated within the dedupe window")
            return
        }
        lastHandledIncoming[incomingKey] = normalizedIncoming to now

        val rule = ruleEngine.findMatchingRule(message, sender = sender)

        if (rule == null) {
            val busyText = ruleEngine.getBusyReplyText()
            if (ruleEngine.isBusyModeActive() && busyText.isNotBlank()) {
                Log.d(TAG, "Busy mode active, using busy reply: '$busyText'")
                notifyPipelineStatus("got_message", sender)
                ConversationHistory.addMessage(sender, "user", message)
                if (ruleEngine.isConfirmBeforeReplyEnabled()) {
                    showConfirmationNotification(
                        notificationKey = sbn.key,
                        sender = sender,
                        replyText = busyText,
                        originalMessage = message,
                        isAiReply = false,
                        aiModelType = "busy_mode",
                        packageName = packageName,
                        shortcutId = getShortcutId(sbn),
                        sbnTag = sbn.tag,
                        sbnId = sbn.id,
                    )
                } else {
                    val replyToSend = busyText
                    scheduleDelayedReply(
                        key = sbn.key,
                        sender = sender,
                        replyText = replyToSend,
                        originalMessage = message,
                        packageName = packageName,
                        shortcutId = getShortcutId(sbn),
                        sbnTag = sbn.tag,
                        sbnId = sbn.id,
                        onBeforeSend = {
                            ConversationHistory.addMessage(sender, "assistant", replyToSend)
                        },
                    )
                }
                return
            }

            if (ruleEngine.isAiReplyEnabled()) {
                if (isNotificationArtifact(message)) {
                    Log.d(TAG, "Skipping notification artifact: '${message.take(50)}'")
                    recordPipelineEvent("Skipped: notification artifact")
                    return
                }
                val modelType = ruleEngine.getAiModelType()
                val batchWindowMs = 2000L
                Log.d(TAG, "No rule matched. Buffering for AI batch reply (model: $modelType, batchWindow: ${batchWindowMs}ms)...")

                val conversation = AnalysisAttempts.conversationKey(
                    packageName, getShortcutId(sbn), sbn.tag, sbn.id, sbn.key)
                val bufferedId = messageBatcher.getPendingAttemptId(conversation)
                val attemptId = if (bufferedId != null && analysisAttempts.isActive(bufferedId)) {
                    bufferedId
                } else {
                    notifyPipelineStatus("got_message", sender)
                    val attempt = analysisAttempts.begin(conversation, sender)
                    val timeout = Runnable {
                        if (analysisAttempts.expireAttempt(attempt.id)) {
                            Log.e(TAG, "AI attempt expired after ${AnalysisAttempts.LIMIT_MS}ms with no engine result")
                            notifyReplyError("AI attempt timed out before any reply was ready")
                        }
                        analysisAttempts.expireDue()
                        analysisTimers.remove(attempt.id)
                        publishAnalysis()
                    }
                    analysisTimers[attempt.id] = timeout
                    mainHandler.postDelayed(timeout, analysisAttempts.remaining(attempt.id))
                    attempt.id
                }
                publishAnalysis()

                messageBatcher.addMessage(
                    conversationKey = conversation,
                    analysisId = attemptId,
                    sender = sender,
                    message = message,
                    notificationKey = sbn.key,
                    packageName = packageName,
                    isGroupChat = isGroupChat,
                    delayMs = batchWindowMs,
                    shortcutId = getShortcutId(sbn),
                    sbnTag = sbn.tag,
                    sbnId = sbn.id,
                ) { batch ->
                    Log.d(TAG, "Batch ready for ${batch.sender}: ${batch.messages.size} messages")
                    sendBatchedAiReply(batch, modelType)
                }
            } else {
                Log.d(TAG, "No matching rule for message: '${message.take(50)}'")
                recordPipelineEvent("Skipped: no rule matched and AI replies are off")
            }
            return
        }

        val replyText = rule.randomReply()

        if (ruleEngine.shouldPreventDuplicates() &&
            ruleEngine.wasReplyRecentlySent(sender, replyText)
        ) return

        notifyPipelineStatus("got_message", sender)
        notifyPipelineStatus("analysing", sender)
        notifyPipelineStatus("reply_ready", sender)

        if (ruleEngine.isConfirmBeforeReplyEnabled()) {
            showConfirmationNotification(
                notificationKey = sbn.key,
                sender = sender,
                replyText = replyText,
                originalMessage = message,
                isAiReply = false,
                aiModelType = "",
                packageName = packageName,
                shortcutId = getShortcutId(sbn),
                sbnTag = sbn.tag,
                sbnId = sbn.id,
            )
            return
        }

        scheduleDelayedReply(
            key = sbn.key,
            sender = sender,
            replyText = replyText,
            originalMessage = message,
            packageName = packageName,
            shortcutId = getShortcutId(sbn),
            sbnTag = sbn.tag,
            sbnId = sbn.id,
        )
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        super.onNotificationRemoved(sbn)
        if (!supportedPackages.contains(sbn.packageName)) return
        mainHandler.post {
            methodChannel?.invokeMethod("onNotificationRemoved", sbn.key)
        }
    }

    private fun notifyReplyScheduled(sender: String, replyText: String, delayMs: Long) {
        val data = JSONObject().apply {
            put("sender", sender)
            put("replyText", replyText)
            put("delayMs", delayMs)
            put("scheduledAt", System.currentTimeMillis())
        }
        mainHandler.post {
            methodChannel?.invokeMethod("onReplyScheduled", data.toString())
        }
    }

    private fun notifyPipelineStatus(state: String, sender: String) {
        val data = JSONObject().apply {
            put("state", state)
            put("sender", sender)
        }
        mainHandler.post {
            methodChannel?.invokeMethod("onPipelineStatus", data.toString())
        }
    }

    fun sendReply(
        key: String,
        sender: String,
        replyText: String,
        isAiReply: Boolean = false,
        aiModelType: String = "",
        expectedPackageName: String? = null,
        expectedShortcutId: String? = null,
        expectedTag: String? = null,
        expectedId: Int? = null,
    ) {
        if(!ruleEngine.isMasterEnabled())return
        try {
            val sbn = confirmedDirectTarget(key, expectedPackageName, expectedShortcutId, expectedTag, expectedId)
            if (sbn == null) {
                notifyUnsafeChatSkipped()
                return
            }

            val extras = sbn.notification.extras
            val appName = getAppName(sbn.packageName)
            val originalMessage = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

            val liveText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty().ifEmpty { originalMessage }
            val queued = activeScheduledReplies.values.firstOrNull { it.notificationKey==key }
            if(queued!=null && queued.originalMessage.isNotEmpty() && queued.originalMessage!=liveText){
                mainHandler.post{methodChannel?.invokeMethod("onReplyFailed","Newer message replaced this draft")};return
            }
            val actions = sbn.notification.actions
            Log.d(TAG, "Notification ${sbn.key} has ${actions?.size ?: 0} actions")
            if (!actions.isNullOrEmpty()) {
                for ((i, action) in actions.withIndex()) {
                    val hasRemote = !action.remoteInputs.isNullOrEmpty()
                    Log.d(TAG, "  Action[$i]: '${action.title}', hasRemoteInput=$hasRemote")
                    if (!action.remoteInputs.isNullOrEmpty()) {
                        val remoteInput = action.remoteInputs[0]
                        val replyIntent = Intent()
                        RemoteInput.addResultsToIntent(
                            action.remoteInputs,
                            replyIntent,
                            Bundle().apply {
                                putCharSequence(remoteInput.resultKey, replyText)
                            }
                        )
                        try {
                            val latest = confirmedDirectTarget(key, expectedPackageName, expectedShortcutId, expectedTag, expectedId)
                            if (latest == null || latest.key != sbn.key || latest.postTime != sbn.postTime) {
                                notifyUnsafeChatSkipped()
                                return
                            }
                            action.actionIntent.send(applicationContext, 0, replyIntent)
                            ruleEngine.recordReplySent(sender, replyText)

                            val arrivedAt = notificationArrivalTimes.remove(key)
                            if (arrivedAt != null) {
                                Log.d(TAG, "Notification-to-reply: ${SystemClock.elapsedRealtime() - arrivedAt} ms for $sender")
                            }
                            Log.d(TAG, "Pipeline event")
                            mainHandler.post {
                                val replyData = JSONObject().apply {
                                    put("sender", sender)
                                    put("replyText", replyText)
                                    put("key", key)
                                    put("appName", appName)
                                    put("originalMessage", originalMessage)
                                    put("isAiReply", isAiReply)
                                    put("aiModelType", aiModelType)
                                }
                                methodChannel?.invokeMethod("onReplySuccess", replyData.toString())
                            }
                            return
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to send reply via PendingIntent", e)
                        }
                    }
                }
            }

            Log.w(TAG, "No direct reply action found for key: $key")
            mainHandler.post {
                methodChannel?.invokeMethod("onReplyFailed", "No direct reply action found")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error sending reply", e)
            mainHandler.post {
                methodChannel?.invokeMethod("onReplyFailed", e.message)
            }
        }
    }

    private fun sendBatchedAiReply(batch: MessageBatcher.BatchReadyCallback, modelType: String) {
        val attemptId = batch.analysisId
        if (!analysisAttempts.isActive(attemptId)) {
            notifyReplyError("Reply analysis expired before it could start")
            return
        }
        notifyPipelineStatus("analysing", batch.sender)
        if (batch.isGroupChat || confirmedDirectTarget(batch.latestNotificationKey, batch.packageName,
                batch.latestShortcutId, batch.latestTag, batch.latestId) == null) {
            notifyReplyError("Reply skipped: conversation could not be confirmed as a one-to-one chat")
            failAnalysis(attemptId)
            return
        }
        val sender = batch.sender
        val messages = batch.messages.map { it.message }
        val rawHistory = ConversationHistory.getHistory(sender)
        val baseSystemPrompt = ruleEngine.getAiSystemPromptWithTraining()
        val fullChatbotCtx = getChatbotContext()
        val chatbotCtx = if (fullChatbotCtx.length > maxChatbotContextChars) {
            fullChatbotCtx.takeLast(maxChatbotContextChars)
        } else {
            fullChatbotCtx
        }
        val finalSystemPrompt = if (chatbotCtx.isNotEmpty()) {
            "$baseSystemPrompt\n\n---\nCHAT CONTEXT (The user told the chatbot this — use it for awareness but do NOT mention the chatbot):\n$chatbotCtx\n---"
        } else {
            baseSystemPrompt
        }

        val history = ConversationTranscriptBuilder.build(
            history = rawHistory,
            batchMessages = emptyList(), // batch messages are passed separately to the AI service
            senderName = sender
        )

        Log.d(TAG, "Pipeline event")

        val batchOriginalMessage = if (messages.size > 1) {
            messages.joinToString(separator = " | ")
        } else {
            messages.lastOrNull() ?: ""
        }

        fun deliverReply(replyText: String, effectiveModelType: String, tokensUsed: Int) {
            mainHandler.post {
                if (!ruleEngine.isMasterEnabled()) { failAnalysis(attemptId); return@post }
                if (confirmedDirectTarget(batch.latestNotificationKey, batch.packageName,
                        batch.latestShortcutId, batch.latestTag, batch.latestId) == null) {
                    failAnalysis(attemptId)
                    return@post
                }
                if (!analysisAttempts.complete(attemptId, "ready")) { publishAnalysis(); return@post }
                analysisTimers.remove(attemptId)?.let { mainHandler.removeCallbacks(it) }
                publishAnalysis()
                for (msg in messages) {
                    ConversationHistory.addMessage(sender, "user", msg)
                }
                ConversationHistory.addMessage(sender, "assistant", replyText)

                notifyPipelineStatus("reply_ready", sender)


                if (ruleEngine.isConfirmBeforeReplyEnabled()) {
                    showConfirmationNotification(
                        notificationKey = batch.latestNotificationKey,
                        sender = sender,
                        replyText = replyText,
                        originalMessage = batchOriginalMessage,
                        isAiReply = true,
                        aiModelType = effectiveModelType,
                        packageName = batch.packageName,
                        shortcutId = batch.latestShortcutId,
                        sbnTag = batch.latestTag,
                        sbnId = batch.latestId,
                    )
                } else {
                    scheduleDelayedReply(
                        key = batch.latestNotificationKey,
                        sender = sender,
                        replyText = replyText,
                        isAiReply = true,
                        aiModelType = effectiveModelType,
                        originalMessage = batchOriginalMessage,
                        packageName = batch.packageName,
                        shortcutId = batch.latestShortcutId,
                        sbnTag = batch.latestTag,
                        sbnId = batch.latestId,
                    )
                }
            }
        }

        fun tryLocalFallback(cloudError: String?) {
            if (!analysisAttempts.isActive(attemptId)) return
            if (confirmedDirectTarget(batch.latestNotificationKey, batch.packageName,
                    batch.latestShortcutId, batch.latestTag, batch.latestId) == null) {
                notifyReplyError("Reply skipped: conversation could not be confirmed as a one-to-one chat")
                failAnalysis(attemptId)
                return
            }
            if (!ruleEngine.isFallbackToLocalEnabled()) {
                Log.w(TAG, "Local fallback is disabled in settings. Skipping reply for $sender")
                notifyReplyError("AI reply failed ($modelType): ${cloudError ?: "error"}. On-phone fallback is off.")
                failAnalysis(attemptId)
                return
            }

            val localModelId = ruleEngine.getSelectedLocalModel()
            val phiService = PhiLocalService.getInstance(applicationContext)

            if (!phiService.isModelAvailable(localModelId)) {
                val errMsg = "Cloud AI ($modelType) failed: ${cloudError ?: "error"}. Local model '$localModelId' is not downloaded."
                Log.e(TAG, errMsg)
                ruleEngine.saveAiUsage(modelType, 0, 0, 0, 0, errMsg)
                notifyAiUsage(0, 0, 0, 0, errMsg)
                notifyReplyError(errMsg)
                failAnalysis(attemptId)
                return
            }

            Log.i(TAG, "Cloud AI ($modelType) failed ($cloudError). Falling back to local model: $localModelId for sender: $sender")
            phiService.getAiReplyBatch(
                modelId = localModelId,
                senderName = sender,
                incomingMessages = messages,
                systemPrompt = finalSystemPrompt,
                conversationHistory = history,
                shouldContinue = { analysisAttempts.isActive(attemptId) },
                remainingBudgetMs = { analysisAttempts.remaining(attemptId) },
            ) { localReply, localUsage ->
                if (!analysisAttempts.isActive(attemptId)) return@getAiReplyBatch
                if (!localReply.isNullOrBlank()) {
                    Log.i(TAG, "Local model fallback succeeded for $sender! Generated reply: '$localReply'")
                    deliverReply(localReply, "phi_local", localUsage?.tokensUsed ?: 0)
                } else {
                    failAnalysis(attemptId)
                    val localErr = "Local fallback also failed: ${localUsage?.error ?: "Empty response"}"
                    Log.e(TAG, localErr)
                    ruleEngine.saveAiUsage("phi_local", 0, 0, 0, 0, localErr)
                    notifyAiUsage(0, 0, 0, 0, localErr)
                    notifyReplyError("AI reply failed ($modelType): ${cloudError ?: "error"}. $localErr")
                }
            }
        }

        val cloudCallbackAdapter: (String?, PhiLocalService.AiUsage?) -> Unit = cloudCallback@{ aiReply, usage ->
            if (!analysisAttempts.isActive(attemptId)) return@cloudCallback
            val tokensUsed = usage?.tokensUsed ?: 0
            val error = usage?.error
            val isLimitReached = usage?.isLimitReached ?: false

            ruleEngine.saveAiUsage(
                provider = modelType,
                tokensUsed = tokensUsed,
                tokensRemaining = usage?.tokensRemaining ?: 0,
                tokensLimit = usage?.tokensLimit ?: 0,
                resetInSeconds = usage?.resetInSeconds ?: 0,
                error = error,
                requestsRemaining = usage?.requestsRemaining,
                requestsLimit = usage?.requestsLimit,
                isLimitReached = isLimitReached,
            )
            notifyAiUsage(
                tokensUsed = tokensUsed,
                tokensRemaining = usage?.tokensRemaining ?: 0,
                tokensLimit = usage?.tokensLimit ?: 0,
                resetInSeconds = usage?.resetInSeconds ?: 0,
                error = error,
                requestsRemaining = usage?.requestsRemaining,
                requestsLimit = usage?.requestsLimit,
                isLimitReached = isLimitReached,
            )

            if (!aiReply.isNullOrBlank()) {
                deliverReply(aiReply, modelType, tokensUsed)
            } else {
                Log.w(TAG, "Cloud AI ($modelType) returned empty/error: $error. Attempting local model fallback...")
                tryLocalFallback(error)
            }
        }

        val localCallbackAdapter: (String?, PhiLocalService.AiUsage?) -> Unit = localCallback@{ aiReply, usage ->
            if (!analysisAttempts.isActive(attemptId)) return@localCallback
            val tokensUsed = usage?.tokensUsed ?: 0
            val error = usage?.error

            if (tokensUsed > 0 || error != null) {
                ruleEngine.saveAiUsage(
                    modelType,
                    tokensUsed,
                    0,
                    0,
                    0,
                    error,
                )
                notifyAiUsage(tokensUsed, 0, 0, 0, error)
            }

            if (!aiReply.isNullOrBlank()) {
                deliverReply(aiReply, "phi_local", tokensUsed)
            } else {
                notifyReplyError("Local reply failed: ${error ?: "empty response"}")
                failAnalysis(attemptId)
            }
        }

        if (modelType != "phi_local" && ruleEngine.isAiLimitReached(modelType)) {
            Log.w(TAG, "Daily limit reached for $modelType. Falling back to local model immediately.")
            tryLocalFallback("Daily limit reached for $modelType")
            return
        }

        try {
        when (modelType) {
            "groq_api" -> {
                val apiKey = ruleEngine.getGroqApiKey()
                if (apiKey.isBlank()) {
                    Log.w(TAG, "Groq API key is blank. Falling back to local model immediately.")
                    tryLocalFallback("Groq API key is missing")
                } else {
                    val model = ruleEngine.getGroqModel()
                    CloudAiService.getInstance(applicationContext).generateReply(
                        engineType = "groq_api",
                        apiKey = apiKey,
                        model = model,
                        senderName = sender,
                        incomingMessages = messages,
                        systemPrompt = finalSystemPrompt,
                        conversationHistory = history,
                        callback = cloudCallbackAdapter
                    )
                }
            }
            "cloudflare_api" -> {
                val apiKey = ruleEngine.getCloudflareApiKey()
                if (apiKey.isBlank()) {
                    Log.w(TAG, "Cloudflare API key is blank. Falling back to local model immediately.")
                    tryLocalFallback("Cloudflare API key is missing")
                } else {
                    val model = ruleEngine.getCloudflareModel()
                    CloudAiService.getInstance(applicationContext).generateReply(
                        engineType = "cloudflare_api",
                        apiKey = apiKey,
                        model = model,
                        accountId = ruleEngine.getCloudflareAccountId(),
                        senderName = sender,
                        incomingMessages = messages,
                        systemPrompt = finalSystemPrompt,
                        conversationHistory = history,
                        callback = cloudCallbackAdapter
                    )
                }
            }
            "gemini_api" -> {
                val apiKey = ruleEngine.getGeminiApiKey()
                if (apiKey.isBlank()) {
                    Log.w(TAG, "Gemini API key is blank. Falling back to local model immediately.")
                    tryLocalFallback("Gemini API key is missing")
                } else {
                    val model = ruleEngine.getGeminiModel()
                    CloudAiService.getInstance(applicationContext).generateReply(
                        engineType = "gemini_api",
                        apiKey = apiKey,
                        model = model,
                        senderName = sender,
                        incomingMessages = messages,
                        systemPrompt = finalSystemPrompt,
                        conversationHistory = history,
                        callback = cloudCallbackAdapter
                    )
                }
            }
            else -> {
                val selectedModel = ruleEngine.getSelectedLocalModel()
                PhiLocalService.getInstance(applicationContext).getAiReplyBatch(
                    modelId = selectedModel,
                    senderName = sender,
                    incomingMessages = messages,
                    systemPrompt = finalSystemPrompt,
                    conversationHistory = history,
                    shouldContinue = { analysisAttempts.isActive(attemptId) },
                    remainingBudgetMs = { analysisAttempts.remaining(attemptId) },
                    callback = localCallbackAdapter
                )
            }
        }
        } catch (e: Throwable) {
            notifyReplyError("Reply pipeline error: ${e.message ?: e.javaClass.simpleName}")
            failAnalysis(attemptId)
        }
    }

    private fun notifyAiUsage(
        tokensUsed: Int,
        tokensRemaining: Int,
        tokensLimit: Int,
        resetInSeconds: Int,
        error: String?,
        requestsRemaining: Int? = null,
        requestsLimit: Int? = null,
        isLimitReached: Boolean = false,
    ) {
        val usageData = org.json.JSONObject().apply {
            put("tokensUsed", tokensUsed)
            put("tokensRemaining", tokensRemaining)
            put("tokensLimit", tokensLimit)
            put("resetInSeconds", resetInSeconds)
            put("error", error ?: "")
            if (requestsRemaining != null) put("requestsRemaining", requestsRemaining)
            if (requestsLimit != null) put("requestsLimit", requestsLimit)
            put("isLimitReached", isLimitReached)

            val statsObj = org.json.JSONObject()
            val providerStats = ruleEngine.getAiProviderStats()
            for ((prov, statMap) in providerStats) {
                statsObj.put(prov, org.json.JSONObject(statMap))
            }
            put("providerStats", statsObj)
        }
        mainHandler.post {
            methodChannel?.invokeMethod("onAiUsageUpdate", usageData.toString())
        }
    }

    private fun getAppName(packageName: String) = when (packageName) {
        "com.whatsapp" -> "WhatsApp"
        "com.instagram.android" -> "Instagram"
        else -> packageName
    }

    private fun hasReplyAction(sbn: StatusBarNotification): Boolean {
        val actions = sbn.notification?.actions ?: return false
        return actions.any { it.remoteInputs?.isNotEmpty() == true }
    }

    private fun resolveConversationIdentity(
        notificationKey: String,
        packageName: String?,
        shortcutId: String?,
        tag: String?,
        id: Int?,
    ): Quadruple<String?, String?, String?, Int?> {
        if (packageName != null) {
            return Quadruple(packageName, shortcutId, tag, id)
        }
        return try {
            val current = activeNotifications?.find { it.key == notificationKey }
            if (current != null) {
                Quadruple(current.packageName, getShortcutId(current), current.tag, current.id)
            } else {
                Quadruple(null, shortcutId, tag, id)
            }
        } catch (_: Exception) {
            Quadruple(packageName, shortcutId, tag, id)
        }
    }

    private fun getShortcutId(sbn: StatusBarNotification): String? {
        return try {
            sbn.notification?.shortcutId
                ?: sbn.notification?.extras?.getString("android.shortcutId")
        } catch (_: Exception) {
            null
        }
    }

    private fun sameConversation(a: StatusBarNotification, shortcutId: String?, tag: String?, id: Int?): Boolean {
        if (!shortcutId.isNullOrEmpty()) {
            val candidateShortcut = getShortcutId(a)
            if (candidateShortcut != null && candidateShortcut == shortcutId) return true
        }
        if (tag != null && id != null && tag == a.tag && id == a.id) return true
        return false
    }

    private fun findSameConversationNotification(
        originalKey: String,
        expectedPackageName: String?,
        expectedShortcutId: String?,
        expectedTag: String?,
        expectedId: Int?,
    ): StatusBarNotification? {
        val active = activeNotifications ?: return null

        active.firstOrNull { it.key == originalKey && hasReplyAction(it) }?.let { exact ->
            if (expectedPackageName == null || exact.packageName == expectedPackageName) {
                return exact
            }
            Log.w(TAG, "Exact key match ${exact.key} is from ${exact.packageName}, expected $expectedPackageName — ignoring")
        }

        if (expectedPackageName == null) {
            Log.w(TAG, "Cannot confirm original conversation for key=$originalKey without package — skipping fallback")
            return null
        }

        val samePackage = active.filter { sbn ->
            if (sbn.packageName != expectedPackageName) return@filter false
            if (sbn.packageName !in supportedPackages) return@filter false
            if (!hasReplyAction(sbn)) return@filter false
            true
        }
        if (samePackage.isEmpty()) {
            Log.w(TAG, "No active replyable notification from $expectedPackageName — skipping send for key=$originalKey")
            return null
        }

        val hasStableIdentity = !expectedShortcutId.isNullOrEmpty() || expectedTag != null
        if (!hasStableIdentity) {
            Log.w(TAG, "No stable conversation identity for key=$originalKey — refusing to guess by sender name")
            return null
        }

        val match = samePackage.lastOrNull { sbn ->
            sameConversation(sbn, expectedShortcutId, expectedTag, expectedId)
        }
        if (match == null) {
            Log.w(TAG, "Original conversation (key=$originalKey, shortcut=$expectedShortcutId, tag=$expectedTag id=$expectedId) no longer active in $expectedPackageName — skipping send")
        }
        return match
    }

    private data class Quadruple<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)

    private fun classifyChat(notification: Notification, pkg: String): ChatTypePolicy.Kind {
        return try {
            val extras = notification.extras
            val rawGroup = if (extras.containsKey(Notification.EXTRA_IS_GROUP_CONVERSATION)) {
                extras.get(Notification.EXTRA_IS_GROUP_CONVERSATION)
            } else null
            if (rawGroup != null && rawGroup !is Boolean) return ChatTypePolicy.Kind.UNKNOWN
            val explicitGroup = rawGroup as? Boolean
            val style = Notification.Builder.recoverBuilder(this, notification).style as? Notification.MessagingStyle
            val styleGroup = if (android.os.Build.VERSION.SDK_INT >= 28) style?.isGroupConversation else explicitGroup
            val senders = if (android.os.Build.VERSION.SDK_INT >= 28) {
                style?.messages.orEmpty().mapNotNull { message ->
                    message.senderPerson?.let { person ->
                        person.key?.takeIf { it.isNotBlank() } ?: person.uri?.takeIf { it.isNotBlank() }
                    }
                }.distinct().size
            } else 0
            ChatTypePolicy.classify(ChatTypePolicy.Evidence(
                supportedPackage = pkg in supportedPackages,
                summary = notification.flags and Notification.FLAG_GROUP_SUMMARY != 0,
                explicitGroup = explicitGroup,
                messagingStyle = style != null,
                styleGroup = styleGroup,
                hasConversationTitle = !extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE).isNullOrBlank(),
                distinctSenders = senders,
            ))
        } catch (_: Exception) { ChatTypePolicy.Kind.UNKNOWN }
    }

    private fun isGroupSummary(sbn: StatusBarNotification): Boolean = try {
        val n = sbn.notification
        n != null && (n.flags and Notification.FLAG_GROUP_SUMMARY) != 0
    } catch (_: Exception) { false }

    private fun chatTarget(sbn: StatusBarNotification) = DirectChatGate.Target(
        sbn.packageName, sbn.key, getShortcutId(sbn), sbn.tag, sbn.id, sbn.userId)

    private fun cancelUnsafeConversation(target: DirectChatGate.Target) {
        val conversation = AnalysisAttempts.conversationKey(target.packageName, target.shortcut,
            target.tag, target.id, target.key)
        messageBatcher.cancelConversation(conversation)
        analysisAttempts.snapshot().filter { it.conversation == conversation && it.state == "analysing" }
            .forEach { attempt ->
                analysisAttempts.complete(attempt.id, "canceled")
                analysisTimers.remove(attempt.id)?.let { mainHandler.removeCallbacks(it) }
            }
        activeScheduledReplies.entries.filter { (_, value) ->
            value.notificationKey == target.key || (value.packageName == target.packageName &&
                ((target.shortcut != null && value.shortcutId == target.shortcut) ||
                 (target.shortcut == null && target.tag != null && value.sbnTag == target.tag && value.sbnId == target.id)))
        }.forEach { (sender, _) -> cancelScheduledReply(sender) }
        pendingReplies.entries.filter { (_, value) ->
            value.notificationKey == target.key || (value.packageName == target.packageName &&
                ((target.shortcut != null && value.shortcutId == target.shortcut) ||
                 (target.shortcut == null && target.tag != null && value.sbnTag == target.tag && value.sbnId == target.id)))
        }.forEach { (id, _) ->
            pendingReplies.remove(id)
            getSystemService(NotificationManager::class.java).cancel(CONFIRM_NOTIFICATION_ID_BASE + id.hashCode())
        }
        publishAnalysis()
    }

    private fun confirmedDirectTarget(key: String, pkg: String?, shortcut: String?, tag: String?, id: Int?): StatusBarNotification? {
        return try {
            val origin = directChatGate.original(key) ?: return null
            if (pkg != null && origin.packageName != pkg) return null
            if (shortcut != null && origin.shortcut != shortcut) return null
            if (tag != null && origin.tag != tag) return null
            if (id != null && origin.id != id) return null
            val active = activeNotifications ?: return null
            val sameIdentity = active.filter { !isGroupSummary(it) && origin.sameConversation(chatTarget(it)) }
            if (sameIdentity.any { classifyChat(it.notification, it.packageName) != ChatTypePolicy.Kind.DIRECT }) return null
            val candidates = sameIdentity.filter { candidate ->
                directChatGate.permits(key, chatTarget(candidate), classifyChat(candidate.notification, candidate.packageName)) &&
                    hasReplyAction(candidate)
            }
            candidates.firstOrNull { it.key == key } ?: candidates.singleOrNull()
        } catch (_: Exception) { null }
    }

    private var replyErrorNotifiedAt = 0L

    private fun notifyReplyError(reason: String) {
        Log.e(TAG, "Reply pipeline error: $reason")
        if (methodChannel == null) recordPipelineEvent(reason)
        mainHandler.post {
            methodChannel?.invokeMethod("onReplyFailed", reason)
        }
        val nowMs = System.currentTimeMillis()
        if (nowMs - replyErrorNotifiedAt < 30_000L) return
        replyErrorNotifiedAt = nowMs
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channel = android.app.NotificationChannel(
                    REPLY_ERROR_CHANNEL_ID,
                    "Reply errors",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply { description = "Shows why an auto-reply failed" }
                getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
            }
            val n = Notification.Builder(this, REPLY_ERROR_CHANNEL_ID)
                .setContentTitle("Auto-reply failed")
                .setContentText(reason)
                .setStyle(Notification.BigTextStyle().bigText(reason))
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setAutoCancel(true)
                .build()
            getSystemService(NotificationManager::class.java).notify(REPLY_ERROR_NOTIFICATION_ID, n)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post reply error notification", e)
        }
    }

    private fun notifyUnsafeChatSkipped() {
        mainHandler.post {
            methodChannel?.invokeMethod("onReplyFailed", "Skipped: one-to-one chat and original conversation could not be confirmed")
        }
    }

    private fun normalizeSenderName(title: String, packageName: String): String {
        return when (packageName) {
            "com.whatsapp" -> {
                title.removePrefix("WhatsApp: ").trim()
            }
            else -> title.trim()
        }
    }

    private fun isNotificationArtifact(message: String): Boolean {
        return ConversationTranscriptBuilder.isArtifact(message)
    }

    private fun senderKey(sender: String): String = sender.trim().lowercase()

    private fun isOutgoingMessagingStyleMessage(notification: Notification, sender: String): Boolean {
        return try {
            val extras = notification.extras ?: return false
            val raw = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return false
            if (raw.isEmpty()) return false
            val last = raw.lastOrNull() as? Bundle ?: return false
            val text = last.getCharSequence("text")?.toString()?.trim() ?: ""
            if (text.isEmpty()) return false

            val senderObj: Any? = try { last.get("sender") } catch (_: Exception) { null }
            if (senderObj == null) return true
            val senderName: String = when (senderObj) {
                is CharSequence -> senderObj.toString().trim()
                else -> try {
                    val m = senderObj.javaClass.getMethod("getName")
                    (m.invoke(senderObj) as? CharSequence)?.toString()?.trim() ?: ""
                } catch (_: Exception) {
                    senderObj.toString().trim()
                }
            }
            if (senderName.isEmpty()) return true
            val lower = senderName.lowercase()
            if (lower == "you" || lower == "me") return true
            val selfDisplay = extras.getCharSequence(Notification.EXTRA_SELF_DISPLAY_NAME)
                ?.toString()?.trim()?.lowercase().orEmpty()
            if (selfDisplay.isNotEmpty() && lower == selfDisplay) return true
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun createConfirmNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                CONFIRM_NOTIFICATION_CHANNEL_ID,
                "Reply Confirmations",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Shows confirmation before sending auto-replies"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun registerConfirmReceiver() {
        confirmReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val confirmId = intent.getStringExtra(EXTRA_CONFIRM_ID) ?: return
                val action = intent.action ?: return

                val pending = pendingReplies.remove(confirmId) ?: return
                val nm = getSystemService(NotificationManager::class.java)
                nm.cancel(CONFIRM_NOTIFICATION_ID_BASE + confirmId.hashCode())

                when (action) {
                    ACTION_APPROVE -> {
                        Log.d(TAG, "Pipeline event")
                        scheduleDelayedReply(
                            key = pending.notificationKey,
                            sender = pending.sender,
                            replyText = pending.replyText,
                            isAiReply = pending.isAiReply,
                            aiModelType = pending.aiModelType,
                            originalMessage = pending.originalMessage,
                            packageName = pending.packageName,
                            shortcutId = pending.shortcutId,
                            sbnTag = pending.sbnTag,
                            sbnId = pending.sbnId,
                        )
                    }
                    ACTION_DENY -> {
                        Log.d(TAG, "User DENIED reply to '${pending.sender}'")
                        mainHandler.post {
                            methodChannel?.invokeMethod("onReplyDenied", pending.sender)
                        }
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(ACTION_APPROVE)
            addAction(ACTION_DENY)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(confirmReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(confirmReceiver, filter, "$packageName.CONFIRM_REPLY", null)
        }
        Log.d(TAG, "Confirm receiver registered")
    }

    private fun unregisterConfirmReceiver() {
        confirmReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        confirmReceiver = null
    }

    private fun showConfirmationNotification(
        notificationKey: String,
        sender: String,
        replyText: String,
        originalMessage: String,
        isAiReply: Boolean,
        aiModelType: String,
        packageName: String,
        shortcutId: String? = null,
        sbnTag: String? = null,
        sbnId: Int? = null,
    ) {
        if (confirmedDirectTarget(notificationKey, packageName, shortcutId, sbnTag, sbnId) == null) {
            notifyUnsafeChatSkipped()
            return
        }
        val confirmId = UUID.randomUUID().toString()
        val notifId = CONFIRM_NOTIFICATION_ID_BASE + confirmId.hashCode()

        pendingReplies[confirmId] = PendingReply(
            confirmId = confirmId,
            notificationKey = notificationKey,
            packageName = packageName,
            shortcutId = shortcutId,
            sbnTag = sbnTag,
            sbnId = sbnId,
            sender = sender,
            replyText = replyText,
            originalMessage = originalMessage,
            isAiReply = isAiReply,
            aiModelType = aiModelType,
        )

        val approveIntent = Intent(ACTION_APPROVE).setPackage(this.packageName).apply {
            putExtra(EXTRA_CONFIRM_ID, confirmId)
            putExtra(EXTRA_NOTIFICATION_KEY, notificationKey)
            putExtra(EXTRA_SENDER, sender)
            putExtra(EXTRA_REPLY_TEXT, replyText)
        }
        val approvePending = PendingIntent.getBroadcast(
            this, notifId, approveIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val denyIntent = Intent(ACTION_DENY).setPackage(this.packageName).apply {
            putExtra(EXTRA_CONFIRM_ID, confirmId)
            putExtra(EXTRA_SENDER, sender)
        }
        val denyPending = PendingIntent.getBroadcast(
            this, notifId + 1, denyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val displayReply = replyText
        val displayOriginal = if (originalMessage.length > 40) originalMessage.take(40) + "..." else originalMessage
        val aiTag = if (isAiReply) " [AI]" else ""

        val collapsedText = "Reply: $displayReply  |  From: $displayOriginal"
        val expandedText = "Reply:\n\"$displayReply\"\n\nFrom $sender:\n\"$displayOriginal\""

        val notification = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            Notification.Builder(this, CONFIRM_NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Reply to $sender?$aiTag")
            .setContentText(collapsedText)
            .setStyle(
                Notification.BigTextStyle()
                    .bigText(expandedText)
                    .setBigContentTitle("Reply to $sender?$aiTag")
                    .setSummaryText("Tap Send or Cancel")
            )
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(
                Notification.Action.Builder(
                    null, "Send", approvePending
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    null, "Cancel", denyPending
                ).build()
            )
            .setPriority(Notification.PRIORITY_HIGH)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .build()

        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(notifId, notification)

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            if (!nm.areNotificationsEnabled()) {
                Log.w(TAG, "POST_NOTIFICATIONS permission not granted — notification may not be visible")
            }
        }

        mainHandler.postDelayed({
            if(pendingReplies.remove(confirmId)!=null) {nm.cancel(notifId);mainHandler.post{methodChannel?.invokeMethod("onReplyDenied", sender)}}
        }, 5*60_000L)

        Log.d(TAG, "Pipeline event")
    }
}
