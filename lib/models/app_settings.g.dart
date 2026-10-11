// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 1;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      masterEnabled: fields[0] as bool,
      whatsappEnabled: fields[1] as bool,
      instagramEnabled: fields[2] as bool,
      minReplyDelaySeconds: fields[3] as int,
      maxReplyDelaySeconds: fields[9] as int,
      preventDuplicateReplies: fields[4] as bool,
      ignoreGroupChats: fields[5] as bool,
      darkMode: fields[6] as bool,
      aiReplyEnabled: fields[10] as bool,
      aiSystemPrompt: fields[12] as String,
      aiModelType: fields[13] as String,
      scheduleEnabled: fields[18] as bool,
      scheduleStartHour: fields[19] as int,
      scheduleStartMinute: fields[20] as int,
      scheduleEndHour: fields[21] as int,
      scheduleEndMinute: fields[22] as int,
      confirmBeforeReply: fields[24] as bool,
      contactWhitelistEnabled: fields[25] as bool,
      contactWhitelist: (fields[26] as List).cast<String>(),
      contactBlacklist: (fields[27] as List).cast<String>(),
      busyModeEnabled: fields[28] as bool,
      busyReplyText: fields[29] as String,
      busyUntilTimestamp: fields[30] as int,
      gemmaLocalServerUrl: fields[31] as String,
      gemmaLocalModel: fields[32] as String,
      selectedLocalModel: fields[33] as String,
      groqApiKey: fields[37] as String? ?? '',
      groqModel: fields[38] as String? ?? 'openai/gpt-oss-20b',
      geminiApiKey: fields[39] as String? ?? '',
      geminiModel: fields[40] as String? ?? 'gemini-3.6-flash',
      trainingExamplesRaw: (fields[36] as List?)?.cast<String>() ?? [],
      groqReplyLimit: fields[42] as int? ?? 0,
      geminiReplyLimit: fields[43] as int? ?? 0,
      localReplyLimit: fields[44] as int? ?? 0,
      fallbackToLocalModel: fields[45] as bool? ?? true,
      lastUpdated: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(36)
      ..writeByte(0)
      ..write(obj.masterEnabled)
      ..writeByte(1)
      ..write(obj.whatsappEnabled)
      ..writeByte(2)
      ..write(obj.instagramEnabled)
      ..writeByte(3)
      ..write(obj.minReplyDelaySeconds)
      ..writeByte(9)
      ..write(obj.maxReplyDelaySeconds)
      ..writeByte(4)
      ..write(obj.preventDuplicateReplies)
      ..writeByte(5)
      ..write(obj.ignoreGroupChats)
      ..writeByte(6)
      ..write(obj.darkMode)
      ..writeByte(7)
      ..write(obj.lastUpdated)
      ..writeByte(10)
      ..write(obj.aiReplyEnabled)
      ..writeByte(12)
      ..write(obj.aiSystemPrompt)
      ..writeByte(13)
      ..write(obj.aiModelType)
      ..writeByte(18)
      ..write(obj.scheduleEnabled)
      ..writeByte(19)
      ..write(obj.scheduleStartHour)
      ..writeByte(20)
      ..write(obj.scheduleStartMinute)
      ..writeByte(21)
      ..write(obj.scheduleEndHour)
      ..writeByte(22)
      ..write(obj.scheduleEndMinute)
      ..writeByte(24)
      ..write(obj.confirmBeforeReply)
      ..writeByte(25)
      ..write(obj.contactWhitelistEnabled)
      ..writeByte(26)
      ..write(obj.contactWhitelist)
      ..writeByte(27)
      ..write(obj.contactBlacklist)
      ..writeByte(28)
      ..write(obj.busyModeEnabled)
      ..writeByte(29)
      ..write(obj.busyReplyText)
      ..writeByte(30)
      ..write(obj.busyUntilTimestamp)
      ..writeByte(31)
      ..write(obj.gemmaLocalServerUrl)
      ..writeByte(32)
      ..write(obj.gemmaLocalModel)
      ..writeByte(33)
      ..write(obj.selectedLocalModel)
      ..writeByte(37)
      ..write('')
      ..writeByte(38)
      ..write(obj.groqModel)
      ..writeByte(39)
      ..write('')
      ..writeByte(40)
      ..write(obj.geminiModel)
      ..writeByte(36)
      ..write(obj.trainingExamplesRaw)
      ..writeByte(42)
      ..write(obj.groqReplyLimit)
      ..writeByte(43)
      ..write(obj.geminiReplyLimit)
      ..writeByte(44)
      ..write(obj.localReplyLimit)
      ..writeByte(45)
      ..write(obj.fallbackToLocalModel);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
