package com.replier.replier

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.NonNull
import com.replier.replier.service.AppNotificationListenerService
import com.replier.replier.service.AutoReplyForegroundService
import com.replier.replier.service.CloudAiService
import com.replier.replier.service.ConversationHistory
import com.replier.replier.service.PhiLocalService
import com.replier.replier.service.RuleEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.replier.replier.reminder.NoteReminderScheduler

class MainActivity : FlutterActivity() {

    private val NATIVE_CHANNEL = "com.replier.replier/native"
    private val NOTIFICATION_CHANNEL = "com.replier.replier/notification"

    private lateinit var nativeMethodChannel: MethodChannel
    private lateinit var notificationMethodChannel: MethodChannel
    private lateinit var ruleEngine: RuleEngine

    override fun onCreate(savedInstanceState: Bundle?) {
        // Switch to normal theme before super.onCreate() to prevent showing launch screen
        setTheme(R.style.NormalTheme)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ruleEngine = RuleEngine(applicationContext)

        // ── Native channel (settings / permissions) ──────────────────────────
        nativeMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, NATIVE_CHANNEL
        )
        nativeMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "loadProviderKeys" -> result.success(mapOf("groq" to ProviderSecrets.read(this,"groq"),"gemini" to ProviderSecrets.read(this,"gemini"),"cloudflare" to ProviderSecrets.read(this,"cloudflare")))
                "saveProviderKey" -> {try{ProviderSecrets.write(this,call.argument<String>("provider")?:"",call.argument<String>("value")?:"");result.success(null)}catch(_:Exception){result.error("SECURE_STORAGE","Could not store provider key",null)}}
                "legacyBlocked" -> result.success(LegacyGuard.blocked(this))
                "consentStatus" -> result.success(getSharedPreferences("automation_consent",0).getBoolean("accepted",false))
                "acceptConsent" -> {getSharedPreferences("automation_consent",0).edit().putBoolean("accepted",true).commit();result.success(null)}

