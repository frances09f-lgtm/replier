import 'package:flutter/material.dart';
import '../theme/draft_theme.dart';
import '../theme/draft_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rule.dart';
import '../providers/rule_provider.dart';

/// Screen for adding or editing a rule.
/// Supports multiple trigger texts and multiple reply texts.
class AddEditRuleScreen extends ConsumerStatefulWidget {
  final Rule? rule;

  const AddEditRuleScreen({super.key, this.rule});

  @override
  ConsumerState<AddEditRuleScreen> createState() => _AddEditRuleScreenState();
}

class _AddEditRuleScreenState extends ConsumerState<AddEditRuleScreen> {
  final _formKey = GlobalKey<FormState>();

  /// Each trigger has its own controller.
  final List<TextEditingController> _triggerControllers = [];

  /// Each reply has its own controller.
  final List<TextEditingController> _replyControllers = [];

  /// Each sender name has its own controller.
  final List<TextEditingController> _senderControllers = [];

  bool _exactMatch = true;
  bool _containsMatch = false;
  bool _caseSensitive = false;
  bool _isEnabled = true;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _exactMatch = rule?.exactMatch ?? true;
    _containsMatch = rule?.containsMatch ?? false;
    _caseSensitive = rule?.caseSensitive ?? false;
    _isEnabled = rule?.isEnabled ?? true;

    // Populate trigger controllers from existing rule
    final triggers = rule?.effectiveTriggers ?? [];
    if (triggers.isEmpty) {
      _triggerControllers.add(TextEditingController());
    } else {
      for (final t in triggers) {
        _triggerControllers.add(TextEditingController(text: t));
      }
    }

    // Populate reply controllers from existing rule
    final replies = rule?.effectiveReplies ?? [];
    if (replies.isEmpty) {
      _replyControllers.add(TextEditingController());
    } else {
      for (final r in replies) {
        _replyControllers.add(TextEditingController(text: r));
      }
    }

