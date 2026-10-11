import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../models/notification_data.dart';
import '../providers/log_provider.dart';
import '../providers/note_provider.dart';
import '../providers/settings_provider.dart';
import '../repositories/log_repository.dart';
import '../repositories/rule_repository.dart';
import 'note_extraction_service.dart';

/// Listens to the notification MethodChannel for logging purposes only.
///
/// The actual auto-reply logic runs entirely on the native (Kotlin) side.
/// This class must NOT send any replies — doing so causes double-replies.
/// It only writes log entries to Hive when the native side reports a success.
class AutoReplyService {
  final RuleRepository _ruleRepository;
  final LogRepository _logRepository;
  final NoteExtractionService _noteExtractionService;
  final ProviderContainer? _providerContainer;

  static const MethodChannel _notificationChannel =
      MethodChannel(AppConstants.notificationChannel);

  static AutoReplyService? _instance;

  /// Callback for AI usage updates
  static Function(Map<String, dynamic>)? onAiUsageUpdate;

  /// Callback for pipeline status events (got_message, analysing, reply_ready)
  static Function(Map<String, dynamic>)? onPipelineStatus;

  /// Callback for reply scheduled (countdown) — multiple listeners supported
  static final List<Function(Map<String, dynamic>)> _onReplyScheduledListeners =
      [];
  static set onReplyScheduled(Function(Map<String, dynamic>)? fn) {
    if (fn != null) _onReplyScheduledListeners.add(fn);
  }

  /// Callback for reply completed (sent or failed) — multiple listeners supported
  static final List<VoidCallback> _onReplyCompletedListeners = [];
  static set onReplyCompleted(VoidCallback? fn) {
    if (fn != null) _onReplyCompletedListeners.add(fn);
  }

  AutoReplyService({
    required RuleRepository ruleRepository,
    required LogRepository logRepository,
    NoteExtractionService? noteExtractionService,
    ProviderContainer? providerContainer,
  })  : _ruleRepository = ruleRepository,
        _logRepository = logRepository,
        _noteExtractionService =
            noteExtractionService ?? NoteExtractionService(),
        _providerContainer = providerContainer {
    _instance = this;
  }

  void initialize() {
    _notificationChannel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onNotificationPosted':
        if (_instance != null && call.arguments != null) {
          final notification = NotificationData.fromJson(
            json.decode(call.arguments as String) as Map<String, dynamic>,
          );
          await _instance!._maybeLog(notification);
        }
        break;
      case 'onPipelineStatus':
        if (call.arguments != null) {
          final data =
              json.decode(call.arguments as String) as Map<String, dynamic>;
          onPipelineStatus?.call(data);
        }
        break;
      case 'onAiUsageUpdate':
        if (call.arguments != null) {
          final usageData =
              json.decode(call.arguments as String) as Map<String, dynamic>;
          onAiUsageUpdate?.call(usageData);
        }
        break;
      case 'onReplyFailed':
        print('AutoReplyService: reply failed — ${call.arguments}');
        for (final fn in _onReplyCompletedListeners) fn();
        break;
      case 'onReplySuccess':
        if (_instance != null && call.arguments != null) {
          final data =
              json.decode(call.arguments as String) as Map<String, dynamic>;
          await _instance!._logReply(data);
        }
        for (final fn in _onReplyCompletedListeners) fn();
        break;
      case 'onReplyScheduled':
        if (call.arguments != null) {
          final data =
              json.decode(call.arguments as String) as Map<String, dynamic>;
          for (final fn in _onReplyScheduledListeners) fn(data);
        }
        break;
      case 'onNotificationRemoved':
      case 'useAccessibilityService':
        break;
    }
    return null;
  }

  Future<void> _maybeLog(NotificationData notification) async {
    try {
      // Skip self-sent / outgoing notifications (never log or extract notes from them)
      final senderLower = notification.sender.trim().toLowerCase();
      if (senderLower == 'you' || senderLower == 'me') return;
      final msgLower = notification.message.trim().toLowerCase();
      if (msgLower.startsWith('you:') ||
          msgLower.startsWith('me:') ||
          msgLower.startsWith('you sent:')) {
        return;
      }

      // Only log if native would have replied (same rule check, no sending)
      final allRules = _ruleRepository.getEnabledRules();
      final lower = notification.message.trim().toLowerCase();

      // Skip self-sent
      if (allRules.any((r) => r.effectiveReplies
          .any((reply) => reply.trim().toLowerCase() == lower))) {
        return;
      }

      // Track every notification received (only for actual external messages)
      await _logRepository.incrementNotificationsReceived();

      // Automatically extract actionable notes, meetings, and reminders
      final extractedNote = await _noteExtractionService.processMessage(
        notification.sender,
        notification.message,
        appName: notification.appName,
      );
      if (extractedNote != null && _providerContainer != null) {
        _providerContainer!.read(notesProvider.notifier).loadNotes();
      }

      // For rule-based replies, create the log here
      final settings = _providerContainer?.read(appSettingsProvider);
      final rule = _ruleRepository.findMatchingRule(
        notification.message,
        sender: notification.sender,
        settings: settings,
      );
      if (rule == null) return;

      final log = _logRepository.createLog(
        sender: notification.sender,
        originalMessage: notification.message,
        autoReplySent: rule.replyText,
        appName: notification.appName,
        ruleId: rule.id,
      );
      await _logRepository.addLog(log);

      if (_providerContainer != null) {
        final notifier = _providerContainer!.read(logsProvider.notifier);
        await notifier.refreshLogs();
      }
    } catch (e) {
      print('AutoReplyService logging error: $e');
    }
  }

  Future<void> _logReply(Map<String, dynamic> data) async {
    try {
      // Only log AI replies here (rule-based replies are logged in _maybeLog)
      if (data['isAiReply'] != true) return;

      final rawOriginal = (data['originalMessage'] ?? '').toString().trim();
      final log = _logRepository.createLog(
        sender: data['sender'] ?? '',
        originalMessage:
            rawOriginal.isNotEmpty ? rawOriginal : 'AI Generated Reply',
        autoReplySent: data['replyText'] ?? '',
        appName: data['appName'] ?? '',
        ruleId: '',
      );
      log.aiModel = data['aiModelType'] as String? ?? '';
      await _logRepository.addLog(log);

      if (_providerContainer != null) {
        final notifier = _providerContainer!.read(logsProvider.notifier);
        await notifier.refreshLogs();
      }
    } catch (e) {
      print('AutoReplyService reply logging error: $e');
    }
  }
}
