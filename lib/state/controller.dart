import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/message_event.dart';
import '../services/ai/ai_provider.dart';
import '../services/bridge.dart';
import '../services/event_store.dart';
import '../services/usage_reporter.dart';

/// Wires notification events -> store -> reply draft -> user review.
/// V1 sends NOTHING on its own: every send is a user tap on Approve.
class ReplierController extends ChangeNotifier {
  ReplierController({
    required this.store,
    required this.bridge,
    this.provider = const LocalRuleProvider(),
  });

  final EventStore store;
  final ReplierBridge bridge;
  final AiProvider provider;

  StreamSubscription? _sub;
  bool autoReplyEnabled = false; // master switch; V1 stays preview-only
  bool notifAccess = false;
  bool accessibilityAccess = false;
  String lastSendNote = '';

  List<MessageEvent> get pending => store.pendingReview();
  List<MessageEvent> get history => store.newestFirst();

  Future<void> start() async {
    await refreshPermissions();
    _sub = bridge.events().listen(_onEvent);
    for (final e in await bridge.drainPending()) {
      _onEvent(e);
    }
  }

  Future<void> refreshPermissions() async {
    final p = await bridge.permissionStatus();
    notifAccess = p['notification'] ?? false;
    accessibilityAccess = p['accessibility'] ?? false;
    notifyListeners();
  }

  Future<void> _onEvent(Map<String, dynamic> raw) async {
    final text = raw['text']?.toString() ?? '';
    if (text.trim().isEmpty) return; // missing notification text: skip safely
    final e = store.addIfNew(
      notifKey: raw['notifKey']?.toString() ?? '',
      appPackage: raw['package']?.toString() ?? '',
      appLabel: raw['appLabel']?.toString() ?? raw['package']?.toString() ?? '',
      sender: raw['sender']?.toString() ?? 'Unknown',
      text: text,
      at: DateTime.fromMillisecondsSinceEpoch(
        (raw['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (e == null) return; // duplicate notification
    e.generatedReply = await provider.generateReply(
      sender: e.sender,
      text: e.text,
    );
    e.status = 'generated';
    await store.save(e);
    UsageReporter.report('draft_created');
    notifyListeners();
  }

  Future<void> reject(MessageEvent e) async {
    e.status = 'rejected';
    await store.save(e);
    UsageReporter.report('draft_rejected');
    notifyListeners();
  }

  /// The ONLY send path in V1: explicit user approval of a reviewed reply.
  Future<String> approve(MessageEvent e, {String? editedText}) async {
    if (e.status == 'sending' ||
        e.status == 'submitted' ||
        e.status == 'opened_unverified' ||
        e.status == 'approved') {
      return 'Already attempted. Check the chat before trying again.';
    }
    final text = (editedText ?? e.generatedReply).trim();
    if (text.isEmpty) return 'The reply is empty.';
    e.finalReply = text;
    e.status = 'sending';
    await store.save(e);
    notifyListeners();
    var result = await bridge.sendReply(e.notifKey, text);
    if (result == 'no_inline') {
      // The app offers no inline reply action: open the chat and let the
      // accessibility service try to type + send.
      result = await bridge.openAndSend(e.notifKey, text);
      if (result == 'opened') {
        e.status = 'opened_unverified';
        lastSendNote = 'Chat opened. Sending is not confirmed. Check the chat before sending again.';
      } else if (result == 'no_accessibility') {
        e.status = 'send_failed';
        lastSendNote = 'Accessibility access is off - enable it in Settings, or the reply could not be sent.';
      } else {
        e.status = 'send_failed';
        lastSendNote = 'Could not send: the notification is gone.';
      }
    } else if (result == 'submitted' || result == 'sent') {
      e.status = 'submitted';
      lastSendNote = 'Reply submitted to the app. Delivery is not confirmed.';
    } else {
      e.status = 'send_failed';
      lastSendNote = 'Could not send the reply.';
    }
    UsageReporter.report('draft_approved', {'edited': editedText != null});
    if (e.status == 'submitted') {
      UsageReporter.report('reply_submitted', {'via': 'inline'});
    } else if (e.status == 'opened_unverified') {
      UsageReporter.report('chat_opened_unverified');
    } else if (e.status == 'send_failed') {
      UsageReporter.report('reply_send_failed');
    }
    await store.save(e);
    notifyListeners();
    return lastSendNote;
  }

  Future<void> setAutoReply(bool on) async {
    autoReplyEnabled = on;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
