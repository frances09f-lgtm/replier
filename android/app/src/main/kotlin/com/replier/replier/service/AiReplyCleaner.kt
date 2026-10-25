package com.replier.replier.service

import android.util.Log

/**
 * Cleans raw AI responses by stripping special tokens, internal thinking/reasoning tags,
 * thought process sections, role echoes, and reasoning commentary leaks.
 */
object AiReplyCleaner {

    private const val TAG = "AiReplyCleaner"

    // Model special tokens
    private const val LLAMA_BEGIN = "<|begin_of_text|>"
    private const val LLAMA_HDR_START = "<|start_header_id|>"
    private const val LLAMA_HDR_END = "<|end_header_id|>"
    private const val LLAMA_EOT = "<|eot_id|>"

    // Tokens that end the model's turn (or start a new one). Text after the first of these is a
    // second, run-on generation (likely cause of the on-device "Ok, cool.Ok, cool.": a reply plus
    // its repeat joined once the token between them was deleted), so we cut there instead.
    private val TURN_END_TOKENS = listOf(
        LLAMA_EOT, LLAMA_HDR_START, "<|im_end|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>",
        "<eos>", "<|end|>", "<|return|>", "<|endoftext|>", "</s>"
    )
    private val LLAMA_HEADER_REGEX = Regex("""<\|start_header_id\|>[^<]{0,40}<\|end_header_id\|>""")

    private val THINK_BLOCK_REGEX = Regex("""(?is)<think\b[^>]*>.*?<\/think>""")
    private val THOUGHT_BLOCK_REGEX = Regex("""(?is)<thought\b[^>]*>.*?<\/thought>""")
    private val REASONING_BLOCK_REGEX = Regex("""(?is)<reasoning\b[^>]*>.*?<\/reasoning>""")

    // Unclosed thinking blocks (truncated before closing tag)
    private val UNCLOSED_THINK_REGEX = Regex("""(?is)<think\b[^>]*>.*$""")
    private val UNCLOSED_THOUGHT_REGEX = Regex("""(?is)<thought\b[^>]*>.*$""")
    private val UNCLOSED_REASONING_REGEX = Regex("""(?is)<reasoning\b[^>]*>.*$""")

    // Sections introduced with Thinking Process / Thought: ...
    private val THINKING_SECTION_REGEX = Regex(
        """(?is)(?:Thinking Process|Thought Process|Internal Monologue|Reasoning Process|Reasoning|Thought|Thinking):.*?(?=(?:\n\s*\n|\b(?:Final Answer|Reply|Response|Output):|$))"""
    )

    private val INSTRUCTION_ARTIFACTS = listOf(
        "output only the", "output: only", "only the message reply", "only the reply text",
        "generate the reply", "reply text only", "output the reply"
    )

    private val REASONING_INDICATOR_PATTERNS = listOf(
        Regex("""(?i)^the user (?:says|is asking|asked|wants)\b"""),
        Regex("""(?i)^we have a conversation\b"""),
        Regex("""(?i)^the instructions:\s*reply as\b"""),
        Regex("""(?i)^in this conversation,\s*the user\b"""),
        Regex("""(?i)^i need to reply as\b"""),
        Regex("""(?i)^we must reply as\b"""),
        Regex("""(?i)^let's reply as\b"""),
        Regex("""(?i)^let's keep it (?:short|simple|casual)\b"""),
        Regex("""(?i)^we should reply\b"""),
        Regex("""(?i)^i should reply\b"""),
        Regex("""(?i)^i will reply\b"""),
        Regex("""(?i)^as abhi's auto-reply\b"""),
        Regex("""(?i)^as an ai assistant\b"""),
    )

    fun clean(
        rawText: String,
        senderName: String = "",
        incomingMessage: String = ""
    ): String {
        var text = rawText.trim()
        if (text.isBlank()) return ""

        // 1. Cut at the end of the first turn, then strip remaining special tokens
        text = truncateAtTurnEnd(text)
        text = stripSpecialTokens(text)

        // 2. Strip thinking / reasoning tags (closed and unclosed)
        text = stripThinkingTags(text)

        // 3. Strip thinking sections
        text = stripThinkingSections(text)

        if (text.isBlank()) return ""

        // 4. Split into paragraphs and find the first non-reasoning paragraph
        val paragraphs = text.split(Regex("""\n\s*\n"""))
            .map { it.trim() }
            .filter { it.isNotBlank() }

        var validReply = ""
        for (para in paragraphs) {
            val cleanedPara = cleanParagraph(para, senderName, incomingMessage)
            if (cleanedPara.isNotBlank() && !isReasoningCommentary(cleanedPara)) {
                validReply = cleanedPara
                break
            }
        }

        if (validReply.isBlank()) {
            // Fall back to entire cleaned text if single paragraph or none matched, but only if not reasoning commentary
            val cleanedEntire = cleanParagraph(text, senderName, incomingMessage)
            if (cleanedEntire.isNotBlank() && !isReasoningCommentary(cleanedEntire)) {
                validReply = cleanedEntire
            }
        }

        if (validReply.isBlank()) {
            logWarn("clean: discarded reply as reasoning/blank. Original: '${rawText.take(150)}'")
            return ""
        }

        return collapseExactRepeat(validReply).take(300)
    }

