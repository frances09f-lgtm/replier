package com.replier.replier.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContactIdentifierTest {

    @Test
    fun phoneNormalization_indianFormatsMatch() {
        assertEquals(
            "919876543210",
            ContactIdentifier.normalizePhoneDigits("+91 98765 43210"),
        )
        assertEquals(
            "919876543210",
            ContactIdentifier.normalizePhoneDigits("9876543210"),
        )
        assertTrue(
            ContactIdentifier.identifiersMatch("+91 98765 43210", "919876543210"),
        )
    }

    @Test
    fun whitelist_blocksUnknownWhenEnabled() {
        assertFalse(
            ContactIdentifier.isSenderAllowedForAutoReply(
                sender = "Rahul",
                whitelistEnabled = true,
                whitelist = listOf("Priya"),
                blacklist = emptyList(),
            ),
        )
    }

    @Test
    fun blacklist_blocksBeforeAiWouldRun() {
        assertFalse(
            ContactIdentifier.isSenderAllowedForAutoReply(
                sender = "+91 9876543210",
                whitelistEnabled = false,
                whitelist = emptyList(),
                blacklist = listOf("9876543210"),
            ),
        )
    }
}
