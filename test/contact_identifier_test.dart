import 'package:replier/utils/contact_identifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePhoneDigits', () {
    test('Indian +91 formats normalize to same digits', () {
      const a = '+91 98765 43210';
      const b = '919876543210';
      const c = '9876543210';
      expect(ContactIdentifier.normalizePhoneDigits(a), '919876543210');
      expect(ContactIdentifier.normalizePhoneDigits(b), '919876543210');
      expect(ContactIdentifier.normalizePhoneDigits(c), '919876543210');
    });

    test('spaces and plus signs are ignored', () {
      expect(
        ContactIdentifier.normalizePhoneDigits('+91 98765 43210'),
        ContactIdentifier.normalizePhoneDigits('91 9876543210'),
      );
    });
  });

  group('isSenderAllowedForAutoReply', () {
    test('blocked contact is not allowed', () {
      expect(
        ContactIdentifier.isSenderAllowedForAutoReply(
          sender: '+91 9876543210',
          whitelistEnabled: false,
          whitelist: const [],
          blacklist: const ['9876543210'],
        ),
        isFalse,
      );
    });

    test('allowed contact passes whitelist', () {
      expect(
        ContactIdentifier.isSenderAllowedForAutoReply(
          sender: '919876543210',
          whitelistEnabled: true,
          whitelist: const ['+91 98765 43210'],
          blacklist: const [],
        ),
        isTrue,
      );
    });

    test('unknown contact blocked when whitelist enabled', () {
      expect(
        ContactIdentifier.isSenderAllowedForAutoReply(
          sender: 'Rahul',
          whitelistEnabled: true,
          whitelist: const ['Priya'],
          blacklist: const [],
        ),
        isFalse,
      );
    });

    test('filtering disabled allows unknown contact', () {
      expect(
        ContactIdentifier.isSenderAllowedForAutoReply(
          sender: 'Rahul',
          whitelistEnabled: false,
          whitelist: const ['Priya'],
          blacklist: const [],
        ),
        isTrue,
      );
    });
  });

  group('Marathi Unicode', () {
    test('normalizeIdentifier preserves Marathi name text', () {
      const marathi = 'तू कुठे आहेस?';
      expect(ContactIdentifier.normalizeIdentifier(marathi),
          marathi.toLowerCase());
    });
  });
}
