package com.replier.replier.service

import java.util.UUID

/** Owns the entire analysis budget, including batching, queueing and model load.
 * Monotonic time is injected so device sleep and wall-clock changes are harmless.
 * Completion and expiry have one synchronized winner. No native inference needs
 * to be interruptible: an expired/superseded attempt can never claim delivery.
 */
class AnalysisAttempts(private val now: () -> Long) {
    companion object {
        const val LIMIT_MS = 100_000L
        const val TERMINAL_DISPLAY_MS = 6_000L
        fun conversationKey(pkg: String, shortcut: String?, tag: String?, id: Int?, key: String): String =
            // Length-prefixed components avoid delimiter collisions. Never use display names.
            listOf(pkg, if (!shortcut.isNullOrBlank()) "shortcut" else "notification",
                shortcut?.takeIf { it.isNotBlank() } ?: key,
                if (shortcut.isNullOrBlank()) tag.orEmpty() else "",
                if (shortcut.isNullOrBlank()) id?.toString().orEmpty() else "")
                .joinToString("") { "${it.length}:$it" }
    }
    data class Attempt(val id: String, val conversation: String, val sender: String,
        val started: Long, val deadline: Long, var state: String = "analysing",
        var finished: Long? = null)
    private val attempts = linkedMapOf<String, Attempt>()

    @Synchronized fun begin(conversation: String, sender: String): Attempt {
        attempts.values.filter { it.conversation == conversation && it.state == "analysing" }
            .forEach { finish(it, "canceled") }
        prune()
        val started = now()
        return Attempt(UUID.randomUUID().toString(), conversation, sender, started, started + LIMIT_MS)
            .also { attempts[it.id] = it }
    }
    @Synchronized fun isActive(id: String): Boolean = attempts[id]?.let {
        it.state == "analysing" && now() < it.deadline
    } ?: false
    @Synchronized fun remaining(id: String): Long = attempts[id]?.let {
        if (it.state == "analysing") (it.deadline - now()).coerceAtLeast(0) else 0
    } ?: 0
    @Synchronized fun complete(id: String, result: String): Boolean {
        require(result in listOf("ready", "failed", "canceled"))
        val a = attempts[id] ?: return false
        if (a.state != "analysing") return false
        if (now() >= a.deadline) { finish(a, "expired"); return false }
        finish(a, result)
        return true
    }
    @Synchronized fun expireDue() {
        attempts.values.filter { it.state == "analysing" && now() >= it.deadline }
            .forEach { finish(it, "expired") }
        prune()
    }
    @Synchronized fun expireAttempt(id: String): Boolean {
        val a = attempts[id] ?: return false
        if (a.state != "analysing" || now() < a.deadline) return false
        finish(a, "expired")
        return true
    }
    @Synchronized fun cancelAll() {
        attempts.values.filter { it.state == "analysing" }.forEach { finish(it, "canceled") }
    }
    @Synchronized fun snapshot(): List<Attempt> {
        expireDue()
        return attempts.values.map { it.copy() }
    }
    private fun finish(a: Attempt, result: String) { a.state = result; a.finished = now() }
    private fun prune() {
        attempts.entries.removeAll { it.value.finished?.let { end -> now() - end >= TERMINAL_DISPLAY_MS } ?: false }
    }
}
