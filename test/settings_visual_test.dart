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
import 'package:replier/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final d = await Directory.systemTemp.createTemp('replier-v24-visual');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => d.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(AppConstants.nativeChannel), (call) async {
      if (call.method == 'loadProviderKeys') return {'groq': '', 'gemini': ''};
      if (call.method == 'consentStatus') return true;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => 1);
    await HiveConfig.initialize();
    await Directory('/tmp/replier24-shots').create(recursive: true);
    final r = SettingsRepository();
    await r.updateSettings(r.getSettings().copyWith(darkMode: true));
  });

  Future<void> shoot(WidgetTester t, String name) async {
    final b =
        t.firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
    await t.runAsync(() async {
      final image = await b.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/replier24-shots/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('v24: info row gone, update button at bottom', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
        child: RepaintBoundary(
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  useMaterial3: true,
                  brightness: Brightness.dark,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xff4f46e5),
                    brightness: Brightness.dark,
                    surface: const Color(0xFF0F172A),
                  ),
                  scaffoldBackgroundColor: const Color(0xFF0F172A),
                ),
                home: const SettingsScreen()))));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Notification replies only'), findsNothing);
    await shoot(t, 'settings_top_v24');

    final list = t.state<ScrollableState>(find.byType(Scrollable).first);
    list.position.jumpTo(list.position.maxScrollExtent);
    await t.pumpAndSettle();
    expect(find.text('Check for updates'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Check for updates'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    await shoot(t, 'settings_bottom_v24');
  });
}
