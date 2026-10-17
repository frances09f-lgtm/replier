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
        sb.append("You are replying on WhatsApp to $effectiveSender as a real person. 1-15 words, casual.\n")

        val trimmedUserPrompt = userSystemPrompt.trim()
        if (trimmedUserPrompt.isNotBlank()) {
            sb.append("Match the user's style - FOLLOW THIS STRICTLY:\n")
            sb.append(trimmedUserPrompt)
            sb.append("\n")
        }

        sb.append("Match any LEARNED RESPONSE PATTERNS example's style closely. Output ONLY the reply text, no prefixes, no explanations.")
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
            if(provider=="cloudflare_api" && model.contains("qwen3")) {
                messagesArray.getJSONObject(messagesArray.length()-1).put("content", currentContent + "\n/no_think")
            }
            put("messages", messagesArray)
            put("max_tokens", maxTokens)
            put("temperature", temperature)

            val isGroqOrReasoning = provider == "groq_api" ||
                model.contains("oss", ignoreCase = true) ||
                model.contains("r1", ignoreCase = true) ||
                model.contains("deepseek", ignoreCase = true)

            if (isGroqOrReasoning && provider != "cloudflare_api") {
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
