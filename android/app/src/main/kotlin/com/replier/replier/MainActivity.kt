package com.replier.replier

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CONTROL = "replier/control"
    private val EVENTS = "replier/events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ReplierNotificationListener.sink = events
                    ReplierNotificationListener.flushToSink()
                }

                override fun onCancel(arguments: Any?) {
                    ReplierNotificationListener.sink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "drainEvents" -> result.success(ReplierNotificationListener.drainBuffer())
                    "permissionStatus" -> result.success(
                        mapOf(
                            "notification" to hasNotificationAccess(),
                            "accessibility" to hasAccessibilityAccess()
                        )
                    )
                    "openNotificationAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "sendReply" -> result.success(
                        ReplierNotificationListener.replyInline(
                            this,
                            call.argument<String>("key") ?: "",
                            call.argument<String>("text") ?: ""
                        )
                    )
                    "openAndSend" -> {
                        if (!hasAccessibilityAccess()) {
                            result.success("no_accessibility")
                        } else {
                            result.success(
                                ReplierNotificationListener.openChatAndQueueSend(
                                    this,
                                    call.argument<String>("key") ?: "",
                                    call.argument<String>("text") ?: ""
                                )
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The listener service lives and dies with the system, but warm the
        // class so its queue exists before the first notification lands.
        ReplierNotificationListener.warm()
    }

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return enabled.contains(packageName)
    }

    private fun hasAccessibilityAccess(): Boolean {
        val expected = ComponentName(this, ReplierAccessibilityService::class.java)
            .flattenToString()
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expected, ignoreCase = true)) return true
        }
        return false
    }
}
