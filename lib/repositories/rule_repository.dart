import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../core/hive_config.dart';
import '../models/app_settings.dart';
import '../models/rule.dart';
import '../utils/contact_identifier.dart';

/// Repository for managing rules
@injectable
class RuleRepository {
  final Uuid _uuid = const Uuid();

  /// Get all rules
  List<Rule> getAllRules() {
    final box = HiveConfig.getRulesBox();
    return box.values.toList();
  }

  /// Get rule by ID
  Rule? getRuleById(String id) {
    final box = HiveConfig.getRulesBox();
    return box.get(id);
  }

  /// Get enabled rules
  List<Rule> getEnabledRules() {
    final rules = getAllRules();
    return rules.where((rule) => rule.isEnabled).toList();
  }

  /// Get active rules count
  int getActiveRulesCount() {
    return getEnabledRules().length;
  }

  /// Add a new rule
  Future<void> addRule(Rule rule) async {
    final box = HiveConfig.getRulesBox();
    await box.put(rule.id, rule);
  }

  /// Update an existing rule
  Future<void> updateRule(Rule rule) async {
    final box = HiveConfig.getRulesBox();
    final updatedRule = rule.copyWith(updatedAt: DateTime.now());
    await box.put(rule.id, updatedRule);
  }

  /// Delete a rule
  Future<void> deleteRule(String id) async {
    final box = HiveConfig.getRulesBox();
    await box.delete(id);
  }

  /// Toggle rule enabled status
  Future<void> toggleRuleEnabled(String id) async {
    final rule = getRuleById(id);
    if (rule != null) {
      final updatedRule = rule.copyWith(
        isEnabled: !rule.isEnabled,
        updatedAt: DateTime.now(),
      );
      await updateRule(updatedRule);
    }
  }

  /// Search rules by trigger text, reply text, or sender name
  List<Rule> searchRules(String query) {
    final rules = getAllRules();
    if (query.isEmpty) return rules;

    final lowerQuery = query.toLowerCase();
    return rules.where((rule) {
      final matchesTriggers = rule.effectiveTriggers
          .any((t) => t.toLowerCase().contains(lowerQuery));
      final matchesSenders =
          rule.senderNames.any((s) => s.toLowerCase().contains(lowerQuery));
      final matchesReplies = rule.effectiveReplies
          .any((r) => r.toLowerCase().contains(lowerQuery));
      return matchesTriggers || matchesReplies || matchesSenders;
    }).toList();
  }

  /// Delete all default/built-in rules
  Future<void> deleteDefaultRules() async {
    final box = HiveConfig.getRulesBox();
    final defaults = box.values.where((r) => r.isDefault).toList();
    for (final rule in defaults) {
      await box.delete(rule.id);
    }
  }

  /// One-time cleanup (v1.3+): remove old generic default rules that hijack
  /// AI (ok/thanks/acha/ha ka/kon/free/online/...). Only touches isDefault
  /// rules whose triggers are in the retired blocklist. Returns count removed.
  Future<int> deleteRetiredHijackDefaults() async {
    const retired = {
      'ha ka',
      'ho ka',
      'khara ka',
      'sure ka',
      'acha',
      'ok',
      'okay',
      'k',
      'kon',
      'kon ahe',
      'kon hota',
      'thanks',
      'thank you',
      'thx',
      'free ahes',
      'online ahes',
      'reply ka nahi dila',
      'aalas ka',
      'kay zala',
      'kuthe hotas',
      'miss kelas',
    };
    final box = HiveConfig.getRulesBox();
    var removed = 0;
    for (final rule in box.values.where((r) => r.isDefault).toList()) {
      final triggers =
          rule.effectiveTriggers.map((t) => t.trim().toLowerCase()).toSet();
      // Delete if ALL triggers are retired generics (don't touch customized
      // rules that mix a retired trigger with a real one).
      if (triggers.isNotEmpty && triggers.every((t) => retired.contains(t))) {
        await box.delete(rule.id);
        removed++;
      }
    }
    return removed;
  }

  /// Check if default rules have been loaded already
  bool hasDefaultRules() {
    final box = HiveConfig.getRulesBox();
    return box.values.any((r) => r.isDefault);
  }

  /// Find matching rule for a message
  Rule? findMatchingRule(String message,
      {String? sender, AppSettings? settings}) {
    if (sender != null && settings != null) {
      if (!ContactIdentifier.isSenderAllowedForAutoReply(
        sender: sender,
        whitelistEnabled: settings.contactWhitelistEnabled,
        whitelist: settings.contactWhitelist,
        blacklist: settings.contactBlacklist,
      )) {
        return null;
      }
    }

    final enabledRules = getEnabledRules();
    for (final rule in enabledRules) {
      if (rule.matches(message, sender: sender)) {
        return rule;
      }
    }
    return null;
  }

  /// Create a new rule with default values
  Rule createRule({
    required String triggerText,
    required String replyText,
    List<String>? triggerTexts,
    List<String>? replies,
    List<String>? senderNames,
    bool exactMatch = true,
    bool containsMatch = false,
    bool caseSensitive = false,
    bool isEnabled = true,
  }) {
    return Rule(
      id: _uuid.v4(),
      triggerText: triggerText,
      triggerTexts: triggerTexts ?? [],
      replyText: replyText,
      replies: replies ?? [],
      senderNames: senderNames ?? [],
      exactMatch: exactMatch,
      containsMatch: containsMatch,
      caseSensitive: caseSensitive,
      isEnabled: isEnabled,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
