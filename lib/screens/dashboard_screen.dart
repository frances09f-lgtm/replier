import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../providers/statistics_provider.dart';
import '../providers/log_provider.dart';
import '../providers/rule_provider.dart';
import '../providers/reply_countdown_provider.dart';
import '../providers/ai_usage_provider.dart';
import '../utils/ai_engine_display.dart';
import '../widgets/pipeline_analysis_card.dart';
import '../widgets/analysis_countdown_card.dart';
import '../providers/analysis_status_provider.dart';
import '../providers/pipeline_status_provider.dart';
import '../theme/draft_theme.dart';
import '../theme/draft_widgets.dart';
import 'notes_screen.dart';
import 'settings_screen.dart';
import 'package:intl/intl.dart';
import '../providers/note_provider.dart';

/// Dashboard screen with master switch and quick-action navigation
class DashboardScreen extends ConsumerWidget {
  final void Function(int tab)? onGoToTab;
  const DashboardScreen({super.key, this.onGoToTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final replyCountdown = ref.watch(replyCountdownProvider);
    final c = DraftColors.of(context);

    final apps = <String>[
      if (settings.whatsappEnabled) 'WhatsApp',
      if (settings.instagramEnabled) 'Instagram',
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(logsProvider.notifier).refreshLogs();
          ref.read(rulesProvider.notifier).refreshRules();
          await ref.read(aiUsageProvider.notifier).loadUsage();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
          children: [
            Text('Dashboard', style: DraftText.display(30, c.tx)),
            const SizedBox(height: 10),

            // Master reply switch hero (draft centerpiece)
            MasterSwitchCard(
              on: settings.masterEnabled,
              onChanged: (_) async {
                try {
                  await ref
                      .read(appSettingsProvider.notifier)
                      .toggleMasterEnabled();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              statusText: settings.masterEnabled
                  ? (apps.isEmpty
                      ? 'Listening to notifications'
                      : 'Listening to ${apps.join(', ')}')
                  : 'Paused. Incoming messages get no reply.',
            ),
            const SizedBox(height: 12),

            // Analysis card (draft): resting ring, live countdown when a
            // reply is scheduled, pipeline stage while processing.
            _buildAnalysisCard(context, ref, replyCountdown),

            // Today statistics
            _buildStatsGrid(context, ref, stats),
            const SizedBox(height: 16),
            _buildAiUsageSection(context, ref),
            const SizedBox(height: 16),
            _buildRecentActivity(context, ref),
            const SizedBox(height: 16),
            _buildSetupChecklist(context, ref),
          ],
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

    final cAi = DraftColors.of(context);
    return DraftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI usage', style: DraftText.display(19, cAi.tx)),
          const SizedBox(height: 6),
          Column(
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
        ],
      ),
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

  Widget _buildAnalysisCard(BuildContext context, WidgetRef ref,
      ReplyCountdownData countdown) {
    final analyses = ref.watch(analysisStatusProvider);
    final pipeline = ref.watch(pipelineStatusProvider);
    // One fixed-height slot for every state (see kAnalysisCardHeight): with
    // several attempts in flight, show the newest-listed one plus "+N more"
    // instead of stacking cards.
    if (analyses.isNotEmpty) {
      final a = analyses.first;
      return AnalysisCountdownCard(
          key: ValueKey(a.id),
          status: a,
          extraCount: analyses.length - 1);
    }
    if (pipeline.stage != null) {
      return PipelineAnalysisCard(status: pipeline);
    }
    if (countdown.isActive) {
      final secs = countdown.remainingMs ~/ 1000;
      return DraftAnalysisCard(
        progress: countdown.progress,
        ringLabel: '$secs',
        text:
            'Reply to ${countdown.sender} is scheduled. Sending in ${countdown.remainingFormatted}.',
      );
    }
    return const DraftAnalysisCard(
      progress: 0,
      ringLabel: '--',
      text: 'Idle. Analysis starts when a new message arrives.',
      idle: true,
    );
  }

  Widget _buildStatsGrid(
      BuildContext context, WidgetRef ref, Map<String, dynamic> stats) {
    final dailyReplies = stats['dailyRepliesSent'] as int? ?? 0;
    final activeNotesCount = ref.watch(activeNotesCountProvider);
    final logs = ref.watch(logsProvider);
    final now = DateTime.now();
    final todayLogs = logs
        .where((l) =>
            l.dateTime.year == now.year &&
            l.dateTime.month == now.month &&
            l.dateTime.day == now.day)
        .toList();
    final ruleReplies = todayLogs.where((l) => l.ruleId.isNotEmpty).length;
    // Only AI replies actually sent: failure / pipeline-event entries (skip
    // reasons, "Ignored WhatsApp summary notification", errors) share the logs
    // box with empty ruleId and must not count.
    final aiReplies = todayLogs.where((l) => l.isAiReplySent).length;
    final c = DraftColors.of(context);

    final settings = ref.watch(appSettingsProvider);
    final int limit;
    switch (settings.aiModelType) {
      case 'groq_api':
        limit = settings.groqReplyLimit;
        break;
      case 'gemini_api':
        limit = settings.geminiReplyLimit;
        break;
      default:
        limit = settings.localReplyLimit;
    }

    Widget stat(String value, String label, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          child: DraftStat(value: value, label: label),
        );

    return DraftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today', style: DraftText.display(19, c.tx)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.1,
            children: [
              stat(dailyReplies.toString(), 'Replies sent',
                  () => _showAiReplyBreakdown(context, ref)),
              stat(ruleReplies.toString(), 'Rules matched', () {
                if (onGoToTab != null) onGoToTab!(1);
              }),
              stat(aiReplies.toString(), 'AI replies', () {
                if (onGoToTab != null) onGoToTab!(3);
              }),
              stat(activeNotesCount.toString(), 'Notes', () {
                if (onGoToTab != null) {
                  onGoToTab!(4);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const NotesScreen()),
                  );
                }
              }),
            ],
          ),
          if (limit > 0) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Daily limit', style: DraftText.body(13.5, c.mut)),
                Text('$dailyReplies of $limit',
                    style: DraftText.body(13.5, c.tx,
                        weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            DraftProg(progress: (dailyReplies / limit).clamp(0.0, 1.0)),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logsProvider);
    final c = DraftColors.of(context);
    final sorted = [...logs]..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final recent = sorted.take(3).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    return DraftCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent activity', style: DraftText.display(19, c.tx)),
                if (onGoToTab != null)
                  DraftButton.tertiary('All logs',
                      onPressed: () => onGoToTab!(3)),
              ],
            ),
            const SizedBox(height: 6),
            ...recent.map((log) {
              final isWa = log.appName.toLowerCase().contains('whats');
              final badgeColor =
                  isWa ? const Color(0xFF1D7A4D) : const Color(0xFFA8326A);
              final source = log.ruleId.isNotEmpty ? 'Rule' : 'AI';
              final time = DateFormat.jm().format(log.dateTime);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        isWa ? 'W' : 'I',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.sender,
                            style: DraftText.body(15, c.tx,
                                weight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$source reply sent, $time',
                            style: DraftText.body(12.5, c.mut),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
    );
  }

  Widget _buildSetupChecklist(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final perms = ref.watch(permissionStatusProvider);
    final c = DraftColors.of(context);
    final steps = <bool>[
      perms['notificationListener'] ?? false,
      perms['postNotification'] ?? false,
      perms['batteryOptimization'] ?? false,
      settings.confirmBeforeReply,
      settings.ignoreGroupChats,
      settings.contactWhitelistEnabled,
      settings.whatsappEnabled || settings.instagramEnabled,
    ];
    final done = steps.where((s) => s).length;
    if (done == steps.length) return const SizedBox.shrink();
    return DraftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Setup checklist', style: DraftText.display(19, c.tx)),
          const SizedBox(height: 4),
          Text('$done of ${steps.length} steps done',
              style: DraftText.body(13.5, c.mut)),
          const SizedBox(height: 10),
          DraftProg(progress: done / steps.length),
          const SizedBox(height: 12),
          DraftButton.secondary(
            'Open setup checklist',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
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


}
