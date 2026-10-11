/// Model for notification data received from Android
class NotificationData {
  final String packageName;
  final String appName;
  final String sender;
  final String message;
  final int timestamp;
  final bool isGroupChat;
  final String key;

  NotificationData({
    required this.packageName,
    required this.appName,
    required this.sender,
    required this.message,
    required this.timestamp,
    required this.isGroupChat,
    required this.key,
  });

  /// Convert from JSON
  factory NotificationData.fromJson(Map<String, dynamic> json) {
    return NotificationData(
      packageName: json['packageName'],
      appName: json['appName'],
      sender: json['sender'],
      message: json['message'],
      timestamp: json['timestamp'],
      isGroupChat: json['isGroupChat'],
      key: json['key'],
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'appName': appName,
      'sender': sender,
      'message': message,
      'timestamp': timestamp,
      'isGroupChat': isGroupChat,
      'key': key,
    };
  }

  /// Get DateTime from timestamp
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  @override
  String toString() {
    return 'NotificationData(packageName: $packageName, appName: $appName, sender: $sender, message: $message)';
  }
}
