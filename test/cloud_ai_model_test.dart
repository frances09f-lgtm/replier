import 'package:replier/utils/cloud_ai_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudAiModel', () {
    test('normalizeGroqModel maps retired gemma2', () {
      expect(
        CloudAiModel.normalizeGroqModel('gemma2-9b-it'),
        CloudAiModel.defaultGroqModel,
      );
    });

    test('normalizeGeminiModel maps retired gemini-2.0-flash', () {
      expect(
        CloudAiModel.normalizeGeminiModel('gemini-2.0-flash'),
        CloudAiModel.defaultGeminiModel,
      );
    });
  });
}
