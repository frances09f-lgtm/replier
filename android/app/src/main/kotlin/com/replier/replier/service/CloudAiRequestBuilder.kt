package com.replier.replier.service

import org.json.JSONArray
import org.json.JSONObject

/**
 * Builds provider-specific AI request bodies (testable, no network).
 */
object CloudAiRequestBuilder {

    fun buildFormattedSystemPrompt(userSystemPrompt: String, senderName: String): String {
        val effectiveSender = if (senderName.isBlank()) "the user" else senderName
        val sb = StringBuilder()
        sb.append(
            "You are the user replying on WhatsApp to $effectiveSender. " +
                "Sound like a real person, NOT an assistant.\n\n"
        )

        // Defaults FIRST so user corrections below override them (recency wins).
        sb.append("the user's default style (use ONLY if nothing below matches):\n")
        sb.append("- Short mixed Hinglish/Marathi+English, casual. 1-10 words typical, max 15 words.\n")
        sb.append("- Match the incoming language (English, Marathi, or mixed Hinglish).\n")
        sb.append("- No full polite sentences, no \"Sure! I'd be happy\", no explanations.\n")
        sb.append("- No emoji unless the incoming message has one.\n\n")

        val trimmedUserPrompt = userSystemPrompt.trim()
        if (trimmedUserPrompt.isNotBlank()) {
            sb.append("How the user ACTUALLY replies — FOLLOW THIS STRICTLY, it overrides the defaults above:\n")
            sb.append(trimmedUserPrompt)
            sb.append("\n\n")
        }

        sb.append("Instructions:\n")
        sb.append("- Reply directly to $effectiveSender. Output ONLY the message reply text.\n")
        sb.append("- If a LEARNED RESPONSE PATTERNS example matches the incoming message topic, copy its style/wording closely.\n")
        sb.append("- Do NOT repeat or echo $effectiveSender's message.\n")
        sb.append("- Do NOT include role prefixes like 'Assistant:', 'AI:', or '$effectiveSender:'.\n")
        sb.append(
            "- CRITICAL: Do NOT think out loud, do NOT include reasoning, internal monologue, thought process, explanations, or notes. " +
                "Output ONLY the final message reply text."
        )

        return sb.toString()
    }

    fun buildOpenAiCompatiblePayload(
        model: String,
        systemPrompt: String,
        incomingMessage: String,
        senderName: String,
        history: List<ConversationHistory.ChatMessage> = emptyList(),
        maxTokens: Int = 80,
        temperature: Double = 0.85,
        provider: String = "",
    ): JSONObject {
        val messagesArray = JSONArray()

        messagesArray.put(JSONObject().apply {
            put("role", "system")
            put("content", systemPrompt)
        })

        for (msg in history) {
            val role = if (msg.role == "user") "user" else "assistant"
            val content = if (msg.role == "user" && !msg.content.startsWith("$senderName:")) {
                "$senderName: ${msg.content}"
            } else {
                msg.content
            }
            messagesArray.put(JSONObject().apply {
                put("role", role)
                put("content", content)
            })
        }

        val currentContent = if (!incomingMessage.startsWith("$senderName:")) {
            "$senderName: $incomingMessage"
        } else {
            incomingMessage
        }

        messagesArray.put(JSONObject().apply {
            put("role", "user")
            put("content", currentContent)
        })

        return JSONObject().apply {
            put("model", model)
            put("messages", messagesArray)
            put("max_tokens", maxTokens)
            put("temperature", temperature)

            val isGroqOrReasoning = provider == "groq_api" ||
                model.contains("oss", ignoreCase = true) ||
                model.contains("r1", ignoreCase = true) ||
                model.contains("deepseek", ignoreCase = true)

            if (isGroqOrReasoning) {
                put("reasoning_format", "hidden")
                if (model.contains("oss", ignoreCase = true)) {
                    put("reasoning_effort", "low")
                }
            }
        }
    }

    fun buildGeminiPayload(
        systemPrompt: String,
        incomingMessage: String,
        senderName: String,
        history: List<ConversationHistory.ChatMessage> = emptyList(),
        maxOutputTokens: Int = 256,
        temperature: Double = 0.7,
    ): JSONObject {
        val contentsArray = JSONArray()

        for (msg in history) {
            val role = if (msg.role == "user") "user" else "model"
            val contentText = if (msg.role == "user" && !msg.content.startsWith("$senderName:")) {
                "$senderName: ${msg.content}"
            } else {
                msg.content
            }
            contentsArray.put(JSONObject().apply {
                put("role", role)
                put("parts", JSONArray().put(JSONObject().put("text", contentText)))
            })
        }

        val currentContent = if (!incomingMessage.startsWith("$senderName:")) {
            "$senderName: $incomingMessage"
        } else {
            incomingMessage
        }

        contentsArray.put(JSONObject().apply {
            put("role", "user")
            put("parts", JSONArray().put(JSONObject().put("text", currentContent)))
        })

        return JSONObject().apply {
            put("contents", contentsArray)
            put("systemInstruction", JSONObject().apply {
                put("parts", JSONArray().put(JSONObject().put("text", systemPrompt)))
            })
            put("generationConfig", JSONObject().apply {
                put("maxOutputTokens", maxOutputTokens)
                put("temperature", temperature)
            })
        }
    }
}
