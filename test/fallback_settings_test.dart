import 'package:replier/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fallback to Local Model Settings', () {
    test('defaults fallbackToLocalModel to true', () {
      final settings = AppSettings(lastUpdated: DateTime.now());
      expect(settings.fallbackToLocalModel, isTrue);
    });

    test('toJson and fromJson preserve fallbackToLocalModel', () {
      final settings = AppSettings(
        lastUpdated: DateTime.now(),
        fallbackToLocalModel: true,
      );
      final json = settings.toJson();
      expect(json['fallbackToLocalModel'], isTrue);

      final reconstructed = AppSettings.fromJson(json);
      expect(reconstructed.fallbackToLocalModel, isTrue);

      final disabledJson = Map<String, dynamic>.from(json);
      disabledJson['fallbackToLocalModel'] = false;
      final disabledReconstructed = AppSettings.fromJson(disabledJson);
      expect(disabledReconstructed.fallbackToLocalModel, isFalse);
    });

    test('copyWith updates fallbackToLocalModel', () {
      final settings = AppSettings(lastUpdated: DateTime.now());
      final disabled = settings.copyWith(fallbackToLocalModel: false);
      expect(disabled.fallbackToLocalModel, isFalse);

      final reEnabled = disabled.copyWith(fallbackToLocalModel: true);
      expect(reEnabled.fallbackToLocalModel, isTrue);
    });

    test('selectedLocalModel preserves qwen_2_5_1_5b across serialization', () {
      final qwenSettings = AppSettings(
        lastUpdated: DateTime.now(),
        selectedLocalModel: 'qwen_2_5_1_5b',
      );
      final qwenJson = qwenSettings.toJson();
      expect(qwenJson['selectedLocalModel'], 'qwen_2_5_1_5b');
      expect(
          AppSettings.fromJson(qwenJson).selectedLocalModel, 'qwen_2_5_1_5b');
    });
  });
}
