import 'package:flutter_test/flutter_test.dart';

/// Documents expected Unicode handling for local Llama prompts (mirrors native batch join).
void main() {
  group('Local AI message batch Unicode', () {
    test('Marathi input unchanged when joined', () {
      const marathi = 'तू कुठे आहेस?';
      final batch = [marathi];
      final combined = batch.join('\n');
      expect(combined, marathi);
      expect(combined.runes.length, greaterThan(marathi.length ~/ 2));
    });

    test('काय करत आहेस? survives pipeline string ops', () {
      const msg = 'काय करत आहेस?';
      expect(msg.trim(), msg);
      expect(msg.toLowerCase(), msg);
    });

    test('mixed message preserved', () {
      const mixed = 'कुठे आहेस? I\'m waiting.';
      expect(mixed.contains('कुठे'), isTrue);
      expect(mixed.contains("I'm waiting."), isTrue);
    });
  });
}
