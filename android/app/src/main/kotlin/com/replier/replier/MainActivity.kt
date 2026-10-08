package com.replier.replier

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.app.ActivityManager
import android.os.StatFs
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
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
                    "resources" -> {
                        val info = ActivityManager.MemoryInfo()
                        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
                        result.success(mapOf("availableRam" to info.availMem,
                            "totalRam" to info.totalMem, "lowMemory" to info.lowMemory,
                            "freeDisk" to StatFs(filesDir.path).availableBytes))
                    }
                    "legacyStatus" -> result.success(LegacyMigration.status(this))
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
                    "openAppSettings" -> {
                        // App info page - the only place Android 13+ exposes
                        // "Allow restricted settings" for sideloaded apps.
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")
                            )
                        )
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
        // Ask the framework which services are actually enabled - string
        // parsing of ENABLED_ACCESSIBILITY_SERVICES breaks on some OEM
        // builds that flatten component names differently (OnePlus/OxygenOS).
        val am = getSystemService(ACCESSIBILITY_SERVICE) as AccessibilityManager
        return am
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.packageName == packageName }
    }
}
