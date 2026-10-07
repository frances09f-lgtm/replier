import 'package:hive/hive.dart';

/// One incoming message notification: what arrived, what the AI drafted,
/// and what the user decided. Status flow:
/// new -> generated -> sending -> submitted | opened_unverified | send_failed
/// Legacy approved records are unverified attempts, not delivery receipts.
class MessageEvent extends HiveObject {
  MessageEvent({
    required this.id,
    required this.notifKey,
    required this.appPackage,
    required this.appLabel,
    required this.sender,
    required this.text,
    required this.at,
    this.generatedReply = '',
    this.status = 'new',
    this.finalReply = '',
  });

  final String id;
  final String notifKey;
  final String appPackage;
  final String appLabel;
  final String sender;
  final String text;
  final DateTime at;
  String generatedReply;
  String status;
  String finalReply;

  String get statusLabel => switch (status) {
    'submitted' => 'Submitted (delivery unconfirmed)',
    'opened_unverified' => 'Chat opened (send unconfirmed)',
    'approved' || 'edited' => 'Past attempt (unverified)',
    'sending' => 'Attempt started (check chat)',
    'send_failed' => 'Send failed',
    _ => status,
  };
}

class MessageEventAdapter extends TypeAdapter<MessageEvent> {
  @override
  final int typeId = 0;

  @override
  MessageEvent read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return MessageEvent(
      id: f[0] as String,
      notifKey: f[1] as String,
      appPackage: f[2] as String,
      appLabel: f[3] as String,
      sender: f[4] as String,
      text: f[5] as String,
      at: DateTime.fromMillisecondsSinceEpoch(f[6] as int),
      generatedReply: f[7] as String? ?? '',
      status: f[8] as String? ?? 'new',
      finalReply: f[9] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, MessageEvent e) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(e.id)
      ..writeByte(1)
      ..write(e.notifKey)
      ..writeByte(2)
      ..write(e.appPackage)
      ..writeByte(3)
      ..write(e.appLabel)
      ..writeByte(4)
      ..write(e.sender)
      ..writeByte(5)
      ..write(e.text)
      ..writeByte(6)
      ..write(e.at.millisecondsSinceEpoch)
      ..writeByte(7)
      ..write(e.generatedReply)
      ..writeByte(8)
      ..write(e.status)
      ..writeByte(9)
      ..write(e.finalReply);
  }
}
