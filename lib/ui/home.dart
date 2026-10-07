import 'package:flutter/material.dart';

import '../models/message_event.dart';
import '../state/controller.dart';

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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Replier')),
      body: [
        _Dashboard(c: c),
        _Logs(c: c),
        _Settings(c: c),
      ][_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
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
        Row(children: [
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
        ]),
        if (!c.notifAccess || !c.accessibilityAccess)
          _RestrictedHint(c: c),
        const SizedBox(height: 16),
        Text('Waiting for review (${c.pending.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'V1 sends nothing on its own - every reply below waits for your tap.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (c.lastSendNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(c.lastSendNote,
                style: const TextStyle(color: Colors.amber, fontSize: 12)),
          ),
        if (c.pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No messages yet. Replier listens once notification access is on.',
                  style: TextStyle(color: Colors.white54)),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(ok ? Icons.check_circle : Icons.warning_amber,
                  color: ok ? Colors.greenAccent : Colors.amber, size: 20),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
              Text(ok ? 'Granted' : 'Tap to grant',
                  style: TextStyle(
                      fontSize: 11,
                      color: ok ? Colors.greenAccent : Colors.amber)),
            ]),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            label: const Text('Open App info', style: TextStyle(fontSize: 12)),
          ),
        ]),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Send')),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${e.sender} · ${e.appLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            Text(_fmtTime(e.at),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text(e.text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Divider(height: 16),
          Text(e.generatedReply.isEmpty ? '(no draft)' : e.generatedReply,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.icon(
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Approve'),
              onPressed: () async {
                final note = await c.approve(e);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(note)));
                }
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton(
                onPressed: () => _editAndApprove(context),
                child: const Text('Edit')),
            const SizedBox(width: 8),
            TextButton(onPressed: () => c.reject(e), child: const Text('Reject')),
          ]),
        ]),
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
          child: Text('Nothing logged yet.', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: all.length,
      itemBuilder: (ctx, i) {
        final e = all[i];
        return Card(
          child: ListTile(
            dense: true,
            title: Text('${e.sender} · ${e.appLabel}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${e.text}\nreply: ${e.finalReply.isNotEmpty ? e.finalReply : e.generatedReply}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(e.status,
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
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
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SwitchListTile(
          title: const Text('Auto-reply'),
          subtitle: const Text(
              'V1 sends nothing automatically - replies are drafted for your review. Automatic sending arrives in V2.'),
          value: c.autoReplyEnabled,
          onChanged: (v) => c.setAutoReply(v),
        ),
        const Divider(),
        ListTile(
          title: const Text('Reply brain'),
          subtitle: Text(c.provider.name),
        ),
        ListTile(
          title: const Text('Notification access'),
          subtitle: Text(c.notifAccess ? 'Granted' : 'Not granted'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: c.bridge.openNotificationAccessSettings,
        ),
        ListTile(
          title: const Text('Accessibility access'),
          subtitle: Text(c.accessibilityAccess ? 'Granted' : 'Not granted'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: c.bridge.openAccessibilitySettings,
        ),
        ListTile(
          title: const Text('App info'),
          subtitle: const Text(
              'Fix "Restricted setting": tap the grayed toggle first, then App info > three-dot menu > Allow restricted settings'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: c.bridge.openAppSettings,
        ),
      ],
    );
  }
}

String _fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
}
