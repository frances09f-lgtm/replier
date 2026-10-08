import 'dart:async';
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import '../ai/ai_provider.dart';
import '../ai/groq_provider.dart';
import 'model_catalog.dart';

/// Injection boundary keeps provider safety tests independent of native FFI.
abstract class LocalRunner {
  Future<String> draft(String path, List<Map<String, String>> messages);
  Future<void> cancel();
}

class LlamaRunner implements LocalRunner {
  LlamaEngine? _engine;
  StreamSubscription<GenerationEvent>? _tokens;
  Completer<String>? _result;
  int _epoch = 0;
  @override
  Future<String> draft(String path, List<Map<String, String>> messages) async {
    final epoch = ++_epoch;
    final engine = await LlamaEngine.spawn(
      modelParams: ModelParams(path: path, gpuLayers: 0),
      contextParams: const ContextParams(
        nCtx: 2048,
        nBatch: 128,
        nThreads: 4,
        nThreadsBatch: 4,
      ),
    );
    if (epoch != _epoch) {
      await engine.dispose();
      throw const ReplyGenerationException(
        'Local draft cancelled. Nothing sent.',
      );
    }
    _engine = engine;
    EngineChat? chat;
    try {
      chat = await engine.createChat();
      if (epoch != _epoch)
        throw const ReplyGenerationException(
          'Local draft cancelled. Nothing sent.',
        );
      for (final m in messages) {
        switch (m['role']) {
          case 'system':
            chat.addSystem('${m['content']} /no_think');
            break;
          case 'assistant':
            chat.addAssistant(m['content']!);
            break;
          default:
            chat.addUser(m['content']!);
        }
      }
      final output = StringBuffer();
      final result = _result = Completer<String>();
      _tokens = chat
          .generate(maxTokens: 256)
          .listen(
            (event) {
              if (event is TokenEvent) output.write(event.text);
              if (event is DoneEvent) {
                output.write(event.trailingText);
                if (!result.isCompleted) result.complete(output.toString());
              }
            },
            onError: (Object error) {
              if (!result.isCompleted) result.completeError(error);
            },
            onDone: () {
              if (!result.isCompleted)
                result.completeError(
                  const ReplyGenerationException(
                    'Local model stopped without a complete draft. Tap Retry or Edit.',
                  ),
                );
            },
          );
      return await result.future.timeout(const Duration(seconds: 90));
    } finally {
      await _tokens?.cancel();
      _tokens = null;
      _result = null;
      await chat?.dispose();
      await engine.dispose();
      if (identical(_engine, engine)) _engine = null;
    }
  }

  @override
  Future<void> cancel() async {
    _epoch++;
    final result = _result;
    if (result != null && !result.isCompleted)
      result.completeError(
        const ReplyGenerationException('Local draft cancelled. Nothing sent.'),
      );
    await _tokens?.cancel();
    // draft's finally owns orderly session and model unloading.
  }
}

class LocalModelProvider implements AiProvider {
  LocalModelProvider({
    required this.model,
    required this.file,
    LocalRunner? runner,
  }) : runner = runner ?? LlamaRunner();
  final LocalModelSpec model;
  final File file;
  final LocalRunner runner;
  bool _busy = false;
  @override
  String get name => 'Local · ${model.label} (phone test)';
  @override
  Future<String> generateReply({
    required String sender,
    required String text,
    List<Map<String, String>> history = const [],
  }) async {
    if (_busy)
      throw const ReplyGenerationException(
        'A local draft is already running. Try again after it finishes.',
      );
    _busy = true;
    try {
      if (!await file.exists() || await file.length() != model.bytes)
        throw const ReplyGenerationException(
          'Download and verify this model in Settings first.',
        );
      final messages = GroqProvider.messages(sender, text, history);
      // No silent cross-provider fallback and no cross-chat reusable session.
      if (messages.fold<int>(0, (n, m) => n + (m['content']?.length ?? 0)) >
          2800)
        throw const ReplyGenerationException(
          'Chat context too long for the local test model. Tap Edit.',
        );
      return GroqProvider.parseDraft(await runner.draft(file.path, messages));
    } on ReplyGenerationException {
      rethrow;
    } catch (_) {
      throw const ReplyGenerationException(
        'Local model could not finish. It may need more free memory or be unsupported. Tap Retry or Edit. No cloud fallback.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> cancel() => runner.cancel();
}
