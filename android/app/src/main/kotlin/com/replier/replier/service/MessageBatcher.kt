package com.replier.replier.service

import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Buffers incoming messages per-sender and batches AI replies.
 *
 * When a message arrives that triggers AI fallback (no rule match),
 * it is added to a per-sender buffer. A timer is started using the
 * user's configured reply delay. If another message arrives from the
 * same sender before the timer fires, the timer is reset.
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
        val isGroupChat: Boolean
    )

    // Per-sender pending messages
    private val pendingBatches = mutableMapOf<String, MutableList<PendingMessage>>()

    // Per-sender timers (runnables posted to mainHandler)
    private val batchTimers = mutableMapOf<String, Runnable>()

    // Track the delay used per sender for the current batch
    private val batchDelays = mutableMapOf<String, Long>()

    /**
     * Add a message to the per-sender buffer and (re)start the batch timer.
     *
     * @param delayMs The batch window in milliseconds (uses user's reply delay)
     * @param onBatchReady Called when the timer fires with all buffered messages
     */
    @Synchronized
    fun addMessage(
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
        val batch = pendingBatches.getOrPut(sender) { mutableListOf() }
        if (batch.any { it.message.trim().equals(message.trim(), ignoreCase = true) }) {
            Log.d(TAG, "Pipeline event")
            // Still reset the timer so the batch waits for truly new messages
        } else {
            batch.add(pendingMsg)
        }
        Log.d(TAG, "Pipeline event")

        // Cancel existing timer for this sender
        batchTimers[sender]?.let { existingRunnable ->
            mainHandler.removeCallbacks(existingRunnable)
            Log.d(TAG, "Pipeline event")
        }

        // Store the delay for this batch
        batchDelays[sender] = delayMs

        // Start new timer
        val runnable = Runnable {
            fireBatch(sender, onBatchReady)
        }
        batchTimers[sender] = runnable
        mainHandler.postDelayed(runnable, delayMs)
        Log.d(TAG, "Pipeline event")
    }

    /**
     * Fire the batch for a sender: collect all messages, invoke callback, clear buffer.
     */
    private fun fireBatch(sender: String, onBatchReady: (BatchReadyCallback) -> Unit) {
        val messages = pendingBatches.remove(sender) ?: return
        batchTimers.remove(sender)
        batchDelays.remove(sender)

        if (messages.isEmpty()) return

        Log.d(TAG, "Pipeline event")

        // Use the latest notification key (most likely to still be active)
        val latest = messages.last()
        val latestKey = latest.notificationKey
        val packageName = latest.packageName
        val isGroupChat = latest.isGroupChat

        onBatchReady(
            BatchReadyCallback(
                sender = sender,
                messages = messages,
                latestNotificationKey = latestKey,
                packageName = packageName,
                latestShortcutId = latest.shortcutId,
                latestTag = latest.sbnTag,
                latestId = latest.sbnId,
                isGroupChat = isGroupChat
            )
        )
    }

    /**
     * Cancel all pending batches (call on service destroy).
     */
    @Synchronized
    fun cancelAll() {
        batchTimers.values.forEach { mainHandler.removeCallbacks(it) }
        batchTimers.clear()
        pendingBatches.clear()
        batchDelays.clear()
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
