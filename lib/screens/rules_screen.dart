import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/draft_theme.dart';
import '../theme/draft_widgets.dart';
import '../models/rule.dart';
import '../providers/rule_provider.dart';
import 'add_edit_rule_screen.dart';

/// Screen for managing auto-reply rules
class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(filteredRulesProvider);
    ref.watch(searchQueryProvider); // keep reactive so list rebuilds on search

    final c = DraftColors.of(context);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
            child: Row(
              children: [
                Expanded(
                    child: Text('Manage rules',
                        style: DraftText.display(30, c.tx))),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    showSearch(
                      context: context,
                      delegate: RuleSearchDelegate(ref),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: rules.isEmpty
                ? _EmptyRulesView(onAddRule: () => _navigateToAddRule(context))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: rules.length,
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      return _RuleCard(
                        rule: rule,
                        onEdit: () => _navigateToEditRule(context, rule),
                        onDelete: () => _deleteRule(context, ref, rule.id),
                        onToggle: () => ref
                            .read(rulesProvider.notifier)
                            .toggleRuleEnabled(rule.id),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAddRule(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _navigateToAddRule(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddEditRuleScreen()),
    );
  }

  void _navigateToEditRule(BuildContext context, Rule rule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditRuleScreen(rule: rule),
      ),
    );
  }

  void _deleteRule(BuildContext context, WidgetRef ref, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule'),
        content: const Text('Are you sure you want to delete this rule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(rulesProvider.notifier).deleteRule(id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyRulesView extends StatelessWidget {
  final VoidCallback onAddRule;

  const _EmptyRulesView({required this.onAddRule});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rule,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No rules yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first auto-reply rule',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAddRule,
            icon: const Icon(Icons.add),
            label: const Text('Add Rule'),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final Rule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _RuleCard({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final triggers = rule.effectiveTriggers;
    final replies = rule.effectiveReplies;
    final senders = rule.senderNames;
    final triggerLabel =
        triggers.length == 1 ? triggers.first : triggers.join(' · ');
    final replyLabel =
        replies.length == 1 ? replies.first : replies.join(' · ');
    final senderLabel = senders.length == 1
        ? senders.first
        : senders.take(2).join(', ') + (senders.length > 2 ? '...' : '');

    final c = DraftColors.of(context);
    return DraftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WHEN A MESSAGE', style: DraftText.eyebrow(c.mut)),
                    const SizedBox(height: 4),
                    Text(
                      triggerLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DraftText.body(16, c.tx,
                          weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              DraftSwitch(
                value: rule.isEnabled,
                onChanged: (_) => onToggle(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Reply: $replyLabel', style: DraftText.body(14, c.mut)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(c, 'Contains Match', ok: true),
              if (senders.isEmpty)
                _chip(c, 'Anyone')
              else
                _chip(
                    c,
                    senderLabel +
                        (senders.length > 1 ? ' (${senders.length})' : '')),
              if (triggers.length > 1)
                _chip(c, '${triggers.length} triggers'),
              if (replies.length > 1)
                _chip(c, '${replies.length} replies (random)'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              DraftButton.secondary('Edit', onPressed: onEdit),
              const SizedBox(width: 8),
              DraftButton.tertiary('Delete', onPressed: onDelete),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(DraftColors c, String label, {bool ok = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ok ? c.pc : Colors.transparent,
          border:
              Border.all(color: ok ? Colors.transparent : c.out, width: 1.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style:
                DraftText.body(13, ok ? c.onpc : c.tx, weight: FontWeight.w500)),
      );
}

class RuleSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;

  RuleSearchDelegate(this.ref);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          ref.read(searchQueryProvider.notifier).state = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        ref.read(searchQueryProvider.notifier).state = '';
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildRuleResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildRuleResults(context);
  }

  Widget _buildRuleResults(BuildContext context) {
    ref.read(searchQueryProvider.notifier).state = query;

    return Consumer(
      builder: (context, searchRef, _) {
        final rules = searchRef.watch(filteredRulesProvider);
        if (rules.isEmpty) {
          return _NoRuleSearchResultsView(
            query: query,
            hasRules: searchRef.watch(rulesProvider).isNotEmpty,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rules.length,
          itemBuilder: (context, index) {
            final rule = rules[index];
            return _RuleCard(
              rule: rule,
              onEdit: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddEditRuleScreen(rule: rule),
                  ),
                );
              },
              onDelete: () => _deleteRule(context, rule.id),
              onToggle: () => searchRef
                  .read(rulesProvider.notifier)
                  .toggleRuleEnabled(rule.id),
            );
          },
        );
      },
    );
  }

  void _deleteRule(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule'),
        content: const Text('Are you sure you want to delete this rule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(rulesProvider.notifier).deleteRule(id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _NoRuleSearchResultsView extends StatelessWidget {
  final String query;
  final bool hasRules;

  const _NoRuleSearchResultsView({
    required this.query,
    required this.hasRules,
  });

  @override
  Widget build(BuildContext context) {
    final isSearching = query.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.search,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            isSearching
                ? 'No matching rules found'
                : hasRules
                    ? 'Start typing to search rules'
                    : 'No rules yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (isSearching) ...[
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
