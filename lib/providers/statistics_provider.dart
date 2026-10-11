import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/statistics_repository.dart';
import 'settings_provider.dart';
import 'rule_provider.dart';
import 'log_provider.dart';

/// Provider for statistics repository
final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return StatisticsRepository(
    ref.watch(settingsRepositoryProvider),
    ref.watch(ruleRepositoryProvider),
    ref.watch(logRepositoryProvider),
  );
});

/// Provider for dashboard statistics (reactive to logs and rules changes)
final dashboardStatsProvider = Provider<Map<String, dynamic>>((ref) {
  // Watch reactive providers so stats update when data changes
  ref.watch(logsProvider);
  ref.watch(rulesProvider);
  ref.watch(appSettingsProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  return repository.getDashboardStats();
});

/// Provider for total notifications received (reactive)
final totalNotificationsProvider = Provider<int>((ref) {
  ref.watch(logsProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  return repository.getTotalNotificationsReceived();
});

/// Provider for total replies sent (reactive)
final totalRepliesProvider = Provider<int>((ref) {
  ref.watch(logsProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  return repository.getTotalRepliesSent();
});

/// Provider for daily notifications received (reactive)
final dailyNotificationsProvider = Provider<int>((ref) {
  ref.watch(logsProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  return repository.getDailyNotificationsReceived();
});

/// Provider for daily replies sent (reactive)
final dailyRepliesProvider = Provider<int>((ref) {
  ref.watch(logsProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  return repository.getDailyRepliesSent();
});

/// Provider for last reply sent (reactive)
final lastReplyProvider = Provider<DateTime?>((ref) {
  ref.watch(logsProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  return repository.getLastReplySent();
});

/// Provider for active rules count (reactive)
final activeRulesCountProvider = Provider<int>((ref) {
  ref.watch(rulesProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  return repository.getActiveRulesCount();
});
