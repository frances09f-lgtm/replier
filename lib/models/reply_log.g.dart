// GENERATED CODE - DO NOT MODIFY BY HAND

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
      aiModel: fields[7] as String,
      rating: fields[8] as int,
      feedbackNote: fields[9] as String,
      correctedReply: fields[10] as String,
      trained: fields[11] as bool,
      // Field 12 was added later; records written by older builds do not
      // have it. Tolerate null instead of crashing the Logs tab on upgrade.
      failureReason: fields[12] == null ? '' : fields[12] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ReplyLog obj) {
    writer
      ..writeByte(13)
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
      ..write(obj.trained)
      ..writeByte(12)
      ..write(obj.failureReason);
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
