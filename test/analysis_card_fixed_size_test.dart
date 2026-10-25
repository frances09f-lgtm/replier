import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/providers/analysis_status_provider.dart';
import 'package:replier/theme/draft_theme.dart';
import 'package:replier/theme/draft_widgets.dart';
import 'package:replier/widgets/analysis_countdown_card.dart';

/// The dashboard Analysis slot must be compact and keep ONE fixed height in
/// every state (idle, each pipeline stage, reply countdown, analysis
/// countdown), even with long text and larger system fonts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> loadFonts() async {
    Future<ByteData> read(String p) async =>
        ByteData.sublistView(await File(p).readAsBytes());
    for (final family in ['Outfit', 'Figtree']) {
      final loader = FontLoader(family);
      for (final w in [400, 600, 700, 800]) {
        final f = File('assets/fonts/$family-$w.ttf');
        if (f.existsSync()) loader.addFont(read(f.path));
      }
      await loader.load();
    }
  }

  const longSender = 'A very long contact name that keeps going and going';
  final states = <String, Widget>{
    'idle': const DraftAnalysisCard(
        progress: 0,
        ringLabel: '--',
        text: 'Idle. Analysis starts when a new message arrives.',
        idle: true),
    'got_message': const DraftAnalysisCard(
        progress: 0.25, ringLabel: '', text: 'Got a new message.'),
    'reply_ready':
        const DraftAnalysisCard(progress: 0.75, ringLabel: '', text: 'Reply ready.'),
    'countdown': DraftAnalysisCard(
        progress: 0.4,
        ringLabel: '120',
        text:
            'Reply to $longSender is scheduled. Sending in 2 min 0 sec, then something more to overflow.'),
    'analysing': AnalysisCountdownCard(
        status: AnalysisStatus(
            id: 'a',
            sender: longSender,
            phase: 'analysing',
            remainingMs: 68000,
            terminalRemainingMs: 6000),
        extraCount: 2),
    'expired': const AnalysisCountdownCard(
        status: AnalysisStatus(
            id: 'b',
            sender: 'Demo contact',
            phase: 'expired',
            remainingMs: 0,
            terminalRemainingMs: 6000)),
  };

  for (final scale in [1.0, 2.0]) {
    for (final dark in [false, true]) {
      testWidgets('analysis card is fixed height (scale $scale, dark $dark)',
          (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(loadFonts);
        const output = String.fromEnvironment('REPLIER_CAPTURE_DIR');
        for (final entry in states.entries) {
          final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
              theme: buildDraftTheme(dark: dark),
              home: MediaQuery(
                  data: MediaQueryData(
                      size: const Size(360, 640),
                      textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                      body: Padding(
                          padding: const EdgeInsets.all(16),
                          child: RepaintBoundary(
                              key: key,
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [entry.value])))))));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: '${entry.key} overflowed');
          final shell = find.byType(DraftAnalysisShell);
          expect(shell, findsOneWidget);
          expect(tester.getSize(shell).height,
              kAnalysisCardHeight + 12 /* bottom margin */,
              reason: entry.key);
          if (output.isNotEmpty && scale == 1.0) {
            await tester.runAsync(() async {
              final boundary = key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 3);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$output/analysis-${dark ? 'dark' : 'light'}-${entry.key}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
