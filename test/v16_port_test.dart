import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replier/core/hive_config.dart';
import 'package:replier/repositories/settings_repository.dart';
import 'package:replier/core/constants.dart';
import 'package:replier/screens/dashboard_screen.dart';
import 'package:replier/screens/settings_screen.dart';
import 'package:replier/screens/rules_screen.dart';
import 'package:replier/screens/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (await File('/tmp/replier-visual-fonts/Roboto-Regular.ttf').exists()) {
      final font = FontLoader('Roboto')
        ..addFont(File('/tmp/replier-visual-fonts/Roboto-Regular.ttf')
            .readAsBytes()
            .then((data) => ByteData.sublistView(data)));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(File(
                '/home/sandbox/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then((data) => ByteData.sublistView(data)));
      await icons.load();
    }
    final d = await Directory.systemTemp.createTemp('replier-v16-tests');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => d.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(AppConstants.nativeChannel), (call) async {
      if (call.method == 'loadProviderKeys') return {'groq': '', 'gemini': ''};
      if (call.method == 'consentStatus') return false;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => call.method == 'requestPermissions' ? {17: 1} : 1);
    await HiveConfig.initialize();
    await Directory('/tmp/replier16-shots').create(recursive: true);
  });
  test('safe first install and no plaintext persistence', () async {
    final r = SettingsRepository();
    expect(r.getSettings().masterEnabled, isFalse);
    expect(r.getSettings().confirmBeforeReply, isTrue);
    await r.updateSettings(r.getSettings().copyWith(
        groqApiKey: 'fixture-secret', geminiApiKey: 'fixture-secret'));
    expect(HiveConfig.getSettingsBox().get('settings')!.groqApiKey, isEmpty);
    expect(HiveConfig.getSettingsBox().get('settings')!.geminiApiKey, isEmpty);
  });
  testWidgets('actual screens at small phone size', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    for (final entry in <String, Widget>{
      'dashboard': const DashboardScreen(),
      'settings': const SettingsScreen(),
      'rules': const RulesScreen(),
      'consent': const SplashScreen()
    }.entries) {
      await t.pumpWidget(ProviderScope(
          child: RepaintBoundary(
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                      fontFamily: "Roboto",
                      useMaterial3: true,
                      colorSchemeSeed: const Color(0xff4f46e5)),
                  home: entry.value))));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
      final b = t.firstRenderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary));
      await t.runAsync(() async {
        final image = await b.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/replier16-shots/${entry.key}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await t.pumpWidget(const SizedBox());
      await t.pump();
    }
  });
  testWidgets('Qwen tile tap calls native download and shows returned failure',
      (t) async {
    var requested = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(AppConstants.nativeChannel), (call) async {
      if (call.method == 'loadProviderKeys') return {'groq': '', 'gemini': ''};
      if (call.method == 'getPhiStatus') return {'available': false};
      if (call.method == 'downloadPhiModel') {
        requested = call.arguments['modelId'] == 'qwen_2_5_1_5b';
        return {'success': false, 'error': 'Fixture model server HTTP 503'};
      }
      return null;
    });
    await t.runAsync(() async {
      final r = SettingsRepository();
      await r.updateSettings(r.getSettings().copyWith(
          aiModelType: 'phi_local',
          fallbackToLocalModel: true,
          aiReplyEnabled: true));
    });
    t.view.physicalSize = const Size(360, 6000);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsScreen())));
    await t.pumpAndSettle();
    final q = find.text('Qwen 2.5 1.5B Instruct');
    expect(q, findsOneWidget);
    await t.pumpAndSettle();
    await t.tap(q);
    await t.pumpAndSettle();
    expect(requested, isTrue);
    expect(
        find.textContaining('Fixture model server HTTP 503'), findsOneWidget);
  });
}
