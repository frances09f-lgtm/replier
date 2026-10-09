import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ReplySettings {
  static const storage = FlutterSecureStorage();
  String key = '';
  String model = 'qwen/qwen3.8-27b';
  bool enabled = false;
  String mode = 'off';
  String localModel = 'qwen35_2b';
  static const models = ['qwen/qwen3.8-27b', 'openai/gpt-oss-120b'];
  Future<void> load() async {
    key = await storage.read(key: 'groq_key') ?? '';
    final saved = await storage.read(key: 'groq_model');
    if (models.contains(saved)) model = saved!;
    enabled = await storage.read(key: 'groq_enabled') == 'true';
    final selected = await storage.read(key: 'provider_mode');
    mode = ['off', 'groq', 'local'].contains(selected)
        ? selected!
        : (enabled ? 'groq' : 'off');
    final local = await storage.read(key: 'local_model');
    if (['qwen3_06b', 'qwen35_2b', 'qwen3_17b'].contains(local))
      localModel = local!;
  }

  Future<void> save(String newKey, String newModel, bool consent) async {
    if (!models.contains(newModel)) throw ArgumentError('Unknown model');
    await storage.write(key: 'groq_key', value: newKey.trim());
    await storage.write(key: 'groq_model', value: newModel);
    await storage.write(key: 'groq_enabled', value: consent.toString());
    key = newKey.trim();
    model = newModel;
    enabled = consent;
    mode = consent ? 'groq' : 'off';
    await storage.write(key: 'provider_mode', value: mode);
  }

  Future<void> saveLocal(String model) async {
    if (!['qwen3_06b', 'qwen35_2b', 'qwen3_17b'].contains(model))
      throw ArgumentError('Unknown local model');
    await storage.write(key: 'local_model', value: model);
    await storage.write(key: 'provider_mode', value: 'local');
    localModel = model;
    mode = 'local';
  }

  Future<void> off() async {
    await storage.write(key: 'provider_mode', value: 'off');
    mode = 'off';
  }
}
