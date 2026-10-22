import 'package:flutter/material.dart';
import '../legacy/history.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/draft_theme.dart';
import '../theme/draft_widgets.dart';
import 'package:intl/intl.dart';
import '../models/reply_log.dart';
import '../providers/log_provider.dart';
import '../providers/settings_provider.dart';

/// Screen for viewing reply logs
class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(filteredLogsProvider);
    final appFilter = ref.watch(appFilterProvider);
    final feedbackFilter = ref.watch(logFeedbackFilterProvider);

    return Scaffold(
      appBar: null,
      body: Column(
        children: [
          Builder(builder: (context) {
            final c = DraftColors.of(context);
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
              child: Row(
                children: [
                  Expanded(
                      child: Text('Logs', style: DraftText.display(30, c.tx))),
                  IconButton(
                                icon: const Icon(Icons.archive_outlined),
                                tooltip: "Previous Replier history",
                                onPressed: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const PreviousHistory()))),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.filter_list),
                              onSelected: (value) {
                                ref.read(appFilterProvider.notifier).state =
                                    value == 'all' ? null : value;
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'all',
                                  child: Text('All Apps'),
                                ),
                                const PopupMenuItem(
                                  value: 'WhatsApp',
                                  child: Text('WhatsApp'),
                                ),
                                const PopupMenuItem(
                                  value: 'Instagram',
                                  child: Text('Instagram'),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _clearLogs(context, ref, appFilter),
                            ),
                ],
              ),
            );
          }),
          Expanded(
            child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _FeedbackChip(
                    label: 'All',
                    value: 'all',
                    current: feedbackFilter,
                    ref: ref),
                const SizedBox(width: 8),
                _FeedbackChip(
                    label: 'Bad 👎',
                    value: 'bad',
                    current: feedbackFilter,
                    ref: ref),
                const SizedBox(width: 8),
                _FeedbackChip(
                    label: 'Unrated',
                    value: 'unrated',
                    current: feedbackFilter,
                    ref: ref),
                const SizedBox(width: 8),
                _FeedbackChip(
                    label: 'Good 👍',
                    value: 'good',
                    current: feedbackFilter,
                    ref: ref),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: DraftWarn(
                'Check the actual conversation - a log entry is not proof of delivery.'),
          ),
          Expanded(
            child: logs.isEmpty
                ? _EmptyLogsView()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return _LogCard(log: log);
                    },
                  ),
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }



  void _clearLogs(BuildContext context, WidgetRef ref, String? appFilter) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Logs'),
        content: Text(appFilter == null
            ? 'Are you sure you want to clear all logs?'
            : 'Are you sure you want to clear logs for $appFilter?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (appFilter == null) {
                ref.read(logsProvider.notifier).clearLogs();
              } else {
                ref.read(logsProvider.notifier).clearLogsByApp(appFilter);
              }
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _EmptyLogsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No logs yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Auto-reply history will appear here',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final WidgetRef ref;

  const _FeedbackChip({
    required this.label,
    required this.value,
    required this.current,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) =>
          ref.read(logFeedbackFilterProvider.notifier).state = value,
    );
  }
}

class _LogCard extends ConsumerWidget {
  final ReplyLog log;

