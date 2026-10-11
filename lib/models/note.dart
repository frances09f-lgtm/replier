import 'package:hive/hive.dart';

/// Model representing a note/reminder/meeting captured automatically from messages or created manually.
@HiveType(typeId: 4)
class Note extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String content;

  @HiveField(3)
  String sender;

  @HiveField(4)
  String appName;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  DateTime? eventTime;

  @HiveField(7)
  bool isCompleted;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.sender = '',
    this.appName = '',
    required this.createdAt,
    this.eventTime,
    this.isCompleted = false,
  });

  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? sender,
    String? appName,
    DateTime? createdAt,
    DateTime? eventTime,
    bool? isCompleted,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      sender: sender ?? this.sender,
      appName: appName ?? this.appName,
      createdAt: createdAt ?? this.createdAt,
      eventTime: eventTime ?? this.eventTime,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'sender': sender,
      'appName': appName,
      'createdAt': createdAt.toIso8601String(),
      'eventTime': eventTime?.toIso8601String(),
      'isCompleted': isCompleted,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      sender: json['sender'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      eventTime: json['eventTime'] != null
          ? DateTime.parse(json['eventTime'] as String)
          : null,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }
}

/// Hive TypeAdapter for Note (typeId: 4)
class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 4;

  @override
  Note read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Note(
      id: fields[0] as String,
      title: fields[1] as String,
      content: fields[2] as String,
      sender: fields[3] as String? ?? '',
      appName: fields[4] as String? ?? '',
      createdAt: fields[5] as DateTime,
      eventTime: fields[6] as DateTime?,
      isCompleted: fields[7] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Note obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.sender)
      ..writeByte(4)
      ..write(obj.appName)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.eventTime)
      ..writeByte(7)
      ..write(obj.isCompleted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
