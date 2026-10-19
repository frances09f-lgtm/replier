import 'package:flutter/material.dart';
import 'update/app_update.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/hive_config.dart';
import 'core/injection_container.dart';
import 'core/provider_container.dart';
import 'providers/settings_provider.dart';
import 'providers/pipeline_status_provider.dart';
import 'providers/note_provider.dart';
import 'repositories/log_repository.dart';
import 'repositories/rule_repository.dart';
import 'services/auto_reply_service.dart';
import 'screens/splash_screen.dart';
import 'services/provider_secrets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ProviderSecrets.load();
  await HiveConfig.initialize();
  await configureDependencies();

  // Logging-only listener — native side handles actual replies.
  // DO NOT call sendReply from here — that would cause double-replies.
  // NOTE: Sample rules are added and synced to native SharedPreferences
  // inside SplashScreen via the provider (which also calls syncRules).
  AutoReplyService(
    ruleRepository: RuleRepository(),
    logRepository: LogRepository(),
    providerContainer: globalProviderContainer,
  ).initialize();

  // Eagerly initialise pipeline status provider so it registers
  // MethodChannel callbacks before the first notification arrives.
  globalProviderContainer.read(pipelineStatusProvider);

  // Eagerly load notes so native reminder alarms (5 minutes before each
  // meeting/deadline) are armed as soon as the app starts.
  globalProviderContainer.read(notesProvider);

  runApp(
    UncontrolledProviderScope(
      container: globalProviderContainer,
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only rebuild MaterialApp on dark-mode changes. Watching the whole
    // settings object rebuilt the entire app (including SettingsScreen's
    // ListView) on every toggle, resetting scroll state and causing jumps.
    final isDark = ref.watch(appSettingsProvider.select((s) => s.darkMode));
    const primaryColor = Color(0xFF4F46E5); // Modern Deep Indigo

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Auto Reply Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: isDark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: isDark ? Brightness.dark : Brightness.light,
          surface: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor:
            isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor:
              isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 3,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
