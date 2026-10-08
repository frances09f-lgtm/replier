import 'dart:async';

import 'package:flutter/services.dart';

/// Talks to the Kotlin side: notification events stream in, reply and
/// permission actions go out. Events posted while the engine was dead are
/// buffered natively and drained on resume - nothing is lost silently.
class ReplierBridge {
  static const _control = MethodChannel('replier/control');
  static const _events = EventChannel('replier/events');

  Future<bool> masterEnabled() async {
    try {
      return await _control.invokeMethod<bool>('masterEnabled') ?? false;
    } on MissingPluginException {
      return true;
    }
  }

  Future<void> setMasterEnabled(bool enabled) =>
      _control.invokeMethod<void>('setMasterEnabled', {'enabled': enabled});

  Future<Map<String, dynamic>> resources() async {
    final raw = await _control.invokeMethod<Map>('resources');
    if (raw == null) throw StateError('Could not read phone resources');
    return Map<String, dynamic>.from(raw);
  }

  Stream<Map<String, dynamic>> events() => _events.receiveBroadcastStream().map(
    (e) => Map<String, dynamic>.from(e as Map),
  );

  /// Events buffered natively while no engine was listening.
  Future<List<Map<String, dynamic>>> drainPending() async {
    try {
      final raw = await _control.invokeListMethod<dynamic>('drainEvents');
      if (raw == null) return const [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException {
      return const [];
    }
  }

  Future<Map<String, bool>> legacyStatus() async {
    try {
      final raw = await _control.invokeMethod<Map>('legacyStatus');
      return {
        'installed': raw?['installed'] == true,
        'notification': raw?['notification'] == true,
        'accessibility': raw?['accessibility'] == true,
      };
    } on PlatformException {
      return {};
    } on MissingPluginException {
      return {};
    }
  }

  /// {notification: bool, accessibility: bool}
  Future<Map<String, bool>> permissionStatus() async {
    try {
      final raw = await _control.invokeMethod<Map>('permissionStatus');
      if (raw == null) return {'notification': false, 'accessibility': false};
      return {
        'notification': raw['notification'] == true,
        'accessibility': raw['accessibility'] == true,
      };
    } on PlatformException {
      return {'notification': false, 'accessibility': false};
    }
  }

  Future<void> openNotificationAccessSettings() =>
      _control.invokeMethod<void>('openNotificationAccessSettings');

  Future<void> openAccessibilitySettings() =>
      _control.invokeMethod<void>('openAccessibilitySettings');

  /// Replier's own App info page - where Android 13+ hides the
  /// "Allow restricted settings" fix for sideloaded apps.
  Future<void> openAppSettings() =>
      _control.invokeMethod<void>('openAppSettings');

  /// Inline reply through the notification's own reply action.
  /// Returns submitted | no_inline | gone | error.
  Future<String> sendReply(String notifKey, String text) async {
    try {
      return await _control.invokeMethod<String>('sendReply', {
            'key': notifKey,
            'text': text,
          }) ??
          'error';
    } on PlatformException {
      return 'error';
    }
  }

  /// Opens the chat and asks the accessibility service to type + send.
  /// Returns opened | gone | no_accessibility | error. 'opened' is
  /// best-effort only. There is no delivery receipt for this path.
  Future<String> openAndSend(String notifKey, String text) async {
    try {
      return await _control.invokeMethod<String>('openAndSend', {
            'key': notifKey,
            'text': text,
          }) ??
          'error';
    } on PlatformException {
      return 'error';
    }
  }
}
