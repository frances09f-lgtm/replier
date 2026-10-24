import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../core/hive_config.dart';
import '../core/constants.dart';
import '../models/reply_log.dart';

/// Repository for managing reply logs
@injectable
class LogRepository {
  final Uuid _uuid = const Uuid();

  /// Get all logs
  List<ReplyLog> getAllLogs() {
    final box = HiveConfig.getLogsBox();
    return box.values.toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  /// Get logs by app name
  List<ReplyLog> getLogsByApp(String appName) {
    final logs = getAllLogs();
    return logs.where((log) => log.appName == appName).toList();
  }

  /// Get logs filtered by app name
  List<ReplyLog> filterLogsByApp(String? appName) {
    if (appName == null || appName.isEmpty) {
      return getAllLogs();
    }
    return getLogsByApp(appName);
  }

  /// Add a new log
  Future<void> addLog(ReplyLog log) async {
    final box = HiveConfig.getLogsBox();
    await box.put(log.id, log);
    await incrementDailyRepliesSent();

    // Enforce maximum log limit
    final logs = getAllLogs();
    if (logs.length > AppConstants.maxLogs) {
      // Remove oldest logs
      final logsToRemove = logs.skip(AppConstants.maxLogs);
      for (final log in logsToRemove) {
        await box.delete(log.id);
      }
    }
  }

  /// Clear all logs
  Future<void> clearLogs() async {
    final box = HiveConfig.getLogsBox();
    await box.clear();
  }

  /// Clear logs by app name
  Future<void> clearLogsByApp(String appName) async {
    final box = HiveConfig.getLogsBox();
    final logs = getLogsByApp(appName);
    for (final log in logs) {
      await box.delete(log.id);
    }
  }

  /// Check and reset daily stats if date has changed
  void _checkAndResetDailyStats() {
    final statsBox = HiveConfig.getStatsBox();
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final lastReset = statsBox.get('lastResetDate', defaultValue: '') as String;

    if (lastReset != todayStr) {
      statsBox.put('dailyNotificationsReceived', 0);
      statsBox.put('dailyRepliesSent', 0);
      statsBox.put('lastResetDate', todayStr);
    }
  }

  /// Get total logs count (replies sent)
  int getTotalLogsCount() {
    final box = HiveConfig.getLogsBox();
    return box.length;
  }

  /// Get daily replies sent
  int getDailyRepliesSent() {
    _checkAndResetDailyStats();
    final statsBox = HiveConfig.getStatsBox();
    return statsBox.get('dailyRepliesSent', defaultValue: 0) as int;
  }

  /// Increment daily replies sent counter
  Future<void> incrementDailyRepliesSent() async {
    _checkAndResetDailyStats();
    final statsBox = HiveConfig.getStatsBox();
    final current = statsBox.get('dailyRepliesSent', defaultValue: 0) as int;
    await statsBox.put('dailyRepliesSent', current + 1);
  }

  /// Increment notifications received counter
  Future<void> incrementNotificationsReceived() async {
    _checkAndResetDailyStats();
    final statsBox = HiveConfig.getStatsBox();
    final current =
        statsBox.get('totalNotificationsReceived', defaultValue: 0) as int;
    await statsBox.put('totalNotificationsReceived', current + 1);
    final daily =
        statsBox.get('dailyNotificationsReceived', defaultValue: 0) as int;
    await statsBox.put('dailyNotificationsReceived', daily + 1);
  }

  /// Get total notifications received (all time)
  int getTotalNotificationsReceived() {
    final statsBox = HiveConfig.getStatsBox();
    return statsBox.get('totalNotificationsReceived', defaultValue: 0) as int;
  }

  /// Get daily notifications received
  int getDailyNotificationsReceived() {
    _checkAndResetDailyStats();
    final statsBox = HiveConfig.getStatsBox();
    return statsBox.get('dailyNotificationsReceived', defaultValue: 0) as int;
  }

  /// Get logs count by app
  int getLogsCountByApp(String appName) {
    final box = HiveConfig.getLogsBox();
    return box.values.where((log) => log.appName == appName).length;
  }

  /// Check if a similar reply was recently sent (for duplicate prevention)
  bool wasReplyRecentlySent(String sender, String message, String reply,
      {Duration within = const Duration(minutes: 5)}) {
    final logs = getAllLogs();
    final now = DateTime.now();

    return logs.any((log) =>
        log.sender == sender &&
        log.originalMessage == message &&
        log.autoReplySent == reply &&
        now.difference(log.dateTime) <= within);
  }

  /// Get replies count grouped by AI model (today only, resets at midnight)
  Map<String, int> getAiReplyCounts() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final logs = getAllLogs();
    final counts = <String, int>{};
    for (final log in logs) {
      if (log.aiModel.isNotEmpty &&
          log.dateTime
              .isAfter(todayStart.subtract(const Duration(seconds: 1)))) {
        counts[log.aiModel] = (counts[log.aiModel] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Get last reply log (sent replies only - failures are not replies)
  ReplyLog? getLastReplyLog() {
    final logs = getAllLogs();
    for (final log in logs) {
      if (log.failureReason.isEmpty) return log;
    }
    return null;
  }

  /// Create a log entry for a failed reply attempt.
  /// Privacy: only the failure reason is stored - no sender, message
  /// content, reply text, keys, or tokens.
  ReplyLog createFailureLog(String reason, {String? existingId, DateTime? at}) {
    return ReplyLog(
      id: existingId ?? _uuid.v4(),
      sender: '',
      originalMessage: '',
      autoReplySent: '',
      appName: '',
      dateTime: at ?? DateTime.now(),
      ruleId: '',
      failureReason: reason,
    );
  }

  /// Whether a log with this exact id already exists (dedupe for
  /// pipeline events recovered from the native side).
  bool hasLog(String id) {
    if (id.isEmpty) return false;
    return HiveConfig.getLogsBox().get(id) != null;
  }

  /// Add a failure log. Unlike [addLog], this does NOT increment the
  /// daily-replies-sent counter, because nothing was sent.
  Future<void> addFailureLog(ReplyLog log) async {
    final box = HiveConfig.getLogsBox();
    await box.put(log.id, log);

    // Enforce maximum log limit
    final logs = getAllLogs();
    if (logs.length > AppConstants.maxLogs) {
      final logsToRemove = logs.skip(AppConstants.maxLogs);
      for (final log in logsToRemove) {
        await box.delete(log.id);
      }
    }
  }

  /// Create a new log
  ReplyLog createLog({
    required String sender,
    required String originalMessage,
    required String autoReplySent,
    required String appName,
    required String ruleId,
  }) {
    return ReplyLog(
      id: _uuid.v4(),
      sender: sender,
      originalMessage: originalMessage,
      autoReplySent: autoReplySent,
      appName: appName,
      dateTime: DateTime.now(),
      ruleId: ruleId,
    );
  }

  /// Save user feedback (thumbs rating + optional correction) on a log.
  Future<void> rateLog(
    String id, {
    required int rating,
    String feedbackNote = '',
    String correctedReply = '',
    bool trained = false,
  }) async {
    final box = HiveConfig.getLogsBox();
    final log = box.get(id);
    if (log == null) return;
    final updated = log.copyWith(
      rating: rating,
      feedbackNote: feedbackNote,
      correctedReply: correctedReply,
      trained: trained,
    );
    await box.put(id, updated);
  }
}
