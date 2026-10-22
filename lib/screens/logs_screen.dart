import 'package:flutter/material.dart';
import '../legacy/history.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/draft_theme.dart';
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getAppIcon(log.appName),
                  size: 20,
                  color: _getAppColor(log.appName),
                ),
                const SizedBox(width: 8),
                Text(
                  log.appName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (log.aiModel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.aiModel,
                      style: const TextStyle(fontSize: 10, color: Colors.blue),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  DateFormat('MMM dd, HH:mm').format(log.dateTime),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    log.sender,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  left: BorderSide(color: Colors.blue, width: 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THEY SAID:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    log.originalMessage.isNotEmpty
                        ? log.originalMessage
                        : '(no incoming text captured)',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  left: BorderSide(color: Colors.green, width: 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SUBMITTED (DELIVERY UNCONFIRMED):',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    log.autoReplySent,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
            if (log.trained && log.correctedReply.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green, width: 0.6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Trained: "${log.correctedReply}"',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.thumb_up,
                    size: 20,
                    color: isGood ? Colors.green : Colors.grey,
                  ),
                  tooltip: 'Good reply',
                  onPressed: () => _rateGood(context, ref, log),
                ),
                IconButton(
                  icon: Icon(
                    Icons.thumb_down,
                    size: 20,
                    color: isBad ? Colors.red : Colors.grey,
                  ),
                  tooltip: 'Bad reply',
                  onPressed: () => _showFeedbackDialog(context, ref, log),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.school, size: 16),
                  label: Text(
                    log.trained ? 'Edit training' : 'Teach better reply',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _showFeedbackDialog(context, ref, log),
                ),
              ],
            ),
          ],
        ),
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

  IconData _getAppIcon(String appName) {
    switch (appName) {
      case 'WhatsApp':
        return Icons.chat;
      case 'Instagram':
        return Icons.camera_alt;
      default:
        return Icons.apps;
    }
  }

  Color _getAppColor(String appName) {
    switch (appName) {
      case 'WhatsApp':
        return Colors.green;
      case 'Instagram':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }
}
