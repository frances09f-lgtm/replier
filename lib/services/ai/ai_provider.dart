/// The pluggable brain. V1 ships the deterministic local provider so the
/// whole pipeline works with zero keys and zero network; real providers
/// (cloud or on-device) slot in behind this interface in later versions.
abstract class AiProvider {
  String get name;
  Future<String> generateReply({required String sender, required String text});
}

class LocalRuleProvider implements AiProvider {
  const LocalRuleProvider();

  @override
  String get name => 'local-rules (v1)';

  @override
  Future<String> generateReply(
      {required String sender, required String text}) async {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return '';
    if (t.endsWith('?')) {
      return "Good question - I'll get back to you on that in a bit.";
    }
    if (RegExp(r'\b(hi|hello|hey|namaste|hii+)\b').hasMatch(t)) {
      return 'Hey $sender! Thanks for the message - will reply properly soon.';
    }
    if (RegExp(r'\b(thanks|thank you|thx)\b').hasMatch(t)) {
      return "You're welcome!";
    }
    return 'Got it - I\'ll reply properly in a little while.';
  }
}
