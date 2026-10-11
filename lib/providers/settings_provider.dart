import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../models/app_settings.dart';
import '../repositories/settings_repository.dart';
import '../services/native_sync_service.dart';
import '../services/notification_service.dart';

/// Provider for settings repository
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

/// Provider for notification service
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final _nativeSyncProvider = Provider<NativeSyncService>((ref) {
  return NativeSyncService();
});

/// Provider for app settings
final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  final syncService = ref.watch(_nativeSyncProvider);
  return AppSettingsNotifier(repository, syncService);
});

/// Notifier for app settings
class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsRepository _repository;
  final NativeSyncService _syncService;

  AppSettingsNotifier(this._repository, this._syncService)
      : super(_repository.getSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    state = _repository.getSettings();
    await _syncService.syncSettings(state);
  }

  Future<void> _updateAndSync(AppSettings settings) async {
    await _repository.updateSettings(settings);
    state = settings;
    await _syncService.syncSettings(settings);
  }

  Future<void> updateSettings(AppSettings settings) => _updateAndSync(settings);

  Future<void> toggleMasterEnabled() async {
    if (!state.masterEnabled) {
      const channel = MethodChannel(AppConstants.nativeChannel);
      if (await channel.invokeMethod<bool>('consentStatus') != true) {
        throw StateError(
            'Complete first-run setup before enabling replies. Reopen Replier to complete it.');
      }
      if (await channel.invokeMethod<bool>('legacyBlocked') == true) {
        throw StateError(
            'Disable notification and accessibility access for old Replier first.');
      }
    }

    await _repository.toggleMasterEnabled();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> toggleWhatsappEnabled() async {
    await _repository.toggleWhatsappEnabled();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> toggleInstagramEnabled() async {
    await _repository.toggleInstagramEnabled();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateReplyDelayRange(int minSeconds, int maxSeconds) async {
    await _repository.updateReplyDelayRange(minSeconds, maxSeconds);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> togglePreventDuplicateReplies() async {
    await _repository.togglePreventDuplicateReplies();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> toggleIgnoreGroupChats() async {
    await _repository.toggleIgnoreGroupChats();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> toggleConfirmBeforeReply() async {
    await _repository.toggleConfirmBeforeReply();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> toggleDarkMode() async {
    await _repository.toggleDarkMode();
    final s = _repository.getSettings();
    state = s;
    // Dark mode is UI-only — no need to sync to native
  }

  Future<void> toggleAiReplyEnabled() async {
    await _repository.toggleAiReplyEnabled();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateAiModelType(String modelType) async {
    await _repository.updateAiModelType(modelType);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateAiSystemPrompt(String prompt) async {
    await _repository.updateAiSystemPrompt(prompt);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateDeepSeekConfig(String serverUrl, String model) async {
    await _repository.updateDeepSeekConfig(serverUrl, model);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateGroqConfig(String apiKey, String model) async {
    await _repository.updateGroqConfig(apiKey, model);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateGeminiConfig(String apiKey, String model) async {
    await _repository.updateGeminiConfig(apiKey, model);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateSelectedLocalModel(String modelId) async {
    await _repository.updateSelectedLocalModel(modelId);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateAiReplyLimits({
    int? groqReplyLimit,
    int? geminiReplyLimit,
    int? localReplyLimit,
  }) async {
    await _repository.updateAiReplyLimits(
      groqReplyLimit: groqReplyLimit,
      geminiReplyLimit: geminiReplyLimit,
      localReplyLimit: localReplyLimit,
    );
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> toggleFallbackToLocalModel() async {
    await _repository.toggleFallbackToLocalModel();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateFallbackToLocalModel(bool enabled) async {
    await _repository.updateFallbackToLocalModel(enabled);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> toggleContactWhitelist() async {
    await _repository.toggleContactWhitelist();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateContactWhitelist(List<String> contacts) async {
    await _repository.updateContactWhitelist(contacts);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> addToWhitelist(String contact) async {
    await _repository.addToWhitelist(contact);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> removeFromWhitelist(String contact) async {
    await _repository.removeFromWhitelist(contact);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateContactBlacklist(List<String> contacts) async {
    await _repository.updateContactBlacklist(contacts);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> addToBlacklist(String contact) async {
    await _repository.addToBlacklist(contact);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> removeFromBlacklist(String contact) async {
    await _repository.removeFromBlacklist(contact);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> setBusyMode(String replyText, int untilTimestamp) async {
    await _repository.updateBusyMode(replyText, untilTimestamp);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> clearBusyMode() async {
    await _repository.clearBusyMode();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> updateSchedule({
    required bool enabled,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
  }) async {
    await _repository.updateSchedule(
      enabled: enabled,
      startHour: startHour,
      startMinute: startMinute,
      endHour: endHour,
      endMinute: endMinute,
    );
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> addTrainingExample(String userMessage, String correctedReply,
      {String note = ''}) async {
    await _repository.addTrainingExample(userMessage, correctedReply,
        note: note);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> removeTrainingExample(String id) async {
    await _repository.removeTrainingExample(id);
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }

  Future<void> clearTrainingExamples() async {
    await _repository.clearTrainingExamples();
    final s = _repository.getSettings();
    state = s;
    await _syncService.syncSettings(s);
  }
}

/// Provider for permission status
final permissionStatusProvider =
    StateNotifierProvider<PermissionStatusNotifier, Map<String, bool>>((ref) {
  final notificationService = ref.watch(notificationServiceProvider);
  return PermissionStatusNotifier(notificationService);
});

/// Notifier for permission status
class PermissionStatusNotifier extends StateNotifier<Map<String, bool>> {
  final NotificationService _notificationService;

  PermissionStatusNotifier(this._notificationService)
      : super({
          'notificationListener': false,
          'accessibilityService': false,
          'batteryOptimization': false,
        }) {
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final notificationListener =
        await _notificationService.isNotificationListenerEnabled();
    final accessibilityService =
        await _notificationService.isAccessibilityServiceEnabled();
    final batteryOptimization =
        await _notificationService.isBatteryOptimizationDisabled();
    final postNotification =
        await _notificationService.isPostNotificationPermissionGranted();

    state = {
      'notificationListener': notificationListener,
      'accessibilityService': accessibilityService,
      'batteryOptimization': batteryOptimization,
      'postNotification': postNotification,
    };
  }

  Future<void> refreshPermissions() async {
    await _checkPermissions();
  }

  Future<void> openNotificationListenerSettings() async {
    await _notificationService.openNotificationListenerSettings();
    await Future.delayed(const Duration(seconds: 2));
    await refreshPermissions();
  }

  Future<void> openAccessibilitySettings() async {
    await _notificationService.openAccessibilitySettings();
    await Future.delayed(const Duration(seconds: 2));
    await refreshPermissions();
  }

  Future<void> openBatteryOptimizationSettings() async {
    await _notificationService.openBatteryOptimizationSettings();
    await Future.delayed(const Duration(seconds: 2));
    await refreshPermissions();
  }

  Future<void> requestPostNotificationPermission() async {
    await _notificationService.requestPostNotificationPermission();
    await refreshPermissions();
  }
}
