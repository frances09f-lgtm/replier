import 'package:flutter/material.dart';
import '../providers/pipeline_status_provider.dart';
import '../theme/draft_widgets.dart';

/// Dashboard "Analysis" card for a pipeline stage. In the sending stage it
/// shows the live reply countdown: remaining seconds inside the ring, the
/// arc filling as the delay runs out, and "Sending in 12s" as the status.
class PipelineAnalysisCard extends StatelessWidget {
  final PipelineStatusData status;

  const PipelineAnalysisCard({super.key, required this.status});

  static const _labels = {
    PipelineStage.gotMessage: 'Got a new message.',
    PipelineStage.analysing: 'Analyzing the message.',
    PipelineStage.replyReady: 'Reply ready.',
  };
  static const _progress = {
    PipelineStage.gotMessage: 0.25,
    PipelineStage.analysing: 0.5,
    PipelineStage.replyReady: 0.75,
  };

  @override
  Widget build(BuildContext context) {
    if (status.stage == PipelineStage.sending) {
      final secs = status.countdownSeconds < 0 ? 0 : status.countdownSeconds;
      final total = status.countdownTotalSeconds;
      final to = status.sender.trim().isEmpty ? '' : ' to ${status.sender}';
      if (secs <= 0) {
        return DraftAnalysisCard(
          progress: 1,
          ringLabel: '0s',
          text: 'Sending now…$to',
          animateProgress: true,
        );
      }
      final progress = total > 0 ? (1 - secs / total).clamp(0.0, 1.0) : 0.0;
      return DraftAnalysisCard(
        progress: progress,
        ringLabel: '${secs}s',
        text: 'Sending in ${secs}s$to',
        animateProgress: true,
      );
    }
    return DraftAnalysisCard(
      progress: _progress[status.stage] ?? 0.5,
      ringLabel: '',
      text: _labels[status.stage] ?? 'Processing.',
    );
  }
}
