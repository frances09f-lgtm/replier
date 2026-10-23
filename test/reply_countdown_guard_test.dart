import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/providers/reply_countdown_provider.dart';

void main() {
  test('a due countdown with no terminal event clears itself', () {
    fakeAsync((async) {
      final notifier = ReplyCountdownNotifier();
      addTearDown(notifier.dispose);

      notifier.handleReplyScheduled(
          {'delayMs': 0, 'sender': 'Demo contact', 'replyText': 'hi'});
      expect(notifier.state.isActive, isTrue);

      async.elapse(const Duration(seconds: 20));
      expect(notifier.state.isActive, isTrue);

      async.elapse(const Duration(seconds: 11));
      expect(notifier.state.isActive, isFalse);
    });
  });

  test('a newer scheduled reply re-arms the guard', () {
    fakeAsync((async) {
      final notifier = ReplyCountdownNotifier();
      addTearDown(notifier.dispose);

      notifier.handleReplyScheduled(
          {'delayMs': 0, 'sender': 'First', 'replyText': 'a'});
      async.elapse(const Duration(seconds: 20));
      notifier.handleReplyScheduled(
          {'delayMs': 0, 'sender': 'Second', 'replyText': 'b'});
      async.elapse(const Duration(seconds: 20));
      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.sender, 'Second');

      async.elapse(const Duration(seconds: 11));
      expect(notifier.state.isActive, isFalse);
    });
  });
}
