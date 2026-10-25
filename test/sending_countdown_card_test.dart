import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/models/reply_log.dart';
import 'package:replier/providers/pipeline_status_provider.dart';
import 'package:replier/theme/draft_theme.dart';
import 'package:replier/theme/draft_widgets.dart';
import 'package:replier/widgets/pipeline_analysis_card.dart';

/// The "Sending the reply." stage must show the live reply-delay countdown:
/// seconds inside the ring, a moving arc and "Sending in Ns" — never an
/// empty ring with no number.
void main() {
  Future<void> pump(WidgetTester tester, PipelineStatusData status) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDraftTheme(dark: false),
      home: Scaffold(body: PipelineAnalysisCard(status: status)),
    ));
    await tester.pump(const Duration(seconds: 1));
  }

  double ringValue(WidgetTester tester) => tester
      .widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator))
      .value!;

  testWidgets('sending stage shows remaining seconds and status',
      (tester) async {
    await pump(
        tester,
        const PipelineStatusData(
            stage: PipelineStage.sending,
            sender: 'Rahul',
            countdownSeconds: 12,
            countdownTotalSeconds: 20));
    expect(find.text('12s'), findsOneWidget);
    expect(find.textContaining('Sending in 12s'), findsOneWidget);
    expect(ringValue(tester), closeTo(0.4, 0.001));
    // Fixed card height plus the shell's 12dp bottom margin.
    expect(tester.getSize(find.byType(DraftAnalysisShell)).height,
        kAnalysisCardHeight + 12);

    // The arc follows the countdown.
    await pump(
        tester,
        const PipelineStatusData(
            stage: PipelineStage.sending,
            sender: 'Rahul',
            countdownSeconds: 5,
            countdownTotalSeconds: 20));
    expect(find.text('5s'), findsOneWidget);
    expect(find.textContaining('Sending in 5s'), findsOneWidget);
    expect(ringValue(tester), closeTo(0.75, 0.001));
  });

  testWidgets('countdown at 0 (or no delay) shows "Sending now…"',
      (tester) async {
    await pump(
        tester,
        const PipelineStatusData(
            stage: PipelineStage.sending, countdownSeconds: 0));
    expect(find.textContaining('Sending now…'), findsOneWidget);
    expect(find.text('0s'), findsOneWidget);
    expect(ringValue(tester), closeTo(1.0, 0.001));
  });

  testWidgets('scheduled reply event reaches the card state', (tester) async {
    final notifier = PipelineStatusNotifier();
    notifier.handleReplyScheduled({
      'sender': 'Rahul',
      'delayMs': 12000,
      'scheduledAt': DateTime.now().millisecondsSinceEpoch,
    });
    expect(notifier.state.stage, PipelineStage.sending);
    expect(notifier.state.countdownSeconds, 12);
    expect(notifier.state.countdownTotalSeconds, 12);
    await pump(tester, notifier.state);
    expect(find.text('12s'), findsOneWidget);
    expect(find.textContaining('Sending in 12s'), findsOneWidget);

    notifier.handleReplyScheduled({
      'sender': 'Rahul',
      'delayMs': 0,
      'scheduledAt': DateTime.now().millisecondsSinceEpoch,
    });
    expect(notifier.state.countdownSeconds, 0);
    await pump(tester, notifier.state);
    expect(find.textContaining('Sending now…'), findsOneWidget);
    notifier.dispose();
  });

  test('failure/pipeline log entries are not AI replies', () {
    final now = DateTime.now();
    final logs = [
      ReplyLog(
          id: '1',
          sender: 'a',
          originalMessage: 'hi',
          autoReplySent: 'hey',
          appName: 'WhatsApp',
          dateTime: now,
          ruleId: ''),
      ReplyLog(
          id: '2',
          sender: '',
          originalMessage: '',
          autoReplySent: '',
          appName: '',
          dateTime: now,
          ruleId: '',
          failureReason: 'Ignored WhatsApp summary notification'),
    ];
    expect(logs.where((l) => l.isAiReplySent).length, 1);
  });
}
