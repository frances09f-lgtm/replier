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
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Notification listener that auto-replies entirely on the native side.
 *
 * Rule matching and settings are read from SharedPreferences via RuleEngine,
 * so this works whether or not the Flutter engine / UI is running.
 *
 * The MethodChannel is used only to notify the Flutter UI about events
 * (e.g. updating the logs screen). It is always optional — if Flutter
 * isn't running, replies still go out.
 */
class AppNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "AppNotificationListener"
        private const val CONFIRM_NOTIFICATION_CHANNEL_ID = "confirm_reply_channel"
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

        // Optional Flutter channel — used only for UI updates, not for core logic
        private var methodChannel: MethodChannel? = null
        private var instance: AppNotificationListenerService? = null

        // Chatbot context from the Flutter chatbot — injected into AI auto-reply system prompt
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
    }

    /** Data class for a reply pending user confirmation */
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

    /** Data class for a reply pending delayed execution */
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

    /** In-memory store of pending confirmations, keyed by confirmId */
    private val pendingReplies = ConcurrentHashMap<String, PendingReply>()
    private var confirmReceiver: BroadcastReceiver? = null

    /** Map of active scheduled replies per sender to prevent overlapping/duplicate timers */
    private val activeScheduledReplies = ConcurrentHashMap<String, ScheduledReply>()

    /** Last genuine incoming message handled per sender: normalized text -> timestamp.
     * Used to ignore notification re-posts of a message we already processed,
     * without blocking NEW messages from the same sender (a blanket cooldown
     * would wrongly swallow fast follow-ups like "😄 Haa haa" 2s after our reply). */
    private val lastHandledIncoming = ConcurrentHashMap<String, Pair<String, Long>>()
    private val incomingDedupeWindowMs = 60_000L

    private val supportedPackages = listOf(
        "com.whatsapp",
        "com.instagram.android"
    )

    private lateinit var ruleEngine: RuleEngine
    private lateinit var messageBatcher: MessageBatcher
    private val mainHandler = Handler(Looper.getMainLooper())

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
        // Cancel any pending timer for this sender so multiple timers don't collide
        cancelScheduledReply(sender)

        // Capture stable conversation identity now, while the original notification
        // is most likely still posted. This is used later to verify we reply to
        // the same conversation — never to a different chat with a similar name.
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

        // Keep CPU awake during delay (crucial for delays > 60s and when screen turns off)
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
        unregisterConfirmReceiver()
        instance = null
        Log.d(TAG, "AppNotificationListenerService destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)

        val packageName = sbn.packageName
        if (!supportedPackages.contains(packageName)) return

        pendingReplies.entries.filter { it.value.notificationKey==sbn.key }.forEach { (id, _)-> pendingReplies.remove(id);getSystemService(NotificationManager::class.java).cancel(CONFIRM_NOTIFICATION_ID_BASE+id.hashCode()) }
        activeScheduledReplies.entries.filter{it.value.notificationKey==sbn.key}.forEach{(sender,_)->cancelScheduledReply(sender)}
        val notification = sbn.notification ?: return
        val extras = notification.extras

        val appName = getAppName(packageName)
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val message = if (bigText.isNotEmpty()) bigText else text
        val isGroupChat = isGroupChat(notification)

        val sender = normalizeSenderName(title, packageName)
        Log.d(TAG, "Pipeline event")

        // Outgoing message via MessagingStyle (e.g. our RemoteInput reply echoed
        // back with a null/“You” sender in EXTRA_MESSAGES) — never reply to it.
        if (isOutgoingMessagingStyleMessage(notification, sender)) {
            Log.d(TAG, "Pipeline event")
            return
        }

        // NOTE: deliberately NO blanket per-sender cooldown here — it would also
        // swallow the contact's genuine fast follow-ups (e.g. "😄 Haa haa" 2s
        // after our reply). Our own echoes are caught precisely by
        // isOutgoingMessagingStyleMessage above and ruleEngine.isSelfSentMessage
        // below; re-posts of an already-handled message are caught by the
        // incoming-dedupe check next to the self-guard.
        val now = System.currentTimeMillis()

        // Avoid re-processing if an identical message from this sender is currently in delayed countdown
        val active = activeScheduledReplies[senderKey(sender)]
        if (active != null && active.originalMessage.isNotBlank() && active.originalMessage.trim().equals(message.trim(), ignoreCase = true)) {
            Log.d(TAG, "Pipeline event")
            return
        }

        if (!ruleEngine.isSenderAllowedForAutoReply(sender)) {
            Log.d(TAG, "Pipeline event")
            return
        }

        // Notify Flutter UI (optional, best-effort)
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

        // ── Core auto-reply logic (fully native, no Flutter needed) ──────────

        // Master switch
        if (!ruleEngine.isMasterEnabled()) {
            Log.d(TAG, "Skipping: master switch is OFF")
            return
        }

        // Schedule window check
        if (!ruleEngine.isWithinScheduleWindow()) {
            Log.d(TAG, "Skipping: outside schedule window")
            return
        }

        // Per-app toggle
        if (!ruleEngine.isAppEnabled(packageName)) {
            Log.d(TAG, "Skipping: $packageName is disabled in settings")
            return
        }

        // Group chat filter
        if (ruleEngine.shouldIgnoreGroupChats() && isGroupChat) {
            Log.d(TAG, "Skipping: group chat ignored")
            return
        }

        // Self-reply guard
        if (ruleEngine.isSelfSentMessage(message, sender)) {
            Log.d(TAG, "Skipping: self-sent message detected")
            return
        }

        // Incoming-dedupe: WhatsApp re-posts the same notification (same text)
        // when our reply lands or the shade refreshes. Ignore such re-posts so
        // we don't reply twice — but let DIFFERENT text from the same sender
        // through immediately (no blanket cooldown).
        val incomingKey = senderKey(sender)
        val normalizedIncoming = message.trim().lowercase()
        val lastIncoming = lastHandledIncoming[incomingKey]
        if (lastIncoming != null &&
            lastIncoming.first == normalizedIncoming &&
            now - lastIncoming.second < incomingDedupeWindowMs
        ) {
            Log.d(TAG, "Pipeline event")
            return
        }
        lastHandledIncoming[incomingKey] = normalizedIncoming to now

        // Emit "got_message" to Flutter UI
        notifyPipelineStatus("got_message", sender)

        // Rule matching
        val rule = ruleEngine.findMatchingRule(message, sender = sender)

        if (rule == null) {
            // Busy mode check — if user set a busy status from chatbot, use it
            val busyText = ruleEngine.getBusyReplyText()
            if (ruleEngine.isBusyModeActive() && busyText.isNotBlank()) {
                Log.d(TAG, "Busy mode active, using busy reply: '$busyText'")
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

            // AI fallback if enabled — buffer messages and batch replies
            if (ruleEngine.isAiReplyEnabled()) {
                // Skip notification artifacts (typing indicators, "X new messages", etc.)
                if (isNotificationArtifact(message)) {
                    Log.d(TAG, "Skipping notification artifact: '${message.take(50)}'")
                    return
                }
                val modelType = ruleEngine.getAiModelType()
                // Batch window: wait 2s for more messages before firing
                val batchWindowMs = 2000L
                Log.d(TAG, "No rule matched. Buffering for AI batch reply (model: $modelType, batchWindow: ${batchWindowMs}ms)...")

                // Emit "analysing" immediately so the UI shows the processing state
                notifyPipelineStatus("analysing", sender)

                messageBatcher.addMessage(
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
            }
            return
        }

        val replyText = rule.randomReply()

        // Duplicate prevention
        if (ruleEngine.shouldPreventDuplicates() &&
            ruleEngine.wasReplyRecentlySent(sender, replyText)
        ) return

        // Emit "analysing" then "reply_ready" now that a rule match was found
        notifyPipelineStatus("analysing", sender)
        notifyPipelineStatus("reply_ready", sender)

        // Confirm before reply: show approval notification instead of sending directly.
        // The countdown is NOT started here — it only starts once the send is actually
        // scheduled (approval or timeout), so the visible timer always matches the real delay.
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

        // Delay + send
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

    /**
     * Send a reply using the notification's direct reply RemoteInput action.
     * Called from onNotificationPosted (native) and from Flutter via MethodChannel.
     */
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
            var sbn = activeNotifications?.find { it.key == key }

            // Guard: an exact key match implicitly belongs to the right package,
            // but if the caller supplied the original package, enforce it so a
            // recycled key can never leak a reply into another app.
            if (sbn != null && expectedPackageName != null && sbn.packageName != expectedPackageName) {
                Log.w(TAG, "Refusing to reply: notification $key is from ${sbn.packageName} but expected $expectedPackageName")
                sbn = null
            }

            // If the original notification is gone or has no reply action, only
            // fall back to the SAME conversation (same package + stable identity).
            // Never fall back by display-name matching — that can hit the wrong chat.
            if (sbn == null || !hasReplyAction(sbn)) {
                Log.d(TAG, "Pipeline event")
                sbn = findSameConversationNotification(key, expectedPackageName, expectedShortcutId, expectedTag, expectedId)
            }

            if (sbn == null) {
                Log.d(TAG, "Pipeline event")
                mainHandler.post {
                    methodChannel?.invokeMethod("onReplyFailed", "Original notification no longer active — skipped to avoid wrong recipient")
                }
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
                            action.actionIntent.send(applicationContext, 0, replyIntent)
                            ruleEngine.recordReplySent(sender, replyText)
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

    /**
     * Send a batched AI reply: collect all buffered messages from the batcher callback,
     * call the appropriate AI service with all messages, then send a single reply.
     */
    private fun sendBatchedAiReply(batch: MessageBatcher.BatchReadyCallback, modelType: String) {
        val sender = batch.sender
        val messages = batch.messages.map { it.message }
        val rawHistory = ConversationHistory.getHistory(sender)
        val baseSystemPrompt = ruleEngine.getAiSystemPromptWithTraining()
        val chatbotCtx = getChatbotContext()
        val finalSystemPrompt = if (chatbotCtx.isNotEmpty()) {
            "$baseSystemPrompt\n\n---\nCHAT CONTEXT (The user told the chatbot this — use it for awareness but do NOT mention the chatbot):\n$chatbotCtx\n---"
        } else {
            baseSystemPrompt
        }

        // Build a clean transcript: filter artifacts, dedup, merge, cap tokens
        val history = ConversationTranscriptBuilder.build(
            history = rawHistory,
            batchMessages = emptyList(), // batch messages are passed separately to the AI service
            senderName = sender
        )

        Log.d(TAG, "Pipeline event")

        // Full incoming text for logs/rating: join batch so multi-message
        // bursts don't lose context (e.g. "hi | kay challay?").
        val batchOriginalMessage = if (messages.size > 1) {
            messages.joinToString(separator = " | ")
        } else {
            messages.lastOrNull() ?: ""
        }

        fun deliverReply(replyText: String, effectiveModelType: String, tokensUsed: Int) {
            for (msg in messages) {
                ConversationHistory.addMessage(sender, "user", msg)
            }
            ConversationHistory.addMessage(sender, "assistant", replyText)

            // Emit "reply_ready" before scheduling the send
            notifyPipelineStatus("reply_ready", sender)

            // Confirm before reply: show approval notification instead of sending directly.
            // Countdown starts only when the send is actually scheduled (approval or timeout).
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
                // Apply the user's configured reply delay on top of the batch window
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

        fun tryLocalFallback(cloudError: String?) {
            if (!ruleEngine.isFallbackToLocalEnabled()) {
                Log.w(TAG, "Local fallback is disabled in settings. Skipping reply for $sender")
                return
            }

            val localModelId = ruleEngine.getSelectedLocalModel()
            val phiService = PhiLocalService.getInstance(applicationContext)

            if (!phiService.isModelAvailable(localModelId)) {
                val errMsg = "Cloud AI ($modelType) failed: ${cloudError ?: "error"}. Local model '$localModelId' is not downloaded."
                Log.e(TAG, errMsg)
                ruleEngine.saveAiUsage(modelType, 0, 0, 0, 0, errMsg)
                notifyAiUsage(0, 0, 0, 0, errMsg)
                mainHandler.post {
                    methodChannel?.invokeMethod("onReplyFailed", errMsg)
                }
                return
            }

            Log.i(TAG, "Cloud AI ($modelType) failed ($cloudError). Falling back to local model: $localModelId for sender: $sender")
            phiService.getAiReplyBatch(
                modelId = localModelId,
                senderName = sender,
                incomingMessages = messages,
                systemPrompt = finalSystemPrompt,
                conversationHistory = history
            ) { localReply, localUsage ->
                if (!localReply.isNullOrBlank()) {
                    Log.i(TAG, "Local model fallback succeeded for $sender! Generated reply: '$localReply'")
                    deliverReply(localReply, "phi_local", localUsage?.tokensUsed ?: 0)
                } else {
                    val localErr = "Local fallback also failed: ${localUsage?.error ?: "Empty response"}"
                    Log.e(TAG, localErr)
                    ruleEngine.saveAiUsage("phi_local", 0, 0, 0, 0, localErr)
                    notifyAiUsage(0, 0, 0, 0, localErr)
                }
            }
        }

        val cloudCallbackAdapter: (String?, PhiLocalService.AiUsage?) -> Unit = { aiReply, usage ->
            val tokensUsed = usage?.tokensUsed ?: 0
            val error = usage?.error
            val isLimitReached = usage?.isLimitReached ?: false

            // Save usage and rate-limit data regardless of tokensUsed (essential for 429/quota tracking)
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

        val localCallbackAdapter: (String?, PhiLocalService.AiUsage?) -> Unit = { aiReply, usage ->
            val tokensUsed = usage?.tokensUsed ?: 0
            val error = usage?.error

            if (tokensUsed > 0) {
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
                Log.d(TAG, "Pipeline event")
            }
        }

        // Check if model has reached daily limit before making network request
        if (modelType != "phi_local" && ruleEngine.isAiLimitReached(modelType)) {
            Log.w(TAG, "Daily limit reached for $modelType. Falling back to local model immediately.")
            tryLocalFallback("Daily limit reached for $modelType")
            return
        }

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
                    callback = localCallbackAdapter
                )
            }
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

    /**
     * Resolve stable conversation identity for [notificationKey], preferring the
     * caller-supplied values captured when the message arrived. Falls back to the
     * currently-posted notification with the same key (best-effort — may be null
     * if it was already dismissed).
     *
     * Returns Quadruple(packageName, shortcutId, tag, id).
     */
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
        // tag+id is only stable when tag is non-null. A null tag with a reused
        // integer id (common: id=0/1 for every chat) must NOT count as a match,
        // otherwise two different chats in the same app could look identical.
        if (tag != null && id != null && tag == a.tag && id == a.id) return true
        return false
    }

    /**
     * Same-conversation fallback: only returns a notification that can be confirmed
     * as the original conversation.
     *
     * - Exact [originalKey] match (implies same package) is preferred.
     * - Otherwise only notifications from [expectedPackageName] whose stable identity
     *   (shortcut ID, or tag+id) matches the original are considered.
     * - Display-name / sender matching is deliberately NOT used: two contacts can
     *   share a name, and a substring match can route a reply to the wrong chat.
     *
     * Returns null when the original conversation can't be confirmed — callers must
     * then skip sending and log it instead of guessing.
     */
    private fun findSameConversationNotification(
        originalKey: String,
        expectedPackageName: String?,
        expectedShortcutId: String?,
        expectedTag: String?,
        expectedId: Int?,
    ): StatusBarNotification? {
        val active = activeNotifications ?: return null

        // Exact key still present (and still replyable)? Use it. If we know the
        // expected package, enforce it as well.
        active.firstOrNull { it.key == originalKey && hasReplyAction(it) }?.let { exact ->
            if (expectedPackageName == null || exact.packageName == expectedPackageName) {
                return exact
            }
            Log.w(TAG, "Exact key match ${exact.key} is from ${exact.packageName}, expected $expectedPackageName — ignoring")
        }

        // Without the original package we cannot safely narrow the search.
        // Do NOT fall back to sender-name search — treat as unconfirmed.
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

        // Stable identity match only (shortcut ID preferred, then non-null tag+id).
        // An id alone (null tag) is not stable — ids are commonly reused across chats.
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

    // Simple 4-tuple — avoids pulling in extra dependencies for an internal helper.
    private data class Quadruple<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)

    private fun isGroupChat(notification: Notification) =
        notification.extras.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION, false)

    /**
     * Normalize sender name for consistent batching.
     * WhatsApp sometimes prefixes titles with "WhatsApp: " — strip it so
     * "WhatsApp: Rahul" and "Rahul" are treated as the same sender.
     */
    private fun normalizeSenderName(title: String, packageName: String): String {
        return when (packageName) {
            "com.whatsapp" -> {
                title.removePrefix("WhatsApp: ").trim()
            }
            else -> title.trim()
        }
    }

    /**
     * Quick check for obvious notification artifacts before they enter the batcher.
     * More thorough filtering is done by [ConversationTranscriptBuilder] at transcript-build time.
     */
    private fun isNotificationArtifact(message: String): Boolean {
        return ConversationTranscriptBuilder.isArtifact(message)
    }

    /** Normalized per-sender map key so "Rahul" and "rahul" share one entry. */
    private fun senderKey(sender: String): String = sender.trim().lowercase()

    /**
     * Best-effort detection of outgoing (self-sent) messages via the
     * notification's MessagingStyle data (Notification.EXTRA_MESSAGES).
     *
     * After we send a RemoteInput reply, WhatsApp updates the notification and
     * the last style message may carry a null/empty sender or a self display
     * name ("You"). In that case the notification is an echo of our own send
     * and must not trigger another reply. Returns false when the data is
     * absent or inconclusive (callers still run the text-based self-guard).
     */
    private fun isOutgoingMessagingStyleMessage(notification: Notification, sender: String): Boolean {
        return try {
            val extras = notification.extras ?: return false
            val raw = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return false
            if (raw.isEmpty()) return false
            val last = raw.lastOrNull() as? Bundle ?: return false
            val text = last.getCharSequence("text")?.toString()?.trim() ?: ""
            if (text.isEmpty()) return false

            // Sender can be a CharSequence, a Person (API 28+), or null for outgoing.
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

    // ── Confirm Before Reply ────────────────────────────────────────────────

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
        val confirmId = UUID.randomUUID().toString()
        val notifId = CONFIRM_NOTIFICATION_ID_BASE + confirmId.hashCode()

        // Store the pending reply, including stable conversation identity so the
        // later send (approve or 15s timeout) can verify the same conversation.
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

        // Build approve intent
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

        // Build deny intent
        val denyIntent = Intent(ACTION_DENY).setPackage(this.packageName).apply {
            putExtra(EXTRA_CONFIRM_ID, confirmId)
            putExtra(EXTRA_SENDER, sender)
        }
        val denyPending = PendingIntent.getBroadcast(
            this, notifId + 1, denyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Truncate original message aggressively so reply text is fully visible
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

        // Verify notification was actually posted (check on Android 13+)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            if (!nm.areNotificationsEnabled()) {
                Log.w(TAG, "POST_NOTIFICATIONS permission not granted — notification may not be visible")
            }
        }

        // No approval means no send. Expired drafts are cancelled.
        mainHandler.postDelayed({
            if(pendingReplies.remove(confirmId)!=null) {nm.cancel(notifId);mainHandler.post{methodChannel?.invokeMethod("onReplyDenied", sender)}}
        }, 5*60_000L)

        Log.d(TAG, "Pipeline event")
    }
}
