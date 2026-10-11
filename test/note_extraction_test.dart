import 'package:flutter_test/flutter_test.dart';
import 'package:replier/services/note_extraction_service.dart';

void main() {
  late NoteExtractionService service;

  setUp(() {
    service = NoteExtractionService();
  });

  group('NoteExtractionService', () {
    test('detects meeting message with typo "tommorow"', () {
      const message = 'we will conduct a meeting tommorow at 9 am';
      expect(service.isActionableMessage(message), isTrue);

      final title = service.extractTitle(message);
      expect(title.toLowerCase(), contains('meeting'));
      expect(title.toLowerCase(), contains('tomorrow'));
      expect(title.toLowerCase(), contains('9 am'));
    });

    test('detects call and appointment messages', () {
      const callMessage = "Let's have a call today at 3pm";
      expect(service.isActionableMessage(callMessage), isTrue);
      final callTitle = service.extractTitle(callMessage);
      expect(callTitle.toLowerCase(), contains('call'));
      expect(callTitle.toLowerCase(), contains('today'));

      const apptMessage = "Doctor appointment tomorrow at 10:30 am";
      expect(service.isActionableMessage(apptMessage), isTrue);
      final apptTitle = service.extractTitle(apptMessage);
      expect(apptTitle.toLowerCase(), contains('appointment'));
    });

    test('detects reminder messages', () {
      const reminder = 'reminder: submit the presentation by 5pm tomorrow';
      expect(service.isActionableMessage(reminder), isTrue);
      final title = service.extractTitle(reminder);
      expect(title.toLowerCase(), contains('reminder'));
    });

    test('parses relative event dates and times', () {
      const message = 'we will conduct a meeting tommorow at 9 am';
      final parsedDate = service.parseEventDateTime(message);
      expect(parsedDate, isNotNull);
      expect(parsedDate!.hour, 9);
      expect(parsedDate.minute, 0);

      final now = DateTime.now();
      final expectedTomorrow = now.add(const Duration(days: 1));
      expect(parsedDate.year, expectedTomorrow.year);
      expect(parsedDate.month, expectedTomorrow.month);
      expect(parsedDate.day, expectedTomorrow.day);
    });

    test('ignores non-actionable casual conversations', () {
      expect(service.isActionableMessage('Hello, how are you doing?'), isFalse);
      expect(service.isActionableMessage('okay thanks!'), isFalse);
      expect(service.isActionableMessage('see you later'), isFalse);
      expect(service.isActionableMessage('sounds good'), isFalse);
    });
  });
}
