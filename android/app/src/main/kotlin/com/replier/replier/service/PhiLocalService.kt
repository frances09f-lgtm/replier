package com.replier.replier.service

import android.content.Context
import android.util.Log
import dev.ffmpegkit.llama.Llama
import dev.ffmpegkit.llama.LlamaConfig
import dev.ffmpegkit.llama.LlamaModel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class PhiLocalService private constructor(private val context: Context) {

    companion object {
        private const val TAG = "PhiLocalService"

        @Volatile
        private var instance: PhiLocalService? = null

        fun getInstance(context: Context): PhiLocalService {
            return instance ?: synchronized(this) {
                instance ?: PhiLocalService(context.applicationContext).also { instance = it }
            }
        }

        data class ModelConfig(
            val id: String,
            val displayName: String,
            val filename: String,
            val url: String,
            val sizeBytes: Long,
            val description: String,
            val threads: Int = 4,
            val contextSize: Int = 2048,
        )

        val MODEL_REGISTRY = mapOf(
            "llama_3_2_1b" to ModelConfig(
                id = "llama_3_2_1b",
                displayName = "Llama 3.2 1B Instruct",
                filename = "llama-3.2-1b-instruct-q4_k_m.gguf",
                url = "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
                sizeBytes = 850_000_000L,
                description = "~800MB, blazing fast for basic replies",
                threads = 4,
                contextSize = 4096,
            ),
            "qwen_2_5_1_5b" to ModelConfig(
                id = "qwen_2_5_1_5b",
                displayName = "Qwen 2.5 1.5B Instruct",
                filename = "qwen2.5-1.5b-instruct-q4_k_m.gguf",
                url = "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf",
                sizeBytes = 986_000_000L,
                description = "~980MB, best for multilingual & casual chats",
                threads = 4,
                contextSize = 4096,
            ),
        )

        private const val LLAMA_BEGIN = "<|begin_of_text|>"
        private const val LLAMA_HDR_START = "<|" + "start_header_id|>"
        private const val LLAMA_HDR_END = "<|" + "end_header_id|>"
        private const val LLAMA_EOT = "<|eot_id|>"
    }

    data class AiUsage(
        val tokensUsed: Int = 0,
        val tokensRemaining: Int = 0,
        val tokensLimit: Int = 0,
        val resetInSeconds: Int = 0,
        val error: String? = null,
        val requestsRemaining: Int? = null,
        val requestsLimit: Int? = null,
        val isLimitReached: Boolean = false,
    )

    private val loadedModels = ConcurrentHashMap<String, LlamaModel>()
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val downloadProgressMap = ConcurrentHashMap<String, Int>()
    private val downloadingMap = ConcurrentHashMap<String, Boolean>()

    fun getModelConfig(modelId: String): ModelConfig? = MODEL_REGISTRY[modelId]

    fun isModelAvailable(modelId: String): Boolean {
        val config = MODEL_REGISTRY[modelId] ?: return false
        val f = getModelFile(config)
        return f.exists() && f.length() > config.sizeBytes / 2
    }

    fun getModelFile(config: ModelConfig): File = File(context.filesDir, config.filename)

    fun isDownloading(modelId: String): Boolean = downloadingMap[modelId] == true

    fun getDownloadProgress(modelId: String): Int = downloadProgressMap[modelId] ?: 0

    fun downloadModel(
        modelId: String,
        onProgress: ((Int) -> Unit)? = null,
        onComplete: ((Boolean, String?) -> Unit)? = null
    ) {
        val config = MODEL_REGISTRY[modelId]
        if (config == null) {
            onComplete?.invoke(false, "Unknown model: $modelId")
            return
        }
        if (downloadingMap[modelId] == true) {
            onComplete?.invoke(false, "Already downloading")
            return
        }
        if (isModelAvailable(modelId)) {
            onComplete?.invoke(true, null)
            return
        }

        downloadingMap[modelId] = true
        downloadProgressMap[modelId] = 0

        executor.execute {
            var conn: HttpURLConnection? = null
            try {
                val url = URL(config.url)
                conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 30_000
                conn.readTimeout = 120_000
                conn.connect()

                val totalSize = conn.contentLength.toLong().coerceAtLeast(config.sizeBytes)
                val input = conn.inputStream
                val output = FileOutputStream(getModelFile(config))

                val buffer = ByteArray(8192)
                var bytesRead: Int
                var totalRead = 0L

                while (input.read(buffer).also { bytesRead = it } != -1) {
                    output.write(buffer, 0, bytesRead)
                    totalRead += bytesRead
                    val progress = ((totalRead * 100) / totalSize).toInt().coerceIn(0, 100)
                    if (progress != (downloadProgressMap[modelId] ?: 0)) {
                        downloadProgressMap[modelId] = progress
                        onProgress?.invoke(progress)
                    }
                }

                output.flush()
                output.close()
                input.close()

                val file = getModelFile(config)
                if (file.exists() && file.length() > config.sizeBytes / 2) {
                    Log.d(TAG, "Model $modelId downloaded: ${file.length()} bytes")
                    onComplete?.invoke(true, null)
                } else {
                    file.delete()
                    onComplete?.invoke(false, "Download incomplete")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Download failed for $modelId", e)
                getModelFile(config).delete()
                onComplete?.invoke(false, e.message)
            } finally {
                conn?.disconnect()
                downloadingMap[modelId] = false
            }
        }
    }

    fun deleteModel(modelId: String) {
        val config = MODEL_REGISTRY[modelId] ?: return
        // Release loaded model first
        loadedModels.remove(modelId)?.let {
            try { Llama.releaseModel(it) } catch (_: Exception) {}
        }
        val file = getModelFile(config)
        if (file.exists()) file.delete()
    }

    private fun loadModel(modelId: String): LlamaModel? {
        loadedModels[modelId]?.let { return it }
        val config = MODEL_REGISTRY[modelId] ?: return null
        try {
            val modelFile = getModelFile(config)
            if (!modelFile.exists()) {
                Log.w(TAG, "Model file not found for $modelId")
                return null
            }

            val loaded = runBlocking {
                Llama.loadModel(
                    modelPath = modelFile.absolutePath,
                    config = LlamaConfig(contextSize = config.contextSize, threads = config.threads)
                )
            }
            loadedModels[modelId] = loaded
            Log.d(TAG, "Model $modelId loaded successfully")
            return loaded
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load model $modelId", e)
            return null
        }
    }

    fun getAiReply(
        modelId: String,
        senderName: String,
        incomingMessage: String,
        systemPrompt: String,
        conversationHistory: List<ConversationHistory.ChatMessage> = emptyList(),
        callback: (String?, AiUsage?) -> Unit,
    ) {
        getAiReplyBatch(modelId, senderName, listOf(incomingMessage), systemPrompt, conversationHistory, callback)
    }

    fun getAiReplyBatch(
        modelId: String,
        senderName: String,
        incomingMessages: List<String>,
        systemPrompt: String,
        conversationHistory: List<ConversationHistory.ChatMessage> = emptyList(),
        callback: (String?, AiUsage?) -> Unit,
    ) {
        executor.execute {
            try {
                if (!isModelAvailable(modelId)) {
                    callback(null, AiUsage(error = "Model not downloaded"))
                    return@execute
                }

                val loadedModel = loadModel(modelId)
                if (loadedModel == null) {
                    callback(null, AiUsage(error = "Failed to load model"))
                    return@execute
                }

                val combinedMessage = incomingMessages.joinToString("\n") { it }
                if (combinedMessage.isBlank()) {
                    callback(null, AiUsage(error = "Empty incoming message"))
                    return@execute
                }

                Log.d(TAG, "Pipeline event")

                val prompt = buildPrompt(modelId, systemPrompt, conversationHistory, combinedMessage, senderName)
                Log.d(TAG, "Running inference for $modelId (prompt: ${prompt.length} chars)")

                val result = runBlocking {
                    withTimeoutOrNull(60_000L) {
                        Llama.complete(
                            model = loadedModel,
                            prompt = prompt,
                            maxTokens = 100
                        )
                    }
                }

                if (result == null) {
                    Log.e(TAG, "Inference timed out for $modelId")
                    callback(null, AiUsage(error = "Inference timed out"))
                } else {
                    val reply = result.text?.trim()
                    Log.d(TAG, "Raw inference result for $modelId: '${reply?.take(200) ?: "NULL"}'")
                    if (reply != null && reply.isNotBlank()) {
                        val cleanReply = postProcess(reply, senderName, combinedMessage)
                        Log.d(TAG, "Inference complete for $modelId: ${result.tokensPerSecond} tok/s")
                        if (cleanReply.isNotBlank()) {
                            Log.d(TAG, "Local AI final reply ($modelId): '$cleanReply'")
                            callback(cleanReply, AiUsage(tokensUsed = prompt.length / 4 + cleanReply.length / 4))
                        } else {
                            Log.e(TAG, "Clean reply is blank after postProcess for $modelId")
                            callback(null, AiUsage(error = "Empty response after processing"))
                        }
                    } else {
                        Log.e(TAG, "Raw reply is null or empty for $modelId")
                        callback(null, AiUsage(error = "Empty response"))
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Inference failed for $modelId", e)
                callback(null, AiUsage(error = e.message))
            }
        }
    }

    private fun buildSystemPrompt(userSystemPrompt: String, senderName: String = "User"): String {
        return CloudAiRequestBuilder.buildFormattedSystemPrompt(userSystemPrompt, senderName)
    }

    private fun buildPrompt(
        modelId: String,
        systemPrompt: String,
        history: List<ConversationHistory.ChatMessage>,
        incomingMessage: String,
        senderName: String = "User"
    ): String {
        val sb = StringBuilder()
        
        val optimizedSystemPrompt = buildSystemPrompt(systemPrompt, senderName)
        
        if (modelId.startsWith("qwen", ignoreCase = true)) {
            // ChatML template for Qwen
            sb.append("<|im_start|>system\n$optimizedSystemPrompt<|im_end|>\n")

            for (msg in history) {
                val role = if (msg.role == "user") "user" else "assistant"
                val content = if (msg.role == "user" && !msg.content.startsWith("$senderName:")) {
                    "$senderName: ${msg.content}"
                } else {
                    msg.content
                }
                sb.append("<|im_start|>$role\n$content<|im_end|>\n")
            }

            val currentTurnContent = if (!incomingMessage.startsWith("$senderName:")) {
                "$senderName: $incomingMessage"
            } else {
                incomingMessage
            }
            sb.append("<|im_start|>user\n$currentTurnContent<|im_end|>\n")
            sb.append("<|im_start|>assistant\n")
        } else {
            // Llama 3.2 Instruct chat template (for 1B)
            sb.append("${LLAMA_BEGIN}${LLAMA_HDR_START}system${LLAMA_HDR_END}\n\n$optimizedSystemPrompt${LLAMA_EOT}\n")

            for (msg in history) {
                val role = if (msg.role == "user") "user" else "assistant"
                val content = if (msg.role == "user" && !msg.content.startsWith("$senderName:")) {
                    "$senderName: ${msg.content}"
                } else {
                    msg.content
                }
                sb.append("${LLAMA_HDR_START}$role${LLAMA_HDR_END}\n\n$content${LLAMA_EOT}\n")
            }

            val currentTurnContent = if (!incomingMessage.startsWith("$senderName:")) {
                "$senderName: $incomingMessage"
            } else {
                incomingMessage
            }
            sb.append("${LLAMA_HDR_START}user${LLAMA_HDR_END}\n\n$currentTurnContent${LLAMA_EOT}\n")
            sb.append("${LLAMA_HDR_START}assistant${LLAMA_HDR_END}\n\n")
        }
        
        val finalPrompt = sb.toString()
        Log.d(TAG, "Built prompt for $modelId (${finalPrompt.length} chars)")
        return finalPrompt
    }

    private fun postProcess(text: String, senderName: String = "", incomingMessage: String = ""): String {
        Log.d(TAG, "postProcess input: '${text.take(200)}'")
        val finalResult = AiReplyCleaner.clean(text, senderName, incomingMessage)
        Log.d(TAG, "postProcess output: '$finalResult'")
        return finalResult
    }

    fun close() {
        loadedModels.values.forEach {
            try { Llama.releaseModel(it) } catch (_: Exception) {}
        }
        loadedModels.clear()
        executor.shutdown()
    }
}

