package com.replier.replier.service

import org.junit.Assert.*
import org.junit.Test

class AnalysisAttemptsTest {
    @Test fun overallDeadlineIncludesQueueAndLoad() {
        var clock = 1000L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("conversation", "Demo")
        clock += 2000 // batching
        clock += 30000 // native executor queue
        clock += 40000 // model load
        assertEquals(28000L, ledger.remaining(a.id))
        clock += 28000
        assertFalse(ledger.isActive(a.id))
        assertFalse(ledger.complete(a.id, "ready"))
        assertEquals("expired", ledger.snapshot().single().state)
    }

    @Test fun successImmediatelyBeforeLimitCanScheduleOnlyOnce() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("c", "Demo")
        clock = 99999
        assertTrue(ledger.complete(a.id, "ready"))
        assertFalse(ledger.complete(a.id, "ready"))
        clock = 100000
        ledger.expireDue()
        assertEquals("ready", ledger.snapshot().single().state)
        // Intentional reply delay/approval is outside the analysis ledger.
        assertFalse(ledger.isActive(a.id))
    }

    @Test fun deadlineIsExclusiveAndRejectsLateNativeCallback() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("c", "Demo")
        clock = 100000
        var schedules = 0
        if (ledger.complete(a.id, "ready")) schedules++
        clock += 500
        if (ledger.complete(a.id, "ready")) schedules++
        assertEquals(0, schedules)
        assertEquals("expired", ledger.snapshot().single().state)
    }

    @Test fun failureCleansActiveStateAndCannotBecomeReady() {
        val ledger = AnalysisAttempts { 500L }
        val a = ledger.begin("c", "Demo")
        assertTrue(ledger.complete(a.id, "failed"))
        assertFalse(ledger.isActive(a.id))
        assertFalse(ledger.complete(a.id, "ready"))
        assertEquals("failed", ledger.snapshot().single().state)
    }

    @Test fun overlappingAttemptsHaveIndependentBudgetsAndTerminalStates() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("one", "Same name")
        clock = 50000
        val b = ledger.begin("two", "Same name")
        clock = 100000
        ledger.expireDue()
        assertFalse(ledger.complete(a.id, "ready"))
        assertTrue(ledger.isActive(b.id))
        assertEquals(50000L, ledger.remaining(b.id))
        assertTrue(ledger.complete(b.id, "ready"))
    }

    @Test fun newerSameConversationInvalidatesOldResult() {
        val ledger = AnalysisAttempts { 0L }
        val a = ledger.begin("one", "Demo")
        val b = ledger.begin("one", "Demo")
        assertNotEquals(a.id, b.id)
        assertFalse(ledger.isActive(a.id))
        assertFalse(ledger.complete(a.id, "ready"))
        assertTrue(ledger.complete(b.id, "ready"))
    }

    @Test fun serviceShutdownInvalidatesEveryPendingResult() {
        val ledger = AnalysisAttempts { 0L }
        val a = ledger.begin("a", "Demo")
        val b = ledger.begin("b", "Demo")
        ledger.cancelAll()
        assertFalse(ledger.complete(a.id, "ready"))
        assertFalse(ledger.complete(b.id, "ready"))
        assertTrue(ledger.snapshot().all { it.state == "canceled" })
    }

    @Test fun terminalStatusExpiresWithoutChangingOtherActiveAttempts() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("a", "Demo")
        ledger.complete(a.id, "failed")
        clock = 1000
        val b = ledger.begin("b", "Demo")
        clock = 6000
        assertEquals(listOf(b.id), ledger.snapshot().map { it.id })
    }

    @Test fun keysKeepOriginalPackageAndConversationRatherThanDisplayName() {
        val a = AnalysisAttempts.conversationKey("com.whatsapp", "123", null, 1, "notification")
        val b = AnalysisAttempts.conversationKey("com.instagram.android", "123", null, 1, "notification")
        val c = AnalysisAttempts.conversationKey("com.whatsapp", "456", null, 1, "notification")
        assertNotEquals(a, b)
        assertNotEquals(a, c)
        assertEquals(a, AnalysisAttempts.conversationKey("com.whatsapp", "123", "new tag", 2, "new key"))
        assertNotEquals(AnalysisAttempts.conversationKey("pkg", null, "x", 1, "k"),
            AnalysisAttempts.conversationKey("pkg", null, "x", 2, "k"))
    }

    @Test fun expireAttemptFiresExactlyOnceForAnalysingAttempt() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("c", "Demo")
        clock = 100000
        assertTrue(ledger.expireAttempt(a.id))
        assertFalse(ledger.expireAttempt(a.id))
        assertEquals("expired", ledger.snapshot().single().state)
    }

    @Test fun expireAttemptDoesNotFireBeforeDeadline() {
        val ledger = AnalysisAttempts { 99999L }
        val a = ledger.begin("c", "Demo")
        assertFalse(ledger.expireAttempt(a.id))
        assertTrue(ledger.isActive(a.id))
        assertEquals("analysing", ledger.snapshot().single().state)
    }

    @Test fun expireAttemptNeverFiresAfterSuccess() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("c", "Demo")
        clock = 5000
        assertTrue(ledger.complete(a.id, "ready"))
        clock = 200000
        assertFalse(ledger.expireAttempt(a.id))
        assertEquals("ready", ledger.snapshot().single().state)
    }

    @Test fun expireAttemptNeverFiresAfterFailureOrCancel() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("a", "Demo")
        val b = ledger.begin("b", "Demo")
        assertTrue(ledger.complete(a.id, "failed"))
        ledger.cancelAll()
        clock = 200000
        assertFalse(ledger.expireAttempt(a.id))
        assertFalse(ledger.expireAttempt(b.id))
        assertEquals(listOf("failed", "canceled"), ledger.snapshot().map { it.state })
    }

    @Test fun expireAttemptRaceWithLateCompleteExpiresOnlyOnce() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("c", "Demo")
        clock = 100000
        // Late engine callback loses the race; expiry then fires exactly once.
        assertFalse(ledger.complete(a.id, "ready"))
        assertTrue(ledger.expireAttempt(a.id))
        assertFalse(ledger.expireAttempt(a.id))
        assertEquals("expired", ledger.snapshot().single().state)
    }

    @Test fun expireAttemptOnSupersededAttemptDoesNotFire() {
        var clock = 0L
        val ledger = AnalysisAttempts { clock }
        val a = ledger.begin("one", "Demo")
        val b = ledger.begin("one", "Demo")
        clock = 200000
        assertFalse(ledger.expireAttempt(a.id))
        assertTrue(ledger.expireAttempt(b.id))
    }
}
