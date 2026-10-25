package com.replier.replier.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AiReplyCleanerTest {

    @Test
    fun stripsThinkTags_returnsActualReply() {
        val raw = "<think>\nThe user is greeting us. We should say hi.\n</think>\nHey there!"
        val cleaned = AiReplyCleaner.clean(raw, senderName = "Maya", incomingMessage = "Hello")
        assertEquals("Hey there!", cleaned)
    }

    @Test
    fun stripsThoughtTags_returnsActualReply() {
        val raw = "<thought>Need a quick reply.</thought>Yes, on my way."
        val cleaned = AiReplyCleaner.clean(raw, senderName = "Maya", incomingMessage = "Coming?")
        assertEquals("Yes, on my way.", cleaned)
    }

    @Test
    fun unclosedThinkTag_returnsEmpty() {
        val raw = "<think>\nThe user says something and I am still thinking about it without ending"
        val cleaned = AiReplyCleaner.clean(raw, senderName = "Maya", incomingMessage = "Hello")
        assertEquals("", cleaned)
    }

    @Test
    fun pureReasoningCommentary_discarded1() {
        // Exact raw output from user's logs
        val raw = "The user says: \"Kiti un ahe baher\". That is Marathi: \"How much is outside?\" " +
            "Might be \"How much is the rent outside?\" Or \"How many units outside?\" " +
            "But it's ambiguous. The user is asking \"Kiti un ahe baher\". It likely means \"How much is it outside?\" " +
            "But we don't know context. But we must reply as the user"
        val cleaned = AiReplyCleaner.clean(raw, senderName = "abheiee: Maya", incomingMessage = "Kiti un ahe baher")
        assertEquals("", cleaned)
    }

    @Test
    fun pureReasoningCommentary_discarded2() {
        // Exact raw output from user's logs
        val raw = "We have a conversation. The user says \"abheiee: Maya: Dok dukaly\". " +
            "This is likely a phrase in Marathi? \"Dok dukaly\" maybe means \"What is that?\" " +
            "Or \"What's going on?\" But the instructions: reply as the user, short, casual, 1-5 words. " +
            "He doesn't like unnecessary conversation. So we reply something short."
        val cleaned = AiReplyCleaner.clean(raw, senderName = "abheiee: Maya", incomingMessage = "Dok dukaly")
        assertEquals("", cleaned)
    }

    @Test
    fun thinkingHeaderPrefix_stripped() {
        val raw = "Thinking Process:\nLet's keep it simple.\n\nNot tonight."
        val cleaned = AiReplyCleaner.clean(raw, senderName = "abheiee: Maya", incomingMessage = "Mg atta video call kr")
        assertEquals("Not tonight.", cleaned)
    }

    @Test
    fun normalReplies_preserved() {
        assertEquals("Not tonight.", AiReplyCleaner.clean("Not tonight."))
        assertEquals("Nice!", AiReplyCleaner.clean("\"Nice!\""))
        assertEquals("the user", AiReplyCleaner.clean("the user"))
        assertEquals("Still short.", AiReplyCleaner.clean("Still short."))
    }

    @Test
    fun rolePrefixes_stripped() {
        val raw = "Assistant: I'm good."
        assertEquals("I'm good.", AiReplyCleaner.clean(raw))

        val raw2 = "abheiee: Maya: Dok dukalay"
        assertEquals("Dok dukalay", AiReplyCleaner.clean(raw2, senderName = "abheiee: Maya"))
    }

    @Test
    fun echoedIncomingMessage_discarded() {
        val cleaned = AiReplyCleaner.clean("Kiti un ahe baher", incomingMessage = "Kiti un ahe baher")
        assertEquals("", cleaned)
    }

    @Test
    fun runOnGenerationAfterEot_isCutNotConcatenated() {
        val raw = "Ok, cool.<|eot_id|>Ok, cool.<|eot_id|>"
        assertEquals("Ok, cool.", AiReplyCleaner.clean(raw, senderName = "Tab", incomingMessage = "On it."))
    }

    @Test
    fun leadingAssistantHeader_thenRunOnTurn_keepsFirstReplyOnly() {
        val raw = "<|start_header_id|>assistant<|end_header_id|>\n\nSounds good!<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\nSounds good!"
        assertEquals("Sounds good!", AiReplyCleaner.clean(raw, senderName = "Tab", incomingMessage = "Done"))
    }

    @Test
    fun exactSentenceRepeat_isCollapsed() {
        assertEquals("Ok, cool.", AiReplyCleaner.clean("Ok, cool.Ok, cool.", senderName = "Tab", incomingMessage = "hi"))
        assertEquals("Sure thing!", AiReplyCleaner.clean("Sure thing! Sure thing!", senderName = "Tab", incomingMessage = "hi"))
    }

    @Test
    fun casualDoubles_areKept() {
        assertEquals("haha haha", AiReplyCleaner.clean("haha haha", senderName = "Tab", incomingMessage = "lol"))
        assertEquals("bye bye", AiReplyCleaner.clean("bye bye", senderName = "Tab", incomingMessage = "cya"))
    }

    // Realistic raw outputs from the on-phone Llama 3.2 1B model (llama.cpp may or may not render
    // special tokens as text). None of these may come back empty.

    @Test
    fun llama_leadingEotThenReply_keepsReply() {
        val raw = "<|eot_id|>\n\nHaan, 5 min mein aata hoon.<|eot_id|>"
        assertEquals("Haan, 5 min mein aata hoon.", AiReplyCleaner.clean(raw, senderName = "Maya", incomingMessage = "Kab aa rahe ho?"))
    }

    @Test
    fun llama_beginAndHeaderPrefix_keepsReply() {
        val raw = "<|begin_of_text|><|start_header_id|>assistant<|end_header_id|>\n\nSure, see you at 7!<|eot_id|>"
        assertEquals("Sure, see you at 7!", AiReplyCleaner.clean(raw, senderName = "Maya", incomingMessage = "Dinner at 7?"))
    }

    @Test
    fun llama_headerTokensDecodedEmpty_bareRoleLineIsDropped() {
        val raw = "assistant\n\nOn my way!"
        assertEquals("On my way!", AiReplyCleaner.clean(raw, senderName = "Maya", incomingMessage = "Where are you?"))
    }

    @Test
    fun llama_runOnSecondTurnWithDecodedEmptyTokens_keepsFirstReply() {
        val raw = "Ok, cool.assistant\n\nOk, cool. Anything else?"
        assertEquals("Ok, cool.", AiReplyCleaner.clean(raw, senderName = "Maya", incomingMessage = "Done"))
    }

    @Test
    fun llama_trailingSecondUserTurn_isCut() {
        val raw = "Yes, I'll call you back.<|eot_id|><|start_header_id|>user<|end_header_id|>\n\nMaya: ok"
        assertEquals("Yes, I'll call you back.", AiReplyCleaner.clean(raw, senderName = "Maya", incomingMessage = "Call me?"))
    }

    @Test
    fun llama_eomAndEndOfTextTokens_areCut() {
        assertEquals("Thanks!", AiReplyCleaner.clean("Thanks!<|eom_id|>Thanks!", senderName = "Maya", incomingMessage = "Here"))
        assertEquals("Thanks!", AiReplyCleaner.clean("Thanks!<|end_of_text|>", senderName = "Maya", incomingMessage = "Here"))
    }

    @Test
    fun plainReplyWithoutTokens_isUnchanged() {
        assertEquals("Busy right now, will text later.", AiReplyCleaner.clean("Busy right now, will text later.", senderName = "Maya", incomingMessage = "Free?"))
    }
}
