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

  test('repeated got_message events do not postpone staleness recovery', () {
    fakeAsync((async) {
      final notifier = PipelineStatusNotifier();
      addTearDown(notifier.dispose);

      // A chatty conversation re-announces the same stage every 10s.
      for (var i = 0; i < 5; i++) {
        AutoReplyService.onPipelineStatus
            ?.call({'state': 'got_message', 'sender': 'Demo contact'});
        async.elapse(const Duration(seconds: 10));
      }
      // 50s after the FIRST event with nothing terminal: recovered, even
      // though the latest event is only 10s old.
      expect(notifier.state.isIdle, isTrue);
    });
  });

  test('a sending stage with no countdown and no terminal event clears itself',
      () {
    fakeAsync((async) {
      final notifier = PipelineStatusNotifier();
      addTearDown(notifier.dispose);

      // Reply delay 0: the reply is already due when native announces it, so
      // no countdown runs. Native then skips the send without any terminal
      // event (for example the master switch was turned off).
      notifier.handleReplyScheduled({
        'sender': 'Demo contact',
        'delayMs': 0,
        'scheduledAt': DateTime.now().millisecondsSinceEpoch,
      });
      expect(notifier.state.stage, PipelineStage.sending);
      expect(notifier.state.countdownSeconds, 0);

      async.elapse(const Duration(seconds: 20));
      expect(notifier.state.stage, PipelineStage.sending);

      async.elapse(const Duration(seconds: 11));
      expect(notifier.state.isIdle, isTrue);
    });
  });

  test('events queued behind a stuck sending stage show once it clears', () {
    fakeAsync((async) {
      final notifier = PipelineStatusNotifier();
      addTearDown(notifier.dispose);

      notifier.handleReplyScheduled({
        'sender': 'Demo contact',
        'delayMs': 0,
        'scheduledAt': DateTime.now().millisecondsSinceEpoch,
      });
      // A new message arrives while the old send is wedged. It is held back.
      AutoReplyService.onPipelineStatus
          ?.call({'state': 'got_message', 'sender': 'Next contact'});
      expect(notifier.state.stage, PipelineStage.sending);

      async.elapse(const Duration(seconds: 31));
      // The guard cleared the stuck send and the queued message went through.
      expect(notifier.state.stage, PipelineStage.gotMessage);
      expect(notifier.state.sender, 'Next contact');

      // And that card recovers on its own as well.
      async.elapse(const Duration(seconds: 46));
      expect(notifier.state.isIdle, isTrue);
    });
  });
}
