import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/core/constants.dart';
import 'package:replier/providers/settings_provider.dart';
import 'package:replier/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel(AppConstants.nativeChannel);
  const notification = MethodChannel(AppConstants.notificationChannel);
  const permission = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final nativeCalls = <String>[];
  final replyCalls = <MethodCall>[];

  setUp(() {
    nativeCalls.clear();
    replyCalls.clear();
    messenger.setMockMethodCallHandler(native, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'isNotificationListenerEnabled' ||
          call.method == 'isBatteryOptimizationDisabled') {
        return true;
      }
      throw MissingPluginException('Unexpected native call: ${call.method}');
    });
    messenger.setMockMethodCallHandler(permission, (call) async => 1);
    messenger.setMockMethodCallHandler(notification, (call) async {
      replyCalls.add(call);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(permission, null);
    messenger.setMockMethodCallHandler(notification, null);
  });

  test('permission refresh checks supported permissions, not Accessibility',
      () async {
    final notifier = PermissionStatusNotifier(NotificationService());
    // Allow the constructor's async permission refresh to finish first.
    await Future<void>.delayed(Duration.zero);
    await notifier.refreshPermissions();
    expect(notifier.state, {
      'notificationListener': true,
      'batteryOptimization': true,
      'postNotification': true,
    });
    expect(nativeCalls.toSet(), {
      'isNotificationListenerEnabled',
      'isBatteryOptimizationDisabled',
    });
    notifier.dispose();
  });

  test('notification reply keeps the exact original notification key',
      () async {
    await NotificationService()
        .sendReply('synthetic-original-key', 'test reply');
    expect(replyCalls, hasLength(1));
    expect(replyCalls.single.method, 'sendReply');
    expect(replyCalls.single.arguments, {
      'key': 'synthetic-original-key',
      'replyText': 'test reply',
    });
    expect(nativeCalls, isEmpty);
  });

  test('failed notification reply raises failure without native fallback',
      () async {
    messenger.setMockMethodCallHandler(notification, (call) async {
      replyCalls.add(call);
      throw PlatformException(code: 'NO_INLINE_REPLY');
    });
    await expectLater(
      NotificationService().sendReply('synthetic-original-key', 'test reply'),
      throwsA(isA<Exception>()),
    );
    expect(replyCalls, hasLength(1));
    expect(nativeCalls, isEmpty);
  });
}
