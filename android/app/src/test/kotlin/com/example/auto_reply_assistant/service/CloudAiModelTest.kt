package com.replier.replier.service

import org.junit.Assert.assertEquals
import org.junit.Test

class CloudAiModelTest {
    @Test
    fun normalizeGroqModel_mapsRetiredGemma2() {
        assertEquals(
            CloudAiModel.DEFAULT_GROQ_MODEL,
            CloudAiModel.normalizeGroqModel("gemma2-9b-it"),
        )
    }

    @Test
    fun normalizeGeminiModel_mapsRetiredFlash20() {
        assertEquals(
            CloudAiModel.DEFAULT_GEMINI_MODEL,
            CloudAiModel.normalizeGeminiModel("gemini-2.0-flash"),
        )
    }
}