                "openNotificationListenerSettings" -> {
                    startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
                    result.success(null)
                }
                "openBatteryOptimizationSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                        )
                    }
                    result.success(null)
                }
                "isNotificationListenerEnabled" ->
                    result.success(isNotificationListenerEnabled())
                "isBatteryOptimizationDisabled" ->
                    result.success(isBatteryOptimizationDisabled())
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("URL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "url is null", null)
                    }
                }

                // Flutter calls this to sync rules into SharedPreferences
                "syncRules" -> {
                    val rulesJson = call.argument<String>("rulesJson")
                    if (rulesJson != null) {
                        ruleEngine.saveRules(rulesJson)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENTS", "rulesJson is null", null)
                    }
                }

                // Flutter calls this to sync settings into SharedPreferences
                "syncSettings" -> {
                    val settingsJson = call.argument<String>("settingsJson")
                    if (settingsJson != null) {
                        ruleEngine.saveSettings(settingsJson)
                        if(ruleEngine.isMasterEnabled()) AutoReplyForegroundService.start(applicationContext) else AutoReplyForegroundService.stop(applicationContext)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENTS", "settingsJson is null", null)
                    }
                }

                // Flutter sends chatbot context — used by AI auto-reply
                "setChatbotContext" -> {
                    val context = call.argument<String>("context") ?: ""
                    AppNotificationListenerService.setChatbotContext(context)
                    result.success(null)
                }

                // Flutter syncs note reminders (meeting/call/deadline) — alarms are
                // armed natively so they fire even when the Flutter UI is closed.
                "syncNoteReminders" -> {
                    val reminders = call.argument<List<Map<String, Any>>>("reminders")
                    NoteReminderScheduler.getInstance(applicationContext)
                        .syncReminders(reminders.orEmpty())
                    result.success(null)
                }

                "cancelNoteReminder" -> {
                    val id = call.argument<String>("id")
                    if (id != null) {
                        NoteReminderScheduler.getInstance(applicationContext).cancelReminder(id)
                    }
                    result.success(null)
                }

                // Chat with on-device local model
                "chatWithPhi" -> {
                    val modelId = call.argument<String>("modelId") ?: "llama_3_2_1b"
                    val message = call.argument<String>("message") ?: ""
                    val systemPrompt = call.argument<String>("systemPrompt") ?: ""
                    val historyRaw = call.argument<List<Map<String, String>>>("history") ?: emptyList()

                    val history = historyRaw.mapNotNull { m ->
                        val role = m["role"] ?: return@mapNotNull null
                        val content = m["content"] ?: return@mapNotNull null
                        ConversationHistory.ChatMessage(role, content)
                    }

                    PhiLocalService.getInstance(applicationContext).getAiReply(
                        modelId = modelId,
                        senderName = "User",
                        incomingMessage = message,
                        systemPrompt = systemPrompt,
                        conversationHistory = history
                    ) { reply, usage ->
                        runOnUiThread {
                            if (reply != null) {
                                result.success(reply)
                            } else {
                                result.error("INFERENCE_FAILED", usage?.error ?: "Local model returned empty", null)
                            }
                        }
                    }
                }

                // Chat with configured AI engine with automatic local fallback if API key fails
                "chatWithAi" -> {
                    val engineType = call.argument<String>("engineType") ?: ruleEngine.getAiModelType()
                    val localModelId = call.argument<String>("localModelId") ?: ruleEngine.getSelectedLocalModel()
                    val message = call.argument<String>("message") ?: ""
                    val systemPrompt = call.argument<String>("systemPrompt") ?: ruleEngine.getAiSystemPromptWithTraining()
                    val historyRaw = call.argument<List<Map<String, String>>>("history") ?: emptyList()

                    val history = historyRaw.mapNotNull { m ->
                        val role = m["role"] ?: return@mapNotNull null
                        val content = m["content"] ?: return@mapNotNull null
                        ConversationHistory.ChatMessage(role, content)
                    }

                    fun invokeLocalFallback(reason: String?) {
                        val phiService = PhiLocalService.getInstance(applicationContext)
                        if (!phiService.isModelAvailable(localModelId)) {
                            runOnUiThread {
                                result.error("FALLBACK_UNAVAILABLE", "Cloud AI failed ($reason), and local model '$localModelId' is not downloaded. Please download it in Settings.", null)
                            }
                            return
                        }
                        phiService.getAiReply(
                            modelId = localModelId,
                            senderName = "User",
                            incomingMessage = message,
                            systemPrompt = systemPrompt,
                            conversationHistory = history
                        ) { reply, usage ->
                            runOnUiThread {
                                if (reply != null) {
                                    result.success(mapOf(
                                        "reply" to reply,
                                        "model" to "phi_local",
                                        "fallback" to true,
                                        "fallbackReason" to (reason ?: "API error")
                                    ))
                                } else {
                                    result.error("INFERENCE_FAILED", usage?.error ?: "Local model returned empty", null)
                                }
                            }
                        }
                    }

                    when (engineType) {
                        "groq_api" -> {
                            val apiKey = ruleEngine.getGroqApiKey()
                            if (apiKey.isBlank()) {
                                invokeLocalFallback("Groq API key is missing")
                            } else {
                                val model = ruleEngine.getGroqModel()
                                CloudAiService.getInstance(applicationContext).generateReply(
                                    engineType = "groq_api",
                                    apiKey = apiKey,
                                    model = model,
                                    senderName = "User",
                                    incomingMessages = listOf(message),
                                    systemPrompt = systemPrompt,
                                    conversationHistory = history
                                ) { reply, usage ->
                                    if (reply != null) {
                                        runOnUiThread {
                                            result.success(mapOf(
                                                "reply" to reply,
                                                "model" to engineType,
                                                "fallback" to false
                                            ))
                                        }
                                    } else {
                                        invokeLocalFallback(usage?.error ?: "Groq API error")
                                    }
                                }
                            }
                        }
                        "cloudflare_api" -> {
                            val apiKey = ruleEngine.getCloudflareApiKey()
                            if (apiKey.isBlank()) {
                                invokeLocalFallback("Cloudflare API key is missing")
                            } else {
                                val model = ruleEngine.getCloudflareModel()
                                CloudAiService.getInstance(applicationContext).generateReply(
                                    engineType = "cloudflare_api",
                                    apiKey = apiKey,
                                    model = model,
                                    accountId = ruleEngine.getCloudflareAccountId(),
                                    senderName = "User",
                                    incomingMessages = listOf(message),
                                    systemPrompt = systemPrompt,
                                    conversationHistory = history
                                ) { reply, usage ->
                                    if (reply != null) {
                                        runOnUiThread {
                                            result.success(mapOf(
                                                "reply" to reply,
                                                "model" to engineType,
                                                "fallback" to false
                                            ))
                                        }
                                    } else {
                                        invokeLocalFallback(usage?.error ?: "Cloudflare API error")
                                    }
                                }
                            }
                        }
                        "gemini_api" -> {
                            val apiKey = ruleEngine.getGeminiApiKey()
                            if (apiKey.isBlank()) {
                                invokeLocalFallback("Gemini API key is missing")
                            } else {
                                val model = ruleEngine.getGeminiModel()
                                CloudAiService.getInstance(applicationContext).generateReply(
                                    engineType = "gemini_api",
                                    apiKey = apiKey,
                                    model = model,
                                    senderName = "User",
                                    incomingMessages = listOf(message),
                                    systemPrompt = systemPrompt,
                                    conversationHistory = history
                                ) { reply, usage ->
                                    if (reply != null) {
                                        runOnUiThread {
                                            result.success(mapOf(
                                                "reply" to reply,
                                                "model" to engineType,
                                                "fallback" to false
                                            ))
                                        }
                                    } else {
                                        invokeLocalFallback(usage?.error ?: "Gemini API error")
                                    }
                                }
                            }
                        }
                        else -> {
                            PhiLocalService.getInstance(applicationContext).getAiReply(
                                modelId = localModelId,
                                senderName = "User",
                                incomingMessage = message,
                                systemPrompt = systemPrompt,
                                conversationHistory = history
                            ) { reply, usage ->
                                runOnUiThread {
                                    if (reply != null) {
                                        result.success(mapOf(
                                            "reply" to reply,
                                            "model" to "phi_local",
                                            "fallback" to false
                                        ))
                                    } else {
                                        result.error("INFERENCE_FAILED", usage?.error ?: "Local model returned empty", null)
                                    }
                                }
                            }
                        }
                    }
                }

                "getPhiStatus" -> {
                    val modelId = call.argument<String>("modelId") ?: "llama_3_2_1b"
                    val service = PhiLocalService.getInstance(applicationContext)
                    val available = service.isModelAvailable(modelId)
                    result.success(mapOf(
                        "available" to available,
                        "configured" to true,
                        "modelId" to modelId
                    ))
                }

                "downloadPhiModel" -> {
                    val modelId = call.argument<String>("modelId") ?: "llama_3_2_1b"
                    val service = PhiLocalService.getInstance(applicationContext)
                    service.downloadModel(
                        modelId = modelId,
                        onProgress = { progress ->
                            runOnUiThread {
                                nativeMethodChannel.invokeMethod("onDownloadProgress", mapOf(
                                    "modelId" to modelId,
                                    "progress" to progress,
                                ))
                            }
                        },
                        onComplete = { success, error ->
                            result.success(mapOf("success" to success, "error" to error, "modelId" to modelId))
                        }
                    )
                }

                "deletePhiModel" -> {
                    val modelId = call.argument<String>("modelId") ?: "llama_3_2_1b"
                    val service = PhiLocalService.getInstance(applicationContext)
                    service.deleteModel(modelId)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // ── Notification channel (send reply + UI callbacks) ─────────────────
        notificationMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL
        )
        notificationMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendReply" -> {
                    val key = call.argument<String>("key")
                    val replyText = call.argument<String>("replyText")
                    if (key != null && replyText != null) {
                        AppNotificationListenerService.getInstance()
                            ?.sendReply(key, "", replyText)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing key or replyText", null)
                    }
                }
                "getAnalysisStatus" -> result.success(
                    AppNotificationListenerService.getInstance()?.analysisSnapshot()
                        ?: "{\"epoch\":\"offline\",\"revision\":0,\"attempts\":[]}")
                "getAiUsage" -> {
                    val usage = ruleEngine.getAiUsage()
                    result.success(usage)
                }
                else -> result.notImplemented()
            }
        }

        // Wire up the method channel so the service can notify Flutter UI
        AppNotificationListenerService.setMethodChannel(notificationMethodChannel)

        // Start the foreground service to keep the process alive
        if(ruleEngine.isMasterEnabled()) AutoReplyForegroundService.start(applicationContext)
    }

    // ── Permission helpers ────────────────────────────────────────────────────

    private fun isNotificationListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        )
        return enabled?.contains(packageName) ?: false
    }

    private fun isBatteryOptimizationDisabled(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            return pm.isIgnoringBatteryOptimizations(packageName)
        }
        return true
    }
}
