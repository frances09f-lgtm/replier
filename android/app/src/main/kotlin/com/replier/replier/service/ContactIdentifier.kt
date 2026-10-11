package com.replier.replier.service

/**
 * Normalizes contact names and phone numbers for consistent allow/deny matching.
 */
object ContactIdentifier {

    /** Minimum digit count to treat an identifier as a phone number. */
    private const val MIN_PHONE_DIGITS = 7

    /**
     * Strip formatting and normalize Indian numbers to a canonical `91` + 10 digits form
     * when possible. Other international numbers keep all digits (no country rewrite).
     */
    fun normalizePhoneDigits(raw: String): String {
        var digits = raw.replace(Regex("[^0-9]"), "")
        if (digits.isEmpty()) return ""

        // 0-prefix local trunk (India): 0XXXXXXXXXX → 91XXXXXXXXXX
        if (digits.length == 11 && digits.startsWith("0")) {
            digits = "91" + digits.substring(1)
        }

        // +91 / 91 + 10-digit mobile
        if (digits.length == 12 && digits.startsWith("91")) {
            return digits
        }

        // 10-digit Indian mobile without country code
        if (digits.length == 10 && digits.all { it.isDigit() }) {
            return "91$digits"
        }

        return digits
    }

    /**
     * Normalize a contact identifier from notifications or saved lists.
     * Phone-like strings → [normalizePhoneDigits]; otherwise trimmed lowercase name.
     */
    fun normalizeIdentifier(identifier: String): String {
        val trimmed = identifier.trim()
        if (trimmed.isEmpty()) return ""

        val digitCount = trimmed.count { it.isDigit() }
        if (digitCount >= MIN_PHONE_DIGITS) {
            val normalized = normalizePhoneDigits(trimmed)
            if (normalized.isNotEmpty()) return normalized
        }

        return trimmed.lowercase()
    }

    fun identifiersMatch(a: String, b: String): Boolean {
        val na = normalizeIdentifier(a)
        val nb = normalizeIdentifier(b)
        if (na.isEmpty() || nb.isEmpty()) return false
        return na == nb
    }

    fun isBlacklisted(sender: String, blacklist: List<String>): Boolean {
        if (blacklist.isEmpty()) return false
        return blacklist.any { identifiersMatch(it, sender) }
    }

    fun isWhitelisted(sender: String, whitelist: List<String>): Boolean {
        if (whitelist.isEmpty()) return false
        return whitelist.any { identifiersMatch(it, sender) }
    }

    /**
     * @return true if auto-reply (rules or AI) may proceed for this sender.
     */
    fun isSenderAllowedForAutoReply(
        sender: String,
        whitelistEnabled: Boolean,
        whitelist: List<String>,
        blacklist: List<String>,
    ): Boolean {
        if (sender.isBlank()) return true
        if (isBlacklisted(sender, blacklist)) return false
        if (whitelistEnabled && whitelist.isNotEmpty() && !isWhitelisted(sender, whitelist)) {
            return false
        }
        return true
    }
}
