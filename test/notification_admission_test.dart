import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native message evidence gate precedes emission', () {
    final source = File(
      'android/app/src/main/kotlin/com/replier/replier/ReplierNotificationListener.kt',
    ).readAsStringSync();
    expect(
      source,
      contains(
        'if (!hasMessages && !hasReply && n.category != Notification.CATEGORY_MESSAGE) return',
      ),
    );
    expect(
      source.indexOf('if (!hasMessages'),
      lessThan(source.indexOf('var sender =')),
    );
    expect(source, contains('it.allowFreeFormInput'));
    expect(source, contains('Checking for new messages'));
  });
  test('local engine keeps weights only, fresh chat each request, smaller CPU budget', () {
    final source = File('lib/services/local/local_provider.dart')
        .readAsStringSync();
    expect(source, contains('Future.value(_engine!)'));
    expect(source, contains('await engine.createChat()'));
    expect(source, contains('await chat?.dispose()'));
    expect(source, contains('nCtx: 1024'));
    expect(source, contains('maxTokens: 96'));
    expect(source, contains("chat.addUser('\${m['content']} /no_think')"));
    expect(source, contains('if (result == null)'));
  });
}
