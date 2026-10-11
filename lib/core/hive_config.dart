import 'package:hive_flutter/hive_flutter.dart';
import '../legacy/message_event.dart';
import 'package:path_provider/path_provider.dart';
import '../models/rule.dart';
import '../models/app_settings.dart';
import '../models/reply_log.dart';
import '../models/chat_message.dart';
import '../models/note.dart';
import '../core/constants.dart';

/// Hive configuration and initialization
class HiveConfig {
  /// Initialize Hive and register adapters
  static Future<void> initialize() async {
    // Get application documents directory
    final appDocDir = await getApplicationDocumentsDirectory();

    // Initialize Hive
    await Hive.initFlutter(appDocDir.path);

    if (!Hive.isAdapterRegistered(0))
      Hive.registerAdapter(MessageEventAdapter());
    await Hive.openBox<MessageEvent>("events");
    // Register adapters
    if (!Hive.isAdapterRegistered(51)) {
      Hive.registerAdapter(RuleAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ReplyLogAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(NoteAdapter());
    }

    // Open boxes (data persists across app launches)
    await Hive.openBox<Rule>(AppConstants.rulesBox);
    await Hive.openBox<AppSettings>(AppConstants.settingsBox);
    await Hive.openBox<ReplyLog>(AppConstants.logsBox);
    await Hive.openBox(AppConstants.statsBox);
    await Hive.openBox<ChatMessage>(AppConstants.chatBox);
    await Hive.openBox<Note>(AppConstants.notesBox);

    print('Hive boxes initialized');
  }

  /// Get rules box
  static Box<Rule> getRulesBox() {
    return Hive.box<Rule>(AppConstants.rulesBox);
  }

  /// Get settings box
  static Box<AppSettings> getSettingsBox() {
    return Hive.box<AppSettings>(AppConstants.settingsBox);
  }

  /// Get logs box
  static Box<ReplyLog> getLogsBox() {
    return Hive.box<ReplyLog>(AppConstants.logsBox);
  }

  /// Get stats box (for counters like total notifications received)
  static Box getStatsBox() {
    return Hive.box(AppConstants.statsBox);
  }

  /// Get chat messages box
  static Box<ChatMessage> getChatBox() {
    return Hive.box<ChatMessage>(AppConstants.chatBox);
  }

  /// Check if notes box is currently open
  static bool isNotesBoxOpen() {
    return Hive.isBoxOpen(AppConstants.notesBox);
  }

  /// Get notes box
  static Box<Note> getNotesBox() {
    return Hive.box<Note>(AppConstants.notesBox);
  }

  /// Ensure notes box is open (safe for hot-reloads without restart)
  static Future<Box<Note>> ensureNotesBoxOpen() async {
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(NoteAdapter());
    }
    if (!Hive.isBoxOpen(AppConstants.notesBox)) {
      return await Hive.openBox<Note>(AppConstants.notesBox);
    }
    return getNotesBox();
  }

  /// Close all boxes
  static Future<void> close() async {
    await Hive.close();
  }

  /// Clear only the rules box
  static Future<void> clearRulesBox() async {
    await getRulesBox().clear();
  }

  /// Clear all data (for testing purposes)
  static Future<void> clearAll() async {
    await getRulesBox().clear();
    await getSettingsBox().clear();
    await getLogsBox().clear();
    await getNotesBox().clear();
  }
}
