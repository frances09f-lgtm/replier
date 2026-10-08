import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/message_event.dart';
import 'services/bridge.dart';
import 'services/ai/groq_provider.dart';
import 'services/ai/reply_settings.dart';
import 'services/event_store.dart';
import 'services/usage_reporter.dart';
import 'state/controller.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Startup must never fail hard: a storage hiccup should not blank the app.
  await Hive.initFlutter();
  Hive.registerAdapter(MessageEventAdapter());
  final store = EventStore();
  await store.init();
  UsageReporter.report('app_start');
  final settings = ReplySettings();
  try {
    await settings.load();
  } catch (_) {
    settings.enabled = false;
  }
  final controller = ReplierController(
    store: store,
    bridge: ReplierBridge(),
    replySettings: settings,
    provider: GroqProvider(key: settings.key, model: settings.model),
  );
  await controller.start();
  runApp(ReplierApp(controller: controller));
}

class ReplierApp extends StatelessWidget {
  const ReplierApp({super.key, required this.controller});

  final ReplierController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Replier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4C8DFF),
        useMaterial3: true,
      ),
      home: ReplierHome(controller: controller),
    );
  }
}
