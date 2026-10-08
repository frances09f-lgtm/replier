import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../services/local/model_catalog.dart';
import '../services/local/model_download.dart';
import '../services/local/local_provider.dart';

import 'package:flutter/foundation.dart';

import '../models/message_event.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/groq_provider.dart';
import '../services/ai/reply_settings.dart';
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
    this.replySettings,
  });

  final EventStore store;
  final ReplierBridge bridge;
  AiProvider provider;
  final ReplySettings? replySettings;
  bool get cloudEnabled =>
      replySettings == null ? true : replySettings!.mode != 'off';
  String get brainName => replySettings == null
      ? provider.name
      : cloudEnabled
      ? provider.name
      : "AI off - write replies manually";

  StreamSubscription? _sub;
  bool autoReplyEnabled = false; // master switch; V1 stays preview-only
  bool notifAccess = false;
  bool accessibilityAccess = false;
  String lastSendNote = '';
  bool legacyInstalled = false,
      legacyNotification = false,
      legacyAccessibility = false;
  bool get legacyBlocked => legacyNotification || legacyAccessibility;

  List<MessageEvent> get pending => store.pendingReview();
  List<MessageEvent> get history => store.newestFirst();

  ModelDownload? downloads;
  Future<void> initLocal() async {
    final root = await getApplicationSupportDirectory();
    downloads = ModelDownload(Directory('${root.path}/models'));
    if (replySettings?.mode == 'local') {
      final spec = LocalModelSpec.all.firstWhere(
        (m) => m.id == replySettings!.localModel,
      );
      provider = LocalModelProvider(
        model: spec,
        file: downloads!.modelFile(spec),
      );
    }
  }

  Future<void> configureLocal(LocalModelSpec spec) async {
    if (downloads == null || !await downloads!.installed(spec))
      throw const ReplyGenerationException('Download this model first.');
    await cancelLocal();
    if (provider is GroqProvider)
      (provider as GroqProvider).client.close(force: true);
    await replySettings!.saveLocal(spec.id);
    provider = LocalModelProvider(
      model: spec,
      file: downloads!.modelFile(spec),
    );
    notifyListeners();
  }

  Future<void> configureOff() async {
    await cancelLocal();
    await replySettings!.off();
    notifyListeners();
  }

  Future<void> cancelLocal() async {
    if (provider is LocalModelProvider)
      await (provider as LocalModelProvider).cancel();
  }

  Future<void> resourceGuard(
    LocalModelSpec spec, {
    required bool download,
  }) async {
    final r = await bridge.resources();
    if (download) {
      final partial = downloads?.partFile(spec);
      final have = partial != null && await partial.exists()
          ? await partial.length()
          : 0;
      if ((r['freeDisk'] as num).toInt() <
          spec.bytes - have + 256 * 1024 * 1024)
        throw const ReplyGenerationException(
          'Not enough free storage. Free space before downloading.',
        );
    } else if (r['lowMemory'] == true ||
        (r['availableRam'] as num).toInt() < spec.bytes + 700 * 1024 * 1024) {
      throw const ReplyGenerationException(
        'Not enough available RAM for this local model. Close other apps or use Groq.',
      );
    }
  }

  Future<void> start() async {
    await refreshPermissions();
    _sub = bridge.events().listen((e) {
      _onEvent(e).catchError((Object _) {});
    });
    for (final e in await bridge.drainPending()) {
      _onEvent(e);
    }
  }

  Future<void> refreshPermissions() async {
    final legacy = await bridge.legacyStatus();
    legacyInstalled = legacy['installed'] ?? false;
    legacyNotification = legacy['notification'] ?? false;
    legacyAccessibility = legacy['accessibility'] ?? false;
    final p = await bridge.permissionStatus();
    notifAccess = p['notification'] ?? false;
    accessibilityAccess = p['accessibility'] ?? false;
    notifyListeners();
  }

  Future<void> _onEvent(Map<String, dynamic> raw) async {
    if (legacyBlocked) return;
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
    await generate(e);
  }

  Future<void> configure(String key, String model, bool enabled) async {
    await cancelLocal();
    await replySettings!.save(key, model, enabled);
    if (provider is GroqProvider)
      (provider as GroqProvider).client.close(force: true);
    provider = GroqProvider(key: key.trim(), model: model);
    notifyListeners();
  }

  Future<void> generate(MessageEvent e) async {
    if (e.status != 'new' &&
        e.status != 'generated' &&
        e.status != 'generation_failed')
      return;
    if (legacyBlocked) return;
    e.status = 'generating';
    e.generatedReply = '';
    e.generationError = '';
    await store.save(e);
    notifyListeners();
    try {
      if (!cloudEnabled)
        throw const ReplyGenerationException(
          'AI is off. Choose Groq or Local in Settings, or tap Edit.',
        );
      if (e.text.length > 4000)
        throw const ReplyGenerationException(
          'Message too long for a short reply. Tap Edit.',
        );
      if (provider is LocalModelProvider)
        await resourceGuard(
          (provider as LocalModelProvider).model,
          download: false,
        );
      final draft = await provider.generateReply(
        sender: e.sender,
        text: e.text,
        history: store.replyHistory(e),
      );
      if (e.status == 'generating') {
        e.generatedReply = draft;
        e.status = 'generated';
        UsageReporter.report('draft_created');
      }
    } catch (error) {
      if (e.status == 'generating') {
        e.status = 'generation_failed';
        e.generationError = error is ReplyGenerationException
            ? error.message
            : 'Could not generate a draft. Tap Retry or Edit.';
      }
    }
    await store.save(e);
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
    if (e.status == 'rejected' || e.status == 'generating')
      return 'This draft is not ready to send.';
    if (e.status == 'superseded')
      return 'A newer message arrived. Review the newest draft instead.';
    if (legacyBlocked)
      return 'Turn off old Replier notification and accessibility access first.';
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
    downloads?.cancel();
    cancelLocal();
    if (provider is GroqProvider)
      (provider as GroqProvider).client.close(force: true);
    super.dispose();
  }
}
