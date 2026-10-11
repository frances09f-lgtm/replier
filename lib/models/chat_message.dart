import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 3)
class ChatMessage extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String role;

  @HiveField(2)
  String content;

  @HiveField(3)
  DateTime timestamp;

  @HiveField(4)
  String? model;

  @HiveField(5)
  bool isTrained;

  @HiveField(6)
  String? originalContent;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.model,
    this.isTrained = false,
    this.originalContent,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();
}
