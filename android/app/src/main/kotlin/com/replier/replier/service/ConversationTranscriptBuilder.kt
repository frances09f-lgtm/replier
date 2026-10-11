package com.replier.replier.service

import android.util.Log

/**
 * Builds a clean conversation transcript from raw history + current batch messages.
 *
 * Responsibilities:
 * - Filters notification artifacts (typing indicators, system pings, stickers, etc.)
 * - Deduplicates messages by content within a sliding window
 * - Merges consecutive same-role entries
 * - Caps output to an approximate token budget
 * - Preserves sender attribution on every user message
 */
object ConversationTranscriptBuilder {

    private const val TAG = "TranscriptBuilder"

    // Approximate chars-per-token ratio used for budget cap.
    // 1 token ~ 4 chars is a conservative estimate for English text.
    private const val CHARS_PER_TOKEN = 4

    // Default max input tokens (conservative for 4k context models)
    private const val DEFAULT_MAX_INPUT_TOKENS = 3000

    // Dedup window: messages with identical content within this many ms are collapsed
    private const val DEDUP_WINDOW_MS = 60_000L

    // ── Notification-artifact patterns ──────────────────────────────────

    /**
     * Regex patterns that match WhatsApp / Instagram notification artifacts
     * that should never be sent to the AI as real conversation content.
     */
    private val artifactPatterns: List<Regex> by lazy {
        listOf(
            // WhatsApp system messages
            Regex("""(?i)^\d+\s+new\s+messages?\s+from\s+.+"""),              // "3 new messages from X"
            Regex("""(?i)^\d+\s+messages?\s+from\s+\d+\s+contacts?"""),        // "5 messages from 2 contacts"
            Regex("""(?i)^Messages?\s+from\s+.+"""),                            // "Messages from X"
            Regex("""(?i)^You\s+missed\s+\d+\s+(voice|video)\s+calls?\b"""),   // "You missed 2 voice calls"
            Regex("""(?i)^Missed\s+(voice|video)\s+call"""),                    // "Missed voice call"
            Regex("""(?i)^\d+\s+missed\s+calls?\b"""),                         // "2 missed calls"
            Regex("""(?i)^Missed\s+call\s+from\s+.+"""),                       // "Missed call from X"

            // Typing / recording indicators
            Regex("""(?i)^typing\.{0,3}$"""),
            Regex("""(?i)^Recording\.{0,3}$"""),
            Regex("""(?i)^录音中$"""),                                           // Chinese "recording"
            Regex("""(?i)^键盘输入中$"""),                                       // Chinese "typing"

            // Sticker / media-only notifications
            Regex("""(?i)^Sticker$"""),
            Regex("""(?i)^GIF$"""),
            Regex("""(?i)^\d+\s+photos?$"""),
            Regex("""(?i)^\d+\s+videos?$"""),
            Regex("""(?i)^\d+\s+documents?$"""),
            Regex("""(?i)^Image$"""),
            Regex("""(?i)^Video$"""),
            Regex("""(?i)^Audio$"""),
            Regex("""(?i)^Document$"""),
            Regex("""(?i)^Contact\s+card$"""),
            Regex("""(?i)^Location$"""),
            Regex("""(?i)^Poll$"""),
            Regex("""(?i)^\u00a0?$"""),                                         // empty / whitespace-only

            // WhatsApp encryption / group subject changes
            Regex("""(?i)^Messages?\s+are\s+end-to-end\s+encrypted"""),
            Regex("""(?i)^created\s+group\s+"""),
            Regex("""(?i)^changed\s+(the\s+)?(subject|group\s+icon)"""),

            // Instagram-specific
            Regex("""(?i)^Sent\s+a\s+reaction"""),
            Regex("""(?i)^Liked\s+a\s+message"""),
            Regex("""(?i)^Replied\s+to\s+a\s+story"""),
            Regex("""(?i)^started\s+a\s+live\s+video"""),

            // File/media names (from shared media, screenshots, etc.)
            Regex("""(?i)\.(png|jpg|jpeg|gif|bmp|webp|svg|mp4|avi|mov|mkv|mp3|wav|ogg|pdf|docx?|xlsx?|zip|rar|7z)$"""),
            Regex("""(?i)^(image|photo|picture|video|audio|file|document|sticker|gif)\s*(\.\w+)?$"""),
            Regex("""(?i)^\d+\s+(photo|photo|video|image|document|file)s?$"""),
            Regex("""(?i)^(image|video|audio|document)\s+(attached|sent|received)$"""),
            Regex("""(?i)^(sent|shared)\s+(a|an)\s+(image|photo|picture|video|audio|file|document|sticker|gif)"""),
        )
    }

    // ── Public API ──────────────────────────────────────────────────────

