import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

/// Coarse telemetry for the owner's personal dashboard.
/// Reports event COUNTS only: app starts, drafts, approvals, sends.
/// Never sends message text, sender names, or notification content.
/// Fire-and-forget: any failure is swallowed - the app works identically
/// with no network, and telemetry can never break replying.
class UsageReporter {
  static const _url =
      'https://ncaialkmxhbtarmhoiei.supabase.co/rest/v1/app_usage';
  static const _key = 'sb_publishable_oNw5xcfdpesEihrdmFXfgQ_HKgsVYAi';
  static String? _device;

  static Future<String> _deviceId() async {
    if (_device != null) return _device!;
    final box = await Hive.openBox('usage');
    var id = box.get('device_id') as String?;
    if (id == null) {
      id = 'dev-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
      await box.put('device_id', id);
    }
    _device = id;
    return id;
  }

  static void report(String kind, [Map<String, dynamic>? meta]) {
    () async {
      try {
        final device = await _deviceId();
        final client = HttpClient();
        try {
          final req = await client
              .postUrl(Uri.parse(_url))
              .timeout(const Duration(seconds: 5));
          req.headers.set('apikey', _key);
          req.headers.set('Authorization', 'Bearer $_key');
          req.headers.set('Content-Type', 'application/json');
          req.headers.set('Prefer', 'return=minimal');
          req.write(
            jsonEncode({
              'app': 'replier',
              'device': device,
              'kind': kind,
              'meta': meta ?? const {},
            }),
          );
          final res = await req.close().timeout(const Duration(seconds: 5));
          await res.drain<void>();
        } finally {
          client.close();
        }
      } catch (_) {
        // telemetry must never affect the app
      }
    }();
  }
}
