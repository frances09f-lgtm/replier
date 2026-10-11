import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/error_handler.dart';

/// Utility class for handling app permissions
class PermissionHandler {
  /// Check and request notification permission
  static Future<bool> requestNotificationPermission(
      BuildContext context) async {
    final status = await Permission.notification.status;

    if (status.isDenied) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        return true;
      } else if (result.isPermanentlyDenied) {
        ErrorHandler.showInfo(
          context,
          'Notification permission is permanently denied. Please enable it in app settings.',
        );
        return false;
      }
      return false;
    }

    return status.isGranted;
  }

  /// Check if notification permission is granted
  static Future<bool> isNotificationPermissionGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Open app settings for permission management
  static Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }

  /// Check all required permissions
  static Future<Map<String, bool>> checkAllPermissions() async {
    return {
      'notification': await isNotificationPermissionGranted(),
    };
  }

  /// Request all required permissions
  static Future<Map<String, bool>> requestAllPermissions(
      BuildContext context) async {
    final results = <String, bool>{};

    // Request notification permission
    results['notification'] = await requestNotificationPermission(context);

    return results;
  }
}