    /**
     * Keeps only the first turn of a generation: drops a leading role header
     * (<|start_header_id|>assistant<|end_header_id|>) and cuts at the first turn-end token that
     * follows real text.
     */
    fun truncateAtTurnEnd(input: String): String {
        val text = LLAMA_HEADER_REGEX.replace(input, "\n")
        var from = 0
        while (from < text.length) {
            var cut = -1
            for (token in TURN_END_TOKENS) {
                val i = text.indexOf(token, from)
                if (i >= 0 && (cut < 0 || i < cut)) cut = i
            }
            if (cut < 0) return text
            val before = text.substring(0, cut)
            if (stripSpecialTokens(before).isNotBlank()) return before
            from = cut + 1
        }
        return text
    }

    /**
     * Safety net for a reply that is one sentence repeated back to back with no or only whitespace
     * between ("Ok, cool.Ok, cool." -> "Ok, cool."). Only collapses when the repeated part ends
     * like a sentence, so casual doubles like "haha haha" or "bye bye" are left alone.
     */
    fun collapseExactRepeat(input: String): String {
        val t = input.trim()
        if (t.length < 4) return t
        for (k in 2..(t.length - 2)) {
            val a = t.substring(0, k).trimEnd()
            if (a.length < 2) continue
            val last = a.last()
            if (last != '.' && last != '!' && last != '?' && last != '…') continue
            if (t.substring(k).trim() == a) return a
        }
        return t
    }

    private fun stripSpecialTokens(input: String): String {
        return input.replace(LLAMA_EOT, "")
            .replace(LLAMA_HDR_START, "")
            .replace(LLAMA_HDR_END, "")
            .replace(LLAMA_BEGIN, "")
            .replace("<|im_start|>", "")
            .replace("<|im_end|>", "")
            .replace("<end_of_turn>", "")
            .replace("<bos>", "")
            .replace("<eos>", "")
            .trim()
    }

    fun stripThinkingTags(input: String): String {
        var res = input
        res = THINK_BLOCK_REGEX.replace(res, "")
        res = THOUGHT_BLOCK_REGEX.replace(res, "")
        res = REASONING_BLOCK_REGEX.replace(res, "")
        // Handle unclosed tags where inference ended inside the think block
        res = UNCLOSED_THINK_REGEX.replace(res, "")
        res = UNCLOSED_THOUGHT_REGEX.replace(res, "")
        res = UNCLOSED_REASONING_REGEX.replace(res, "")
        return res.trim()
    }

    fun stripThinkingSections(input: String): String {
        var res = THINKING_SECTION_REGEX.replace(input, "").trim()
        return res
    }

    private fun cleanParagraph(para: String, senderName: String, incomingMessage: String): String {
        var res = para.trim()

        // Strip role prefixes
        val prefixesToRemove = listOf(
            "Final Answer:", "Assistant:", "Human:", "User:", "AI:", "Reply:", "Response:",
            if (senderName.isNotBlank()) "$senderName:" else ""
        ).filter { it.isNotBlank() }

        for (prefix in prefixesToRemove) {
            if (res.startsWith(prefix, ignoreCase = true)) {
                res = res.substring(prefix.length).trim()
            }
        }

        // Remove surrounding quotes
        if (res.startsWith("\"") && res.endsWith("\"") && res.length > 2) {
            res = res.substring(1, res.length - 1).trim()
        }

        // Echo check
        if (incomingMessage.isNotBlank() && res.equals(incomingMessage.trim(), ignoreCase = true)) {
            return ""
        }

        // Instruction artifacts
        val lower = res.lowercase()
        if (INSTRUCTION_ARTIFACTS.any { lower.contains(it) }) {
            return ""
        }

        return res
    }

    fun isReasoningCommentary(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isBlank()) return true

        for (pattern in REASONING_INDICATOR_PATTERNS) {
            if (pattern.containsMatchIn(trimmed)) {
                return true
            }
        }

        val lower = trimmed.lowercase()
        val metaClues = listOf(
            "this is likely a phrase in",
            "but we don't know context",
            "but we must reply as",
            "he doesn't like unnecessary conversation",
            "reply as abhi",
            "keep it extremely short",
            "that is marathi:"
        )
        if (metaClues.any { lower.contains(it) }) {
            return true
        }

        return false
    }

    private fun logWarn(message: String) {
        try {
            Log.w(TAG, message)
        } catch (_: Throwable) {
            // Android Log not mocked in plain JVM unit tests
        }
    }
}
