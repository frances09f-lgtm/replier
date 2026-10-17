import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../services/auto_reply_service.dart';

class AnalysisStatus {
  final String id, sender, phase;
  final int remainingMs, terminalRemainingMs;
  const AnalysisStatus(
      {required this.id,
      required this.sender,
      required this.phase,
      required this.remainingMs,
      this.terminalRemainingMs = 0});
  bool get isAnalysing => phase == 'analysing';
  int get seconds => (remainingMs / 1000).ceil().clamp(0, 100);
}

/// Native owns the deadline and permission to deliver. Flutter only animates the
/// remaining budget; reaching zero alone must NEVER claim a reply was prevented.
class AnalysisStatusNotifier extends StateNotifier<List<AnalysisStatus>>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel(AppConstants.notificationChannel);
  final bool connectNative;
  final int Function() _now;
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _ticker;
  List<AnalysisStatus> _snapshot = [];
  int _receivedAt = 0, _revision = -1;
  String? _epoch;
  final Set<String> _retiredEpochs = {};
  int _snapshotGeneration = 0;
  bool _refreshing = false,
      _deadlineRefreshRequested = false,
      _disposed = false;

  AnalysisStatusNotifier({this.connectNative = true, int Function()? nowMs})
      : _now = nowMs ?? (() => 0),
        super([]) {
    if (connectNative) {
      WidgetsBinding.instance.addObserver(this);
      AutoReplyService.onAnalysisStatus = applySnapshot;
      refresh();
    }
  }
  int get _elapsedNow => connectNative ? _clock.elapsedMilliseconds : _now();

  void applySnapshot(Map<String, dynamic> data) {
    if (_disposed) return;
    final epoch = data['epoch'] as String? ?? 'offline';
    final revision = (data['revision'] as num?)?.toInt() ?? 0;
    if (_retiredEpochs.contains(epoch)) return;
    if (_epoch == epoch && revision <= _revision) return;
    if (_epoch != null && _epoch != epoch) _retiredEpochs.add(_epoch!);
    _snapshotGeneration++;
    _epoch = epoch;
    _revision = revision;
    _receivedAt = _elapsedNow;
    _deadlineRefreshRequested = false;
    _snapshot = (data['attempts'] as List? ?? [])
        .map((raw) {
          final a = Map<String, dynamic>.from(raw as Map);
          return AnalysisStatus(
              id: a['id'] as String,
              sender: a['sender'] as String? ?? '',
              phase: a['state'] as String,
              remainingMs:
                  ((a['remainingMs'] as num?)?.toInt() ?? 0).clamp(0, 100000),
              terminalRemainingMs:
                  ((a['terminalRemainingMs'] as num?)?.toInt() ?? 0)
                      .clamp(0, 6000));
        })
        .where(
            (a) => a.isAnalysing || a.phase == 'expired' || a.phase == 'failed')
        .toList();
    tick();
    _ticker?.cancel();
    if (_snapshot.isNotEmpty) {
      _ticker =
          Timer.periodic(const Duration(milliseconds: 100), (_) => tick());
    }
  }

  void tick() {
    if (_disposed) return;
    final elapsed = (_elapsedNow - _receivedAt).clamp(0, 1 << 31);
    state = _snapshot
        .where((a) => a.isAnalysing || a.terminalRemainingMs > elapsed)
        .map((a) => AnalysisStatus(
            id: a.id,
            sender: a.sender,
            phase: a.phase,
            remainingMs: (a.remainingMs - elapsed).clamp(0, 100000),
            terminalRemainingMs:
                (a.terminalRemainingMs - elapsed).clamp(0, 6000)))
        .toList();
    if (connectNative &&
        !_deadlineRefreshRequested &&
        state.any((a) => a.isAnalysing && a.remainingMs == 0)) {
      _deadlineRefreshRequested = true;
      refresh();
    }
    if (state.isEmpty) _ticker?.cancel();
  }

  Future<void> refresh() async {
    if (_disposed || _refreshing || !connectNative) return;
    _refreshing = true;
    final generation = _snapshotGeneration;
    try {
      final raw = await _channel
          .invokeMethod<String>('getAnalysisStatus')
          .timeout(const Duration(seconds: 3));
      if (!_disposed && raw != null && generation == _snapshotGeneration) {
        applySnapshot(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      }
    } catch (_) {
      // Keep a valid active countdown. Once its budget is over, show an honest
      // status-unavailable result, not an unverified "no reply sent" claim.
      if (!_disposed && state.any((a) => a.isAnalysing && a.remainingMs == 0)) {
        _snapshot = state
            .map((a) => a.isAnalysing && a.remainingMs == 0
                ? AnalysisStatus(
                    id: a.id,
                    sender: a.sender,
                    phase: 'unknown',
                    remainingMs: 0,
                    terminalRemainingMs: 6000)
                : a)
            .toList();
        _receivedAt = _elapsedNow;
        tick();
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    if (connectNative) {
      WidgetsBinding.instance.removeObserver(this);
      if (AutoReplyService.onAnalysisStatus == applySnapshot) {
        AutoReplyService.onAnalysisStatus = null;
      }
    }
    super.dispose();
  }
}

final analysisStatusProvider =
    StateNotifierProvider<AnalysisStatusNotifier, List<AnalysisStatus>>(
        (ref) => AnalysisStatusNotifier());
