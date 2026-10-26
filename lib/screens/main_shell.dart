import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../theme/draft_widgets.dart';
import 'dashboard_screen.dart';
import 'rules_screen.dart';
import 'chat_screen.dart';
import 'logs_screen.dart';
import 'notes_screen.dart';
import 'orion_settings_screen.dart';

/// App shell recreating the approved draft layout: pill header bar on top,
/// five tabs, floating pill dock at the bottom.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _tab = 0;

  static const _titles = ['Replier', 'Rules', 'Chat test', 'Logs', 'Notes'];

  void _goToTab(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DraftHeader(
              title: _titles[_tab],
              isDark: isDark,
              onToggleTheme: () {
                final current = ref.read(appSettingsProvider);
                ref
                    .read(appSettingsProvider.notifier)
                    .updateSettings(current.copyWith(darkMode: !isDark));
              },
              onOpenSettings: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OrionSettingsScreen(),
                  ),
                );
              },
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  DashboardScreen(onGoToTab: _goToTab),
                  const RulesScreen(),
                  const ChatScreen(),
                  const LogsScreen(),
                  const NotesScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DraftNav(
        selected: _tab,
        onSelect: _goToTab,
        items: const [
          (icon: Icons.grid_view_rounded, label: 'Dashboard'),
          (icon: Icons.rule_rounded, label: 'Rules'),
          (icon: Icons.chat_bubble_outline_rounded, label: 'Chat'),
          (icon: Icons.history_rounded, label: 'Logs'),
          (icon: Icons.event_note_rounded, label: 'Notes'),
        ],
      ),
    );
  }
}
