import 'package:flutter/material.dart';

import '../theme/draft_theme.dart';
import 'settings_screen.dart';

/// Gives the existing Settings screen an Orion-inspired canvas and app bar.
/// All setting state, controls, and actions remain in SettingsScreen.
class OrionSettingsScreen extends StatelessWidget {
  const OrionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = DraftColors.of(context);
    final baseTheme = Theme.of(context);
    final settingsTheme = baseTheme.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        titleTextStyle: DraftText.display(26, colors.tx),
      ),
    );

    return Theme(
      data: settingsTheme,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _OrionSettingsBackdrop(colors),
              ),
            ),
          ),
          const SettingsScreen(),
        ],
      ),
    );
  }
}

class _OrionSettingsBackdrop extends CustomPainter {
  const _OrionSettingsBackdrop(this.colors);

  final DraftColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(colors.bg, BlendMode.src);

    final mint = Paint()..color = colors.pc.withValues(alpha: 0.22);
    final blue = Paint()..color = colors.tc.withValues(alpha: 0.16);

    canvas.drawCircle(Offset(size.width + 18, 82), 142, mint);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(-96, size.height * 0.38, 192, 330),
        topRight: const Radius.circular(132),
        bottomRight: const Radius.circular(76),
        bottomLeft: const Radius.circular(124),
      ),
      blue,
    );
    canvas.drawCircle(Offset(size.width * 0.94, size.height * 0.79), 88, blue);
  }

  @override
  bool shouldRepaint(covariant _OrionSettingsBackdrop oldDelegate) =>
      oldDelegate.colors != colors;
}
