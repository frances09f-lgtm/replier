import 'package:hive/hive.dart';

part 'reply_log.g.dart';

/// Model for reply logs
/// Stores history of all auto-replies sent
@HiveType(typeId: 2)
class ReplyLog extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String sender;

  @HiveField(2)
  String originalMessage;

  @HiveField(3)
  String autoReplySent;

  @HiveField(4)
  String appName;

  @HiveField(5)
  DateTime dateTime;

  @HiveField(6)
  String ruleId;

  @HiveField(7)
  String aiModel;

  /// User feedback: 1 = good (thumbs up), -1 = bad (thumbs down), 0 = unrated.
  @HiveField(8)
  int rating;

  /// Optional note describing what was wrong (e.g. "too formal").
  @HiveField(9)
  String feedbackNote;

  /// Corrected reply the user taught ("should be: ...").
  @HiveField(10)
  String correctedReply;

  /// Whether this log has already contributed a training example.
  @HiveField(11)
  bool trained;

  /// Why the reply failed, for entries that record a failed attempt instead
  /// of a sent reply. Empty for normal (sent) logs. Stores only the native
  /// failure reason - never message content, keys, or tokens.
  @HiveField(12)
  String failureReason;

  ReplyLog({
    required this.id,
    required this.sender,
    required this.originalMessage,
    required this.autoReplySent,
    required this.appName,
    required this.dateTime,
    required this.ruleId,
    this.aiModel = '',
    this.rating = 0,
    this.feedbackNote = '',
    this.correctedReply = '',
    this.trained = false,
    this.failureReason = '',
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'originalMessage': originalMessage,
      'autoReplySent': autoReplySent,
      'appName': appName,
      'dateTime': dateTime.toIso8601String(),
      'ruleId': ruleId,
      'aiModel': aiModel,
      'rating': rating,
      'feedbackNote': feedbackNote,
      'correctedReply': correctedReply,
      'trained': trained,
      'failureReason': failureReason,
    };
  }

  /// Create from JSON
  factory ReplyLog.fromJson(Map<String, dynamic> json) {
    return ReplyLog(
      id: json['id'],
      sender: json['sender'],
      originalMessage: json['originalMessage'],
      autoReplySent: json['autoReplySent'],
      appName: json['appName'],
      dateTime: DateTime.parse(json['dateTime']),
      ruleId: json['ruleId'],
      aiModel: json['aiModel'] ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      feedbackNote: json['feedbackNote'] ?? '',
      correctedReply: json['correctedReply'] ?? '',
      trained: json['trained'] ?? false,
      failureReason: json['failureReason'] ?? '',
    );
  }

  /// Create a copy with updated fields
  ReplyLog copyWith({
    String? id,
    String? sender,
    String? originalMessage,
    String? autoReplySent,
    String? appName,
    DateTime? dateTime,
    String? ruleId,
    String? aiModel,
    int? rating,
    String? feedbackNote,
    String? correctedReply,
    bool? trained,
    String? failureReason,
  }) {
    return ReplyLog(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      originalMessage: originalMessage ?? this.originalMessage,
      autoReplySent: autoReplySent ?? this.autoReplySent,
      appName: appName ?? this.appName,
      dateTime: dateTime ?? this.dateTime,
      ruleId: ruleId ?? this.ruleId,
      aiModel: aiModel ?? this.aiModel,
      rating: rating ?? this.rating,
      feedbackNote: feedbackNote ?? this.feedbackNote,
      correctedReply: correctedReply ?? this.correctedReply,
      trained: trained ?? this.trained,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}
