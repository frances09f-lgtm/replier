import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/pipeline_status_provider.dart';
import '../providers/analysis_status_provider.dart';
import 'analysis_countdown_card.dart';

/// Single persistent card that animates between pipeline stages.
/// Uses AnimatedSwitcher for content cross-fade and AnimatedContainer
/// for the smooth background colour transition.
class PipelineStatusCard extends ConsumerWidget {
  const PipelineStatusCard({super.key});

  // ── Per-stage styling ────────────────────────────────────────────────────

  static const _bg = {
    PipelineStage.gotMessage: Color(0xFFE3F2FD), // blue 50
    PipelineStage.analysing: Color(0xFFFFF8E1), // amber 50
    PipelineStage.replyReady: Color(0xFFE8F5E9), // green 50
    PipelineStage.sending: Color(0xFFF3E5F5), // purple 50
  };

  static const _accent = {
    PipelineStage.gotMessage: Color(0xFF1565C0), // blue 800
    PipelineStage.analysing: Color(0xFFE65100), // deep orange 900
    PipelineStage.replyReady: Color(0xFF2E7D32), // green 800
    PipelineStage.sending: Color(0xFF6A1B9A), // purple 800
  };

  static const _icon = {
    PipelineStage.gotMessage: Icons.move_to_inbox_rounded,
    PipelineStage.analysing: Icons.hourglass_top_rounded,
    PipelineStage.replyReady: Icons.check_circle_rounded,
    PipelineStage.sending: Icons.send_rounded,
  };

  static const _label = {
    PipelineStage.gotMessage: 'Got new message',
    PipelineStage.analysing: 'Analysing',
    PipelineStage.replyReady: 'Reply ready',
    PipelineStage.sending: 'Sending',
  };

  static const _stageOrder = [
    PipelineStage.gotMessage,
    PipelineStage.analysing,
    PipelineStage.replyReady,
    PipelineStage.sending,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyses = ref.watch(analysisStatusProvider);
    final status = ref.watch(pipelineStatusProvider);
    if (analyses.isNotEmpty) {
      return Column(
          children: analyses
              .map((a) => AnalysisCountdownCard(key: ValueKey(a.id), status: a))
              .toList());
    }

    // Keep the last known stage if idle to prevent sudden color changes during exit animation
    final stage = status.stage ?? PipelineStage.gotMessage;
    final bg = _bg[stage]!;
    final accent = _accent[stage]!;

    return AnimatedSize(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutExpo,
      alignment: Alignment.topCenter,
      child: status.isIdle
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      // ── Left: icon / spinner ─────────────────────────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: stage == PipelineStage.analysing
                            ? SizedBox(
                                key: const ValueKey('spinner'),
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(accent),
                                ),
                              )
                            : Icon(
                                _icon[stage],
                                key: ValueKey(stage),
                                color: accent,
                                size: 28,
                              ),
                      ),

                      const SizedBox(width: 14),

                      // ── Centre: label + sender ───────────────────────────────────
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.2),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Column(
                            key: ValueKey(stage),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                stage == PipelineStage.sending
                                    ? 'Sending in ${status.countdownSeconds}s'
                                    : _label[stage]!,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                  fontSize: 15,
                                ),
                              ),
                              if (status.sender.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  status.sender,
                                  style: TextStyle(
                                    color: accent.withValues(alpha: 0.75),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // ── Right: progress dots ─────────────────────────────────────
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _stageOrder.map((s) {
                          final idx = _stageOrder.indexOf(s);
                          final current = _stageOrder.indexOf(stage);
                          final isActive = idx == current;
                          final isDone = idx < current;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutBack,
                            margin: const EdgeInsets.only(left: 6),
                            width: isActive ? 10 : 6,
                            height: isActive ? 10 : 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(
                                alpha: isActive
                                    ? 1.0
                                    : isDone
                                        ? 0.3
                                        : 0.1,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
