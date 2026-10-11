package com.replier.replier.service

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SelfSentReplyGuardTest {
    private val sent = setOf("sahara.", "canberra.")

    @Test
    fun ignoresContactMessageThatMentionsPastReply() {
        assertFalse(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "Right! Canberra.\n\nNext:\nWhich country has the most time zones?",
                sender = "Meta AI",
                sentReplyTexts = sent,
            ),
        )
    }

    @Test
    fun detectsOwnOutgoingNotification() {
        assertTrue(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "Canberra.",
                sender = "You",
                sentReplyTexts = sent,
            ),
        )
    }

    @Test
    fun doesNotTreatContactExactReplyWordAsSelfSent() {
        assertFalse(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "Sahara.",
                sender = "Meta AI",
                sentReplyTexts = sent,
            ),
        )
    }

    // ── Own-message fixes ────────────────────────────────────────────────

    @Test
    fun treatsAnyYouSenderMessageAsSelfSentEvenWithoutMatch() {
        assertTrue(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "I typed this manually",
                sender = "You",
                sentReplyTexts = sent,
            ),
        )
    }

    @Test
    fun treatsSelfPrefixedGroupMessageAsSelfSent() {
        assertTrue(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "You: hello everyone",
                sender = "Family Group",
                sentReplyTexts = emptySet(),
            ),
        )
    }

    @Test
    fun detectsSameSenderEchoWithinWindow() {
        val now = 1_000_000L
        assertTrue(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "Sahara.",
                sender = "Rahul",
                sentRepliesForSender = mapOf("sahara." to (now - 5_000L)),
                nowMs = now,
            ),
        )
    }

    @Test
    fun ignoresEchoOutsideWindow() {
        val now = 1_000_000L
        assertFalse(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "Sahara.",
                sender = "Rahul",
                sentRepliesForSender = mapOf("sahara." to (now - 300_000L)),
                nowMs = now,
            ),
        )
    }

    @Test
    fun ignoresSameTextWhenWeNeverRepliedToThatSender() {
        val now = 1_000_000L
        assertFalse(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "Sahara.",
                sender = "Rahul",
                sentRepliesForSender = emptyMap(),
                nowMs = now,
            ),
        )
    }

    @Test
    fun detectsMultilineEchoWithReplyAsLastLine() {
        val now = 1_000_000L
        assertTrue(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "Hi\nSahara.",
                sender = "Rahul",
                sentRepliesForSender = mapOf("sahara." to (now - 5_000L)),
                nowMs = now,
            ),
        )
    }

    @Test
    fun ignoresContactMessageMerelyContainingReplyWord() {
        val now = 1_000_000L
        assertFalse(
            SelfSentReplyGuard.isSelfSentMessage(
                message = "Thanks Sahara.",
                sender = "Rahul",
                sentRepliesForSender = mapOf("sahara." to (now - 5_000L)),
                nowMs = now,
            ),
        )
    }
}
