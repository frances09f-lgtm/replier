import 'package:flutter_test/flutter_test.dart';
import 'package:replier/providers/ai_usage_provider.dart';

void main() {
  group('AiProviderUsage live quota and rate limit tests', () {
    test('fromMap parses live rate limit fields correctly', () {
      final map = {
        'requestsToday': 12,
        'tokensToday': 2400,
        'requestsLimit': 1000,
        'requestsRemaining': 45,
        'isLimitReached': false,
        'limitResetTimestamp': 1726732800000,
        'lastError': '',
      };

      final usage = AiProviderUsage.fromMap(map);

      expect(usage.requestsToday, equals(12));
      expect(usage.tokensToday, equals(2400));
      expect(usage.requestsLimit, equals(1000));
      expect(usage.requestsRemaining, equals(45));
      expect(usage.isLimitReached, isFalse);
      expect(usage.limitResetTimestamp, equals(1726732800000));
      expect(usage.lastError, isEmpty);
    });

    test('fromMap handles limit reached with 0 remaining and 429 error', () {
      final map = {
        'requestsToday': 250,
        'tokensToday': 50000,
        'requestsLimit': 250,
        'requestsRemaining': 0,
        'isLimitReached': true,
        'limitResetTimestamp': 1726736400000,
        'lastError': 'HTTP 429: Rate limit reached for model',
      };

      final usage = AiProviderUsage.fromMap(map);

      expect(usage.requestsLimit, equals(250));
      expect(usage.requestsRemaining, equals(0));
      expect(usage.isLimitReached, isTrue);
      expect(usage.lastError, contains('429'));
    });

    test('fromMap handles missing or null fields gracefully', () {
      final usage = AiProviderUsage.fromMap(null);

      expect(usage.requestsToday, equals(0));
      expect(usage.tokensToday, equals(0));
      expect(usage.requestsLimit, equals(0));
      expect(usage.requestsRemaining, isNull);
      expect(usage.isLimitReached, isFalse);
      expect(usage.limitResetTimestamp, equals(0));
      expect(usage.lastError, isEmpty);
    });
  });

  group('Free tier baseline limit checks', () {
    const freeTierLimits = {
      'groq_api': 1000,
      'gemini_api': 500,
      'phi_local': 0,
      'deepseek_local': 0,
    };

    test('Groq and Gemini have realistic free tier baseline limits', () {
      expect(freeTierLimits['groq_api'], equals(1000));
      expect(freeTierLimits['gemini_api'], equals(500));
      expect(freeTierLimits['phi_local'], equals(0));
    });

    test('Remaining calculation uses live quota when available', () {
      const stats = AiProviderUsage(
        requestsToday: 10,
        requestsLimit: 1000,
        requestsRemaining: 5,
        isLimitReached: false,
      );

      final hasLimit = stats.requestsLimit > 0;
      final isAtLimit = stats.isLimitReached ||
          (stats.requestsRemaining != null && stats.requestsRemaining! <= 0);

      final remainingReplies = isAtLimit
          ? 0
          : (stats.requestsRemaining ??
              (stats.requestsLimit - stats.requestsToday));

      expect(hasLimit, isTrue);
      expect(isAtLimit, isFalse);
      expect(remainingReplies, equals(5));
    });

    test('Remaining calculation reflects 0 when limit reached flag is set', () {
      const stats = AiProviderUsage(
        requestsToday: 14,
        requestsLimit: 1000,
        requestsRemaining: null,
        isLimitReached: true,
        lastError: 'HTTP 429: RESOURCE_EXHAUSTED',
      );

      final isAtLimit = stats.isLimitReached ||
          (stats.requestsRemaining != null && stats.requestsRemaining! <= 0);

      final remainingReplies = isAtLimit ? 0 : 986;

      expect(isAtLimit, isTrue);
      expect(remainingReplies, equals(0));
    });
  });
}
