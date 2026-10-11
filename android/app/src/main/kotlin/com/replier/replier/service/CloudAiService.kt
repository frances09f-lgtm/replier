package com.replier.replier.service

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class CloudAiService private constructor(private val context: Context) {

    companion object {
        private const val TAG = "CloudAiService"

        @Volatile
        private var instance: CloudAiService? = null

        fun getInstance(context: Context): CloudAiService {
            return instance ?: synchronized(this) {
                instance ?: CloudAiService(context.applicationContext).also { instance = it }
            }
        }
    }

    private val executor: ExecutorService = Executors.newCachedThreadPool()

    fun generateReply(
        engineType: String,
        apiKey: String,
        model: String,
        accountId: String = "",
        senderName: String,
        incomingMessages: List<String>,
        systemPrompt: String,
        conversationHistory: List<ConversationHistory.ChatMessage> = emptyList(),
        callback: (String?, PhiLocalService.AiUsage?) -> Unit
    ) {
        if (apiKey.isBlank()) {
            Log.e(TAG, "API key is missing for engine: $engineType")
            callback(null, PhiLocalService.AiUsage(error = "API key missing for $engineType"))
            return
        }

        executor.execute {
            try {
                val combinedMessage = incomingMessages.joinToString("\n") { it }
                if (combinedMessage.isBlank()) {
                    Log.e(TAG, "Incoming message batch is empty ($engineType)")
                    callback(null, PhiLocalService.AiUsage(error = "Empty incoming message"))
                    return@execute
                }

                val effectiveSender = if (senderName.isBlank()) "the user" else senderName
                val formattedSystemPrompt =
                    CloudAiRequestBuilder.buildFormattedSystemPrompt(systemPrompt, effectiveSender)

                logRequestDebug(engineType, model, formattedSystemPrompt, combinedMessage, effectiveSender)

                val result = when (engineType) {
                    "groq_api" -> callOpenAiCompatible(
                        endpoint = "https://api.groq.com/openai/v1/chat/completions",
                        apiKey = apiKey,
                        model = CloudAiModel.normalizeGroqModel(model),
                        systemPrompt = formattedSystemPrompt,
                        incomingMessage = combinedMessage,
                        senderName = effectiveSender,
                        history = conversationHistory,
                        provider = "groq_api",
                    )
                    "cloudflare_api" -> {
                        if(!Regex("^[a-fA-F0-9]{32}$").matches(accountId))
                            CloudAiResult(null,PhiLocalService.AiUsage(error="Cloudflare account ID missing or invalid"))
                        else callOpenAiCompatible(
                            endpoint="https://api.cloudflare.com/client/v4/accounts/$accountId/ai/v1/chat/completions",
                            apiKey=apiKey,model=model,systemPrompt=formattedSystemPrompt,
                            incomingMessage=combinedMessage,senderName=effectiveSender,
                            history=conversationHistory,provider="cloudflare_api")
                    }
                    "gemini_api" -> callGemini(
                        apiKey = apiKey,
                        model = CloudAiModel.normalizeGeminiModel(model),
                        systemPrompt = formattedSystemPrompt,
                        incomingMessage = combinedMessage,
                        senderName = effectiveSender,
                        history = conversationHistory
                    )
                    else -> CloudAiResult(null, PhiLocalService.AiUsage(error = "Unknown engine type: $engineType"))
                }

                if (result.usage.error != null || result.reply.isNullOrBlank()) {
                    Log.e(TAG, "Cloud AI call failed ($engineType): ${result.usage.error}")
                    callback(null, result.usage)
                    return@execute
                }

                Log.d(TAG, "Cloud AI raw response ($engineType): '${result.reply.take(300)}'")

                val cleanReply = postProcess(result.reply, effectiveSender, combinedMessage)
                if (cleanReply.isNotBlank()) {
                    Log.d(TAG, "Cloud AI ($engineType) final reply: '$cleanReply'")
                    callback(cleanReply, result.usage)
                } else {
                    Log.w(TAG, "Clean reply is blank after postProcess ($engineType)")
                    callback(null, result.usage.copy(error = "Empty response after processing"))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Cloud AI exception ($engineType)", e)
                callback(null, PhiLocalService.AiUsage(error = e.message))
            }
        }
    }

    private fun logRequestDebug(
        engineType: String,
        model: String,
        systemPrompt: String,
        userMessage: String,
        senderName: String,
    ) {
        Log.d(
            TAG,
            "AI request provider=$engineType model=$model sender=$senderName " +
                "userMessageLen=${userMessage.length}"
        )
        Log.d(TAG, "Pipeline event")
        Log.d(
            TAG,
            "AI systemPrompt (${systemPrompt.length} chars): ${systemPrompt.take(400)}"
        )
    }

    data class CloudAiResult(
        val reply: String?,
        val usage: PhiLocalService.AiUsage,
    )

    private fun parseResetTimeSeconds(resetStr: String?, retryAfter: Int?): Int {
        if (retryAfter != null && retryAfter > 0) return retryAfter
        if (resetStr.isNullOrBlank()) return 0
        val trimmed = resetStr.trim().lowercase()
        trimmed.toIntOrNull()?.let { return it }
        trimmed.toDoubleOrNull()?.let { return it.toInt() }

        var totalSeconds = 0
        val hourMatch = Regex("""(\d+)\s*h""").find(trimmed)
        val minMatch = Regex("""(\d+)\s*m(?!s)""").find(trimmed)
        val secMatch = Regex("""(\d+(?:\.\d+)?)\s*s""").find(trimmed)

        hourMatch?.groupValues?.get(1)?.toIntOrNull()?.let { totalSeconds += it * 3600 }
        minMatch?.groupValues?.get(1)?.toIntOrNull()?.let { totalSeconds += it * 60 }
        secMatch?.groupValues?.get(1)?.toDoubleOrNull()?.let { totalSeconds += it.toInt() }

        return totalSeconds
    }

    private fun callOpenAiCompatible(
        endpoint: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        incomingMessage: String,
        senderName: String,
        history: List<ConversationHistory.ChatMessage>,
        provider: String = "",
    ): CloudAiResult {
        var conn: HttpURLConnection? = null
        try {
            val url = URL(endpoint)
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.connectTimeout = 15_000
            conn.readTimeout = 20_000
            conn.doOutput = true

            val payload = CloudAiRequestBuilder.buildOpenAiCompatiblePayload(
                model = model,
                systemPrompt = systemPrompt,
                incomingMessage = incomingMessage,
                senderName = senderName,
                history = history,
                provider = provider,
            )

            val writer = OutputStreamWriter(conn.outputStream, Charsets.UTF_8)
            writer.write(payload.toString())
            writer.flush()
            writer.close()

            val statusCode = conn.responseCode

            // Extract rate limit headers (present on both 200 OK and 429 Too Many Requests)
            val limitReq = conn.getHeaderField("x-ratelimit-limit-requests")?.toIntOrNull()
                ?: conn.getHeaderField("x-ratelimit-limit-requests-day")?.toIntOrNull()
            val remReq = conn.getHeaderField("x-ratelimit-remaining-requests")?.toIntOrNull()
                ?: conn.getHeaderField("x-ratelimit-remaining-requests-day")?.toIntOrNull()
            val limitTokens = conn.getHeaderField("x-ratelimit-limit-tokens")?.toIntOrNull()
                ?: conn.getHeaderField("x-ratelimit-limit-tokens-minute")?.toIntOrNull()
            val remTokens = conn.getHeaderField("x-ratelimit-remaining-tokens")?.toIntOrNull()
                ?: conn.getHeaderField("x-ratelimit-remaining-tokens-minute")?.toIntOrNull()
            val resetReq = conn.getHeaderField("x-ratelimit-reset-requests")
            val retryAfter = conn.getHeaderField("retry-after")?.toIntOrNull()
            val resetSec = parseResetTimeSeconds(resetReq, retryAfter)

            if (statusCode == 200) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8))
                val responseStr = reader.readText()
                reader.close()

                val json = JSONObject(responseStr)
                val choices = json.optJSONArray("choices")
                val firstChoice = choices?.optJSONObject(0)
                val messageObj = firstChoice?.optJSONObject("message")
                var text = messageObj?.optString("content", "")?.trim()

                // Only check legacy "text" field if content is missing.
                // NEVER fall back to reasoning/thinking fields (reasoning_content/reasoning)
                // because those contain internal deliberation, not user-facing replies.
                if (text.isNullOrBlank()) {
                    text = firstChoice?.optString("text", "")?.trim()
                }

                val usageObj = json.optJSONObject("usage")
                val totalTokens = usageObj?.optInt("total_tokens", 0) ?: 0
                val isLimitReached = (remReq != null && remReq <= 0) || (remTokens != null && remTokens <= 0)

                if (text.isNullOrBlank()) {
                    Log.w(TAG, "Empty content in API response: ${responseStr.take(400)}")
                    return CloudAiResult(
                        reply = null,
                        usage = PhiLocalService.AiUsage(
                            tokensUsed = totalTokens,
                            tokensRemaining = remTokens ?: 0,
                            tokensLimit = limitTokens ?: 0,
                            resetInSeconds = resetSec,
                            error = "Empty content in API response",
                            requestsRemaining = remReq,
                            requestsLimit = limitReq,
                            isLimitReached = isLimitReached,
                        )
                    )
                }

                return CloudAiResult(
                    reply = text,
                    usage = PhiLocalService.AiUsage(
                        tokensUsed = totalTokens,
                        tokensRemaining = remTokens ?: 0,
                        tokensLimit = limitTokens ?: 0,
                        resetInSeconds = resetSec,
                        requestsRemaining = remReq,
                        requestsLimit = limitReq,
                        isLimitReached = isLimitReached,
                    )
                )
            } else {
                val errorStream = conn.errorStream
                val errorText = if (errorStream != null) {
                    BufferedReader(InputStreamReader(errorStream, Charsets.UTF_8)).readText()
                } else "HTTP Error $statusCode"

                val is429 = statusCode == 429
                val isQuotaError = is429 ||
                    errorText.contains("rate_limit", ignoreCase = true) ||
                    errorText.contains("quota", ignoreCase = true) ||
                    errorText.contains("exceeded", ignoreCase = true)

                val parsedLimit = limitReq ?: Regex("""Limit\s*[:=]?\s*(\d+)""", RegexOption.IGNORE_CASE)
                    .find(errorText)?.groupValues?.get(1)?.toIntOrNull()

                val effectiveRemaining = if (isQuotaError) 0 else remReq

                Log.d(TAG, "Pipeline event")
                return CloudAiResult(
                    reply = null,
                    usage = PhiLocalService.AiUsage(
                        tokensUsed = 0,
                        tokensRemaining = remTokens ?: 0,
                        tokensLimit = limitTokens ?: 0,
                        resetInSeconds = resetSec,
                        error = "HTTP $statusCode: ${errorText.take(300)}",
                        requestsRemaining = effectiveRemaining,
                        requestsLimit = parsedLimit,
                        isLimitReached = isQuotaError,
                    )
                )
            }
        } catch (e: Exception) {
            return CloudAiResult(
                reply = null,
                usage = PhiLocalService.AiUsage(error = e.message)
            )
        } finally {
            conn?.disconnect()
        }
    }

    private fun callGemini(
        apiKey: String,
        model: String,
        systemPrompt: String,
        incomingMessage: String,
        senderName: String,
        history: List<ConversationHistory.ChatMessage>
    ): CloudAiResult {
        var conn: HttpURLConnection? = null
        try {
            val endpoint =
                "https://generativelanguage.googleapis.com/v1/models/$model:generateContent?key=$apiKey"
            val url = URL(endpoint)
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.connectTimeout = 15_000
            conn.readTimeout = 20_000
            conn.doOutput = true

            val payload = CloudAiRequestBuilder.buildGeminiPayload(
                systemPrompt = systemPrompt,
                incomingMessage = incomingMessage,
                senderName = senderName,
                history = history,
            )

            val writer = OutputStreamWriter(conn.outputStream, Charsets.UTF_8)
            writer.write(payload.toString())
            writer.flush()
            writer.close()

            val statusCode = conn.responseCode
            if (statusCode == 200) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8))
                val responseStr = reader.readText()
                reader.close()

                val json = JSONObject(responseStr)
                val candidates = json.optJSONArray("candidates")
                val firstCandidate = candidates?.optJSONObject(0)
                val contentObj = firstCandidate?.optJSONObject("content")
                val parts = contentObj?.optJSONArray("parts")
                val text = parts?.optJSONObject(0)?.optString("text", "")?.trim()

                if (text.isNullOrBlank()) {
                    return CloudAiResult(
                        reply = null,
                        usage = PhiLocalService.AiUsage(error = "Empty content in Gemini response")
                    )
                }

                val usageMetadata = json.optJSONObject("usageMetadata")
                val totalTokens = usageMetadata?.optInt("totalTokenCount", 0) ?: 0

                return CloudAiResult(
                    reply = text,
                    usage = PhiLocalService.AiUsage(tokensUsed = totalTokens, isLimitReached = false)
                )
            } else {
                val errorStream = conn.errorStream
                val errorText = if (errorStream != null) {
                    BufferedReader(InputStreamReader(errorStream, Charsets.UTF_8)).readText()
                } else "HTTP Error $statusCode"

                val is429 = statusCode == 429
                val isQuotaError = is429 ||
                    errorText.contains("RESOURCE_EXHAUSTED", ignoreCase = true) ||
                    errorText.contains("Quota exceeded", ignoreCase = true)

                val parsedLimit = Regex("""limit\s*[:=]?\s*(\d+)""", RegexOption.IGNORE_CASE)
                    .find(errorText)?.groupValues?.get(1)?.toIntOrNull()

                Log.d(TAG, "Pipeline event")
                return CloudAiResult(
                    reply = null,
                    usage = PhiLocalService.AiUsage(
                        tokensUsed = 0,
                        error = "HTTP $statusCode: ${errorText.take(300)}",
                        requestsRemaining = if (isQuotaError) 0 else null,
                        requestsLimit = parsedLimit,
                        isLimitReached = isQuotaError,
                    )
                )
            }
        } catch (e: Exception) {
            return CloudAiResult(
                reply = null,
                usage = PhiLocalService.AiUsage(error = e.message)
            )
        } finally {
            conn?.disconnect()
        }
    }

    private fun postProcess(text: String, senderName: String, incomingMessage: String): String {
        return AiReplyCleaner.clean(text, senderName, incomingMessage)
    }
}
