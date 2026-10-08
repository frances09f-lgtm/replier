import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:replier/services/local/local_provider.dart';
import 'package:replier/services/local/model_catalog.dart';

class FakeRunner implements LocalRunner {
  String output = '{"reply":"नमस्कार","needs_owner_input":false}';
  List<Map<String, String>> seen = [];
  int calls = 0;
  @override
  Future<String> draft(String path, List<Map<String, String>> messages) async {
    calls++;
    seen = messages;
    return output;
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
  test('unknown personal fact never becomes draft', () async {
    runner.output = '{"reply":"I ate","needs_owner_input":true}';
    await expectLater(
      provider.generateReply(sender: 'Sam', text: 'ate?'),
      throwsException,
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
  test('malformed or thinking output stays manual', () async {
    runner.output = '<think>secret</think>';
    await expectLater(
      provider.generateReply(sender: 'Sam', text: 'hi'),
      throwsException,
    );
  });
}
