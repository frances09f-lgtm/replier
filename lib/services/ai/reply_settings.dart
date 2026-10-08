import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ReplySettings {
  static const storage = FlutterSecureStorage();
  String key = '';
  String model = 'qwen/qwen3.8-27b';
  bool enabled = false;
  static const models = ['qwen/qwen3.8-27b', 'openai/gpt-oss-120b'];
  Future<void> load() async {
    key = await storage.read(key: 'groq_key') ?? '';
    final saved = await storage.read(key: 'groq_model');
    if (models.contains(saved)) model = saved!;
    enabled = await storage.read(key: 'groq_enabled') == 'true';
  }

  Future<void> save(String newKey, String newModel, bool consent) async {
    if (!models.contains(newModel)) throw ArgumentError('Unknown model');
    await storage.write(key: 'groq_key', value: newKey.trim());
    await storage.write(key: 'groq_model', value: newModel);
    await storage.write(key: 'groq_enabled', value: consent.toString());
    key = newKey.trim();
    model = newModel;
    enabled = consent;
  }
}
