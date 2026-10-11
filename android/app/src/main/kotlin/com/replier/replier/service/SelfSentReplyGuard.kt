package com.replier.replier.service

/**
 * Detects notifications for messages this app sent, without treating
 * third-party text that merely mentions a past reply as self-sent.
 *
 * Background: after we send a reply via RemoteInput, WhatsApp posts an
 * updated notification where the title is STILL the contact name (e.g.
 * "Rahul") but the text is our just-sent reply. A guard that only checks
 * for sender == "You"/"Me" misses this echo and the app replies to its
 * own message in a loop.
 *
 * This guard combines three signals:
 *  1. Sender is "You"/"Me" (outgoing notification) -> always self.
 *  2. Message carries an outgoing prefix ("You:", "Me:", "You sent:")
 *     (group-chat own messages) -> always self.
 *  3. Echo: the message text equals a reply we recently sent to THIS SAME
 *     sender (within [ECHO_WINDOW_MS]). This catches the RemoteInput echo
 *     while avoiding false positives for other senders or stale replies.
 */
object SelfSentReplyGuard {

    /** How long after sending a reply an identical incoming text from the
     * same sender is treated as our own echo. Kept short on purpose: the
     * real echo arrives within seconds, while a longer window would risk
     * swallowing a contact's genuine message that happens to match our reply. */
    const val ECHO_WINDOW_MS = 60_000L

    private val selfPrefixes = listOf("you:", "me:", "you sent:")

    fun isSelfSender(sender: String): Boolean {
        val normalized = sender.trim().lowercase()
        return normalized == "you" || normalized == "me"
    }

    fun hasSelfPrefix(message: String): Boolean {
        val lower = message.trim().lowercase()
        return selfPrefixes.any { lower.startsWith(it) }
    }

    fun stripSelfPrefixes(message: String): String {
        var lower = message.trim()
        var stripped: Boolean
        do {
            stripped = false
            val l = lower.lowercase()
            for (prefix in selfPrefixes) {
                if (l.startsWith(prefix)) {
                    lower = lower.substring(prefix.length).trim()
                    stripped = true
                    break
                }
            }
        } while (stripped)
        return lower
    }

    private fun normalize(text: String): String = text.trim().lowercase()

    /**
     * Legacy overload (global reply set, no timestamps).
     *
     * Any "You"/"Me" sender or self-prefixed message is self-sent, even if
     * the text doesn't match a known reply (covers manually-typed messages).
     * Non-self senders are never treated as self-sent here — use the
     * per-sender overload below for echo detection.
     */
    fun isSelfSentMessage(
        message: String,
        sender: String,
        sentReplyTexts: Set<String>,
    ): Boolean {
        if (message.trim().isBlank()) return true
        // "You: hello" in a group chat is our own outgoing message.
        if (hasSelfPrefix(message)) return true
        // Outgoing notification — always ours, regardless of text match.
        if (isSelfSender(sender)) return true
        // Never treat a contact's message as self-sent on global text match
        // alone — that caused false positives when contacts quoted our reply.
        return false
    }

    /**
     * Per-sender echo detection with a time window.
     *
     * @param sentRepliesForSender map of normalized reply text -> timestamp
     *        (ms) when we sent that reply to THIS sender.
     */
    fun isSelfSentMessage(
        message: String,
        sender: String,
        sentRepliesForSender: Map<String, Long>,
        nowMs: Long = System.currentTimeMillis(),
        echoWindowMs: Long = ECHO_WINDOW_MS,
    ): Boolean {
        if (message.trim().isBlank()) return true
        if (hasSelfPrefix(message)) return true
        if (isSelfSender(sender)) return true
        if (sentRepliesForSender.isEmpty()) return false

        val stripped = normalize(stripSelfPrefixes(message))
        if (stripped.isBlank()) return true

        for ((sentText, sentAt) in sentRepliesForSender) {
            if (sentText.isBlank()) continue
            if (nowMs - sentAt > echoWindowMs) continue
            val sent = normalize(sentText)
            if (stripped == sent) return true
            // WhatsApp bigText echoes can append our reply as the last line
            // of a multi-line transcript ("Hi\nSahara.").
            if (stripped.endsWith("\n$sent")) return true
        }
        return false
    }
}
