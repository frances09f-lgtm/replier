import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/hive_config.dart';
import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/rule.dart';
import 'rule_provider.dart';
import 'settings_provider.dart';

final chatProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) {
  return ChatNotifier(ref);
});

final chatLoadingProvider = StateProvider<bool>((ref) => false);

final chatErrorProvider = StateProvider<String?>((ref) => null);

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;

  ChatNotifier(this._ref) : super([]) {
    print('[Chat] ChatNotifier constructor');
    _loadMessages();
  }

  void _loadMessages() {
    final box = HiveConfig.getChatBox();
    final messages = box.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    state = messages;
  }

  Future<void> sendMessage(String text) async {
    print('[Chat] sendMessage called with: "$text"');
    if (text.trim().isEmpty) return;

    _ref.read(chatErrorProvider.notifier).state = null;
    _ref.read(chatLoadingProvider.notifier).state = true;

    final userMessage = ChatMessage(role: 'user', content: text.trim());
    final box = HiveConfig.getChatBox();
    await box.put(userMessage.id, userMessage);
    state = [...state, userMessage];

    try {
      final settings = _ref.read(appSettingsProvider);

      final aiResponse = await _callAi(text, settings);
      final aiMessage = ChatMessage(
        role: 'assistant',
        content: aiResponse.reply,
        model: aiResponse.model,
      );
      await box.put(aiMessage.id, aiMessage);
      state = [...state, aiMessage];

      // Check for busy/meeting intent in user message and set busy mode
      _checkAndSetBusyMode(text);
      _syncChatbotContext();
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _ref.read(chatErrorProvider.notifier).state = msg;
      final errorMessage = ChatMessage(
        role: 'assistant',
        content: 'Error: $msg',
      );
      await box.put(errorMessage.id, errorMessage);
      state = [...state, errorMessage];
      _syncChatbotContext();
    } finally {
      _ref.read(chatLoadingProvider.notifier).state = false;
    }
  }

  void _checkAndSetBusyMode(String text) {
    final lower = text.toLowerCase();

    // Detect busy intent keywords
    bool hasMeeting = lower.contains('meeting');
    bool hasBusy = lower.contains('busy');
    bool hasAway = lower.contains('away') ||
        lower.contains('afk') ||
        lower.contains('leave');
    bool hasDriving = lower.contains('driving') || lower.contains('drive');
    bool hasWork = lower.contains('work') || lower.contains('office');
    bool hasSleep = lower.contains('sleep') ||
        lower.contains('sleeping') ||
        lower.contains('bed');
    bool hasClass = lower.contains('class') ||
        lower.contains('lecture') ||
        lower.contains('study');

    if (!hasMeeting &&
        !hasBusy &&
        !hasAway &&
        !hasDriving &&
        !hasWork &&
        !hasSleep &&
        !hasClass) return;

    // Determine reply text
    String replyText;
    if (hasMeeting) {
      replyText = "I'm currently in a meeting. I'll get back to you shortly.";
    } else if (hasDriving) {
      replyText = "I'm driving right now. I'll reply when I arrive.";
    } else if (hasSleep) {
      replyText = "I'm sleeping right now. I'll reply when I wake up.";
    } else if (hasClass) {
      replyText = "I'm in class right now. I'll reply after it ends.";
    } else if (hasAway) {
      replyText = "I'm away right now. I'll get back to you soon.";
    } else if (hasWork) {
      replyText = "I'm at work right now. I'll reply when I'm free.";
    } else {
      replyText = "I'm busy right now. I'll reply later.";
    }

    // Extract duration
    int durationMinutes = 120; // default 2 hours

    final durationRegex = RegExp(
      r'(?:for\s+)?(?:an?|one|two|three|four|five|six|seven|eight|nine|ten|'
      r'\d+|half\s+an?)\s*(hour|hr|minute|min|day|days|hours|hrs|minutes|mins)',
      caseSensitive: false,
    );
    final match = durationRegex.firstMatch(lower);
    if (match != null) {
      final numStr = match.group(0)!.toLowerCase();
      final unit = match.group(1)!.toLowerCase();

      int numericValue = 0;
      if (numStr.contains('an') ||
          numStr.contains('one') ||
          numStr.contains('a ')) {
        numericValue = 1;
      } else if (numStr.contains('two')) {
        numericValue = 2;
      } else if (numStr.contains('three')) {
        numericValue = 3;
      } else if (numStr.contains('four')) {
        numericValue = 4;
      } else if (numStr.contains('five')) {
        numericValue = 5;
      } else if (numStr.contains('six')) {
        numericValue = 6;
      } else if (numStr.contains('seven')) {
        numericValue = 7;
      } else if (numStr.contains('eight')) {
        numericValue = 8;
      } else if (numStr.contains('nine')) {
        numericValue = 9;
      } else if (numStr.contains('ten')) {
        numericValue = 10;
      } else if (numStr.contains('half')) {
        numericValue = 0;
        if (unit.startsWith('hour') || unit.startsWith('hr')) {
          durationMinutes = 30;
        } else {
          durationMinutes = 30;
        }
      } else {
        final digits = RegExp(r'\d+').firstMatch(numStr);
        if (digits != null) {
          numericValue = int.tryParse(digits.group(0)!) ?? 1;
        } else {
          numericValue = 1;
        }
      }

      if (unit.startsWith('day') || unit.startsWith('days')) {
        durationMinutes = numericValue * 24 * 60;
      } else if (unit.startsWith('hour') || unit.startsWith('hr')) {
        durationMinutes = numericValue * 60;
      } else {
        durationMinutes = numericValue;
      }
    }

    final untilTimestamp =
        DateTime.now().millisecondsSinceEpoch + (durationMinutes * 60 * 1000);
    _ref
        .read(appSettingsProvider.notifier)
        .setBusyMode(replyText, untilTimestamp);

    final durationStr = durationMinutes >= 1440
        ? '${durationMinutes ~/ 1440} day(s)'
        : durationMinutes >= 60
            ? '${durationMinutes ~/ 60} hour(s)'
            : '$durationMinutes minute(s)';

    // Show confirmation in chat
    final confirmMsg = ChatMessage(
      role: 'assistant',
      content:
          '✅ Busy mode activated: "$replyText"\nDuration: $durationStr\nAuto-reply will use this message.',
      model: 'system',
    );
    final box = HiveConfig.getChatBox();
    box.put(confirmMsg.id, confirmMsg);
    state = [...state, confirmMsg];
    print(
        '[Chat] Busy mode set: reply="$replyText", duration=${durationMinutes}min, until=$untilTimestamp');
  }

  String _sanitize(String s) {
    final sb = StringBuffer();
    for (final rune in s.runes) {
      if (rune >= 0x20 && rune <= 0xD7FF ||
          rune >= 0xE000 && rune <= 0xFFFD ||
          rune >= 0x10000 && rune <= 0x10FFFF) {
        sb.writeCharCode(rune);
      } else if (rune == 0x0A || rune == 0x0D || rune == 0x09) {
        sb.writeCharCode(rune);
      }
    }
    return sb.toString();
  }

  Future<({String reply, String model, bool fallback, String? fallbackReason})>
      _callAi(String text, AppSettings settings) async {
    const channel = MethodChannel('com.replier.replier/native');
    try {
      final history = state
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .map((m) => {
                'role': m.role,
                'content': _sanitize(m.content),
              })
          .toList();

      final recent =
          history.length > 10 ? history.sublist(history.length - 10) : history;

      final fullPrompt =
          _sanitize(settings.aiSystemPrompt + settings.formatTrainingPrompt());

      final res = await channel.invokeMapMethod<String, dynamic>('chatWithAi', {
        'engineType': settings.aiModelType,
        'localModelId': settings.selectedLocalModel,
        'message': text,
        'systemPrompt': fullPrompt,
        'history': recent,
      });

      if (res != null) {
        final reply = res['reply'] as String? ?? '';
        final model = res['model'] as String? ?? 'phi_local';
        final fallback = res['fallback'] as bool? ?? false;
        final fallbackReason = res['fallbackReason'] as String?;
        if (reply.isNotEmpty) {
          return (
            reply: reply,
            model: model,
            fallback: fallback,
            fallbackReason: fallbackReason
          );
        }
      }

      // Fallback: call legacy chatWithPhi
      final result = await channel.invokeMethod<String>('chatWithPhi', {
        'modelId': settings.selectedLocalModel,
        'message': text,
        'systemPrompt': fullPrompt,
        'history': recent,
      });

      if (result == null || result.isEmpty) {
        throw Exception('AI returned empty response');
      }
      return (
        reply: result,
        model: 'phi_local',
        fallback: false,
        fallbackReason: null
      );
    } catch (e) {
      if (e is MissingPluginException) {
        throw Exception(
            'AI not available. Download the local model in Settings first.');
      }
      rethrow;
    }
  }

  /// Correct an AI reply directly in chat, train the model, and optionally create an auto-reply rule
  Future<void> correctAiReply(String messageId, String newContent,
      {bool createRule = false}) async {
    final idx = state.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    final targetMsg = state[idx];
    if (targetMsg.role != 'assistant') return;

    final originalText = targetMsg.originalContent ?? targetMsg.content;

    // Find the preceding user message to pair with this reply
    String userMessageText = '';
    for (int i = idx - 1; i >= 0; i--) {
      if (state[i].role == 'user') {
        userMessageText = state[i].content;
        break;
      }
    }

    final updatedMsg = ChatMessage(
      id: targetMsg.id,
      role: targetMsg.role,
      content: newContent.trim(),
      timestamp: targetMsg.timestamp,
      model: targetMsg.model,
      isTrained: true,
      originalContent: originalText,
    );

    final box = HiveConfig.getChatBox();
    await box.put(updatedMsg.id, updatedMsg);

    final newState = List<ChatMessage>.from(state);
    newState[idx] = updatedMsg;
    state = newState;

    if (userMessageText.isNotEmpty) {
      await _ref
          .read(appSettingsProvider.notifier)
          .addTrainingExample(userMessageText, newContent.trim());

      if (createRule) {
        final ruleRepo = _ref.read(ruleRepositoryProvider);
        final newRule = Rule(
          id: const Uuid().v4(),
          triggerText: userMessageText,
          replyText: newContent.trim(),
          exactMatch: false,
          containsMatch: true,
          caseSensitive: false,
          isEnabled: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          triggerTexts: [userMessageText],
          replies: [newContent.trim()],
        );
        await ruleRepo.addRule(newRule);
        await _ref.read(rulesProvider.notifier).refreshRules();
      }
    }

    _syncChatbotContext();
  }

  Future<void> clearConversation() async {
    final box = HiveConfig.getChatBox();
    await box.clear();
    state = [];
    _ref.read(chatErrorProvider.notifier).state = null;
    _syncChatbotContext();
  }

  void _syncChatbotContext() {
    try {
      final recent = state
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .where((m) => !m.content.startsWith('Error:'))
          .map((m) =>
              '${m.role == 'user' ? 'the user' : 'Assistant'}: ${m.content}')
          .toList();

      final context = recent.length > 6
          ? recent.sublist(recent.length - 6).join('\n')
          : recent.join('\n');

      const channel = MethodChannel('com.replier.replier/native');
      channel.invokeMethod('setChatbotContext', {'context': context});
      print(
          '[Chat] Synced chatbot context to Kotlin (${context.length} chars)');
    } catch (e) {
      print('[Chat] Failed to sync chatbot context: $e');
    }
  }
}
