// Regression test for the instrumentation gap behind:
//   user: "stuck at got new message" + "There are no entries" + "Its not replying"
//
// The native pipeline (AppNotificationListenerService.kt) reports every failed
// attempt to Dart as onReplyFailed WITH a human-readable reason
// ("Model not downloaded", "No direct reply action found", engine errors, ...).
// Before the fix, AutoReplyService discarded that reason: no log entry for
// failures, no entry for AI-path receipts (only rule matches), and only
// onReplySuccess persisted. On a phone where every reply fails, the Logs tab
// stayed EMPTY forever - exactly what the user reported.
//
// The fix persists a privacy-safe failure entry: reason only, no sender,
// no message content, no reply text; the daily-replies-sent counter must not
// move (nothing was sent) and last-reply / AI-count stats must ignore
// failures. Reasons are sanitized before persisting (URLs, auth headers,
// emails, phone numbers, token-like runs redacted) while keeping the useful
// error category ("Model not downloaded", "HTTP 401", ...).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:replier/core/constants.dart';
import 'package:replier/core/hive_config.dart';
import 'package:replier/models/reply_log.dart';
import 'package:replier/repositories/log_repository.dart';
import 'package:replier/repositories/rule_repository.dart';
import 'package:replier/services/auto_reply_service.dart';

/// Writes the OLD 12-field record format (before failureReason existed), so
/// we can prove records written by older app builds still read after upgrade.
class LegacyReplyLogAdapter extends TypeAdapter<ReplyLog> {
  @override
  final int typeId = 2;