    // Populate sender name controllers from existing rule
    final senders = rule?.senderNames ?? [];
    if (senders.isEmpty) {
      _senderControllers.add(TextEditingController());
    } else {
      for (final s in senders) {
        _senderControllers.add(TextEditingController(text: s));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _triggerControllers) {
      c.dispose();
    }
    for (final c in _replyControllers) {
      c.dispose();
    }
    for (final c in _senderControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTrigger() {
    setState(() {
      _triggerControllers.add(TextEditingController());
    });
  }

  void _removeTrigger(int index) {
    if (_triggerControllers.length == 1) return;
    setState(() {
      _triggerControllers[index].dispose();
      _triggerControllers.removeAt(index);
    });
  }

  void _addReply() {
    setState(() {
      _replyControllers.add(TextEditingController());
    });
  }

  void _removeReply(int index) {
    if (_replyControllers.length == 1) return;
    setState(() {
      _replyControllers[index].dispose();
      _replyControllers.removeAt(index);
    });
  }

  void _addSender() {
    setState(() {
      _senderControllers.add(TextEditingController());
    });
  }

  void _removeSender(int index) {
    if (_senderControllers.length == 1) return;
    setState(() {
      _senderControllers[index].dispose();
      _senderControllers.removeAt(index);
    });
  }

  void _saveRule() {
    if (_formKey.currentState!.validate()) {
      _saveRuleAsync();
    }
  }

  Future<void> _saveRuleAsync() async {
    final ruleNotifier = ref.read(rulesProvider.notifier);
    final triggers = _triggerControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final replies = _replyControllers
        .map((c) => c.text.trim())
        .where((r) => r.isNotEmpty)
        .toList();
    final senders = _senderControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final primaryTrigger = triggers.isNotEmpty ? triggers.first : '';
    final primaryReply = replies.isNotEmpty ? replies.first : '';

    if (widget.rule != null) {
      final updatedRule = widget.rule!.copyWith(
        triggerText: primaryTrigger,
        triggerTexts: triggers,
        replyText: primaryReply,
        replies: replies,
        senderNames: senders,
        exactMatch: _exactMatch,
        containsMatch: _containsMatch,
        caseSensitive: _caseSensitive,
        isEnabled: _isEnabled,
      );
      await ruleNotifier.updateRule(updatedRule);
    } else {
      final newRule = ruleNotifier.createRule(
        triggerText: primaryTrigger,
        triggerTexts: triggers,
        replyText: primaryReply,
        replies: replies,
        senderNames: senders,
        exactMatch: _exactMatch,
        containsMatch: _containsMatch,
        caseSensitive: _caseSensitive,
        isEnabled: _isEnabled,
      );
      await ruleNotifier.addRule(newRule);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.rule != null;
    final colorScheme = Theme.of(context).colorScheme;
    final c = DraftColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Rule' : 'Add Rule'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Trigger texts section ─────────────────────────────────────
            DraftCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Row(
              children: [
                Text('TRIGGER TEXTS', style: DraftText.eyebrow(c.mut)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addTrigger,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The rule fires when any of these match the incoming message.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.mut,
                  ),
            ),
            const SizedBox(height: 12),

            ...List.generate(_triggerControllers.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _triggerControllers[i],
                        decoration: InputDecoration(
                          labelText: 'Trigger ${i + 1}',
                          hintText: 'e.g., hi',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.text_fields, size: 18),
                        ),
                        validator: (value) {
                          if (i == 0 &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Enter at least one trigger text';
                          }
                          return null;
                        },
                      ),
                    ),
                    if (_triggerControllers.length > 1) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _removeTrigger(i),
                        icon: Icon(Icons.remove_circle_outline,
                            color: colorScheme.error),
                        tooltip: 'Remove trigger',
                      ),
                    ],
                  ],
                ),
              );
            }),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Reply texts section ───────────────────────────────────────
            DraftCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Row(
              children: [
                Text('REPLY TEXTS', style: DraftText.eyebrow(c.mut)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addReply,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'One reply is randomly selected when the rule fires.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.mut,
                  ),
            ),
            const SizedBox(height: 12),

            ...List.generate(_replyControllers.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _replyControllers[i],
                        decoration: InputDecoration(
                          labelText: 'Reply ${i + 1}',
                          hintText: 'e.g., Hey! I\'ll get back to you soon.',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.reply, size: 18),
                        ),
                        maxLines: 2,
                        validator: (value) {
                          if (i == 0 &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Enter at least one reply text';
                          }
                          return null;
                        },
                      ),
                    ),
                    if (_replyControllers.length > 1) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _removeReply(i),
                        icon: Icon(Icons.remove_circle_outline,
                            color: colorScheme.error),
                        tooltip: 'Remove reply',
                      ),
                    ],
                  ],
                ),
              );
            }),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Sender names section ──────────────────────────────────────
            DraftCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Row(
              children: [
                Text('SPECIFIC CONTACTS', style: DraftText.eyebrow(c.mut)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addSender,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Leave empty to reply to everyone. Add names to reply only to specific contacts.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.mut,
                  ),
            ),
            const SizedBox(height: 12),

            ...List.generate(_senderControllers.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _senderControllers[i],
                        decoration: InputDecoration(
                          labelText: 'Contact ${i + 1}',
                          hintText: 'e.g., John Doe',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.person, size: 18),
                        ),
                      ),
                    ),
                    if (_senderControllers.length > 1) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _removeSender(i),
                        icon: Icon(Icons.remove_circle_outline,
                            color: colorScheme.error),
                        tooltip: 'Remove contact',
                      ),
                    ],
                  ],
                ),
              );
            }),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Match options ─────────────────────────────────────────────
            DraftCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Text('MATCH OPTIONS', style: DraftText.eyebrow(c.mut)),
            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('Exact Match'),
              subtitle: const Text('Message must exactly match a trigger'),
              value: _exactMatch,
              onChanged: (value) {
                setState(() {
                  _exactMatch = value;
                  _containsMatch = !value;
                });
              },
            ),

            SwitchListTile(
              title: const Text('Contains Match'),
              subtitle: const Text('Message must contain a trigger'),
              value: _containsMatch,
              onChanged: (value) {
                setState(() {
                  _containsMatch = value;
                  _exactMatch = !value;
                });
              },
            ),

            SwitchListTile(
              title: const Text('Case Sensitive'),
              subtitle: const Text('Match case exactly'),
              value: _caseSensitive,
              onChanged: (value) {
                setState(() {
                  _caseSensitive = value;
                });
              },
            ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            DraftCard(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
              child: SwitchListTile(
                title: const Text('Enable Rule'),
                subtitle: const Text('Rule will be active when enabled'),
                value: _isEnabled,
                onChanged: (value) {
                  setState(() {
                    _isEnabled = value;
                  });
                },
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: DraftButton(
                isEditing ? 'Update Rule' : 'Add Rule',
                onPressed: _saveRule,
                icon: Icons.check_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
