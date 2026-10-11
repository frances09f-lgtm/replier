import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';

/// Service for handling native Android communication
class NotificationService {
  static const MethodChannel _nativeChannel =
      MethodChannel(AppConstants.nativeChannel);
  static const MethodChannel _notificationChannel =
      MethodChannel(AppConstants.notificationChannel);

  /// Initialize method channels
  void initialize() {
    // Channel handler is owned by AutoReplyService.
    // NotificationService only provides helper methods for settings/permissions.
  }

  /// Open notification listener settings
  Future<void> openNotificationListenerSettings() async {
    try {
      await _nativeChannel.invokeMethod('openNotificationListenerSettings');
    } catch (e) {
      throw Exception('Failed to open notification listener settings: $e');
    }
  }

  /// Open accessibility settings
  Future<void> openAccessibilitySettings() async {
    try {
      await _nativeChannel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      throw Exception('Failed to open accessibility settings: $e');
    }
  }

  /// Open battery optimization settings
  Future<void> openBatteryOptimizationSettings() async {
    try {
      await _nativeChannel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      throw Exception('Failed to open battery optimization settings: $e');
    }
  }

  /// Check if notification listener is enabled
  Future<bool> isNotificationListenerEnabled() async {
    try {
      final result =
          await _nativeChannel.invokeMethod('isNotificationListenerEnabled');
      return result as bool;
    } catch (e) {
      return false;
    }
  }

  /// Check if accessibility service is enabled
  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final result =
          await _nativeChannel.invokeMethod('isAccessibilityServiceEnabled');
      return result as bool;
    } catch (e) {
      return false;
    }
  }

  /// Check if battery optimization is disabled
  Future<bool> isBatteryOptimizationDisabled() async {
    try {
      final result =
          await _nativeChannel.invokeMethod('isBatteryOptimizationDisabled');
      return result as bool;
    } catch (e) {
      return false;
    }
  }

  /// Check if POST_NOTIFICATIONS permission is granted (Android 13+)
  Future<bool> isPostNotificationPermissionGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Request POST_NOTIFICATIONS permission
  Future<bool> requestPostNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Send reply via notification listener service
  Future<void> sendReply(String key, String replyText) async {
    try {
      await _notificationChannel.invokeMethod('sendReply', {
        'key': key,
        'replyText': replyText,
      });
    } catch (e) {
      throw Exception('Failed to send reply: $e');
    }
  }

  /// Get AI usage data from native side
  Future<Map<String, dynamic>?> getAiUsage() async {
    try {
      final result = await _notificationChannel.invokeMethod('getAiUsage');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
