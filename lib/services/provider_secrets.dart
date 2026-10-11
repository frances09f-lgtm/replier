import 'package:flutter/services.dart';
import '../core/constants.dart';

class ProviderSecrets {
  static const _channel = MethodChannel(AppConstants.nativeChannel);
  static String groq = '', gemini = '';
  static Future<void> load() async {
    try {
      final values =
          await _channel.invokeMapMethod<String, dynamic>('loadProviderKeys') ??
              {};
      groq = values['groq'] as String? ?? '';
      gemini = values['gemini'] as String? ?? '';
    } on MissingPluginException {
      groq = '';
      gemini = '';
    }
  }

  static Future<void> write(String provider, String value) async {
    await _channel.invokeMethod(
        'saveProviderKey', {'provider': provider, 'value': value});
    if (provider == 'groq') {
      groq = value;
    } else {
      gemini = value;
    }
  }
}