  const _LogCard({required this.log});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGood = log.rating == 1;
    final isBad = log.rating == -1;
    final c = DraftColors.of(context);
    final tt = Theme.of(context).textTheme;
    final isWa = log.appName.toLowerCase().contains('whats');
    final badgeColor =
        isWa ? const Color(0xFF1D7A4D) : const Color(0xFFA8326A);
    return DraftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.sender,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: c.tx,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      DateFormat('MMM dd, HH:mm').format(log.dateTime),
                      style: tt.bodySmall?.copyWith(color: c.mut),
                    ),
                  ],
                ),
                Text(log.appName,
                    style: tt.bodySmall?.copyWith(color: c.mut)),
                const SizedBox(height: 6),
                Text(
                  'In: ${log.originalMessage.isNotEmpty ? log.originalMessage : '(no incoming text captured)'}',
                  style: tt.bodyMedium?.copyWith(color: c.tx),
                ),
                const SizedBox(height: 2),
                Text(
                  'Out: ${log.autoReplySent}',
                  style: tt.bodyMedium?.copyWith(
                    color: c.tx,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _DraftStatusChip(
                      label: 'Submitted',
                      bg: c.tc,
                      fg: c.otc,
                    ),
                    _DraftStatusChip(
                      label:
                          'Source: ${log.aiModel.isNotEmpty ? 'AI' : 'Rule'}',
                      bg: Colors.transparent,
                      fg: c.tx,
                      outlined: true,
                      outline: c.out,
                    ),
                    if (isGood)
                      _DraftStatusChip(
                          label: 'Good', bg: c.pc, fg: c.onpc),
                    if (isBad)
                      _DraftStatusChip(
                          label: 'Bad', bg: c.errc, fg: c.oerr),
                  ],
                ),
                if (log.trained && log.correctedReply.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.s1,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Trained: "${log.correctedReply}"',
                      style: tt.bodySmall?.copyWith(color: c.tx),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    _DraftIconAction(
                      icon: Icons.thumb_up_outlined,
                      activeIcon: Icons.thumb_up,
                      active: isGood,
                      activeColor: c.pri,
                      color: c.mut,
                      tooltip: 'Good reply',
                      onPressed: () => _rateGood(context, ref, log),
                    ),
                    const SizedBox(width: 4),
                    _DraftIconAction(
                      icon: Icons.thumb_down_outlined,
                      activeIcon: Icons.thumb_down,
                      active: isBad,
                      activeColor: c.err,
                      color: c.mut,
                      tooltip: 'Bad reply',
                      onPressed: () => _showFeedbackDialog(context, ref, log),
                    ),
                    const Spacer(),
                    DraftButton.secondary(
                      log.trained ? 'Edit training' : 'Teach better',
                      icon: Icons.school_outlined,
                      onPressed: () => _showFeedbackDialog(context, ref, log),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Batch logs join with " | " — training needs the atomic last message.
  String _trainingKey(String originalMessage) {
    final parts = originalMessage.split(' | ');
    return parts.last.trim().isNotEmpty
        ? parts.last.trim()
        : originalMessage.trim();
  }

  Future<void> _rateGood(
      BuildContext context, WidgetRef ref, ReplyLog target) async {
    // Thumbs up: save as positive training example immediately.
    await ref.read(logsProvider.notifier).rateLog(
          target.id,
          rating: 1,
          feedbackNote: '',
          correctedReply: target.autoReplySent,
          trained: true,
        );
    await ref.read(appSettingsProvider.notifier).addTrainingExample(
        _trainingKey(target.originalMessage), target.autoReplySent);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('👍 Saved! Future replies will copy this style.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showFeedbackDialog(
      BuildContext context, WidgetRef ref, ReplyLog target) {
    final noteCtrl = TextEditingController(text: target.feedbackNote);
    final correctCtrl = TextEditingController(
      text: target.correctedReply.isNotEmpty
          ? target.correctedReply
          : target.autoReplySent,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.school, color: Colors.blue),
            SizedBox(width: 8),
            Text('Teach better reply', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Incoming: "${target.originalMessage}"',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Sent: "${target.autoReplySent}"',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              const Text('What was wrong? (optional)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'e.g. too formal, too long',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text('Correct reply should be: *',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: correctCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'e.g. Ky nahi',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final corrected = correctCtrl.text.trim();
              if (corrected.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please write the correct reply.')),
                );
                return;
              }
              final note = noteCtrl.text.trim();
              await ref.read(logsProvider.notifier).rateLog(
                    target.id,
                    rating: -1,
                    feedbackNote: note,
                    correctedReply: corrected,
                    trained: true,
                  );
              await ref.read(appSettingsProvider.notifier).addTrainingExample(
                  _trainingKey(target.originalMessage), corrected,
                  note: note);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        '✅ Trained! Next similar message will use this style.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Save training'),
          ),
        ],
      ),
    );
  }


}

class _DraftStatusChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final bool outlined;
  final Color? outline;

  const _DraftStatusChip({
    required this.label,
    required this.bg,
    required this.fg,
    this.outlined = false,
    this.outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(999),
        border: outlined ? Border.all(color: outline ?? bg, width: 1.5) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }
}

class _DraftIconAction extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final Color activeColor;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _DraftIconAction({
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.activeColor,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        active ? activeIcon : icon,
        size: 20,
        color: active ? activeColor : color,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
