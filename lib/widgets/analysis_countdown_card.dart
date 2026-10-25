import 'package:flutter/material.dart';
import '../theme/draft_theme.dart';
import '../theme/draft_widgets.dart';
import '../providers/analysis_status_provider.dart';

/// A deadline visualization, not an estimate of model completion/progress.
/// Rendered inside the same fixed-height [DraftAnalysisShell] as the
/// dashboard's Analysis card, so switching between states never resizes it.
class AnalysisCountdownCard extends StatelessWidget {
  final AnalysisStatus status;

  /// Other attempts running at the same time (shown as "+N more" instead of
  /// stacking extra cards, which would change the slot's height).
  final int extraCount;
  const AnalysisCountdownCard(
      {super.key, required this.status, this.extraCount = 0});

  @override
  Widget build(BuildContext context) {
    final active = status.isAnalysing;
    final waiting = active && status.remainingMs == 0;
    final expired = status.phase == 'expired';
    final unknown = status.phase == 'unknown';
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: reducedMotion ? 0 : 180);
    final c = DraftColors.of(context);
    final accent = c.pri;
    final title = active
        ? (waiting ? 'Checking status…' : 'Analysing')
        : expired
            ? '100-second limit reached'
            : unknown
                ? 'Status unavailable'
                : 'Couldn’t analyse message';
    final subtitle = active
        ? '100-second analysis limit'
        : unknown
            ? 'Reply status could not be verified'
            : 'Reply skipped for this attempt';
    return Semantics(
      label: active
          ? '$title, ${status.seconds} seconds remaining, ${status.sender}'
          : title,
      child: KeyedSubtree(
        key: ValueKey('analysis-${status.id}'),
        child: DraftAnalysisShell(
        child: Row(children: [
          SizedBox(
              width: kAnalysisRingSize,
              height: kAnalysisRingSize,
              child: Stack(alignment: Alignment.center, children: [
                if (active)
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: status.remainingMs / 100000),
                    duration: duration,
                    builder: (context, remaining, child) => SizedBox(
                        width: kAnalysisRingSize,
                        height: kAnalysisRingSize,
                        child: CircularProgressIndicator(
                            value: remaining,
                            strokeWidth: 6,
                            strokeCap: StrokeCap.round,
                            backgroundColor: c.s2,
                            valueColor: AlwaysStoppedAnimation(accent))),
                  ),
                if (active)
                  AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                              position: Tween<Offset>(
                                      begin: const Offset(0, .2),
                                      end: Offset.zero)
                                  .animate(animation),
                              child: child)),
                      child: Text('${status.seconds}s',
                          key: ValueKey(status.seconds),
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)))
                else
                  Icon(
                      unknown
                          ? Icons.help_outline_rounded
                          : Icons.timer_off_outlined,
                      size: 32,
                      color: accent),
              ])),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                if (status.sender.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                          extraCount > 0
                              ? '${status.sender} · +$extraCount more'
                              : status.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.tx,
                              fontWeight: FontWeight.w600))),
                const SizedBox(height: 3),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.mut, fontSize: 12)),
              ])),
        ]),
        ),
      ),
    );
  }
}
