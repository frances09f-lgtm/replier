// GENERATED CODE - DO NOT MODIFY BY HAND
// Manually extended for feedback fields (HiveFields 8-11) with backward compat.

part of 'reply_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReplyLogAdapter extends TypeAdapter<ReplyLog> {
  @override
  final int typeId = 2;

  @override
  ReplyLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReplyLog(
      id: fields[0] as String,
      sender: fields[1] as String,
      originalMessage: fields[2] as String,
      autoReplySent: fields[3] as String,
      appName: fields[4] as String,
      dateTime: fields[5] as DateTime,
      ruleId: fields[6] as String,
      aiModel: fields[7] as String? ?? '',
      rating: (fields[8] as num?)?.toInt() ?? 0,
      feedbackNote: fields[9] as String? ?? '',
      correctedReply: fields[10] as String? ?? '',
      trained: fields[11] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, ReplyLog obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.sender)
      ..writeByte(2)
      ..write(obj.originalMessage)
      ..writeByte(3)
      ..write(obj.autoReplySent)
      ..writeByte(4)
      ..write(obj.appName)
      ..writeByte(5)
      ..write(obj.dateTime)
      ..writeByte(6)
      ..write(obj.ruleId)
      ..writeByte(7)
      ..write(obj.aiModel)
      ..writeByte(8)
      ..write(obj.rating)
      ..writeByte(9)
      ..write(obj.feedbackNote)
      ..writeByte(10)
      ..write(obj.correctedReply)
      ..writeByte(11)
      ..write(obj.trained);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplyLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
