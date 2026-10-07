import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:replier/models/message_event.dart';
import 'package:replier/services/ai/ai_provider.dart';
import 'package:replier/services/event_store.dart';

void main() {
  late Directory dir;
  late EventStore store;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('replier_test');
    Hive.init(dir.path);
    Hive.registerAdapter(MessageEventAdapter());
  });

  setUp(() async {
    store = EventStore();
    await store.init();
  });

  tearDown(() async {
    await Hive.box<MessageEvent>('events').clear();
    await Hive.box<String>('seen_notifs').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  MessageEvent? add(String key, {String text = 'hello'}) => store.addIfNew(
    notifKey: key,
    appPackage: 'com.example.chat',
    appLabel: 'Chat',
    sender: 'Mom',
    text: text,
    at: DateTime(2026, 10, 7, 3, 0),
  );

  test('stores a new notification event', () {
    expect(add('k1'), isNotNull);
    expect(store.newestFirst().length, 1);
  });

  test('exact notification message repeat is suppressed', () {
    expect(add('k1'), isNotNull);
    expect(add('k1'), isNull);
    expect(add('k1'), isNull);
    expect(store.newestFirst().length, 1);
  });

  test('different keys both land, newest first', () {
    add('k1');
    add('k2', text: 'later');
    expect(store.newestFirst().length, 2);
  });

  test('pending review only holds generated/new events', () {
    final e = add('k1')!;
    expect(store.pendingReview().length, 1);
    e.status = 'rejected';
    store.save(e);
    expect(store.pendingReview().length, 0);
  });

  test('local rule provider answers questions as questions', () async {
    const p = LocalRuleProvider();
    final r = await p.generateReply(sender: 'Mom', text: 'Are you coming?');
    expect(r.toLowerCase(), contains('get back'));
  });

  test('local rule provider greets back', () async {
    const p = LocalRuleProvider();
    final r = await p.generateReply(sender: 'Mom', text: 'Hi beta');
    expect(r.toLowerCase(), contains('hey'));
  });

  test('local rule provider never invents content for empty text', () async {
    const p = LocalRuleProvider();
    expect(await p.generateReply(sender: 'Mom', text: '   '), isEmpty);
  });

  ;
  test(
    'same notification key accepts later text and replaces pending old draft',
    () {
      final first = add('k1')!;
      first.status = 'generated';
      final second = add('k1', text: 'another message');
      expect(second, isNotNull);
      expect(first.status, 'superseded');
      expect(store.pendingReview().length, 1);
    },
  );
  test('same text at a later message timestamp is new', () {
    add('k1');
    final second = store.addIfNew(
      notifKey: 'k1',
      appPackage: 'com.example.chat',
      appLabel: 'Chat',
      sender: 'Mom',
      text: 'hello',
      at: DateTime(2026, 10, 7, 3, 1),
    );
    expect(second, isNotNull);
  });
}
