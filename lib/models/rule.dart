import 'package:hive/hive.dart';

part 'rule.g.dart';

/// Model for auto-reply rules
/// Each rule defines when and how to automatically reply to messages
@HiveType(typeId: 51)
class Rule extends HiveObject {
  @HiveField(0)
  String id;

  /// Legacy single trigger — kept for Hive backward compatibility.
  /// Use [triggerTexts] for all new logic.
  @HiveField(1)
  String triggerText;

  @HiveField(2)
  String replyText;

  @HiveField(3)
  bool exactMatch;

  @HiveField(4)
  bool containsMatch;

  @HiveField(5)
  bool caseSensitive;

  @HiveField(6)
  bool isEnabled;

  @HiveField(7)
  DateTime createdAt;

  @HiveField(8)
  DateTime updatedAt;

  /// Multiple trigger texts — the rule fires if ANY of these match.
  /// Falls back to [triggerText] when this list is empty (migration path).
  @HiveField(9)
  List<String> triggerTexts;

  /// Multiple reply texts — one is randomly selected when the rule fires.
  /// Falls back to [replyText] when this list is empty (migration path).
  @HiveField(10)
  List<String> replies;

  /// Specific sender names this rule applies to.
  /// When empty, the rule matches messages from any sender.
  /// When populated, the rule only fires for messages from these senders.
  @HiveField(11)
  List<String> senderNames;

  /// Whether this rule is a default/built-in rule.
  /// Default rules can be batch-removed by the user.
  @HiveField(12)
  bool isDefault;

  Rule({
    required this.id,
    required this.triggerText,
    required this.replyText,
    this.exactMatch = true,
    this.containsMatch = false,
    this.caseSensitive = false,
    this.isEnabled = true,
    required this.createdAt,
    required this.updatedAt,
    List<String>? triggerTexts,
    List<String>? replies,
    List<String>? senderNames,
    this.isDefault = false,
  })  : triggerTexts = triggerTexts ?? [],
        replies = replies ?? [],
        senderNames = senderNames ?? [];

  /// All active trigger texts: uses [triggerTexts] when populated,
  /// otherwise falls back to the legacy [triggerText].
  List<String> get effectiveTriggers =>
      triggerTexts.isNotEmpty ? triggerTexts : [triggerText];

  /// All active reply texts: uses [replies] when populated,
  /// otherwise falls back to the legacy [replyText].
  List<String> get effectiveReplies =>
      replies.isNotEmpty ? replies : [replyText];

  /// Normalize a message: trim, remove trailing punctuation, lowercase.
  /// This ensures a single rule matches variations like "Kay challay?", "KAY CHALLAY!!", etc.
  static String normalizeMessage(String text) {
    var result = text.trim();
    // Remove trailing punctuation: ? ! . , ; : ) ] }
    result = result.replaceAll(RegExp(r'[?!,;:\)\]\}]+$'), '');
    result = result.trim().toLowerCase();
    return result;
  }

  /// Check if a message matches this rule, optionally filtering by sender.
  /// If [senderNames] is non-empty, the sender must be in the list.
  /// Messages are normalized (trimmed, punctuation stripped, lowered) before matching.
  bool matches(String message, {String? sender}) {
    if (!isEnabled) return false;

    // Sender filter: if senderNames is set, sender must be in the list
    if (senderNames.isNotEmpty && sender != null) {
      final matched = senderNames.any(
        (name) => name.toLowerCase() == sender.toLowerCase(),
      );
      if (!matched) return false;
    } else if (senderNames.isNotEmpty && sender == null) {
      // senderNames is set but no sender info available — skip
      return false;
    }

    final msg = caseSensitive ? message : normalizeMessage(message);
    return effectiveTriggers.any((t) {
      final trigger = caseSensitive ? t : normalizeMessage(t);
      if (exactMatch) return msg == trigger;
      if (containsMatch) return msg.contains(trigger);
      return false;
    });
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'triggerText': triggerText,
      'triggerTexts': triggerTexts,
      'replyText': replyText,
      'replies': replies,
      'senderNames': senderNames,
      'exactMatch': exactMatch,
      'containsMatch': containsMatch,
      'caseSensitive': caseSensitive,
      'isEnabled': isEnabled,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory Rule.fromJson(Map<String, dynamic> json) {
    final rawTriggers = json['triggerTexts'];
    final List<String> triggers = rawTriggers is List
        ? rawTriggers.map((e) => e.toString()).toList()
        : <String>[];
    final rawReplies = json['replies'];
    final List<String> replyList = rawReplies is List
        ? rawReplies.map((e) => e.toString()).toList()
        : <String>[];
    final rawSenders = json['senderNames'];
    final List<String> senderList = rawSenders is List
        ? rawSenders.map((e) => e.toString()).toList()
        : <String>[];
    return Rule(
      id: json['id'],
      triggerText: json['triggerText'] ?? '',
      replyText: json['replyText'] ?? '',
      replies: replyList,
      senderNames: senderList,
      exactMatch: json['exactMatch'] ?? true,
      containsMatch: json['containsMatch'] ?? false,
      caseSensitive: json['caseSensitive'] ?? false,
      isEnabled: json['isEnabled'] ?? true,
      isDefault: json['isDefault'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      triggerTexts: triggers,
    );
  }

  /// Create a copy with updated fields
  Rule copyWith({
    String? id,
    String? triggerText,
    List<String>? triggerTexts,
    String? replyText,
    List<String>? replies,
    List<String>? senderNames,
    bool? exactMatch,
    bool? containsMatch,
    bool? caseSensitive,
    bool? isEnabled,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Rule(
      id: id ?? this.id,
      triggerText: triggerText ?? this.triggerText,
      triggerTexts: triggerTexts ?? List.from(this.triggerTexts),
      replyText: replyText ?? this.replyText,
      replies: replies ?? List.from(this.replies),
      senderNames: senderNames ?? List.from(this.senderNames),
      exactMatch: exactMatch ?? this.exactMatch,
      containsMatch: containsMatch ?? this.containsMatch,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      isEnabled: isEnabled ?? this.isEnabled,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
