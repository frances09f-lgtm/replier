/// Normalizes contact names and phone numbers for allow/deny list matching.
class ContactIdentifier {
  static const int minPhoneDigits = 7;

  static String normalizePhoneDigits(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    if (digits.length == 11 && digits.startsWith('0')) {
      digits = '91${digits.substring(1)}';
    }

    if (digits.length == 12 && digits.startsWith('91')) {
      return digits;
    }

    if (digits.length == 10 && RegExp(r'^\d+$').hasMatch(digits)) {
      return '91$digits';
    }

    return digits;
  }

  static String normalizeIdentifier(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return '';

    final digitCount = trimmed.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digitCount >= minPhoneDigits) {
      final normalized = normalizePhoneDigits(trimmed);
      if (normalized.isNotEmpty) return normalized;
    }

    return trimmed.toLowerCase();
  }

  static bool identifiersMatch(String a, String b) {
    final na = normalizeIdentifier(a);
    final nb = normalizeIdentifier(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb;
  }

  static bool isBlacklisted(String sender, List<String> blacklist) {
    if (blacklist.isEmpty) return false;
    return blacklist.any((entry) => identifiersMatch(entry, sender));
  }

  static bool isWhitelisted(String sender, List<String> whitelist) {
    if (whitelist.isEmpty) return false;
    return whitelist.any((entry) => identifiersMatch(entry, sender));
  }

  static bool isSenderAllowedForAutoReply({
    required String sender,
    required bool whitelistEnabled,
    required List<String> whitelist,
    required List<String> blacklist,
  }) {
    if (sender.trim().isEmpty) return true;
    if (isBlacklisted(sender, blacklist)) return false;
    if (whitelistEnabled &&
        whitelist.isNotEmpty &&
        !isWhitelisted(sender, whitelist)) {
      return false;
    }
    return true;
  }
}
