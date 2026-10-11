/// Maps retired or invalid cloud model IDs to current replacements.
class CloudAiModel {
  CloudAiModel._();

  static const String defaultGroqModel = 'openai/gpt-oss-20b';
  static const String defaultGeminiModel = 'gemini-3.6-flash';

  static const Map<String, String> _groqReplacements = {
    'gemma2-9b-it': defaultGroqModel,
    'gemma-7b-it': defaultGroqModel,
    'llama-3.1-8b-instant': defaultGroqModel,
    'llama-3.3-70b-versatile': 'openai/gpt-oss-120b',
    'llama3-8b-8192': defaultGroqModel,
    'llama3-70b-8192': 'openai/gpt-oss-120b',
  };

  static const Map<String, String> _geminiReplacements = {
    'gemini-1.5-flash': defaultGeminiModel,
    'gemini-1.5-flash-8b': defaultGeminiModel,
    'gemini-1.5-flash-latest': defaultGeminiModel,
    'gemini-1.5-pro': defaultGeminiModel,
    'gemini-1.5-pro-latest': defaultGeminiModel,
    'gemini-2.0-flash': defaultGeminiModel,
    'gemini-2.0-flash-lite': defaultGeminiModel,
    'gemini-2.5-flash': defaultGeminiModel,
    'gemini-2.5-pro': defaultGeminiModel,
  };

  static String normalizeGroqModel(String? model) {
    final trimmed = (model ?? '').trim();
    if (trimmed.isEmpty) return defaultGroqModel;
    return _groqReplacements[trimmed] ?? trimmed;
  }

  static String normalizeGeminiModel(String? model) {
    final trimmed = (model ?? '').trim();
    if (trimmed.isEmpty) return defaultGeminiModel;
    return _geminiReplacements[trimmed] ?? trimmed;
  }
}
