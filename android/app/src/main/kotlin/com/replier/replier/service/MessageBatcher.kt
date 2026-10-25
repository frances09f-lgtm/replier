package com.replier.replier.service

import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Buffers incoming messages per-conversation and batches AI replies.
 *
 * When a message arrives that triggers AI fallback (no rule match),
 * it is added to a per-conversation buffer. A timer is started using the
 * short collection window (separate from the user's reply delay). If another message arrives from the
 * same conversation before the timer fires, the timer is reset.
 *
 * Once the timer fires (no new messages for the delay period),
 * all buffered messages for that sender are collected and sent
 * to the AI as context for a single reply.
 */
class MessageBatcher(private val mainHandler: Handler) {

    companion object {
        private const val TAG = "MessageBatcher"
    }

    data class PendingMessage(
        val sender: String,
        val message: String,
        val notificationKey: String,
        val packageName: String,
        val shortcutId: String?,
        val sbnTag: String?,
        val sbnId: Int?,
        val isGroupChat: Boolean,
        val timestamp: Long
    )

    /**
     * Callback invoked when a batch is ready to be sent to AI.
     * @param sender The sender name
     * @param messages All buffered messages in order
     * @param latestNotificationKey The key of the most recent notification (best candidate for reply)
     * @param packageName The app package (WhatsApp/Instagram)
     * @param latestShortcutId Stable conversation shortcut ID, if available
     * @param latestTag StatusBarNotification tag for the latest message
     * @param latestId StatusBarNotification id for the latest message
     * @param isGroupChat Whether this is a group chat
     */
    data class BatchReadyCallback(
        val sender: String,
        val messages: List<PendingMessage>,
        val latestNotificationKey: String,
        val packageName: String,
        val latestShortcutId: String?,
        val latestTag: String?,
        val latestId: Int?,
        val isGroupChat: Boolean,
        val analysisId: String,
    )

    // Per-sender pending messages
    private val pendingBatches = mutableMapOf<String, MutableList<PendingMessage>>()

    // Per-sender timers (runnables posted to mainHandler)
    private val batchTimers = mutableMapOf<String, Runnable>()

    // Track the delay used per sender for the current batch
    private val batchDelays = mutableMapOf<String, Long>()
    private val attemptIds = mutableMapOf<String, String>()
    private val resetCounts = mutableMapOf<String, Int>() // DEBUG
    @Synchronized fun getPendingAttemptId(conversationKey: String): String? = attemptIds[conversationKey]

    /**
     * Add a message to the per-conversation buffer and (re)start the batch timer.
     *
     * @param delayMs The batch window in milliseconds (uses user's reply delay)
     * @param onBatchReady Called when the timer fires with all buffered messages
     */
    @Synchronized
    fun addMessage(
        conversationKey: String,
        analysisId: String,
        sender: String,
        message: String,
        notificationKey: String,
        packageName: String,
        isGroupChat: Boolean,
        delayMs: Long,
        shortcutId: String? = null,
        sbnTag: String? = null,
        sbnId: Int? = null,
        onBatchReady: (BatchReadyCallback) -> Unit,
    ) {
        val pendingMsg = PendingMessage(
            sender = sender,
            message = message,
            notificationKey = notificationKey,
            packageName = packageName,
            shortcutId = shortcutId,
            sbnTag = sbnTag,
            sbnId = sbnId,
            isGroupChat = isGroupChat,
            timestamp = System.currentTimeMillis()
        )

        // Add to buffer (skip if identical content already pending for this sender)
        // A previous batch may have expired while incoming messages continued.
        // Never transfer expired messages into a new analysis attempt.
        val dbgPrev = attemptIds[conversationKey]
        if (attemptIds[conversationKey] != null && attemptIds[conversationKey] != analysisId) {
            val dropped = pendingBatches.remove(conversationKey)?.size ?: 0
            AppNotificationListenerService.dbg("B1 batcher: attempt changed ${dbgPrev?.take(8)} -> ${analysisId.take(8)}, dropped $dropped buffered msg(s)")
        }
        attemptIds[conversationKey] = analysisId
        val batch = pendingBatches.getOrPut(conversationKey) { mutableListOf() }
        if (batch.any { it.message.trim().equals(message.trim(), ignoreCase = true) }) {
            Log.d(TAG, "Pipeline event")
            AppNotificationListenerService.dbg("B2 batcher: identical text already buffered (not added, timer still reset)")
            // Still reset the timer so the batch waits for truly new messages
        } else {
            batch.add(pendingMsg)
        }
        Log.d(TAG, "Pipeline event")

        // Cancel existing timer for this sender
        val dbgHadTimer = batchTimers[conversationKey] != null
        batchTimers[conversationKey]?.let { existingRunnable ->
            mainHandler.removeCallbacks(existingRunnable)
            Log.d(TAG, "Pipeline event")
        }
        val dbgResets = if (dbgHadTimer) (resetCounts[conversationKey] ?: 0) + 1 else 0
        resetCounts[conversationKey] = dbgResets

        // Store the delay for this batch
        batchDelays[conversationKey] = delayMs

        // Start new timer
        val dbgScheduledAt = android.os.SystemClock.elapsedRealtime()
        val runnable = Runnable {
            AppNotificationListenerService.dbg("B4 batcher: timer FIRED after ${android.os.SystemClock.elapsedRealtime() - dbgScheduledAt}ms (asked ${delayMs}ms)")
            try {
                fireBatch(conversationKey, onBatchReady)
            } catch (t: Throwable) {
                AppNotificationListenerService.dbg("B4x batcher: fireBatch threw ${t.javaClass.simpleName}: ${t.message}")
            }
        }
        batchTimers[conversationKey] = runnable
        val dbgPosted = mainHandler.postDelayed(runnable, delayMs)
        Log.d(TAG, "Pipeline event")
        AppNotificationListenerService.dbg("B3 batcher: addMessage conv=${AppNotificationListenerService.dh(conversationKey)} buffered=${batch.size} timerResets=$dbgResets delay=${delayMs}ms posted=$dbgPosted mainLooperAlive=${mainHandler.looper.thread.isAlive}")
    }

    /**
     * Fire the batch for a sender: collect all messages, invoke callback, clear buffer.
     */
    @Synchronized
    private fun fireBatch(sender: String, onBatchReady: (BatchReadyCallback) -> Unit) {
        resetCounts.remove(sender)
        val messages = pendingBatches.remove(sender) ?: run {
            AppNotificationListenerService.dbg("B5x fireBatch return: no pending batch for conv=${AppNotificationListenerService.dh(sender)}")
            return
        }
        batchTimers.remove(sender)
        batchDelays.remove(sender)

        if (messages.isEmpty()) {
            AppNotificationListenerService.dbg("B5x fireBatch return: batch empty")
            return
        }
        if (attemptIds[sender] == null) {
            AppNotificationListenerService.dbg("B5x fireBatch return: no attempt id for this batch (callback will NOT run)")
        }
        AppNotificationListenerService.dbg("B5 fireBatch: ${messages.size} msg(s), attempt=${attemptIds[sender]?.take(8)} -> calling callback")

        Log.d(TAG, "Pipeline event")

        // Use the latest notification key (most likely to still be active)
        val latest = messages.last()
        val latestKey = latest.notificationKey
        val packageName = latest.packageName
        val isGroupChat = latest.isGroupChat

        onBatchReady(
            BatchReadyCallback(
                sender = latest.sender,
                messages = messages,
                latestNotificationKey = latestKey,
                packageName = packageName,
                latestShortcutId = latest.shortcutId,
                latestTag = latest.sbnTag,
                latestId = latest.sbnId,
                isGroupChat = isGroupChat,
                analysisId = attemptIds.remove(sender) ?: return,
            )
        )
    }

    /** Revoke buffered content when notification metadata becomes unsafe. */
    @Synchronized
    fun cancelConversation(conversationKey: String) {
        AppNotificationListenerService.dbg("B6 batcher: cancelConversation conv=${AppNotificationListenerService.dh(conversationKey)} hadPending=${pendingBatches[conversationKey]?.size ?: 0} hadTimer=${batchTimers[conversationKey] != null}")
        resetCounts.remove(conversationKey)
        batchTimers.remove(conversationKey)?.let { mainHandler.removeCallbacks(it) }
        pendingBatches.remove(conversationKey)
        batchDelays.remove(conversationKey)
        attemptIds.remove(conversationKey)
    }

    /**
     * Cancel all pending batches (call on service destroy).
     */
    @Synchronized
    fun cancelAll() {
        AppNotificationListenerService.dbg("B7 batcher: cancelAll (service destroyed?) pending=${pendingBatches.size}")
        resetCounts.clear()
        batchTimers.values.forEach { mainHandler.removeCallbacks(it) }
        batchTimers.clear()
        pendingBatches.clear()
        batchDelays.clear()
        attemptIds.clear()
        Log.d(TAG, "All batches cancelled")
    }

    /**
     * Get the current batch size for a sender (for debugging/logging).
     */
    @Synchronized
    fun getPendingCount(sender: String): Int {
        return pendingBatches[sender]?.size ?: 0
    }
}
