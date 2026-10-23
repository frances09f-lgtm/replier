import 'package:flutter/material.dart';
import '../models/message_event.dart';
import '../services/ai/reply_settings.dart';
import '../state/controller.dart';
import 'local_settings.dart';
import 'settings_style.dart';

class ReplierHome extends StatefulWidget {
  const ReplierHome({super.key, required this.controller});

  final ReplierController controller;

  @override
  State<ReplierHome> createState() => _ReplierHomeState();
}

class _ReplierHomeState extends State<ReplierHome> with WidgetsBindingObserver {
  int _tab = 0;

  ReplierController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.refreshPermissions();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached)
      c.cancelLocal();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Replier'),
        actions: [IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => setState(() => _tab = 2),
        )],
      ),
      body: Column(
        children: [
          if (c.legacyInstalled) _LegacyCard(c: c),
          Expanded(
            child: [_Dashboard(c: c), _Logs(c: c), _Settings(c: c)][_tab],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab == 2 ? 0 : _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Logs'),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.c});
  final ReplierController c;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          color: c.masterEnabled
              ? const Color(0xFF173A2A)
              : const Color(0xFF3B2A18),
          child: SwitchListTile(
            title: Text(
              c.masterEnabled ? 'Replier ON' : 'Replier PAUSED',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              c.masterEnabled
                  ? 'Captures new messages. Drafts need review before sending.'
                  : 'No capture, no drafts, no sends. Saved history is kept.',
            ),
            value: c.masterEnabled,
            onChanged: c.masterSaving
                ? null
                : (on) async {
                    try {
                      await c.setMaster(on);
                    } catch (_) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not change the master switch. Try again.',
                            ),
                          ),
                        );
                    }
                  },
          ),
        ),
        Row(
          children: [
            _PermCard(
              label: 'Notification access',
              ok: c.notifAccess,
              onFix: c.bridge.openNotificationAccessSettings,
            ),
            const SizedBox(width: 8),
            _PermCard(
              label: 'Accessibility access',
              ok: c.accessibilityAccess,
              onFix: c.bridge.openAccessibilitySettings,
            ),
          ],
        ),
        if (!c.notifAccess || !c.accessibilityAccess) _RestrictedHint(c: c),
        const SizedBox(height: 16),
        Text(
          'Waiting for review (${c.pending.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'AI: ${c.brainName}. Drafts need review before sending.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (c.lastSendNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              c.lastSendNote,
              style: const TextStyle(color: Colors.amber, fontSize: 12),
            ),
          ),
        if (c.pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No messages yet. Replier listens once notification access is on.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          )
        else
          for (final e in c.pending) _ReplyCard(e: e, c: c),
      ],
    );
  }
}

