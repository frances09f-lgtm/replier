/// App constants
class AppConstants {
  // App info
  static const String appName = 'Auto Reply Assistant';
  static const String appVersion = '1.0.16';

  // Hive box names
  static const String rulesBox = 'rules';
  static const String settingsBox = 'settings';
  static const String logsBox = 'logs';
  static const String statsBox = 'stats';
  static const String notesBox = 'notes';

  // Method channel names
  static const String nativeChannel = 'com.replier.replier/native';
  static const String notificationChannel = 'com.replier.replier/notification';
  static const String accessibilityChannel =
      'com.replier.replier/accessibility';

  // Supported apps
  static const String whatsappPackage = 'com.whatsapp';
  static const String instagramPackage = 'com.instagram.android';

  // Default settings
  static const int defaultMinReplyDelay = 1;
  static const int defaultMaxReplyDelay = 10;
  static const int maxReplyDelay = 300;
  static const bool defaultPreventDuplicateReplies = true;
  static const bool defaultIgnoreGroupChats = true;

  // AI defaults
  static const bool defaultAiReplyEnabled = false;
  static const String defaultAiModelType = 'phi_local';
  static const String defaultSelectedLocalModel = 'llama_3_2_1b';
  static const String defaultAiSystemPrompt =
      'Write a short reply in your usual style. Reply short casual Hinglish, 1-10 words. Match incoming language. No polite assistant sentences.';

  // Schedule defaults
  static const bool defaultScheduleEnabled = false;
  static const int defaultScheduleStartHour = 8;
  static const int defaultScheduleStartMinute = 0;
  static const int defaultScheduleEndHour = 22;
  static const int defaultScheduleEndMinute = 0;

  // Hive box names
  static const String chatBox = 'chat_messages';

  // Storage limits
  static const int maxLogs = 1000;
}