  @override
  ReplyLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReplyLog(
      id: fields[0] as String,
      sender: fields[1] as String,
      originalMessage: fields[2] as String,
      autoReplySent: fields[3] as String,
      appName: fields[4] as String,
      dateTime: fields[5] as DateTime,
      ruleId: fields[6] as String,
      aiModel: fields[7] as String,
      rating: fields[8] as int,
      feedbackNote: fields[9] as String,
      correctedReply: fields[10] as String,
      trained: fields[11] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ReplyLog obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.sender)
      ..writeByte(2)
      ..write(obj.originalMessage)
      ..writeByte(3)
      ..write(obj.autoReplySent)
      ..writeByte(4)
      ..write(obj.appName)
      ..writeByte(5)
      ..write(obj.dateTime)
      ..writeByte(6)
      ..write(obj.ruleId)
      ..writeByte(7)
      ..write(obj.aiModel)
      ..writeByte(8)
      ..write(obj.rating)
      ..writeByte(9)
      ..write(obj.feedbackNote)
      ..writeByte(10)
      ..write(obj.correctedReply)
      ..writeByte(11)
      ..write(obj.trained);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final d = await Directory.systemTemp.createTemp('replier-failure-gap');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => d.path);
    await HiveConfig.initialize();
  });

  Future<void> nativeCall(String method, Object? args) async {
    const channel = MethodChannel(AppConstants.notificationChannel);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      AppConstants.notificationChannel,
      channel.codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  test('failed AI reply writes a privacy-safe failure entry to the Logs tab',
      () async {
    AutoReplyService(
      ruleRepository: RuleRepository(),
      logRepository: LogRepository(),
    ).initialize();

    final repo = LogRepository();
    final before = repo.getAllLogs().length;
    final sentBefore = repo.getDailyRepliesSent();
    final lastBefore = repo.getLastReplyLog();

    await nativeCall(
        'onAiUsageUpdate', jsonEncode({'error': 'Model not downloaded'}));
    await nativeCall('onReplyFailed', 'Model not downloaded');

    final logs = repo.getAllLogs();
    expect(logs.length, before + 1,
        reason: 'a failed attempt must appear in the Logs tab');
    final failure =
        logs.firstWhere((l) => l.failureReason == 'Model not downloaded');
    expect(failure.sender, isEmpty);
    expect(failure.originalMessage, isEmpty);
    expect(failure.autoReplySent, isEmpty);
    // Stats honesty: nothing was sent.
    expect(repo.getDailyRepliesSent(), sentBefore);
    expect(repo.getLastReplyLog()?.id, lastBefore?.id);
    expect(repo.getAiReplyCounts().values.fold<int>(0, (a, b) => a + b), 0,
        reason: 'failures carry no model and must not inflate AI counts');
    // App filter: an entry with no app must not appear under a real app.
    expect(repo.filterLogsByApp('WhatsApp').where((l) => l.id == failure.id),
        isEmpty);

    // Control: a successful AI reply still logs and counts normally.
    await nativeCall(
        'onReplySuccess',
        jsonEncode({
          'isAiReply': true,
          'sender': 'Asha',
          'replyText': 'On my way',
          'originalMessage': 'where are you',
          'appName': 'WhatsApp',
          'aiModelType': 'phi_local',
        }));
    expect(repo.getAllLogs().length, before + 2);
    expect(repo.getDailyRepliesSent(), sentBefore + 1);
  });

  test('failure reasons are sanitized but keep their error category',
      () async {
    AutoReplyService(
      ruleRepository: RuleRepository(),
      logRepository: LogRepository(),
    ).initialize();

    final repo = LogRepository();
    Future<String> stored(String raw) async {
      await nativeCall('onReplyFailed', raw);
      final matches = repo
          .getAllLogs()
          .where((l) => l.failureReason.isNotEmpty)
          .toList();
      return matches.first.failureReason;
    }

    // Category preserved verbatim.
    expect(await stored('Model not downloaded'), 'Model not downloaded');
    // Credential-bearing URL: host kept, creds/path/query dropped.
    final url = await stored(
        'HTTP 401 from https://user:secretpass@api.example.com/v1/chat?key=ABC123');
    expect(url.contains('secretpass'), isFalse);
    expect(url.contains('ABC123'), isFalse);
    expect(url.contains('https://api.example.com/...'), isTrue);
    expect(url.startsWith('HTTP 401'), isTrue);
    // Auth headers / bearer tokens.
    final bearer = await stored('request failed: Bearer gsk_abc123xyz token');
    expect(bearer.contains('gsk_abc123xyz'), isFalse);
    // Email + phone.
    expect((await stored('cannot send to bob@example.com now'))
        .contains('bob@example.com'), isFalse);
    expect((await stored('undeliverable to +91 95298 43414 tomorrow'))
        .contains('95298'), isFalse);
    // Long token run.
    const tokenLike = 'abcdef1234567890abcdef1234567890abcdef12';
    final t = await stored('HTTP 401 unauthorized key=$tokenLike check it');
    expect(t.contains(tokenLike), isFalse);
    expect(t.contains('[redacted]'), isTrue);
    expect(t.startsWith('HTTP 401 unauthorized key='), isTrue);
    // Cap.
    final long = await stored('x' * 500);
    expect(long.length, lessThanOrEqualTo(200));
  });

  test('records written by older builds (no failureReason field) still read',
      () async {
    // Swap in the legacy 12-field writer, store a record the way an old
    // build would have, then read it back with the CURRENT adapter.
    Hive.registerAdapter(LegacyReplyLogAdapter(), override: true);
    final legacy = ReplyLog(
      id: 'legacy-record-1',
      sender: 'Asha',
      originalMessage: 'old message',
      autoReplySent: 'old reply',
      appName: 'WhatsApp',
      dateTime: DateTime.now(),
      ruleId: '',
      aiModel: 'phi_local',
    );
    await HiveConfig.getLogsBox().put(legacy.id, legacy);
    // Restore the current adapter - this is what an upgraded app runs.
    Hive.registerAdapter(ReplyLogAdapter(), override: true);

    final repo = LogRepository();
    final readBack =
        repo.getAllLogs().firstWhere((l) => l.id == 'legacy-record-1');
    expect(readBack.sender, 'Asha');
    expect(readBack.failureReason, '',
        reason: 'old records have no field 12; must read as a sent reply');
    // And it must still count as a sent reply for last-reply stats.
    expect(repo.getLastReplyLog()?.id, 'legacy-record-1');
  });
}
