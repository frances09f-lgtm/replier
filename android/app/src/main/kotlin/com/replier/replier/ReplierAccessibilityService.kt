package com.replier.replier

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/// Last-resort sender for apps without an inline-reply notification action.
/// V1 scope: after the chat is opened by the notification's content intent,
/// find the message field, set the text, tap a send-like node. Best-effort
/// and honest: if the field or button is not found, nothing is typed and
/// the app already told the user to paste manually.
class ReplierAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile private var pendingText: String? = null
        @Volatile private var attempts = 0

        fun queueSend(text: String) {
            pendingText = text
            attempts = 0
        }

        fun clearQueue() {
            pendingText = null
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!MasterPause.enabled(this)) { clearQueue(); return }
        if (LegacyMigration.blocked(this)) { clearQueue(); return }
        val text = pendingText ?: return
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) return
        if (attempts++ > 6) { // the chat had its chance; stop poking the UI
            clearQueue()
            return
        }
        val root = rootInActiveWindow ?: return

        val edit = findFirstEditText(root)
        if (edit != null) {
            val args = Bundle()
            args.putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text
            )
            if (!MasterPause.enabled(this)) { clearQueue(); return }
            edit.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            val send = findSendNode(root)
            if (send != null) {
                if (!MasterPause.enabled(this)) { clearQueue(); return }
                send.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                clearQueue()
                return
            }
        }
        root.recycle()
    }

    private fun findFirstEditText(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.className?.toString()?.contains("EditText") == true) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val hit = findFirstEditText(child)
            if (hit != null) return hit
        }
        return null
    }

    private fun findSendNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val desc = node.contentDescription?.toString()?.lowercase() ?: ""
        val label = node.text?.toString()?.lowercase() ?: ""
        if (node.isClickable && (desc.contains("send") || label == "send")) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val hit = findSendNode(child)
            if (hit != null) return hit
        }
        return null
    }

    override fun onInterrupt() {
        clearQueue()
    }
}
