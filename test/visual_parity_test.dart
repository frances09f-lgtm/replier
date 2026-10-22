import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replier/core/hive_config.dart';
import 'package:replier/core/constants.dart';
import 'package:replier/repositories/settings_repository.dart';
import 'package:replier/screens/main_shell.dart';
import 'package:replier/theme/draft_theme.dart';
import 'package:replier/models/rule.dart';
import 'package:replier/models/reply_log.dart';
import 'package:replier/repositories/rule_repository.dart';
import 'package:replier/repositories/log_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final d = await Directory.systemTemp.createTemp('replier-parity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => d.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(AppConstants.nativeChannel), (call) async {
      if (call.method == 'loadProviderKeys') return {'groq': '', 'gemini': ''};
      if (call.method == 'consentStatus') return true;
      if (call.method == 'isNotificationListenerEnabled') return false;
      if (call.method == 'isBatteryOptimizationDisabled') return false;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => 1);
    await HiveConfig.initialize();
    await Directory('/tmp/parity-shots').create(recursive: true);
    for (final fam in {
      'Outfit': [400, 600, 700, 800],
      'Figtree': [400, 500, 600]
    }.entries) {
      final loader = FontLoader(fam.key);
      for (final w in fam.value) {
        final bytes = await File('assets/fonts/${fam.key}-$w.ttf').readAsBytes();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }
    // Load MaterialIcons from the local Flutter SDK (path differs per machine)
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
    final miFile = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (miFile.existsSync()) {
      final mi = FontLoader('MaterialIcons')
        ..addFont(
            Future.value(ByteData.view(miFile.readAsBytesSync().buffer)));
      await mi.load();
    }
    final r = SettingsRepository();
    await r.updateSettings(r.getSettings().copyWith(
        masterEnabled: true,
        whatsappEnabled: true,
        instagramEnabled: true,
        darkMode: false));
    // Seed sample data so populated cards render (rules, logs)
    final rules = RuleRepository();
    final now = DateTime.now();
    await rules.addRule(Rule(
        id: 'r1',
        triggerText: 'hours',
        replyText: 'We are open 9 to 5, Monday to Friday.',
        containsMatch: true,
        exactMatch: false,
        createdAt: now,
        updatedAt: now));
    await rules.addRule(Rule(
        id: 'r2',
        triggerText: 'price list',
        replyText: 'I will send the price list shortly.',
        containsMatch: true,
        exactMatch: false,
        senderNames: ['Sample Client A'],
        createdAt: now,
        updatedAt: now));
    await rules.addRule(Rule(
        id: 'r3',
        triggerText: 'OK?',
        replyText: 'Yes, all good.',
        exactMatch: true,
        caseSensitive: true,
        isEnabled: false,
        createdAt: now,
        updatedAt: now));
    final logs = LogRepository();
    await logs.addLog(ReplyLog(
        id: 'l1',
        sender: 'Maya (sample)',
        originalMessage: 'Are we still on for 6?',
        autoReplySent: 'Yes, 6 pm works. See you then.',
        appName: 'WhatsApp',
        dateTime: now,
        ruleId: '',
        aiModel: 'phi'));
    await logs.addLog(ReplyLog(
        id: 'l2',
        sender: 'Sample Client A',
        originalMessage: 'What are your hours?',
        autoReplySent: 'We are open 9 to 5, Monday to Friday.',
        appName: 'Instagram',
        dateTime: now.subtract(const Duration(hours: 1)),
        ruleId: 'r1'));
  });

  Future<void> shoot(WidgetTester t, String name) async {
    final b =
        t.firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
    await t.runAsync(() async {
      final image = await b.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/parity-shots/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> shootAll(WidgetTester t, String theme) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final dark = theme == 'dark';
    await t.pumpWidget(ProviderScope(
        child: RepaintBoundary(
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildDraftTheme(dark: dark),
                home: const MainShell()))));
    await t.pump(); await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    await shoot(t, 'app-dash-$theme');
    for (final tab in ['Rules', 'Chat', 'Logs', 'Notes']) {
      await t.tap(find.text(tab).last);
      await t.pump(); await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
      await shoot(t, 'app-${tab.toLowerCase()}-$theme');
    }
  }

  testWidgets('light parity shots', (t) async {
    await shootAll(t, 'light');
  });

  testWidgets('dark parity shots', (t) async {
    await t.runAsync(() async {
      final r = SettingsRepository();
      await r.updateSettings(r.getSettings().copyWith(darkMode: true));
    });
    await shootAll(t, 'dark');
  });
}
