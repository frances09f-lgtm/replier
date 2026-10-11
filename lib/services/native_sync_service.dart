import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../models/app_settings.dart';
import '../models/rule.dart';

/// Syncs rules and settings to the native Android side using TWO mechanisms:
///
/// 1. **File-based sync (primary)**: Writes rules.json to the app's internal
///    files directory. Kotlin reads this file directly — works even when
///    MainActivity is not running and needs zero MethodChannel activity.
///
/// 2. **MethodChannel sync (secondary)**: Also writes via MethodChannel to
///    SharedPreferences for backward compatibility and instant updates.
class NativeSyncService {
  static const MethodChannel _nativeChannel =
      MethodChannel(AppConstants.nativeChannel);

  static const String _rulesFileName = 'auto_reply_rules.json';
  static const String _settingsFileName = 'auto_reply_settings.json';

  /// Push all rules to:
  ///   (a) a JSON file in the app's files directory (always works)
  ///   (b) native SharedPreferences via MethodChannel (when app is foregrounded)
  Future<void> syncRules(List<Rule> rules) async {
    final rulesJson = jsonEncode(rules.map((r) => r.toJson()).toList());

    // (a) Write to file — reliable, works in background and after restart
    await _writeToFile(_rulesFileName, rulesJson);

    // (b) MethodChannel — instant update when MainActivity is alive
    try {
      await _nativeChannel.invokeMethod('syncRules', {'rulesJson': rulesJson});
    } on MissingPluginException {
      // Engine not ready yet — file sync above is sufficient
    } catch (e) {
      // MainActivity may not be running — file sync above is sufficient
      print('NativeSyncService: MethodChannel syncRules skipped ($e)');
    }
  }

  /// Push current settings similarly.
  Future<void> syncSettings(AppSettings settings) async {
    final safe = settings.toJson()
      ..remove('groqApiKey')
      ..remove('geminiApiKey');
    final settingsJson = jsonEncode(safe);

    await _writeToFile(_settingsFileName, settingsJson);

    try {
      await _nativeChannel
          .invokeMethod('syncSettings', {'settingsJson': settingsJson});
    } on MissingPluginException {
      // Engine not ready yet
    } catch (e) {
      print('NativeSyncService: MethodChannel syncSettings skipped ($e)');
    }
  }

  Future<void> _writeToFile(String fileName, String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(content, flush: true);
      print('NativeSyncService: wrote $fileName (${content.length} bytes)');
    } catch (e) {
      print('NativeSyncService: failed to write $fileName: $e');
    }
  }
}
