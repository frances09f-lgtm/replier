import 'package:flutter_test/flutter_test.dart';
import 'package:replier/models/app_settings.dart';
import 'package:replier/utils/ai_engine_display.dart';

void main() {
  test('old settings keep providers and existing model when Cloudflare added',
      () {
    final original = AppSettings(
        lastUpdated: DateTime(2026),
        aiModelType: 'groq_api',
        groqModel: 'openai/gpt-oss-120b',
        selectedLocalModel: 'qwen_2_5_1_5b');
    final restored = AppSettings.fromJson(original.toJson());
    expect(restored.aiModelType, 'groq_api');
    expect(restored.groqModel, 'openai/gpt-oss-120b');
    expect(restored.selectedLocalModel, 'qwen_2_5_1_5b');
    expect(restored.cloudflareApiKey, '');
    expect(restored.cloudflareAccountId, '');
    expect(restored.cloudflareModel, '@cf/qwen/qwen3-30b-a3b-fp8');
  });
  test('Cloudflare configuration roundtrip, no key imported from plain backup',
      () {
    final settings = AppSettings(lastUpdated: DateTime(2026)).copyWith(
        cloudflareAccountId: 'a' * 32,
        cloudflareApiKey: 'fixture-no-real-secret',
        cloudflareModel: '@cf/openai/gpt-oss-20b');
    final imported = AppSettings.fromJson(settings.toJson());
    expect(imported.cloudflareAccountId, 'a' * 32);
    expect(imported.cloudflareModel, '@cf/openai/gpt-oss-20b');
    expect(imported.cloudflareApiKey, '');
  });
  test('Cloudflare display added without removing existing engines', () {
    expect(AiEngineDisplay.allEngineIds,
        containsAll(['groq_api', 'gemini_api', 'cloudflare_api', 'phi_local']));
    expect(AiEngineDisplay.forEngine('cloudflare_api').label, 'Cloudflare AI');
  });
}
