// Web-only preview entry: renders the real v1.1.0 UI with seeded sample data.
// Not shipped in the APK (main.dart is the app entry). Used to generate
// honest screenshots of the shipped design for design comparison.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants.dart';
import 'core/default_rules.dart';
import 'core/provider_container.dart';
import 'legacy/message_event.dart';
import 'models/app_settings.dart';
import 'models/chat_message.dart';
import 'models/note.dart';
import 'models/reply_log.dart';
import 'models/rule.dart';
import 'providers/settings_provider.dart';
import 'screens/main_shell.dart';
import 'theme/draft_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MessageEventAdapter());
  if (!Hive.isAdapterRegistered(51)) Hive.registerAdapter(RuleAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(AppSettingsAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ReplyLogAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(ChatMessageAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(NoteAdapter());
  await Hive.openBox<MessageEvent>('events');
  final rules = await Hive.openBox<Rule>(AppConstants.rulesBox);
  final settings = await Hive.openBox<AppSettings>(AppConstants.settingsBox);
  final logs = await Hive.openBox<ReplyLog>(AppConstants.logsBox);
  final chat = await Hive.openBox<ChatMessage>(AppConstants.chatBox);
  final notes = await Hive.openBox<Note>(AppConstants.notesBox);

  if (settings.isEmpty) {
    await settings.put(
        'settings',
        AppSettings(
          masterEnabled: true,
          whatsappEnabled: true,
          instagramEnabled: true,
          confirmBeforeReply: true,
          scheduleEnabled: true,
          lastUpdated: DateTime.now(),
        ));
  }
  if (rules.isEmpty) {
    for (final r in defaultRules.take(12)) {
      await rules.put(r.id, r);
    }
  }
  if (logs.isEmpty) {
    final now = DateTime.now();
    final samples = [
      ReplyLog(
          id: 'l1',
          sender: 'Maya (sample)',
          originalMessage: 'Are we still on for 6?',
          autoReplySent: 'Yes, 6 pm works. See you then.',
          appName: 'WhatsApp',
          dateTime: now.subtract(const Duration(hours: 2)),
          ruleId: '',
          aiModel: 'gemini-3.6-flash'),
      ReplyLog(
          id: 'l2',
          sender: 'Sample Client A',
          originalMessage: 'What are your hours?',
          autoReplySent: 'We are open 9 to 5, Monday to Friday.',
          appName: 'Instagram',
          dateTime: now.subtract(const Duration(hours: 3)),
          ruleId: 'r1'),
      ReplyLog(
          id: 'l3',
          sender: 'Jo (sample)',
          originalMessage: 'Can you send the price list?',
          autoReplySent: 'I will send the price list shortly.',
          appName: 'WhatsApp',
          dateTime: now.subtract(const Duration(hours: 4)),
          ruleId: 'r2',
          rating: 1),
      ReplyLog(
          id: 'l4',
          sender: 'Sam (sample)',
          originalMessage: 'Call me when free',
          autoReplySent: 'I am away right now. I will reply when I am back.',
          appName: 'Instagram',
          dateTime: now.subtract(const Duration(days: 1)),
          ruleId: '',
          aiModel: 'gemini-3.6-flash',
          rating: -1),
    ];
    for (final l in samples) {
      await logs.put(l.id, l);
    }
  }
  if (chat.isEmpty) {
    await chat.add(ChatMessage(
        role: 'user', content: 'Hi, are we still on for 6?'));
    await chat.add(ChatMessage(
        role: 'ai', content: 'Yes, 6 pm works. See you then.'));
  }
  if (notes.isEmpty) {
    await notes.add(Note(
        id: 'n1',
        title: 'Call the bank',
        content: 'Ask about the card limit increase.',
        sender: 'Maya (sample)',
        appName: 'WhatsApp',
        createdAt: DateTime.now(),
        eventTime: DateTime.now().add(const Duration(days: 1, hours: 3))));
  }

  runApp(
    UncontrolledProviderScope(
      container: globalProviderContainer,
      child: const _PreviewApp(),
    ),
  );
}

class _PreviewApp extends ConsumerWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(appSettingsProvider.select((s) => s.darkMode));
    return MaterialApp(
      title: 'Replier',
      debugShowCheckedModeBanner: false,
      theme: buildDraftTheme(dark: false),
      darkTheme: buildDraftTheme(dark: true),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const MainShell(),
    );
  }
}
