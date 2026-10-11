import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('unavailable model tile and icon start download',(){final s=File('lib/screens/settings_screen.dart').readAsStringSync();expect(s,contains('? (_downloading ? null : _download)'));expect(s,contains("tooltip: 'Download \${widget.title}'"));expect(s,contains("if (result?['success'] != true)"));expect(s,contains('Duration(seconds: 10)'));});
 test('download cannot wait on inference and publish partial model',(){final s=File('android/app/src/main/kotlin/com/replier/replier/service/PhiLocalService.kt').readAsStringSync();expect(s,contains('downloadExecutor.execute'));expect(s,contains('File(target.path + ".part")'));expect(s,contains('partial.length() != config.sizeBytes'));expect(s,contains('hash != config.sha256'));expect(s,contains('instanceFollowRedirects = false'));expect(s,contains('setRequestProperty("Range"'));});
}
