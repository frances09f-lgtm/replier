import 'package:replier/utils/cloud_ai_request_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const incoming = 'Where are you?';
  const systemPrompt =
      'You are an AI assistant generating an appropriate reply to an incoming message.';
  const sender = 'Alex';

  group('Groq OpenAI-compatible payload', () {
    test('contains incoming message and system prompt', () {
      final formatted = CloudAiRequestBuilder.buildFormattedSystemPrompt(
        systemPrompt,
        sender,
      );
      final payload = CloudAiRequestBuilder.buildOpenAiCompatiblePayload(
        model: 'llama-3.1-8b-instant',
        systemPrompt: formatted,
        incomingMessage: incoming,
        senderName: sender,
      );

      expect(
        CloudAiRequestBuilder.openAiPayloadContainsMessageAndSystem(
          payload,
          formatted,
          incoming,
          sender,
        ),
        isTrue,
      );

      final messages = payload['messages'] as List<dynamic>;
      final userContent = (messages.last as Map)['content'] as String;
      expect(userContent, contains(incoming));
      expect(userContent, isNot('Thank you.'));

      final systemContent = (messages.first as Map)['content'] as String;
      expect(systemContent, contains(systemPrompt));
    });
  });

  group('Gemini payload', () {
    test('contains incoming message and system instruction', () {
      final formatted = CloudAiRequestBuilder.buildFormattedSystemPrompt(
        systemPrompt,
        sender,
      );
      final payload = CloudAiRequestBuilder.buildGeminiPayload(
        systemPrompt: formatted,
        incomingMessage: incoming,
        senderName: sender,
      );

      final contents = payload['contents'] as List<dynamic>;
      final lastUser = contents.last as Map<String, dynamic>;
      final text = ((lastUser['parts'] as List).first as Map)['text'] as String;
      expect(text, 'Alex: Where are you?');

      final sys = payload['systemInstruction'] as Map<String, dynamic>;
      final sysText = ((sys['parts'] as List).first as Map)['text'] as String;
      expect(sysText, contains(systemPrompt));
    });
  });

  group('Marathi in user message', () {
    test('Unicode preserved in OpenAI user content', () {
      const marathi = 'तू कुठे आहेस?';
      final formatted = CloudAiRequestBuilder.buildFormattedSystemPrompt(
        systemPrompt,
        sender,
      );
      final payload = CloudAiRequestBuilder.buildOpenAiCompatiblePayload(
        model: 'test',
        systemPrompt: formatted,
        incomingMessage: marathi,
        senderName: sender,
      );
      final messages = payload['messages'] as List<dynamic>;
      final userContent = (messages.last as Map)['content'] as String;
      expect(userContent, contains(marathi));
    });

    test('mixed Marathi/English preserved', () {
      const mixed = 'कुठे आहेस? I\'m waiting.';
      final payload = CloudAiRequestBuilder.buildOpenAiCompatiblePayload(
        model: 'test',
        systemPrompt: 'prompt',
        incomingMessage: mixed,
        senderName: sender,
      );
      final messages = payload['messages'] as List<dynamic>;
      final userContent = (messages.last as Map)['content'] as String;
      expect(userContent, contains(mixed));
    });
  });
}
