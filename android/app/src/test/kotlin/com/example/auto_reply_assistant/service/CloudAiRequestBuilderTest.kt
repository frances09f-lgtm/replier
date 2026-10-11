package com.replier.replier.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudAiRequestBuilderTest {

    @Test
    fun openAiPayload_includesSystemPromptAndIncomingMessage() {
        val system = "You are an AI assistant generating an appropriate reply."
        val formatted = CloudAiRequestBuilder.buildFormattedSystemPrompt(system, "Alex")
        val payload = CloudAiRequestBuilder.buildOpenAiCompatiblePayload(
            model = "llama-3.1-8b-instant",
            systemPrompt = formatted,
            incomingMessage = "Where are you?",
            senderName = "Alex",
        )

        val messages = payload.getJSONArray("messages")
        assertEquals("system", messages.getJSONObject(0).getString("role"))
        assertTrue(messages.getJSONObject(0).getString("content").contains(system))

        val user = messages.getJSONObject(messages.length() - 1)
        assertEquals("user", user.getString("role"))
        assertEquals("Alex: Where are you?", user.getString("content"))
    }

    @Test
    fun geminiPayload_includesSystemInstructionAndUserMessage() {
        val formatted = CloudAiRequestBuilder.buildFormattedSystemPrompt("My prompt", "Sam")
        val payload = CloudAiRequestBuilder.buildGeminiPayload(
            systemPrompt = formatted,
            incomingMessage = "Where are you?",
            senderName = "Sam",
        )

        val sys = payload.getJSONObject("systemInstruction")
            .getJSONArray("parts")
            .getJSONObject(0)
            .getString("text")
        assertTrue(sys.contains("My prompt"))

        val contents = payload.getJSONArray("contents")
        val last = contents.getJSONObject(contents.length() - 1)
        val text = last.getJSONArray("parts").getJSONObject(0).getString("text")
        assertEquals("Sam: Where are you?", text)
    }

    @Test
    fun openAiPayload_groqReasoningModel_hidesReasoning() {
        val payload = CloudAiRequestBuilder.buildOpenAiCompatiblePayload(
            model = "openai/gpt-oss-20b",
            systemPrompt = "System",
            incomingMessage = "Hi",
            senderName = "Alex",
            provider = "groq_api",
        )

        assertEquals("hidden", payload.getString("reasoning_format"))
        assertEquals("low", payload.getString("reasoning_effort"))
        assertEquals(80, payload.getInt("max_tokens"))
    }
}
