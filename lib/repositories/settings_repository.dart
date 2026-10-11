import 'dart:convert';
import '../services/provider_secrets.dart';
import 'package:injectable/injectable.dart';
import '../core/hive_config.dart';
import '../core/constants.dart';
import '../models/app_settings.dart';
import '../utils/cloud_ai_model.dart';
import '../utils/contact_identifier.dart';

/// Repository for managing app settings
@injectable
class SettingsRepository {
  /// Get app settings
  AppSettings getSettings() {
    final box = HiveConfig.getSettingsBox();
    if (box.isEmpty) {
      // Create default settings
      final defaultSettings = AppSettings(
        masterEnabled: false,
        whatsappEnabled: true,
        instagramEnabled: true,
        minReplyDelaySeconds: AppConstants.defaultMinReplyDelay,
        maxReplyDelaySeconds: AppConstants.defaultMaxReplyDelay,
        preventDuplicateReplies: AppConstants.defaultPreventDuplicateReplies,
        ignoreGroupChats: AppConstants.defaultIgnoreGroupChats,
        darkMode: false,
        lastUpdated: DateTime.now(),
      );
      box.put('settings', defaultSettings);
      return defaultSettings;
    }
    final settings = box.get('settings')!;
    return _migrateCloudModelsIfNeeded(settings).copyWith(
        groqApiKey: ProviderSecrets.groq,
        geminiApiKey: ProviderSecrets.gemini,
        cloudflareApiKey: ProviderSecrets.cloudflare);
  }

  AppSettings _migrateCloudModelsIfNeeded(AppSettings settings) {
    final groqModel = CloudAiModel.normalizeGroqModel(settings.groqModel);
    final geminiModel = CloudAiModel.normalizeGeminiModel(settings.geminiModel);
    if (groqModel == settings.groqModel &&
        geminiModel == settings.geminiModel) {
      return settings;
    }
    final migrated = settings.copyWith(
      groqModel: groqModel,
      geminiModel: geminiModel,
    );
    HiveConfig.getSettingsBox().put('settings', migrated);
    return migrated;
  }

  /// Update app settings
  Future<void> updateSettings(AppSettings settings) async {
    final box = HiveConfig.getSettingsBox();
    final updatedSettings = settings.copyWith(
      lastUpdated: DateTime.now(),
    );
    await box.put(
        'settings',
        updatedSettings.copyWith(
            groqApiKey: '', geminiApiKey: '', cloudflareApiKey: ''));
  }

