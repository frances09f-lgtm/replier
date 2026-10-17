import 'package:flutter/material.dart';
import '../providers/analysis_status_provider.dart';

/// A deadline visualization, not an estimate of model completion/progress.
class AnalysisCountdownCard extends StatelessWidget {
  final AnalysisStatus status;
  const AnalysisCountdownCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final active = status.isAnalysing;
    final waiting = active && status.remainingMs == 0;
    final expired = status.phase == 'expired';
    final unknown = status.phase == 'unknown';
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: reducedMotion ? 0 : 180);
    const accent = Color(0xFFAE4C18);
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
      child: AnimatedContainer(
        key: ValueKey('analysis-${status.id}'),
        duration: duration,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF5E8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF1DBBF))),
        child: Row(children: [
          SizedBox(
              width: 58,
              height: 58,
              child: Stack(alignment: Alignment.center, children: [
                if (active)
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: status.remainingMs / 100000),
                    duration: duration,
                    builder: (context, remaining, child) => SizedBox(
                        width: 58,
                        height: 58,
                        child: CircularProgressIndicator(
                            value: remaining,
                            strokeWidth: 4,
                            strokeCap: StrokeCap.round,
                            backgroundColor: const Color(0xFFF0DDC5),
                            valueColor: const AlwaysStoppedAnimation(accent))),
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
                          style: const TextStyle(
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                if (status.sender.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(status.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF79533F),
                              fontWeight: FontWeight.w600))),
                const SizedBox(height: 5),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF886F5C), fontSize: 12)),
              ])),
        ]),
      ),
    );
  }
}
