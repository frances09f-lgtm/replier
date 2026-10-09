import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:replier/services/local/local_provider.dart';
import 'package:replier/services/local/model_catalog.dart';

class FakeRunner implements LocalRunner {
  String output = '{"reply":"नमस्कार","needs_owner_input":false}';
  List<Map<String, String>> seen = [];
  int calls = 0;
  int active = 0, maxActive = 0;
  bool fail = false;
  @override
  Future<String> draft(String path, List<Map<String, String>> messages) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (fail) throw StateError('native failure');
      seen = messages;
      return output;
    } finally {
      active--;
    }
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  const spec = LocalModelSpec('test', 'test', 'r', 'r', 'f', 4, 'h');
  late Directory dir;
  late File file;
  late FakeRunner runner;
  late LocalModelProvider provider;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('local-test');
    file = File('${dir.path}/model');
    await file.writeAsBytes([1, 2, 3, 4]);
    runner = FakeRunner();
    provider = LocalModelProvider(model: spec, file: file, runner: runner);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('lighter CPU option pinned size hash, old selections retained', () {
    expect(LocalModelSpec.light.bytes, 484220320);
    expect(LocalModelSpec.light.sha256.length, 64);
    expect(LocalModelSpec.all, contains(LocalModelSpec.primary));
    expect(LocalModelSpec.all, contains(LocalModelSpec.alternate));
  });
  test('local JSON and same-chat context only', () async {
    expect(
      await provider.generateReply(
        sender: 'Sam',
        text: 'hi',
        history: [
          {'role': 'user', 'content': 'prior'},
        ],
      ),
      'नमस्कार',
    );
    expect(runner.calls, 1);
    expect(runner.seen.length, 3);
  });
  test('unknown personal fact becomes neutral reviewed draft', () async {
    runner.output = '{"reply":"I ate","needs_owner_input":true}';
    expect(
      await provider.generateReply(sender: 'Sam', text: 'ate?'),
      "I'll get back to you on that.",
    );
  });
  test('missing model does not invoke runner', () async {
    await file.delete();
    await expectLater(
      provider.generateReply(sender: 'Sam', text: 'hi'),
      throwsException,
    );
    expect(runner.calls, 0);
  });
  test('bounded input refuses before inference', () async {
    await expectLater(
      provider.generateReply(sender: 'Sam', text: 'x' * 3000),
      throwsException,
    );
    expect(runner.calls, 0);
  });
  test('plain quiz text and reasoning wrapper accepted', () async {
    runner.output = '<think>reasoning hidden</think>Answer: B) Shah Jahan';
    expect(
      await provider.generateReply(
        sender: 'Meta AI',
        text: 'Taj Mahal konत्या samratane bandhla? A) Akbar B) Shah Jahan',
      ),
      'B) Shah Jahan',
    );
    expect(runner.seen.first['content'], contains('MCQ or quiz'));
  });
  test('code fenced json and unicode plain text accepted', () {
    expect(
      LocalModelProvider.parseLocalDraft(
        '```json\n{"reply":"B) Shah Jahan"}\n```',
      ),
      'B) Shah Jahan',
    );
    expect(LocalModelProvider.parseLocalDraft('हो, बोलूया.'), 'हो, बोलूया.');
  });
  test('format failure releases queue for next message', () async {
    runner.output = '<think>only reasoning</think>';
    await expectLater(
      provider.generateReply(sender: 'A', text: 'one'),
      throwsException,
    );
    runner.output = 'B) Shah Jahan';
    expect(
      await provider.generateReply(sender: 'A', text: 'two'),
      'B) Shah Jahan',
    );
  });
  test('native failure releases queue for retry', () async {
    runner.fail = true;
    await expectLater(
      provider.generateReply(sender: 'A', text: 'one'),
      throwsException,
    );
    runner.fail = false;
    runner.output = 'Hi';
    expect(await provider.generateReply(sender: 'A', text: 'two'), 'Hi');
  });
  test('overlapping drafts serialize instead of busy failure', () async {
    runner.output = 'Hi';
    final results = await Future.wait([
      provider.generateReply(sender: 'A', text: 'one'),
      provider.generateReply(sender: 'B', text: 'two'),
    ]);
    expect(results, ['Hi', 'Hi']);
    expect(runner.maxActive, 1);
  });
  test('malformed or thinking output stays manual', () async {
    runner.output = '<think>secret</think>';
    await expectLater(
      provider.generateReply(sender: 'Sam', text: 'hi'),
      throwsException,
    );
  });
}
