import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/default_rules.dart';
import '../providers/rule_provider.dart';
import 'dashboard_screen.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';

/// Splash screen that initializes the app and navigates to dashboard
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    const channel = MethodChannel(AppConstants.nativeChannel);
    final accepted = await channel.invokeMethod<bool>('consentStatus') ?? false;
    if (!accepted && mounted) {
      final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
                  title: const Text('Set up Replier'),
                  content: const SingleChildScrollView(
                      child: Text(
                          'Replier reads message notifications from WhatsApp and Instagram to make replies. Notification access can expose private message text. Choose apps, rules, contacts and quiet hours in Settings.\n\nReplies need your approval by default. Automatic sending starts only when you turn on the master switch and turn off Confirm Before Reply. Turning off the master switch stops new replies.\n\nLocal models run on your phone. Cloud AI sends message text and conversation context to the provider you choose, using your own runtime key. Android encrypts provider keys on this device.\n\nDisable notification and accessibility access for the old Replier app to avoid duplicate replies. Accessibility sending is disabled in this version because the recipient cannot be verified.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Not now')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Continue with replies off'))
                  ]));
      if (result == true) await channel.invokeMethod('acceptConsent');
    }
    if (await Permission.notification.isDenied)
      await Permission.notification.request();
    if (mounted)
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const DashboardScreen()));

    // Refresh rules to sync with native side on startup
    try {
      final notifier = ref.read(rulesProvider.notifier);

      // Load default rules on first launch
      if (!notifier.hasDefaultRules()) {
        for (final rule in defaultRules) {
          await notifier.addRule(rule);
        }
      } else {
        // One-time cleanup: drop retired generic defaults so AI handles
        // small-talk instead of canned Ha/Hmm. Safe: only isDefault rules
        // with purely-retired triggers are removed.
        try {
          await notifier.deleteRetiredHijackDefaults();
        } catch (_) {}
        await notifier.refreshRules();
      }
    } catch (e) {
      print('Error refreshing rules on startup: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.reply_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Auto Reply Assistant',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
