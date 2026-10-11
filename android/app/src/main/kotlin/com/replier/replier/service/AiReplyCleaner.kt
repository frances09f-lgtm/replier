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

        // 1. Strip special tokens
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

        return validReply.take(300)
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
