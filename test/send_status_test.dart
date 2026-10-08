import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:replier/models/message_event.dart';
import 'package:replier/services/event_store.dart';
import 'package:replier/services/bridge.dart';
import 'package:replier/state/controller.dart';

class FakeBridge extends ReplierBridge {
  String inline = 'no_inline', fallback = 'opened';
  int calls = 0;
  @override
  Future<String> sendReply(String key, String text) async {
    calls++;
    return inline;
  }

  @override
  Future<String> openAndSend(String key, String text) async => fallback;
}

void main() {
  late Directory dir;
  late EventStore store;
  late FakeBridge bridge;
  late ReplierController c;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp();
    Hive.init(dir.path);
    Hive.registerAdapter(MessageEventAdapter());
  });
  setUp(() async {
    store = EventStore();
    await store.init();
    bridge = FakeBridge();
    c = ReplierController(store: store, bridge: bridge);
  });
  tearDown(() async {
    c.dispose();
    await Hive.box<MessageEvent>('events').clear();
    await Hive.box<String>('seen_notifs').clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  MessageEvent e() =>
      store.addIfNew(
          notifKey: 'k',
          appPackage: 'chat',
          appLabel: 'Chat',
          sender: 'A',
          text: 'Hello',
          at: DateTime(2026),
        )!
        ..generatedReply = 'Hi'
        ..status = 'generated';
  test('opened chat never becomes sent or approved; retries guarded', () async {
    final m = e();
    expect(await c.approve(m), contains('not confirmed'));
    expect(m.status, 'opened_unverified');
    await c.approve(m);
    expect(bridge.calls, 1);
  });
  test('inline handoff is submitted, never delivered', () async {
    bridge.inline = 'submitted';
    final m = e();
    expect(await c.approve(m), contains('Delivery is not confirmed'));
    expect(m.status, 'submitted');
    await c.approve(m);
    expect(bridge.calls, 1);
  });
  for (final failure in ['gone', 'error', 'no_accessibility']) {
    test('fallback $failure stays failed', () async {
      bridge.fallback = failure;
      final m = e();
      await c.approve(m);
      expect(m.status, 'send_failed');
    });
  }
  test('legacy approvals labelled unverified', () {
    final m = e()..status = 'approved';
    expect(m.statusLabel, contains('unverified'));
  });
  test('empty reply never fires', () async {
    final m = e()..generatedReply = '';
    await c.approve(m);
    expect(bridge.calls, 0);
  });
  test('old active listener blocks outgoing attempt', () async {
    c.legacyNotification = true;
    final m = e();
    expect(await c.approve(m), contains('Turn off old'));
    expect(bridge.calls, 0);
  });
  test('generating or rejected drafts cannot be approved', () async {
    final m = e()..status = 'generating';
    await c.approve(m, editedText: 'hello');
    expect(bridge.calls, 0);
    m.status = 'rejected';
    await c.approve(m);
    expect(bridge.calls, 0);
  });
}
