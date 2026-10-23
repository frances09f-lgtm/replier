import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auto_reply_service.dart';

/// Model for reply countdown state
class ReplyCountdownData {
  final bool isActive;
  final String sender;
  final String replyText;
  final int totalMs;
  final int remainingMs;
  final DateTime scheduledAt;

  ReplyCountdownData({
    this.isActive = false,
    this.sender = '',
    this.replyText = '',
    this.totalMs = 0,
    this.remainingMs = 0,
    DateTime? scheduledAt,
  }) : scheduledAt = scheduledAt ?? DateTime.now();

  double get progress =>
      totalMs > 0 ? (1 - remainingMs / totalMs).clamp(0.0, 1.0) : 0.0;

  String get remainingFormatted {
    final seconds = remainingMs ~/ 1000;
    if (seconds > 0) return '${seconds}s';
    if (remainingMs == 0 && !isActive) return '';
    return '0s';
  }

  ReplyCountdownData copyWith({
    bool? isActive,
    String? sender,
    String? replyText,
    int? totalMs,
    int? remainingMs,
    DateTime? scheduledAt,
  }) {
    return ReplyCountdownData(
      isActive: isActive ?? this.isActive,
      sender: sender ?? this.sender,
      replyText: replyText ?? this.replyText,
      totalMs: totalMs ?? this.totalMs,
      remainingMs: remainingMs ?? this.remainingMs,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }
}

/// Notifier for reply countdown state
class ReplyCountdownNotifier extends StateNotifier<ReplyCountdownData> {
  /// How long a countdown may sit at 0s waiting for the native side to report
  /// success or failure before the card clears itself. Native can drop a
  /// scheduled reply (cancelled, master switch off, service destroyed) without
  /// sending a terminal event, which used to leave "Sending in 0s" forever.
  static const Duration staleAfterDue = Duration(seconds: 30);

  Timer? _countdownTimer;
  Timer? _staleTimer;

  ReplyCountdownNotifier() : super(ReplyCountdownData()) {
    AutoReplyService.onReplyScheduled = handleReplyScheduled;
    AutoReplyService.onReplyCompleted = _onReplyCompleted;
  }

  @visibleForTesting
  void handleReplyScheduled(Map<String, dynamic> data) {
    final delayMs = (data['delayMs'] as num?)?.toInt() ?? 0;
    final sender = data['sender'] as String? ?? '';
    final replyText = data['replyText'] as String? ?? '';
    final scheduledAtMs = (data['scheduledAt'] as num?)?.toInt();
    final scheduledAt = scheduledAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(scheduledAtMs)
        : DateTime.now();

    _countdownTimer?.cancel();
    _staleTimer?.cancel();

    final elapsed = DateTime.now().millisecondsSinceEpoch -
        scheduledAt.millisecondsSinceEpoch;
    final initialRemaining = (delayMs - elapsed).clamp(0, delayMs);

    state = ReplyCountdownData(
      isActive: true,
      sender: sender,
      replyText: replyText,
      totalMs: delayMs,
      remainingMs: initialRemaining,
      scheduledAt: scheduledAt,
    );

    if (initialRemaining > 0) {
      _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _tick();
      });
    } else {
      _armStaleGuard();
    }
  }

  void _armStaleGuard() {
    _staleTimer?.cancel();
    _staleTimer = Timer(staleAfterDue, () {
      if (mounted && state.isActive) {
        state = ReplyCountdownData();
      }
    });
  }

  void _onReplyCompleted() {
    _countdownTimer?.cancel();
    _staleTimer?.cancel();
    state = ReplyCountdownData();
  }

  void _tick() {
    final elapsed = DateTime.now().millisecondsSinceEpoch -
        state.scheduledAt.millisecondsSinceEpoch;
    final remaining = (state.totalMs - elapsed).clamp(0, state.totalMs);
    if (remaining <= 0) {
      _countdownTimer?.cancel();
      state = state.copyWith(remainingMs: 0);
      _armStaleGuard();
      return;
    }
    state = state.copyWith(remainingMs: remaining);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _staleTimer?.cancel();
    AutoReplyService.onReplyScheduled = null;
    AutoReplyService.onReplyCompleted = null;
    super.dispose();
  }
}

/// Provider for reply countdown data
final replyCountdownProvider =
    StateNotifierProvider<ReplyCountdownNotifier, ReplyCountdownData>((ref) {
  return ReplyCountdownNotifier();
});
