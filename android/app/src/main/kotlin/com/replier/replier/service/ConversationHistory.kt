package com.replier.replier.service

import android.util.Log

/**
 * In-memory per-sender conversation history for AI context.
 *
 * Keeps the last [MAX_MESSAGES] messages (alternating user/assistant)
 * so the AI can answer follow-up questions with context.
 * History is keyed by sender name and resets when the service restarts.
 */
object ConversationHistory {

    private const val TAG = "ConversationHistory"
    private const val MAX_MESSAGES = 5
    private const val EXPIRATION_MS = 15 * 60 * 1000L // 15 minutes inactivity TTL

    data class ChatMessage(
        val role: String,   // "user" or "assistant"
        val content: String,
        val timestamp: Long = System.currentTimeMillis()
    )

    // Per-sender history, keyed by sender name
    private val histories = mutableMapOf<String, MutableList<ChatMessage>>()

    @Synchronized
    fun addMessage(sender: String, role: String, content: String) {
        val history = histories.getOrPut(sender) { mutableListOf() }
        val now = System.currentTimeMillis()

        // If last message was more than EXPIRATION_MS ago, clear stale history for a fresh conversation
        if (history.isNotEmpty() && (now - history.last().timestamp) > EXPIRATION_MS) {
            Log.d(TAG, "Pipeline event")
            history.clear()
        }

        history.add(ChatMessage(role, content, now))
        // Trim to last MAX_MESSAGES
        while (history.size > MAX_MESSAGES) {
            history.removeAt(0)
        }
        Log.d(TAG, "Pipeline event")
    }

    @Synchronized
    fun getHistory(sender: String): List<ChatMessage> {
        val history = histories[sender] ?: return emptyList()
        val now = System.currentTimeMillis()

        // Purge expired entries
        if (history.isNotEmpty() && (now - history.last().timestamp) > EXPIRATION_MS) {
            Log.d(TAG, "Pipeline event")
            history.clear()
            return emptyList()
        }

        return history.toList()
    }

    @Synchronized
    fun clearHistory(sender: String) {
        histories.remove(sender)
        Log.d(TAG, "Pipeline event")
    }

    @Synchronized
    fun clearAll() {
        histories.clear()
        Log.d(TAG, "clearAll")
    }
}
