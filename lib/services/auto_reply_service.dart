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
  static Function(Map<String, dynamic>)? onAnalysisStatus;

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

  /// Runs every completed listener. One throwing listener must not stop the
  /// others, otherwise a status card can stay stuck.
  static void _notifyReplyCompleted() {
    for (final fn in List<VoidCallback>.of(_onReplyCompletedListeners)) {
      try {
        fn();
      } catch (e) {
        print('AutoReplyService completed listener error: $e');
      }
    }
  }

  static void _notifyReplyScheduled(Map<String, dynamic> data) {
    for (final fn
        in List<Function(Map<String, dynamic>)>.of(_onReplyScheduledListeners)) {
      try {
        fn(data);
      } catch (e) {
        print('AutoReplyService scheduled listener error: $e');
      }
    }
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
    _drainNativePipelineEvents();
  }

  /// Pull pipeline events recorded natively while the app was closed and turn
  /// them into Logs entries, so off-screen failures and skips stay visible.
  Future<void> _drainNativePipelineEvents() async {
    try {
      final dynamic events =
          await _notificationChannel.invokeMethod('getPipelineEvents');
      if (events is! List || events.isEmpty) return;
      int added = 0;
      for (final raw in events) {
        try {
          final event = json.decode(raw.toString()) as Map<String, dynamic>;
          final reason =
              _sanitizeFailureReason(event['reason']?.toString() ?? '');
          if (reason.isEmpty) continue;
          final id = event['id']?.toString() ?? '';
          if (_logRepository.hasLog(id)) continue;
          final ts = int.tryParse('${event['ts'] ?? ''}');
          final log = _logRepository.createFailureLog(
            reason,
            existingId: id.isEmpty ? null : id,
            at: ts == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(ts),
          );
          await _logRepository.addFailureLog(log);
          added++;
        } catch (e) {
          print('AutoReplyService pipeline event error: $e');
        }
      }
      if (added > 0 && _providerContainer != null) {
        final notifier = _providerContainer!.read(logsProvider.notifier);
        await notifier.refreshLogs();
      }
    } catch (e) {
      // Native side unavailable (unit tests, or listener offline): nothing to drain.
      print('AutoReplyService drain error: $e');
    }
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
      case 'onAnalysisStatus':
        if (call.arguments != null) {
          final data =
              json.decode(call.arguments as String) as Map<String, dynamic>;
          onAnalysisStatus?.call(data);
          // The correlated analysis display owns these states. Do not let an
          // unrelated global reply-completed callback clear another attempt.
          onPipelineStatus?.call({'state': 'analysis_managed'});
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
        _notifyReplyCompleted();
        if (_instance != null) {
          final reason =
              _sanitizeFailureReason(call.arguments?.toString() ?? '');
          if (reason.isNotEmpty) {
            try {
              await _instance!._logFailure(reason);
            } catch (e) {
              print('AutoReplyService failure logging error: $e');
            }
          }
        }
        break;
      case 'onReplySuccess':
        // Clear the status cards first. The log write below touches Hive and
        // re-sorts every log, and the cards used to wait for it.
        _notifyReplyCompleted();
        if (_instance != null && call.arguments != null) {
          try {
            final data =
                json.decode(call.arguments as String) as Map<String, dynamic>;
            await _instance!._logReply(data);
          } catch (e) {
            print('AutoReplyService onReplySuccess error: $e');
          }
        }
        break;
      case 'onReplyScheduled':
        if (call.arguments != null) {
          final data =
              json.decode(call.arguments as String) as Map<String, dynamic>;
          _notifyReplyScheduled(data);
        }
        break;
      case 'onNotificationRemoved':
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

  /// Keep only a short, technical failure reason. A native exception message
  /// could in theory carry message content or a key, so redact token-like
  /// runs and cap the length before anything is persisted.
  static String _sanitizeFailureReason(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    // URLs: keep scheme + host (which provider failed stays visible), drop
    // userinfo, path and query (can carry keys or echoed content).
    s = s.replaceAllMapped(
        RegExp(r'(https?://)([^/?@\s]+@)?([^/?\s]+)[^\s]*'),
        (m) => '${m[1]}${m[3]}/...');
    // Auth headers / bearer tokens.
    s = s.replaceAllMapped(
        RegExp(r'(bearer|authorization:?)\s+\S+', caseSensitive: false),
        (m) => '${m[1]} [redacted]');
    // Email addresses.
    s = s.replaceAll(RegExp(r'[^\s@]+@[^\s@]+\.[^\s@]+'), '[email]');
    // Long token-like runs (API keys, secrets). Must run before the phone
    // rule so digit-heavy keys are redacted, not mangled.
    s = s.replaceAllMapped(
        RegExp(r'[A-Za-z0-9_\-]{32,}'), (_) => '[redacted]');
    // Phone numbers (8+ digits allowing +, spaces and dashes).
    s = s.replaceAll(RegExp(r'\+?\d[\d \-]{6,}\d'), '[number]');
    const maxLen = 200;
    if (s.length > maxLen) s = s.substring(0, maxLen);
    return s;
  }

  /// Persist a failed attempt so the Logs tab shows WHY nothing was sent.
  Future<void> _logFailure(String reason) async {
    final log = _logRepository.createFailureLog(reason);
    await _logRepository.addFailureLog(log);
    if (_providerContainer != null) {
      final notifier = _providerContainer!.read(logsProvider.notifier);
      await notifier.refreshLogs();
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
