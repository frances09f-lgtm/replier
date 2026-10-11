import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../providers/statistics_provider.dart';
import '../providers/log_provider.dart';
import '../providers/rule_provider.dart';
import '../providers/reply_countdown_provider.dart';
import '../providers/ai_usage_provider.dart';
import '../utils/ai_engine_display.dart';
import '../widgets/pipeline_status_card.dart';
import 'rules_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'notes_screen.dart';
import '../providers/note_provider.dart';

/// Dashboard screen with master switch and quick-action navigation
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final replyCountdown = ref.watch(replyCountdownProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ChatScreen()),
          );
        },
        child: const Icon(Icons.chat_bubble),
      ),
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(logsProvider.notifier).refreshLogs();
          ref.read(rulesProvider.notifier).refreshRules();
          await ref.read(aiUsageProvider.notifier).loadUsage();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Engine Status Card
              _buildHeroStatusCard(context, ref, settings),

              // Reply delay badge
              if (settings.masterEnabled) ...[
                const SizedBox(height: 12),
                _buildReplyDelayBadge(context, settings, replyCountdown),
              ],

              // Pipeline status box — live real-time processing status
              const PipelineStatusCard(),

              // Schedule status badge
              if (settings.scheduleEnabled) ...[
                const SizedBox(height: 12),
                _buildScheduleBadge(context, settings),
              ],

              // Confirm before reply badge
              if (settings.confirmBeforeReply) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.amber.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFFCD34D)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.shield_outlined,
                              color: Colors.amber.shade900, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Safety Mode: Confirm Before Reply',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'You will be asked to approve each reply',
                                style: TextStyle(
                                  color: Colors.amber.shade800,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Statistics section
              Text(
                'Statistics',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: 12),
              _buildStatsGrid(context, ref, stats),
              const SizedBox(height: 16),
              _buildAiUsageSection(context, ref),
              const SizedBox(height: 24),

              // Quick actions
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: 12),

              _NavigationCard(
                title: 'Notes & Reminders',
                subtitle: 'View meetings and captured notes',
                icon: Icons.event_note_rounded,
                iconColor: const Color(0xFF9333EA),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const NotesScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              _NavigationCard(
                title: 'Manage Rules',
                subtitle: 'Create and edit auto-reply rules',
                icon: Icons.rule_rounded,
                iconColor: const Color(0xFF4F46E5),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const RulesScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              _NavigationCard(
                title: 'View Logs',
                subtitle: 'See all auto-reply history',
                icon: Icons.history_toggle_off_rounded,
                iconColor: const Color(0xFF0D9488),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LogsScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              _NavigationCard(
                title: 'Settings',
                subtitle: 'Configure app preferences',
                icon: Icons.settings_outlined,
                iconColor: const Color(0xFF6366F1),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Known realistic free-tier daily limits per engine (used as defaults when not reported by API)
  static const Map<String, int> _freeTierLimits = {
    'groq_api': 0, // No guessed vendor quota
    'gemini_api': 0, // No guessed vendor quota
    'phi_local': 0, // unlimited – on-device execution
    'deepseek_local': 0, // unlimited – local execution
  };

  Widget _buildAiUsageSection(BuildContext context, WidgetRef ref) {
    ref.watch(logsProvider);
    final aiUsage = ref.watch(aiUsageProvider);
    final settings = ref.watch(appSettingsProvider);
    final replyCounts = ref.read(logRepositoryProvider).getAiReplyCounts();
    final engineIds = {
      ...AiEngineDisplay.allEngineIds,
      ...replyCounts.keys,
      ...aiUsage.providerStats.keys,
    }.toList()
      ..sort();

    // Use user-configured limit if set (> 0), otherwise live API reported limit, otherwise realistic free-tier default
    int limitFor(String engineId, AiProviderUsage? tokenStats) {
      final custom = switch (engineId) {
        'groq_api' => settings.groqReplyLimit,
        'gemini_api' => settings.geminiReplyLimit,
        'phi_local' || 'deepseek_local' => settings.localReplyLimit,
        _ => 0,
      };
      if (custom > 0) return custom;
      if (tokenStats != null && tokenStats.requestsLimit > 0) {
        return tokenStats.requestsLimit;
      }
      return _freeTierLimits[engineId] ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI Usage Today',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < engineIds.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  _buildAiUsageRow(
                    context,
                    engineIds[i],
                    replyCounts[engineIds[i]] ?? 0,
                    aiUsage.providerStats[engineIds[i]],
                    limitFor(engineIds[i], aiUsage.providerStats[engineIds[i]]),
                    isCustomLimit: switch (engineIds[i]) {
                      'groq_api' => settings.groqReplyLimit > 0,
                      'gemini_api' => settings.geminiReplyLimit > 0,
                      'phi_local' ||
                      'deepseek_local' =>
                        settings.localReplyLimit > 0,
                      _ => false,
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiUsageRow(
    BuildContext context,
    String engineId,
    int repliesToday,
    AiProviderUsage? tokenStats,
    int dailyLimit, {
    bool isCustomLimit = false,
  }) {
    final display = AiEngineDisplay.forEngine(engineId);
    final tokensToday = tokenStats?.tokensToday ?? 0;
    final apiRequests = tokenStats?.requestsToday ?? 0;

    final hasLimit = dailyLimit > 0;

    // Real limit reached check:
    // 1. Explicitly marked as limit reached by native (e.g. 429 HTTP error or quota exhausted)
    // 2. API header returned 0 remaining requests
    // 3. Local count has reached or exceeded the daily limit
    final bool isAtLimit = (tokenStats?.isLimitReached == true) ||
        (tokenStats?.requestsRemaining != null &&
            tokenStats!.requestsRemaining! <= 0) ||
        (hasLimit && repliesToday >= dailyLimit);

    // Compute remaining replies accurately:
    final int remainingReplies = isAtLimit
        ? 0
        : (tokenStats?.requestsRemaining != null
            ? tokenStats!.requestsRemaining!
            : (hasLimit ? math.max(0, dailyLimit - repliesToday) : 0));

    final usagePercent = isAtLimit
        ? 1.0
        : (hasLimit
            ? ((dailyLimit - remainingReplies) / dailyLimit).clamp(0.0, 1.0)
            : 0.0);

    final isNearLimit = !isAtLimit && hasLimit && usagePercent >= 0.8;

    final limitColor = isAtLimit
        ? Colors.red
        : isNearLimit
            ? Colors.orange
            : display.color;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: display.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(display.icon, color: display.color, size: 22),
            ),
            title: Text(
              display.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              tokensToday > 0
                  ? '$repliesToday replies · ~$tokensToday tokens · $apiRequests API calls'
                  : '$repliesToday replies today',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: hasLimit
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$repliesToday',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: limitColor,
                            ),
                      ),
                      Text(
                        '/ $dailyLimit',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                            ),
                      ),
                    ],
                  )
                : Text(
                    repliesToday.toString(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: display.color,
                        ),
                  ),
          ),
          // Progress bar — always shown when a limit exists
          if (hasLimit)
            Padding(
              padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Label row: left = status text, right = percentage
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAtLimit
                              ? (tokenStats != null &&
                                      tokenStats.lastError.isNotEmpty &&
                                      (tokenStats.lastError.contains('429') ||
                                          tokenStats.lastError
                                              .toLowerCase()
                                              .contains('quota') ||
                                          tokenStats.lastError
                                              .toLowerCase()
                                              .contains('rate_limit') ||
                                          tokenStats.lastError
                                              .toLowerCase()
                                              .contains('resource_exhausted')))
                                  ? '⚠ Quota exhausted (Rate limited)'
                                  : '⚠ Daily limit reached (0 remaining)'
                              : isNearLimit
                                  ? '$remainingReplies replies remaining'
                                  : isCustomLimit
                                      ? '$remainingReplies of $dailyLimit remaining'
                                      : (tokenStats != null &&
                                              tokenStats.requestsLimit > 0)
                                          ? 'Live API quota · $remainingReplies of $dailyLimit remaining'
                                          : 'Local cap · $remainingReplies of $dailyLimit remaining',
                          style: TextStyle(
                            color: isAtLimit
                                ? Colors.red
                                : isNearLimit
                                    ? Colors.orange
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: isAtLimit || isNearLimit
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      Text(
                        '${(usagePercent * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: limitColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usagePercent,
                      minHeight: 6,
                      backgroundColor: limitColor.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(limitColor),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(
      BuildContext context, WidgetRef ref, Map<String, dynamic> stats) {
    final dailyReplies = stats['dailyRepliesSent'] as int? ?? 0;
    final activeNotesCount = ref.watch(activeNotesCountProvider);

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.reply,
            label: 'Today\'s Replies',
            value: dailyReplies.toString(),
            color: Colors.green,
            onTap: () => _showAiReplyBreakdown(context, ref),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.event_note_rounded,
            label: 'Notes',
            value: activeNotesCount.toString(),
            color: const Color(0xFF9333EA),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotesScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReplyDelayBadge(BuildContext context, AppSettings settings,
      ReplyCountdownData countdown) {
    final min = settings.minReplyDelaySeconds;
    final max = settings.maxReplyDelaySeconds;

    if (countdown.isActive) {
      return Card(
        color: Colors.teal.shade50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  value: countdown.progress,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                  backgroundColor: Colors.teal.shade100,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Replying to ${countdown.sender}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (countdown.replyText.isNotEmpty)
                      Text(
                        '"${countdown.replyText}"',
                        style: TextStyle(
                          color: Colors.teal.shade600,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        countdown.remainingFormatted,
                        style: TextStyle(
                          color: Colors.teal.shade600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                countdown.remainingFormatted,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.timer, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reply Delay',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    min == max
                        ? 'Fixed ${min}s delay before reply'
                        : 'Random delay ${min}s – ${max}s before reply',
                    style: TextStyle(
                      color: Colors.blue.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleBadge(BuildContext context, AppSettings settings) {
    final isWithin = settings.isWithinSchedule();
    final startHour = settings.scheduleStartHour;
    final startMin = settings.scheduleStartMinute;
    final endHour = settings.scheduleEndHour;
    final endMin = settings.scheduleEndMinute;

    final startStr = _formatTime(startHour, startMin);
    final endStr = _formatTime(endHour, endMin);

    final color = isWithin ? Colors.green : Colors.orange;
    final bgColor = isWithin ? Colors.green.shade50 : Colors.orange.shade50;
    final icon = isWithin ? Icons.check_circle : Icons.pause_circle;
    final statusText = isWithin ? 'Active' : 'Paused';
    final detailText = isWithin
        ? 'Auto-reply is active ($startStr - $endStr)'
        : 'Auto-reply paused (outside $startStr - $endStr)';

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Schedule: $statusText',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detailText,
                    style: TextStyle(
                      color: color.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  void _showAiReplyBreakdown(BuildContext context, WidgetRef ref) {
    final repository = ref.read(logRepositoryProvider);
    final counts = repository.getAiReplyCounts();
    final totalAi = counts.values.fold(0, (a, b) => a + b);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'AI Replies Breakdown',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                "Today's AI replies: $totalAi",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 16),
              if (counts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No AI replies recorded yet',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ),
                )
              else
                ...counts.entries.map((entry) =>
                    _buildAiModelRow(context, entry.key, entry.value)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAiModelRow(BuildContext context, String modelKey, int count) {
    final display = AiEngineDisplay.forEngine(modelKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(display.icon, color: display.color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              display.label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: display.color,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatusCard(
      BuildContext context, WidgetRef ref, AppSettings settings) {
    final isEnabled = settings.masterEnabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isEnabled
            ? const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isEnabled
            ? null
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isEnabled ? Colors.white : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEnabled ? 'ENGINE ACTIVE' : 'ENGINE PAUSED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: isEnabled
                              ? Colors.white.withValues(alpha: 0.9)
                              : (isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Auto-Reply Assistant',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isEnabled
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEnabled
                        ? 'Listening to notifications...'
                        : 'Auto-reply is currently disabled',
                    style: TextStyle(
                      fontSize: 12,
                      color: isEnabled
                          ? Colors.white.withValues(alpha: 0.8)
                          : (isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.1,
              child: Switch.adaptive(
                value: isEnabled,
                thumbColor: WidgetStateProperty.all(Colors.white),
                activeTrackColor: Colors.white.withValues(alpha: 0.3),
                inactiveThumbColor: Colors.grey.shade400,
                onChanged: (value) async {
                  try {
                    await ref
                        .read(appSettingsProvider.notifier)
                        .toggleMasterEnabled();
                  } catch (e) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (onTap != null)
                    Icon(Icons.info_outline,
                        size: 16, color: color.withValues(alpha: 0.5)),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _NavigationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
