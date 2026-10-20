import 'dart:async';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auto_reply_service.dart';

/// The four stages of the auto-reply pipeline
enum PipelineStage { gotMessage, analysing, replyReady, sending }

/// State held by the pipeline status provider
class PipelineStatusData {
  final PipelineStage? stage;
  final String sender;
  final int countdownSeconds;

  const PipelineStatusData({
    this.stage,
    this.sender = '',
    this.countdownSeconds = 0,
  });

  bool get isIdle => stage == null;

  PipelineStatusData copyWith({
    PipelineStage? stage,
    String? sender,
    int? countdownSeconds,
  }) {
    return PipelineStatusData(
      stage: stage ?? this.stage,
      sender: sender ?? this.sender,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    );
  }
}

// Internal event types
enum _EventType { gotMessage, analysing, replyReady, replyCompleted }

class _PipelineEvent {
  final _EventType type;
  final String sender;
  const _PipelineEvent(this.type, {this.sender = ''});
}

class PipelineStatusNotifier extends StateNotifier<PipelineStatusData> {
  // Minimum time each stage stays visible before the next one shows
  static const _minDisplayMs = {
    PipelineStage.gotMessage: 500,
    PipelineStage.analysing: 600,
    PipelineStage.replyReady: 500,
    PipelineStage.sending: 0, // sending runs its real countdown
  };

  final Queue<_PipelineEvent> _queue = Queue();
  bool _processing = false;
  Timer? _stageTimer;
  Timer? _countdownTimer;
  Timer? _stalenessTimer;

  PipelineStatusNotifier() : super(const PipelineStatusData()) {
    AutoReplyService.onPipelineStatus = _onPipelineStatus;
    AutoReplyService.onReplyScheduled = _onReplyScheduled;
    AutoReplyService.onReplyCompleted = _onReplyCompleted;
  }

  // ── Incoming native events ────────────────────────────────────────────────

  void _onPipelineStatus(Map<String, dynamic> data) {
    final stageStr = data['state'] as String? ?? '';
    if (stageStr == 'analysis_managed') {
      if (state.stage == PipelineStage.gotMessage ||
          state.stage == PipelineStage.analysing) {
        _queue.clear();
        _cancelTimers();
        state = const PipelineStatusData();
        _processing = false;
      }
      return;
    }
    final sender = data['sender'] as String? ?? '';

    final type = switch (stageStr) {
      'got_message' => _EventType.gotMessage,
      'analysing' => _EventType.analysing,
      'reply_ready' => _EventType.replyReady,
      _ => null,
    };
    if (type == null) return;

    _enqueue(_PipelineEvent(type, sender: sender));
  }

  void _onReplyScheduled(Map<String, dynamic> data) {
    final delayMs = (data['delayMs'] as num?)?.toInt() ?? 0;
    final sender = data['sender'] as String? ?? '';
    final scheduledAtMs = (data['scheduledAt'] as num?)?.toInt();
    final scheduledAt = scheduledAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(scheduledAtMs)
        : DateTime.now();

    // Reply is already scheduled on native — drop any lingering analysis queue
    _queue.clear();
    _cancelStageTimer();

    // Transition smoothly into sending countdown without artificial delays
    _startSending(sender, delayMs, scheduledAt);
  }

  void _onReplyCompleted() {
    // Terminal event — skip the queue, go idle immediately
    _queue.clear();
    _cancelTimers();
    state = const PipelineStatusData();
    _processing = false;
  }

  // ── Queue processor ───────────────────────────────────────────────────────

  void _enqueue(_PipelineEvent event) {
    _queue.addLast(event);
    if (!_processing) _processNext();
  }

  void _processNext() {
    if (_queue.isEmpty) {
      _processing = false;
      return;
    }

    _processing = true;
    final event = _queue.removeFirst();

    switch (event.type) {
      case _EventType.gotMessage:
        _showStage(PipelineStage.gotMessage, event.sender);
        break;

      case _EventType.analysing:
        _showStage(PipelineStage.analysing, event.sender);
        break;

      case _EventType.replyReady:
        _showStage(PipelineStage.replyReady, event.sender);
        break;

      case _EventType.replyCompleted:
        _cancelTimers();
        state = const PipelineStatusData();
        _processing = false;
        break;
    }
  }

  /// Display a stage for at least its minimum duration, then process next event.
  void _showStage(PipelineStage stage, String sender) {
    _cancelStageTimer();
    state = PipelineStatusData(stage: stage, sender: sender);

    final minMs = _minDisplayMs[stage] ?? 400;
    _stageTimer = Timer(Duration(milliseconds: minMs), () {
      _stageTimer = null;
      _processNext();
    });

    // Staleness guard: a native terminal event can always be lost (process
    // death, channel restart). Never leave a non-terminal stage wedged on
    // screen - fall back to idle so the next message starts clean.
    _stalenessTimer?.cancel();
    _stalenessTimer = Timer(const Duration(seconds: 45), () {
      if (!state.isIdle && state.stage != PipelineStage.sending) {
        _queue.clear();
        _cancelTimers();
        state = const PipelineStatusData();
        _processing = false;
      }
    });
  }

  /// Start the sending stage with a live countdown synchronized to wall-clock time.
  void _startSending(String sender, int delayMs, DateTime scheduledAt) {
    _cancelStageTimer();
    _cancelCountdownTimer();

    final targetTime = scheduledAt.add(Duration(milliseconds: delayMs));
    final initialRemainingMs =
        targetTime.difference(DateTime.now()).inMilliseconds;
    final countdownSecs =
        initialRemainingMs <= 0 ? 0 : (initialRemainingMs / 1000).ceil();

    state = PipelineStatusData(
      stage: PipelineStage.sending,
      sender: sender,
      countdownSeconds: countdownSecs,
    );

    if (countdownSecs > 0) {
      _countdownTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final remMs = targetTime.difference(DateTime.now()).inMilliseconds;
        final remSecs = remMs <= 0 ? 0 : (remMs / 1000).ceil();
        if (remSecs <= 0) {
          _cancelCountdownTimer();
          state = state.copyWith(countdownSeconds: 0);
          // Staleness guard: auto-clear if terminal event never arrives
          _stalenessTimer = Timer(const Duration(seconds: 30), () {
            if (!state.isIdle) {
              state = const PipelineStatusData();
              _processing = false;
            }
          });
        } else if (remSecs != state.countdownSeconds) {
          state = state.copyWith(countdownSeconds: remSecs);
        }
      });
    }

    // Sending holds until onReplyCompleted — don't call _processNext here
    _processing = true;
  }

  // ── Timer helpers ─────────────────────────────────────────────────────────

  void _cancelStageTimer() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }

  void _cancelCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _cancelTimers() {
    _cancelStageTimer();
    _cancelCountdownTimer();
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    AutoReplyService.onPipelineStatus = null;
    super.dispose();
  }
}

final pipelineStatusProvider =
    StateNotifierProvider<PipelineStatusNotifier, PipelineStatusData>((ref) {
  return PipelineStatusNotifier();
});
