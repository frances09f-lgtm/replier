import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/providers/pipeline_status_provider.dart';
import 'package:replier/services/auto_reply_service.dart';

void main() {
  test('a got_message with no terminal event auto-clears to idle', () {
    fakeAsync((async) {
      final notifier = PipelineStatusNotifier();
      addTearDown(notifier.dispose);

      // Simulate the native event the way the service channel delivers it.
      AutoReplyService.onPipelineStatus
          ?.call({'state': 'got_message', 'sender': 'Demo contact'});
      expect(notifier.state.stage, PipelineStage.gotMessage);
      expect(notifier.state.isIdle, isFalse);

      // Past the minimum display time, still nothing terminal: card stays.
      async.elapse(const Duration(seconds: 10));
      expect(notifier.state.stage, PipelineStage.gotMessage);

      // The staleness guard eventually recovers the UI instead of wedging.
      async.elapse(const Duration(seconds: 40));
      expect(notifier.state.isIdle, isTrue);
    });
  });

  test('a fresh stage re-arms the staleness guard instead of inheriting age', () {
    fakeAsync((async) {
      final notifier = PipelineStatusNotifier();
      addTearDown(notifier.dispose);

      AutoReplyService.onPipelineStatus
          ?.call({'state': 'got_message', 'sender': 'First'});
      async.elapse(const Duration(seconds: 40));
      AutoReplyService.onPipelineStatus
          ?.call({'state': 'analysing', 'sender': 'Second'});
      async.elapse(const Duration(seconds: 30));
      // 70s after the first event, but only 30s after the latest: still showing.
      expect(notifier.state.stage, PipelineStage.analysing);
      async.elapse(const Duration(seconds: 20));
      expect(notifier.state.isIdle, isTrue);
    });
  });

  test('analysis_managed still clears promptly (guard must not delay it)', () {
    fakeAsync((async) {
      final notifier = PipelineStatusNotifier();
      addTearDown(notifier.dispose);

      AutoReplyService.onPipelineStatus
          ?.call({'state': 'got_message', 'sender': 'Demo contact'});
      async.elapse(const Duration(seconds: 1));
      AutoReplyService.onPipelineStatus?.call({'state': 'analysis_managed'});
      expect(notifier.state.isIdle, isTrue);
    });
  });
}
