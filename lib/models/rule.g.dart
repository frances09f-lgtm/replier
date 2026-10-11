// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RuleAdapter extends TypeAdapter<Rule> {
  @override
  final int typeId = 51;

  @override
  Rule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Rule(
      id: fields[0] as String,
      triggerText: fields[1] as String,
      replyText: fields[2] as String,
      exactMatch: fields[3] as bool,
      containsMatch: fields[4] as bool,
      caseSensitive: fields[5] as bool,
      isEnabled: fields[6] as bool,
      createdAt: fields[7] as DateTime,
      updatedAt: fields[8] as DateTime,
      triggerTexts: (fields[9] as List?)?.cast<String>(),
      replies: (fields[10] as List?)?.cast<String>(),
      senderNames: (fields[11] as List?)?.cast<String>(),
      isDefault: fields[12] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Rule obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.triggerText)
      ..writeByte(2)
      ..write(obj.replyText)
      ..writeByte(3)
      ..write(obj.exactMatch)
      ..writeByte(4)
      ..write(obj.containsMatch)
      ..writeByte(5)
      ..write(obj.caseSensitive)
      ..writeByte(6)
      ..write(obj.isEnabled)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.updatedAt)
      ..writeByte(9)
      ..write(obj.triggerTexts)
      ..writeByte(10)
      ..write(obj.replies)
      ..writeByte(11)
      ..write(obj.senderNames)
      ..writeByte(12)
      ..write(obj.isDefault);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
