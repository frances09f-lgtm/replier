import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/message_event.dart';

/// Local-first store. A notification is processed exactly once: the
/// notification key is remembered in a seen-set, so re-posts and engine
/// restarts never generate a second reply draft for the same notification.
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
    if (_seen.values.contains(notifKey)) return null;
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
    _seen.add(notifKey);
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
      .where((e) => e.status == 'generated' || e.status == 'new')
      .toList();

  Future<void> save(MessageEvent e) => e.save();
}