class _PermCard extends StatelessWidget {
  const _PermCard({required this.label, required this.ok, required this.onFix});
  final String label;
  final bool ok;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: ok ? null : onFix,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.warning_amber,
                  color: ok ? Colors.greenAccent : Colors.amber,
                  size: 20,
                ),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 12)),
                Text(
                  ok ? 'Granted' : 'Tap to grant',
                  style: TextStyle(
                    fontSize: 11,
                    color: ok ? Colors.greenAccent : Colors.amber,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RestrictedHint extends StatelessWidget {
  const _RestrictedHint({required this.c});
  final ReplierController c;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Switch grayed out, or Android says 'Restricted setting'?",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'On Android 14 the fix is hidden until you trigger it once: '
              '1) Tap the Replier toggle anyway - when the "Restricted setting" '
              'dialog pops up, tap OK. 2) Stay in Settings and open Replier\'s '
              'App info (button below, or Settings > Apps > App management > '
              'Replier). 3) The three-dot menu (top right) should now be there - '
              'tap it > "Allow restricted settings". If the dots are missing, '
              'tap the toggle once more and check again. 4) Grant both '
              'permissions. Fallback: delete Replier and reinstall the APK with '
              'a Play Store installer app (APKMirror Installer or Uptodown APK '
              'Installer) - apps installed that way skip the restriction.',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: c.bridge.openAppSettings,
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text(
                'Open App info',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({required this.e, required this.c});
  final MessageEvent e;
  final ReplierController c;

  Future<void> _editAndApprove(BuildContext context) async {
    final ctrl = TextEditingController(text: e.generatedReply);
    final edited = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit reply'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (edited != null) {
      final note = await c.approve(e, editedText: edited);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(note)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${e.sender} · ${e.appLabel}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  _fmtTime(e.at),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              e.text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const Divider(height: 16),
            Text(
              e.status == 'queued'
                  ? 'Queued for drafting'
                  : e.status == 'generating'
                      ? 'Drafting…'
                      : e.generatedReply.isEmpty
                          ? e.status == 'new'
                              ? 'Queued for drafting'
                              : 'No draft yet'
                          : e.generatedReply,
              style: const TextStyle(fontSize: 14),
            ),
            if (e.generationError.isNotEmpty)
              Text(
                e.generationError,
                style: const TextStyle(color: Colors.amber),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (e.status == 'generation_failed' ||
                    e.status == 'new' ||
                    e.status == 'queued')
                  TextButton(
                    onPressed: c.masterEnabled
                        ? () {
                            c.generate(e);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(c.generationNote)),
                            );
                          }
                        : null,
                    child: const Text('Retry'),
                  ),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  onPressed:
                      !c.masterEnabled ||
                              e.status != 'generated' ||
                              e.generatedReply.isEmpty
                          ? null
                          : () async {
                              final note = await c.approve(e);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text(note)));
                              }
                            },
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: e.status == 'generating'
                      ? null
                      : () => _editAndApprove(context),
                  child: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => c.reject(e),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Logs extends StatelessWidget {
  const _Logs({required this.c});
  final ReplierController c;

  @override
  Widget build(BuildContext context) {
    final all = c.history;
    if (all.isEmpty) {
      return const Center(
        child: Text(
          'Nothing logged yet.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: all.length,
      itemBuilder: (ctx, i) {
        final e = all[i];
        return Card(
          child: ListTile(
            dense: true,
            title: Text(
              '${e.sender} · ${e.appLabel}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${e.text}\nreply: ${e.finalReply.isNotEmpty ? e.finalReply : e.generatedReply}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: SizedBox(
              width: 145,
              child: Text(
                e.statusLabel,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Settings extends StatefulWidget {
  const _Settings({required this.c});
  final ReplierController c;

  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  bool? _dark;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final dark = _dark ?? Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: settingsTheme(dark),
      child: Builder(builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return ColoredBox(
          color: colors.surface,
          child: ListView(
            key: const PageStorageKey('orion-settings'),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              Text('Settings', style: TextStyle(fontSize: 42,
                  fontWeight: FontWeight.w600, letterSpacing: -1.2,
                  color: colors.onSurface)),
              const SizedBox(height: 8),
              Text('Your reply settings. Existing reply behavior is unchanged.',
                  style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              SettingsSection(title: 'Appearance', icon: Icons.dark_mode_outlined,
                child: Row(children: [
                  Expanded(child: _themePick(context, 'Light', false, dark)),
                  const SizedBox(width: 8),
                  Expanded(child: _themePick(context, 'Dark', true, dark)),
                ])),
              SettingsSection(title: 'Auto reply', icon: Icons.bolt_outlined, alt: true,
                child: Column(children: [
                  SwitchListTile(
                    title: const Text('Master reply switch'),
                    subtitle: const Text('Turns message capture and reply drafts on or off.'),
                    value: c.masterEnabled,
                    onChanged: c.masterSaving ? null : (on) async {
                      try {
                        await c.setMaster(on);
                      } catch (_) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not change the master switch. Try again.')));
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  const ListTile(
                    title: Text('Confirm before reply'),
                    subtitle: Text('Always on. Review and approve each reply before sending.'),
                    trailing: Icon(Icons.lock_outline),
                  ),
                  SwitchListTile(
                    title: const Text('Reply as me'),
                    subtitle: const Text('AI drafts replies in your own first-person voice.'),
                    value: c.replyAsUser,
                    onChanged: (val) async {
                      await c.setReplyAsUser(val);
                      if (mounted) setState(() {});
                    },
                  ),
                  const ListTile(title: Text('Daily reply limit'),
                    subtitle: Text('Not available in this branch. No new limit is applied.')),
                ])),
              SettingsSection(title: 'AI provider', icon: Icons.auto_awesome_outlined,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ListTile(title: const Text('Reply brain'), subtitle: Text(c.brainName)),
                  if (c.replySettings != null) _GroqSettings(c: c),
                  if (c.replySettings != null) LocalModelSettings(c: c),
                  const SizedBox(height: 8),
                  const Text('Gemini and Cloudflare are not available in this branch.'),
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: colors.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20)),
                    child: Text('On-device models keep message text on this phone. Groq receives message text and recent notification context when selected.',
                      style: TextStyle(color: colors.onTertiaryContainer))),
                ])),
              const SettingsSection(title: 'Schedule', icon: Icons.schedule_outlined, alt: true,
                child: Text('Scheduled hours and days are not available in this branch. No schedule is applied.')),
              const SettingsSection(title: 'Contacts', icon: Icons.person_outline,
                child: Text('Contact whitelist and group-chat settings are not available in this branch. Existing message filtering is unchanged.')),
              SettingsSection(title: 'Apps and access', icon: Icons.grid_view_outlined, alt: true,
                child: Column(children: [
                  ListTile(title: const Text('Notification access'),
                    subtitle: Text(c.notifAccess ? 'Granted' : 'Not granted'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: c.bridge.openNotificationAccessSettings),
                  ListTile(title: const Text('Accessibility access'),
                    subtitle: Text(c.accessibilityAccess ? 'Granted' : 'Not granted'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: c.bridge.openAccessibilitySettings),
                  const ListTile(title: Text('Listening apps'),
                    subtitle: Text('App-specific switches are not available in this branch.')),
                  ListTile(title: const Text('App info'),
                    subtitle: const Text('Fix "Restricted setting": tap the grayed toggle first, then App info > three-dot menu > Allow restricted settings'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: c.bridge.openAppSettings),
                ])),
              const SettingsSection(title: 'About', icon: Icons.info_outline,
                child: Text('Settings UI preview on the local-reply-engine branch. No release or version change. Clear logs and reset settings are not added.')),
            ],
          ),
        );
      }),
    );
  }

  Widget _themePick(BuildContext context, String label, bool value, bool dark) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(selected: value == dark,
      child: OutlinedButton(
        onPressed: () => setState(() => _dark = value),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 72),
          backgroundColor: value == dark ? colors.primaryContainer : colors.surface,
          foregroundColor: value == dark ? colors.onPrimaryContainer : colors.onSurface,
          side: BorderSide(color: value == dark ? colors.primary : colors.outline, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
        child: Text(label)));
  }
}

String _fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
}

class _LegacyCard extends StatelessWidget {
  final ReplierController c;
  const _LegacyCard({required this.c});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Old Replier is installed',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            c.legacyBlocked
                ? 'New Replier is paused. Turn off the old app notification and accessibility access to avoid two listeners.'
                : 'Old app access is off. New Replier can be used.',
          ),
          const Text(
            'This is a separate app. Old settings and drafts stay in the old app; they are not copied. Use the launcher named Replier New.',
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: c.bridge.openNotificationAccessSettings,
                child: const Text('Notification access'),
              ),
              TextButton(
                onPressed: c.bridge.openAccessibilitySettings,
                child: const Text('Accessibility'),
              ),
              TextButton(
                onPressed: c.refreshPermissions,
                child: const Text('Recheck'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _GroqSettings extends StatefulWidget {
  const _GroqSettings({required this.c});
  final ReplierController c;

  @override
  State<_GroqSettings> createState() => _GroqSettingsState();
}

class _GroqSettingsState extends State<_GroqSettings> {
  final keyField = TextEditingController();
  late String model;
  late bool enabled;
  bool saving = false;
  bool obscureKey = true;

  @override
  void initState() {
    super.initState();
    model = widget.c.replySettings!.model;
    enabled = widget.c.replySettings!.mode == 'groq';
  }

  @override
  void dispose() {
    keyField.clear();
    keyField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Groq API settings',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'When enabled, incoming text and up to 6 recent messages from the same chat, plus submitted replies, go to Groq. History is notification-only, not the full chat. Groq may retain data for limited reliability/abuse checks unless ZDR is enabled in your account.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: keyField,
            obscureText: obscureKey,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: widget.c.replySettings!.key.isEmpty
                  ? 'Paste your Groq key'
                  : 'Key saved - paste to replace',
              suffixIcon: TextButton(
                onPressed: () => setState(() => obscureKey = !obscureKey),
                child: Text(obscureKey ? 'Show' : 'Hide')),
              border: const OutlineInputBorder(),
            ),
          ),
          const Text(
            'Encrypted on this phone. Never built into the APK. Do not send keys in chat.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: model,
            items: ReplySettings.models
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(m, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
            onChanged: (m) => setState(() => model = m!),
            decoration: const InputDecoration(labelText: 'Model'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use Groq for drafts'),
            subtitle: const Text(
              'Saving this selects Groq or Off. Local is selected separately below; no automatic cloud fallback.',
            ),
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setState(() => saving = true);
                        try {
                          final key = keyField.text.trim().isEmpty
                              ? widget.c.replySettings!.key
                              : keyField.text.trim();
                          if (enabled && key.isEmpty)
                            throw Exception('missing key');
                          await widget.c.configure(key, model, enabled);
                          keyField.clear();
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Saved. New drafts use these settings.',
                                ),
                              ),
                            );
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not save. Add a key to enable Groq, or check secure storage.',
                                ),
                              ),
                            );
                        }
                        if (mounted) setState(() => saving = false);
                      },
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        try {
                          await widget.c.configure('', model, false);
                          keyField.clear();
                          if (mounted) setState(() => enabled = false);
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not remove key. Try again.',
                                ),
                              ),
                            );
                        }
                      },
                child: const Text('Remove key'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
