import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/providers/analysis_status_provider.dart';
import 'package:replier/widgets/analysis_countdown_card.dart';

Map<String, dynamic> snapshot(int revision, List<Map<String, dynamic>> attempts,
        {String epoch = 'service-one'}) =>
    {'epoch': epoch, 'revision': revision, 'attempts': attempts};
Map<String, dynamic> attempt(String id,
        {int remaining = 100000,
        String phase = 'analysing',
        int terminal = 6000}) =>
    {
      'id': id,
      'sender': 'Demo contact',
      'state': phase,
      'remainingMs': remaining,
      'terminalRemainingMs': terminal
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      '100 seconds decreases monotonically and zero is not a sent/skipped claim',
      () {
    var now = 0;
    final notifier =
        AnalysisStatusNotifier(connectNative: false, nowMs: () => now);
    addTearDown(notifier.dispose);
    notifier.applySnapshot(snapshot(1, [attempt('a')]));
    expect(notifier.state.single.seconds, 100);
    now = 999;
    notifier.tick();
    expect(notifier.state.single.seconds, 100);
    now = 1000;
    notifier.tick();
    expect(notifier.state.single.seconds, 99);
    now = 100000;
    notifier.tick();
    expect(notifier.state.single.seconds, 0);
    expect(notifier.state.single.phase, 'analysing');
    notifier.applySnapshot(
        snapshot(2, [attempt('a', phase: 'expired', remaining: 0)]));
    expect(notifier.state.single.phase, 'expired');
    now += 6000;
    notifier.tick();
    expect(notifier.state, isEmpty);
  });
  test('overlap, success, late snapshot, and error are correlated by attempt',
      () {
    final notifier = AnalysisStatusNotifier(connectNative: false);
    addTearDown(notifier.dispose);
    notifier.applySnapshot(
        snapshot(1, [attempt('a'), attempt('b', remaining: 95000)]));
    expect(notifier.state.map((a) => a.id), ['a', 'b']);
    notifier.applySnapshot(snapshot(
        3, [attempt('a', phase: 'ready'), attempt('b', phase: 'failed')]));
    expect(notifier.state.single.id, 'b');
    expect(notifier.state.single.phase, 'failed');
    notifier.applySnapshot(snapshot(2, [attempt('a'), attempt('b')]));
    expect(notifier.state.single.phase, 'failed');
  });
  test('a retired service epoch cannot resurrect a stale attempt', () {
    final notifier = AnalysisStatusNotifier(connectNative: false);
    addTearDown(notifier.dispose);
    notifier.applySnapshot(snapshot(5, [attempt('old')]));
    notifier.applySnapshot(snapshot(1, [], epoch: 'new-service'));
    notifier.applySnapshot(snapshot(99, [attempt('old')]));
    expect(notifier.state, isEmpty);
  });
  test('resume snapshot uses native remainder rather than restarting at 100',
      () {
    var now = 0;
    final notifier =
        AnalysisStatusNotifier(connectNative: false, nowMs: () => now);
    addTearDown(notifier.dispose);
    notifier.applySnapshot(snapshot(1, [attempt('a')]));
    now = 70000;
    notifier.applySnapshot(snapshot(2, [attempt('a', remaining: 30000)]));
    expect(notifier.state.single.seconds, 30);
    now += 1000;
    notifier.tick();
    expect(notifier.state.single.seconds, 29);
    notifier.applySnapshot(snapshot(0, [], epoch: 'restarted-service'));
    expect(notifier.state, isEmpty);
    notifier
        .applySnapshot(snapshot(99, [attempt('old')], epoch: 'service-one'));
    expect(notifier.state, isEmpty);
  });
  test('superseded attempt disappears; a different conversation stays visible',
      () {
    final notifier = AnalysisStatusNotifier(connectNative: false);
    addTearDown(notifier.dispose);
    notifier.applySnapshot(snapshot(1, [attempt('old'), attempt('other')]));
    notifier.applySnapshot(snapshot(2,
        [attempt('old', phase: 'canceled'), attempt('new'), attempt('other')]));
    expect(notifier.state.map((a) => a.id), ['new', 'other']);
  });

  testWidgets(
      'real countdown card animates at phone width and shows honest terminal states',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    const fontDir = String.fromEnvironment('REPLIER_FONT_DIR');
    if (fontDir.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto');
        loader.addFont(File('$fontDir/Roboto-Regular.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)));
        await loader.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(File('$fontDir/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)));
        await icons.load();
      });
    }

    Future<void> show(int remaining, String phase, int frame,
        {Duration advance = const Duration(milliseconds: 250)}) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: RepaintBoundary(
              key: key,
              child: Scaffold(
                  backgroundColor: const Color(0xFFF9F7F2),
                  appBar: AppBar(
                      title: const Text('Replier · preview'),
                      backgroundColor: const Color(0xFFF9F7F2)),
                  body: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            const Text('Analysis time limit',
                                style: TextStyle(
                                    fontSize: 26, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            const Text('Synthetic message · demo only',
                                style: TextStyle(color: Color(0xFF786F66))),
                            const SizedBox(height: 18),
                            AnalysisCountdownCard(
                                status: AnalysisStatus(
                                    id: 'demo',
                                    sender: 'Demo contact',
                                    phase: phase,
                                    remainingMs: remaining,
                                    terminalRemainingMs: 6000)),
                            const SizedBox(height: 20),
                            const Text(
                                'Time budget includes waiting for the model.\nYour reply delay starts after analysis finishes.',
                                style: TextStyle(
                                    fontSize: 14,
                                    height: 1.6,
                                    color: Color(0xFF786F66))),
                          ]))))));
      await tester.pump(advance);
      expect(tester.takeException(), isNull);
      const output = String.fromEnvironment('REPLIER_CAPTURE_DIR');
      if (output.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/frame-${frame.toString().padLeft(3, '0')}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }

    await show(100000, 'analysing', 0);
    expect(find.text('100s'), findsOneWidget);
    expect(find.text('Analysing'), findsOneWidget);
    await show(68000, 'analysing', 1);
    expect(find.text('68s'), findsOneWidget);
    await show(12000, 'analysing', 2);
    await show(0, 'analysing', 3);
    expect(find.text('Checking status…'), findsOneWidget);
    expect(find.textContaining('Reply skipped'), findsNothing);
    await show(0, 'expired', 4);
    expect(find.text('100-second limit reached'), findsOneWidget);
    expect(find.text('Reply skipped for this attempt'), findsOneWidget);
    await show(0, 'unknown', 5);
    expect(find.text('Reply status could not be verified'), findsOneWidget);
    // Actual AnimatedSwitcher / ring transition frames for a short synthetic
    // preview (not a device recording or performance benchmark).
    if (const String.fromEnvironment('REPLIER_CAPTURE_DIR').isNotEmpty) {
      await show(100000, 'analysing', 100);
      for (var i = 1; i <= 5; i++) {
        await tester.pump(const Duration(milliseconds: 820));
        await show((100 - i) * 1000, 'analysing', 99 + i * 2,
            advance: const Duration(milliseconds: 90));
        await show((100 - i) * 1000, 'analysing', 100 + i * 2,
            advance: const Duration(milliseconds: 90));
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
