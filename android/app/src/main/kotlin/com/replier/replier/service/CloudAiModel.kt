package com.replier.replier.service

object CloudAiModel {
    const val DEFAULT_GROQ_MODEL = "openai/gpt-oss-20b"
    const val DEFAULT_GEMINI_MODEL = "gemini-3.6-flash"

    private val groqReplacements = mapOf(
        "gemma2-9b-it" to DEFAULT_GROQ_MODEL,
        "gemma-7b-it" to DEFAULT_GROQ_MODEL,
        "llama-3.1-8b-instant" to DEFAULT_GROQ_MODEL,
        "llama-3.3-70b-versatile" to "openai/gpt-oss-120b",
        "llama3-8b-8192" to DEFAULT_GROQ_MODEL,
        "llama3-70b-8192" to "openai/gpt-oss-120b",
    )

    private val geminiReplacements = mapOf(
        "gemini-1.5-flash" to DEFAULT_GEMINI_MODEL,
        "gemini-1.5-flash-8b" to DEFAULT_GEMINI_MODEL,
        "gemini-1.5-flash-latest" to DEFAULT_GEMINI_MODEL,
        "gemini-1.5-pro" to DEFAULT_GEMINI_MODEL,
        "gemini-1.5-pro-latest" to DEFAULT_GEMINI_MODEL,
        "gemini-2.0-flash" to DEFAULT_GEMINI_MODEL,
        "gemini-2.0-flash-lite" to DEFAULT_GEMINI_MODEL,
        "gemini-2.5-flash" to DEFAULT_GEMINI_MODEL,
        "gemini-2.5-pro" to DEFAULT_GEMINI_MODEL,
    )

    fun normalizeGroqModel(model: String?): String {
        val trimmed = model?.trim().orEmpty()
        if (trimmed.isEmpty()) return DEFAULT_GROQ_MODEL
        return groqReplacements[trimmed] ?: trimmed
    }

    fun normalizeGeminiModel(model: String?): String {
        val trimmed = model?.trim().orEmpty()
        if (trimmed.isEmpty()) return DEFAULT_GEMINI_MODEL
        return geminiReplacements[trimmed] ?: trimmed
    }
}