    /**
     * Build a clean transcript from raw conversation history and current batch messages.
     *
     * @param history       Previous messages from [ConversationHistory]
     * @param batchMessages Raw incoming messages from the current batch (strings)
     * @param senderName    Normalized sender name for attribution
     * @param maxTokens     Approximate max input token budget (default 3000)
     * @return Clean list of [ConversationHistory.ChatMessage] ready for injection into any provider
     */
    fun build(
        history: List<ConversationHistory.ChatMessage>,
        batchMessages: List<String>,
        senderName: String,
        maxTokens: Int = DEFAULT_MAX_INPUT_TOKENS
    ): List<ConversationHistory.ChatMessage> {
        val raw = mutableListOf<ConversationHistory.ChatMessage>()

        // 1. Add history entries (already have role from store)
        for (msg in history) {
            val cleanedContent = cleanText(msg.content, senderName)
            raw.add(msg.copy(content = cleanedContent))
        }

        // 2. Add current batch messages as "user" entries
        for (text in batchMessages) {
            val cleanedContent = cleanText(text, senderName)
            raw.add(ConversationHistory.ChatMessage(role = "user", content = cleanedContent))
        }

        // 3. Filter out artifacts
        val filtered = raw.filter { !isArtifact(it.content) }
        Log.d(TAG, "After artifact filter: ${filtered.size}/${raw.size} messages remain")

        // 4. Deduplicate by content within sliding window
        val deduped = deduplicate(filtered)
        Log.d(TAG, "After dedup: ${deduped.size} messages remain")

        // 5. Merge consecutive same-role entries
        val merged = mergeConsecutive(deduped)
        Log.d(TAG, "After merge: ${merged.size} messages remain")

        // 6. Cap to token budget
        val capped = capToTokenBudget(merged, maxTokens)
        Log.d(TAG, "After token cap (${maxTokens} tokens): ${capped.size} messages remain")

        return capped
    }

    /**
     * Clean message content by stripping self prefixes ("You:", "Me:") or sender name prefixes.
     */
    fun cleanText(content: String, senderName: String): String {
        var trimmed = content.trim()
        val prefixesToStrip = listOf("you:", "me:", "you sent:", "${senderName.lowercase()}:")
        for (prefix in prefixesToStrip) {
            if (trimmed.lowercase().startsWith(prefix)) {
                trimmed = trimmed.substring(prefix.length).trim()
            }
        }
        return trimmed
    }

    // ── Internals ───────────────────────────────────────────────────────

    /**
     * Returns true if the message content looks like a notification artifact
     * rather than a real user message. Can be called directly for early filtering.
     */
    fun isArtifact(content: String): Boolean {
        val trimmed = content.trim()
        if (trimmed.isEmpty()) return true
        return artifactPatterns.any { it.containsMatchIn(trimmed) }
    }

    /**
     * Remove duplicate messages with identical content that arrive within [DEDUP_WINDOW_MS].
     * Preserves the first occurrence.
     */
    private fun deduplicate(messages: List<ConversationHistory.ChatMessage>): List<ConversationHistory.ChatMessage> {
        if (messages.size <= 1) return messages

        val result = mutableListOf<ConversationHistory.ChatMessage>()
        val seen = LinkedHashMap<String, Long>() // content hash -> timestamp approximation

        for (msg in messages) {
            val key = msg.content.trim().lowercase()
            val now = System.currentTimeMillis()

            val lastSeen = seen[key]
            if (lastSeen == null || (now - lastSeen) > DEDUP_WINDOW_MS) {
                result.add(msg)
                seen[key] = now
            }
        }
        return result
    }

    /**
     * Merge consecutive messages with the same role into a single entry.
     * User messages are joined with newlines; assistant messages are joined with newlines.
     */
    private fun mergeConsecutive(messages: List<ConversationHistory.ChatMessage>): List<ConversationHistory.ChatMessage> {
        if (messages.size <= 1) return messages

        val result = mutableListOf<ConversationHistory.ChatMessage>()
        var current = messages[0]

        for (i in 1 until messages.size) {
            val next = messages[i]
            if (next.role == current.role) {
                // Merge: append content
                current = ConversationHistory.ChatMessage(
                    role = current.role,
                    content = "${current.content}\n${next.content}"
                )
            } else {
                result.add(current)
                current = next
            }
        }
        result.add(current)
        return result
    }

    /**
     * Keep messages from the tail end until the approximate token budget is exhausted.
     * Always keeps at least the last user message (the current input).
     */
    private fun capToTokenBudget(
        messages: List<ConversationHistory.ChatMessage>,
        maxTokens: Int
    ): List<ConversationHistory.ChatMessage> {
        if (messages.isEmpty()) return messages

        val maxChars = maxTokens * CHARS_PER_TOKEN
        var charCount = 0
        // Start at 0: if no message exceeds budget, we keep everything (subList(0, size))
        var cutoffIndex = 0

        // Walk from the end, accumulating char counts
        for (i in messages.size - 1 downTo 0) {
            charCount += messages[i].content.length
            if (charCount > maxChars) {
                // Budget exceeded — drop everything before index i+1
                cutoffIndex = i + 1
                break
            }
        }

        // Always include at least the last message (the current user input)
        val result = messages.subList(cutoffIndex.coerceAtMost(messages.size - 1), messages.size).toList()
        return result
    }
}
