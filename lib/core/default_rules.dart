import 'package:uuid/uuid.dart';
import '../models/rule.dart';

const _uuid = Uuid();
String _id() => _uuid.v4();

/// Helper: creates a default rule with multiple triggers and replies.
Rule _rule({
  required List<String> triggers,
  required List<String> replies,
}) {
  final now = DateTime.now();
  return Rule(
    id: _id(),
    triggerText: triggers.first,
    triggerTexts: triggers,
    replyText: replies.first,
    replies: replies,
    exactMatch: true,
    containsMatch: false,
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );
}

/// All built-in default rules.
/// Loaded on first launch. Users can delete any or all of them.
final List<Rule> defaultRules = [
  // ── Greetings ──────────────────────────────────────────────────────────
  _rule(triggers: ['hi'], replies: ['Hi']),
  _rule(triggers: ['hii'], replies: ['Hi']),
  _rule(triggers: ['hello'], replies: ['Hey']),
  _rule(triggers: ['hey'], replies: ['Hi']),
  _rule(triggers: ['yo'], replies: ['Ky re']),
  _rule(triggers: ['sup'], replies: ['Ky nahi']),
  _rule(triggers: ['gm'], replies: ['Morning']),
  _rule(triggers: ['good morning'], replies: ['Morning']),
  _rule(triggers: ['gn'], replies: ['By']),

  // ── Small Talk ─────────────────────────────────────────────────────────
  _rule(triggers: ['kay challay', 'ky challay'], replies: ['Ky nahi']),
  _rule(triggers: ['kay chalay', 'ky chalay'], replies: ['Asach']),
  _rule(
      triggers: ['ani ky', 'ky mg', 'kai mg', 'kay mg'], replies: ['Ky nahi']),
  _rule(triggers: ['kai nahi', 'ky nahi'], replies: ['Hmm']),
  _rule(triggers: ['kay mhntos', 'ky mhntos'], replies: ['Ky nahi']),
  _rule(triggers: ['kai chalu'], replies: ['Asach']),

  // ── Work ───────────────────────────────────────────────────────────────
  _rule(triggers: ['busy ahes'], replies: ['Kam ahe']),
  _rule(triggers: ['busy ka'], replies: ['Ho']),
  _rule(triggers: ['kam ahe ka'], replies: ['Ho']),
  _rule(triggers: ['ky kartos'], replies: ['Kam ahe']),
  _rule(triggers: ['office madhe ahes ka'], replies: ['Ho']),

  // ── Sleep ──────────────────────────────────────────────────────────────
  _rule(triggers: ['zopla ka'], replies: ['Nahi']),
  _rule(triggers: ['zoplas'], replies: ['Nahi']),
  _rule(triggers: ['zopto ka'], replies: ['Ata']),
  _rule(triggers: ['zop'], replies: ['Zopto']),

  // ── Time ───────────────────────────────────────────────────────────────
  _rule(triggers: ['kava yenar'], replies: ['Thodya velat']),
  _rule(triggers: ['kitila yenar'], replies: ['Bgu']),
  _rule(triggers: ['kiti vajta'], replies: ['Bagu']),
  _rule(triggers: ['kava'], replies: ['Nantar']),

  // ── Calls ──────────────────────────────────────────────────────────────
  _rule(
    triggers: ['call kar', 'phone kar', 'call me', 'call kr', 'ring kar'],
    replies: ['Ok'],
  ),

  // ── Teasing ────────────────────────────────────────────────────────────
  _rule(triggers: ['kutrya', 'kutryaaa'], replies: ['🤣']),
  _rule(triggers: ['lavdya'], replies: ['🤣']),
  _rule(triggers: ['chutiya'], replies: ['Tu']),
  _rule(triggers: ['bhadvya'], replies: ['🤣']),

  // ── Bye ────────────────────────────────────────────────────────────────
  _rule(triggers: ['bye', 'by'], replies: ['By']),
  _rule(triggers: ['nighato', 'chalto'], replies: ['By']),
  _rule(triggers: ['tc', 'take care'], replies: ['Tu pn']),

  // NOTE: Generic small-talk (ok/okay/k, thanks, acha, ha ka/ho ka,
  // kon, free/online/...) intentionally NOT included as default rules —
  // Groq AI handles those with context so replies sound natural
  // instead of canned. Existing users keep their old rules; new installs
  // get only the style-defining rules above.
];
