import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/message_event.dart';

/// Local-first store. Android notification keys identify a conversation slot,
/// not a message. Deduplicate exact message updates, not permanent keys.
class EventStore {
  static const _eventsBox = 'events';
  static const _seenBox = 'seen_notifs';
  static const _maxEvents = 500;

  late Box<MessageEvent> _events;
  late Box<String> _seen;

  Future<void> init() async {
    _events = await Hive.openBox<MessageEvent>(_eventsBox);
    _seen = await Hive.openBox<String>(_seenBox);
  }

  /// Returns the stored event, or null when this notification key was
  /// already processed (duplicate suppression).
  MessageEvent? addIfNew({
    required String notifKey,
    required String appPackage,
    required String appLabel,
    required String sender,
    required String text,
    required DateTime at,
  }) {
    final identity = jsonEncode([
      appPackage,
      notifKey,
      sender,
      text,
      at.millisecondsSinceEpoch,
    ]);
    if (_seen.values.contains(identity)) return null;
    for (final previous in _events.values) {
      if (previous.notifKey == notifKey &&
          previous.appPackage == appPackage &&
          (previous.status == 'new' ||
              previous.status == 'generated' ||
              previous.status == 'generating' ||
              previous.status == 'generation_failed')) {
        previous.status = 'superseded';
        _events.put(previous.id, previous);
      }
    }
    final e = MessageEvent(
      id: const Uuid().v4(),
      notifKey: notifKey,
      appPackage: appPackage,
      appLabel: appLabel,
      sender: sender,
      text: text,
      at: at,
    );
    _events.put(e.id, e);
    _seen.add(identity);
    while (_seen.length > 2000) {
      _seen.delete(_seen.keyAt(0));
    }
    _trim();
    return e;
  }

  void _trim() {
    while (_events.length > _maxEvents) {
      final oldest = _events.values.reduce(
        (a, b) => a.at.isBefore(b.at) ? a : b,
      );
      oldest.delete();
    }
  }

  List<MessageEvent> newestFirst() =>
      _events.values.toList()..sort((a, b) => b.at.compareTo(a.at));

  List<MessageEvent> pendingReview() => newestFirst()
      .where(
        (e) =>
            e.status == 'generated' ||
            e.status == 'new' ||
            e.status == 'generating' ||
            e.status == 'generation_failed',
      )
      .toList();

  /// Conservative chat boundary: app + notification slot + exact sender.
  /// Ambiguous or changed identifiers lose context rather than leak another chat.
  List<Map<String, String>> replyHistory(MessageEvent current) {
    final previous = newestFirst()
        .where(
          (e) =>
              e.id != current.id &&
              e.at.isBefore(current.at) &&
              e.appPackage == current.appPackage &&
              e.notifKey == current.notifKey &&
              e.sender == current.sender &&
              current.at.difference(e.at).inHours < 24,
        )
        .take(6)
        .toList()
        .reversed;
    final turns = <Map<String, String>>[];
    for (final e in previous) {
      turns.add({
        'role': 'user',
        'content': e.text.length > 800 ? e.text.substring(0, 800) : e.text,
      });
      if (e.status == 'submitted' && e.finalReply.isNotEmpty) {
        turns.add({
          'role': 'assistant',
          'content': e.finalReply.length > 600
              ? e.finalReply.substring(0, 600)
              : e.finalReply,
        });
      }
    }
    return turns;
  }

  Future<void> save(MessageEvent e) => e.save();
}