  /// Toggle master enabled
  Future<void> toggleMasterEnabled() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      masterEnabled: !settings.masterEnabled,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle WhatsApp enabled
  Future<void> toggleWhatsappEnabled() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      whatsappEnabled: !settings.whatsappEnabled,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle Instagram enabled
  Future<void> toggleInstagramEnabled() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      instagramEnabled: !settings.instagramEnabled,
    );
    await updateSettings(updatedSettings);
  }

  /// Update reply delay range
  Future<void> updateReplyDelayRange(int minSeconds, int maxSeconds) async {
    final settings = getSettings();
    final clampedMin = minSeconds.clamp(0, AppConstants.maxReplyDelay);
    final clampedMax = maxSeconds.clamp(clampedMin, AppConstants.maxReplyDelay);
    final updatedSettings = settings.copyWith(
      minReplyDelaySeconds: clampedMin,
      maxReplyDelaySeconds: clampedMax,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle prevent duplicate replies
  Future<void> togglePreventDuplicateReplies() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      preventDuplicateReplies: !settings.preventDuplicateReplies,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle ignore group chats
  Future<void> toggleIgnoreGroupChats() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      ignoreGroupChats: !settings.ignoreGroupChats,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle confirm before reply
  Future<void> toggleConfirmBeforeReply() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      confirmBeforeReply: !settings.confirmBeforeReply,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle dark mode
  Future<void> toggleDarkMode() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      darkMode: !settings.darkMode,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle AI reply enabled
  Future<void> toggleAiReplyEnabled() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      aiReplyEnabled: !settings.aiReplyEnabled,
    );
    await updateSettings(updatedSettings);
  }

  /// Update AI model type (deepseek_local)
  Future<void> updateAiModelType(String modelType) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(aiModelType: modelType);
    await updateSettings(updatedSettings);
  }

  /// Update AI system prompt
  Future<void> updateAiSystemPrompt(String prompt) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(aiSystemPrompt: prompt);
    await updateSettings(updatedSettings);
  }

  /// Update DeepSeek server config
  Future<void> updateDeepSeekConfig(String serverUrl, String model) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      gemmaLocalServerUrl: serverUrl,
      gemmaLocalModel: model,
    );
    await updateSettings(updatedSettings);
  }

  /// Update Groq API config
  Future<void> updateGroqConfig(String apiKey, String model) async {
    await ProviderSecrets.write("groq", apiKey);
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      groqApiKey: apiKey,
      groqModel: model,
    );
    await updateSettings(updatedSettings);
  }

  Future<void> updateCloudflareConfig(
      String key, String account, String model) async {
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(account)) {
      throw const FormatException(
          'Enter the 32-character Cloudflare account ID');
    }
    await ProviderSecrets.write('cloudflare', key);
    await updateSettings(getSettings()
        .copyWith(cloudflareAccountId: account, cloudflareModel: model));
  }

  /// Update Gemini API config
  Future<void> updateGeminiConfig(String apiKey, String model) async {
    await ProviderSecrets.write("gemini", apiKey);
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      geminiApiKey: apiKey,
      geminiModel: model,
    );
    await updateSettings(updatedSettings);
  }

  /// Update selected local model ID
  Future<void> updateSelectedLocalModel(String modelId) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(selectedLocalModel: modelId);
    await updateSettings(updatedSettings);
  }

  /// Update per-engine daily reply limits (0 = unlimited)
  Future<void> updateAiReplyLimits({
    int? groqReplyLimit,
    int? geminiReplyLimit,
    int? localReplyLimit,
  }) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      groqReplyLimit: groqReplyLimit,
      geminiReplyLimit: geminiReplyLimit,
      localReplyLimit: localReplyLimit,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle fallback to local model when cloud API keys fail
  Future<void> toggleFallbackToLocalModel() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      fallbackToLocalModel: !settings.fallbackToLocalModel,
    );
    await updateSettings(updatedSettings);
  }

  /// Update fallback to local model
  Future<void> updateFallbackToLocalModel(bool enabled) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      fallbackToLocalModel: enabled,
    );
    await updateSettings(updatedSettings);
  }

  /// Update schedule settings
  Future<void> updateSchedule({
    required bool enabled,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
  }) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      scheduleEnabled: enabled,
      scheduleStartHour: startHour,
      scheduleStartMinute: startMinute,
      scheduleEndHour: endHour,
      scheduleEndMinute: endMinute,
    );
    await updateSettings(updatedSettings);
  }

  /// Toggle contact whitelist enabled
  Future<void> toggleContactWhitelist() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      contactWhitelistEnabled: !settings.contactWhitelistEnabled,
    );
    await updateSettings(updatedSettings);
  }

  /// Update the entire contact whitelist
  Future<void> updateContactWhitelist(List<String> contacts) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(contactWhitelist: contacts);
    await updateSettings(updatedSettings);
  }

  /// Add a contact to the whitelist
  Future<void> addToWhitelist(String contact) async {
    final settings = getSettings();
    final list = List<String>.from(settings.contactWhitelist);
    if (!list.any((c) => c.toLowerCase() == contact.toLowerCase())) {
      list.add(contact);
      final updatedSettings = settings.copyWith(contactWhitelist: list);
      await updateSettings(updatedSettings);
    }
  }

  /// Remove a contact from the whitelist
  Future<void> removeFromWhitelist(String contact) async {
    final settings = getSettings();
    final list = List<String>.from(settings.contactWhitelist);
    list.removeWhere((c) => c.toLowerCase() == contact.toLowerCase());
    final updatedSettings = settings.copyWith(contactWhitelist: list);
    await updateSettings(updatedSettings);
  }

  /// Update the entire contact blacklist
  Future<void> updateContactBlacklist(List<String> contacts) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(contactBlacklist: contacts);
    await updateSettings(updatedSettings);
  }

  /// Add a contact to the blacklist
  Future<void> addToBlacklist(String contact) async {
    final settings = getSettings();
    final list = List<String>.from(settings.contactBlacklist);
    if (!list.any((c) => c.toLowerCase() == contact.toLowerCase())) {
      list.add(contact);
      final updatedSettings = settings.copyWith(contactBlacklist: list);
      await updateSettings(updatedSettings);
    }
  }

  /// Remove a contact from the blacklist
  Future<void> removeFromBlacklist(String contact) async {
    final settings = getSettings();
    final list = List<String>.from(settings.contactBlacklist);
    list.removeWhere((c) => c.toLowerCase() == contact.toLowerCase());
    final updatedSettings = settings.copyWith(contactBlacklist: list);
    await updateSettings(updatedSettings);
  }

  /// Check if a contact is blacklisted
  bool isContactBlacklisted(String contact) {
    final settings = getSettings();
    return ContactIdentifier.isBlacklisted(contact, settings.contactBlacklist);
  }

  /// Check if a contact is whitelisted
  bool isContactWhitelisted(String contact) {
    final settings = getSettings();
    return ContactIdentifier.isWhitelisted(contact, settings.contactWhitelist);
  }

  /// Update busy mode settings
  Future<void> updateBusyMode(String replyText, int untilTimestamp) async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      busyModeEnabled: true,
      busyReplyText: replyText,
      busyUntilTimestamp: untilTimestamp,
    );
    await updateSettings(updatedSettings);
  }

  /// Clear busy mode
  Future<void> clearBusyMode() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(
      busyModeEnabled: false,
      busyReplyText: '',
      busyUntilTimestamp: 0,
    );
    await updateSettings(updatedSettings);
  }

  /// Check if busy mode is active (enabled and not expired)
  bool isBusyModeActive() {
    final settings = getSettings();
    if (!settings.busyModeEnabled) return false;
    if (settings.busyUntilTimestamp <= 0) return true;
    return DateTime.now().millisecondsSinceEpoch < settings.busyUntilTimestamp;
  }

  /// Add a training example pair (with optional style note).
  /// Keeps at most 50 examples (FIFO) so prompts stay small.
  Future<void> addTrainingExample(String userMessage, String correctedReply,
      {String note = ''}) async {
    final settings = getSettings();
    final list = List<String>.from(settings.trainingExamplesRaw);
    final entry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'userMessage': userMessage,
      'correctedReply': correctedReply,
      'note': note,
      'timestamp': DateTime.now().toIso8601String(),
    };
    list.add(jsonEncode(entry));
    // Cap to 50 most recent
    while (list.length > 50) {
      list.removeAt(0);
    }
    final updatedSettings = settings.copyWith(trainingExamplesRaw: list);
    await updateSettings(updatedSettings);
  }

  /// Remove a training example pair by id
  Future<void> removeTrainingExample(String id) async {
    final settings = getSettings();
    final list = List<String>.from(settings.trainingExamplesRaw);
    list.removeWhere((e) {
      try {
        final map = jsonDecode(e) as Map<String, dynamic>;
        return map['id'] == id;
      } catch (_) {
        return false;
      }
    });
    final updatedSettings = settings.copyWith(trainingExamplesRaw: list);
    await updateSettings(updatedSettings);
  }

  /// Clear all training examples
  Future<void> clearTrainingExamples() async {
    final settings = getSettings();
    final updatedSettings = settings.copyWith(trainingExamplesRaw: []);
    await updateSettings(updatedSettings);
  }

  /// Check if app is enabled for a specific package
  bool isAppEnabled(String packageName) {
    final settings = getSettings();
    if (!settings.masterEnabled) return false;

    switch (packageName) {
      case AppConstants.whatsappPackage:
        return settings.whatsappEnabled;
      case AppConstants.instagramPackage:
        return settings.instagramEnabled;
      default:
        return false;
    }
  }
}
