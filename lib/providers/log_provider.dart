import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reply_log.dart';
import '../repositories/log_repository.dart';

/// Provider for log repository
final logRepositoryProvider = Provider<LogRepository>((ref) {
  return LogRepository();
});

/// Provider for all logs
final logsProvider = StateNotifierProvider<LogsNotifier, List<ReplyLog>>((ref) {
  final repository = ref.watch(logRepositoryProvider);
  return LogsNotifier(repository);
});

/// Notifier for logs
class LogsNotifier extends StateNotifier<List<ReplyLog>> {
  final LogRepository _repository;

  LogsNotifier(this._repository) : super([]) {
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    state = _repository.getAllLogs();
  }

  Future<void> refreshLogs() async {
    state = _repository.getAllLogs();
  }

  Future<void> addLog(ReplyLog log) async {
    await _repository.addLog(log);
    state = _repository.getAllLogs();
  }

  Future<void> clearLogs() async {
    await _repository.clearLogs();
    state = [];
  }

  Future<void> clearLogsByApp(String appName) async {
    await _repository.clearLogsByApp(appName);
    state = _repository.getAllLogs();
  }

  List<ReplyLog> filterLogsByApp(String? appName) {
    return _repository.filterLogsByApp(appName);
  }

  bool wasReplyRecentlySent(String sender, String message, String reply) {
    return _repository.wasReplyRecentlySent(sender, message, reply);
  }

  ReplyLog? getLastReplyLog() {
    return _repository.getLastReplyLog();
  }

  Future<void> rateLog(
    String id, {
    required int rating,
    String feedbackNote = '',
    String correctedReply = '',
    bool trained = false,
  }) async {
    await _repository.rateLog(
      id,
      rating: rating,
      feedbackNote: feedbackNote,
      correctedReply: correctedReply,
      trained: trained,
    );
    state = _repository.getAllLogs();
  }
}

/// Provider for app filter
final appFilterProvider = StateProvider<String?>((ref) => null);

/// Feedback filter: 'all', 'bad', 'unrated', 'good'
final logFeedbackFilterProvider = StateProvider<String>((ref) => 'all');

/// Provider for filtered logs
final filteredLogsProvider = Provider<List<ReplyLog>>((ref) {
  final logs = ref.watch(logsProvider);
  final appFilter = ref.watch(appFilterProvider);
  final feedbackFilter = ref.watch(logFeedbackFilterProvider);

  var result = logs;
  if (appFilter != null && appFilter.isNotEmpty) {
    result = result.where((l) => l.appName == appFilter).toList();
  }
  switch (feedbackFilter) {
    case 'bad':
      result = result.where((l) => l.rating == -1).toList();
      break;
    case 'good':
      result = result.where((l) => l.rating == 1).toList();
      break;
    case 'unrated':
      result = result.where((l) => l.rating == 0).toList();
      break;
    case 'all':
    default:
      break;
  }
  return result;
});
