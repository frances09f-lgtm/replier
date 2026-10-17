package com.replier.replier.service

import org.junit.Assert.*
import org.junit.Test

class ChatTypePolicyTest {
    private fun direct() = ChatTypePolicy.Evidence(true, explicitGroup = false,
        messagingStyle = true, styleGroup = false, distinctSenders = 1)
    private val d get() = ChatTypePolicy.Kind.DIRECT
    private val g get() = ChatTypePolicy.Kind.GROUP
    private val u get() = ChatTypePolicy.Kind.UNKNOWN
    private fun target(key: String = "direct", shortcut: String? = "contact-1", tag: String? = "chat-1", pkg: String = "com.whatsapp", id: Int = 1) =
        DirectChatGate.Target(pkg, key, shortcut, tag, id)

    @Test fun explicitDirectMessagingStylePermitted() = assertEquals(d, ChatTypePolicy.classify(direct()))
    @Test fun trueGroupFlagAlwaysRejected() = assertEquals(g, ChatTypePolicy.classify(direct().copy(explicitGroup = true)))
    @Test fun falseFlagConflictingStyleIsGroup() = assertEquals(g, ChatTypePolicy.classify(direct().copy(styleGroup = true)))
    @Test fun groupTitleConflictsWithFalseFlag() = assertEquals(g, ChatTypePolicy.classify(direct().copy(hasConversationTitle = true)))
    @Test fun multipleStableSendersAreGroup() = assertEquals(g, ChatTypePolicy.classify(direct().copy(distinctSenders = 2)))
    @Test fun missingFlagIsNotDirect() = assertEquals(u, ChatTypePolicy.classify(direct().copy(explicitGroup = null)))
    @Test fun oneVisibleSenderDoesNotProveDirect() = assertEquals(u, ChatTypePolicy.classify(direct().copy(explicitGroup = null, styleGroup = false)))
    @Test fun noMessagingStyleIsUnknown() = assertEquals(u, ChatTypePolicy.classify(direct().copy(messagingStyle = false, styleGroup = null)))
    @Test fun missingStyleTypeIsUnknown() = assertEquals(u, ChatTypePolicy.classify(direct().copy(styleGroup = null)))
    @Test fun summaryIsNotConversation() = assertEquals(ChatTypePolicy.Kind.SUMMARY, ChatTypePolicy.classify(direct().copy(summary = true)))
    @Test fun malformedMetadataFailsClosed() = assertEquals(u, ChatTypePolicy.classify(direct().copy(malformed = true)))
    @Test fun unsupportedPackageFailsClosed() = assertEquals(u, ChatTypePolicy.classify(direct().copy(supportedPackage = false)))
    @Test fun ordinaryBundledChildIsNotSummary() {
        // Android groupKey is deliberately not an input to the policy.
        assertEquals(d, ChatTypePolicy.classify(direct().copy(summary = false)))
    }
    @Test fun groupWithSingleVisibleParticipantStillGroup() = assertEquals(g, ChatTypePolicy.classify(direct().copy(explicitGroup = true)))
    @Test fun directDoesNotRequireSenderDisplayName() = assertEquals(d, ChatTypePolicy.classify(direct().copy(distinctSenders = 0)))
    @Test fun unadmittedKeyCannotSend() = assertFalse(DirectChatGate().permits("direct", target(), d))
    @Test fun admittedDirectAllowsSameConversation() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertTrue(gate.permits(a.key, a, d))
    }
    @Test fun directReceiptCannotAuthorizeGroupRepost() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertFalse(gate.permits(a.key, a, g))
        assertEquals(listOf(a), gate.record(a, g)); assertNull(gate.original(a.key))
    }
    @Test fun missingMetadataRevokesOldAdmission() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d); gate.record(a, u)
        assertFalse(gate.permits(a.key, a, d))
    }
    @Test fun summaryRevokesOnlyItsOwnIdentity() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        gate.record(target("summary", "summary-id", "summary"), ChatTypePolicy.Kind.SUMMARY)
        assertTrue(gate.permits(a.key, a, d))
    }
    @Test fun packageCannotChangeOnExactKey() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertFalse(gate.permits(a.key, a.copy(packageName = "com.instagram.android"), d))
    }
    @Test fun shortcutCannotChangeOnExactKey() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertFalse(gate.permits(a.key, a.copy(shortcut = "group-id"), d))
    }
    @Test fun lostShortcutCannotFallBackToTag() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertFalse(gate.permits(a.key, a.copy(shortcut = null), d))
    }
    @Test fun tagAndIdWorkWhenNoShortcutWasAvailable() {
        val gate = DirectChatGate(); val a = target(shortcut = null); gate.record(a, d)
        assertTrue(gate.permits(a.key, a.copy(key = "replacement"), d))
        assertFalse(gate.permits(a.key, a.copy(tag = "other"), d))
        assertFalse(gate.permits(a.key, a.copy(id = 2), d))
    }
    @Test fun nullTagReusedIdNeverAdmitted() {
        val gate = DirectChatGate(); val a = target(shortcut = null, tag = null); gate.record(a, d)
        assertFalse(gate.permits(a.key, a, d))
    }
    @Test fun blankTagNeverAdmitted() {
        val gate = DirectChatGate(); val a = target(shortcut = null, tag = ""); gate.record(a, d)
        assertNull(gate.original(a.key))
    }
    @Test fun matchingNameAcrossDirectAndGroupHasNoEffect() {
        val gate = DirectChatGate(); val direct = target(); val group = target("group", "group-id", "group-tag")
        gate.record(direct, d); gate.record(group, g)
        assertTrue(gate.permits(direct.key, direct, d)); assertFalse(gate.permits(group.key, group, g))
    }
    @Test fun changedIdentityRevokesOldAttemptEvenIfStillDirect() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertEquals(listOf(a), gate.record(a.copy(shortcut = "new-contact"), d))
        assertFalse(gate.permits(a.key, a, d))
    }
    @Test fun newGroupKeyForSameIdentityRevokesDelayedDirect() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertEquals(listOf(a), gate.record(a.copy(key = "new-key"), g))
        assertFalse(gate.permits(a.key, a, d))
    }
    @Test fun sameDirectRepostDoesNotCancelAnalysis() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertTrue(gate.record(a, d).isEmpty()); assertTrue(gate.permits(a.key, a, d))
    }
    @Test fun groupsAndUnknownNeverStartQueueOrInference() {
        var starts = 0; val gate = DirectChatGate()
        listOf(g, u, ChatTypePolicy.Kind.SUMMARY).forEach { kind ->
            val a = target(); gate.record(a, kind)
            if (gate.permits(a.key, a, kind)) starts++
        }
        assertEquals(0, starts)
    }
    @Test fun revocationCancelsAnalysisSoLateCallbackCannotClaimSend() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        val attempts = AnalysisAttempts { 0L }; val attempt = attempts.begin("conversation", "Same name")
        gate.record(a, g).forEach { attempts.complete(attempt.id, "canceled") }
        assertFalse(attempts.isActive(attempt.id)); assertFalse(attempts.complete(attempt.id, "ready"))
        assertFalse(gate.permits(a.key, a, d))
    }
    @Test fun delayedAndApprovalRechecksRejectNewGroupType() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertTrue(gate.permits(a.key, a, d)) // generated/awaiting approval
        assertFalse(gate.permits(a.key, a, g)) // latest metadata at schedule/send
        assertFalse(gate.permits(a.key, a, u))
    }
    @Test fun restartingServiceLosesOldAdmissionRatherThanGuessing() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d); gate.clear()
        assertFalse(gate.permits(a.key, a, d))
    }
    @Test fun identityCannotCrossAndroidUserProfiles() {
        val gate = DirectChatGate(); val a = target(); gate.record(a, d)
        assertFalse(gate.permits(a.key, a.copy(userId = 10), d))
    }
    @Test fun gainingShortcutCannotUpgradeTagIdentitySilently() {
        val gate = DirectChatGate(); val a = target(shortcut = null); gate.record(a, d)
        assertFalse(gate.permits(a.key, a.copy(shortcut = "different-channel"), d))
    }
}
