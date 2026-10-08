import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native pause covers capture sends and queued accessibility', () {
    const root = 'android/app/src/main/kotlin/com/replier/replier/';
    final n = File('${root}ReplierNotificationListener.kt').readAsStringSync();
    final a = File('${root}ReplierAccessibilityService.kt').readAsStringSync();
    final m = File('${root}MasterPause.kt').readAsStringSync();
    expect(n.contains('if (!MasterPause.enabled(this)) return'), true);
    expect(
      RegExp('!MasterPause.enabled\\(context\\)').allMatches(n).length,
      greaterThanOrEqualTo(4),
    );
    expect(
      a.contains('if (!MasterPause.enabled(this)) { clearQueue(); return }'),
      true,
    );
    expect(m.contains('ReplierNotificationListener.clearBuffer()'), true);
    expect(m.contains('ReplierAccessibilityService.clearQueue()'), true);
    expect(m.contains('.commit()'), true);
  });
}
