package com.replier.replier.service

/** App-supplied notification evidence, never display names or AI guesses. */
object ChatTypePolicy {
    enum class Kind { DIRECT, GROUP, SUMMARY, UNKNOWN }
    data class Evidence(
        val supportedPackage: Boolean,
        val summary: Boolean = false,
        val explicitGroup: Boolean? = null,
        val messagingStyle: Boolean = false,
        val styleGroup: Boolean? = null,
        val hasConversationTitle: Boolean = false,
        val distinctSenders: Int = 0,
        val malformed: Boolean = false,
    )
    fun classify(e: Evidence): Kind = when {
        !e.supportedPackage || e.malformed -> Kind.UNKNOWN
        e.summary -> Kind.SUMMARY
        e.explicitGroup == true || e.styleGroup == true ||
            e.hasConversationTitle || e.distinctSenders > 1 -> Kind.GROUP
        // An absent boolean is NOT false. One observed participant alone is not
        // proof: a group may have only one sender in its current notification.
        e.explicitGroup == false && e.messagingStyle && e.styleGroup == false -> Kind.DIRECT
        else -> Kind.UNKNOWN
    }
}

/** A fresh DIRECT classification AND an original stable identity are necessary
 * at every boundary. Notification bundling/groupKey is intentionally not used. */
class DirectChatGate {
    data class Target(val packageName: String, val key: String,
        val shortcut: String?, val tag: String?, val id: Int, val userId: Int = 0) {
        val stable: Boolean get() = !shortcut.isNullOrBlank() || !tag.isNullOrBlank()
        fun sameConversation(other: Target): Boolean {
            if (packageName != other.packageName || userId != other.userId) return false
            if (!shortcut.isNullOrBlank()) return shortcut == other.shortcut
            // Never downgrade a missing/changed shortcut to tag or display name.
            return other.shortcut.isNullOrBlank() && !tag.isNullOrBlank() && tag == other.tag && id == other.id
        }
    }
    private val admitted = linkedMapOf<String, Target>()
    @Synchronized fun record(target: Target, kind: ChatTypePolicy.Kind): List<Target> {
        val revoked = admitted.values.filter {
            it.key == target.key || (kind != ChatTypePolicy.Kind.DIRECT && it.sameConversation(target))
        }
        revoked.forEach { admitted.remove(it.key) }
        if (kind == ChatTypePolicy.Kind.DIRECT && target.stable) {
            admitted[target.key] = target
            // Bounded safety cache. Eviction refuses a future send, never widens it.
            while (admitted.size > 512) admitted.remove(admitted.keys.first())
        }
        return revoked.filter { kind != ChatTypePolicy.Kind.DIRECT || !it.sameConversation(target) }
    }
    @Synchronized fun permits(originalKey: String, candidate: Target, kind: ChatTypePolicy.Kind): Boolean {
        val original = admitted[originalKey] ?: return false
        return kind == ChatTypePolicy.Kind.DIRECT && candidate.stable && original.sameConversation(candidate)
    }
    @Synchronized fun original(key: String): Target? = admitted[key]
    @Synchronized fun clear() = admitted.clear()
}
