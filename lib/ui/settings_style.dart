import 'package:flutter/material.dart';

// Tokens from the approved draft, used only by Settings.
ThemeData settingsTheme(bool dark) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF006B5E),
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    surface: dark ? const Color(0xFF1C2B2D) : const Color(0xFFF4FBF8),
    surfaceContainer: dark ? const Color(0xFF26383A) : const Color(0xFFE6F1ED),
    surfaceContainerHighest: dark ? const Color(0xFF324A4C) : const Color(0xFFD6E6E1),
    primary: dark ? const Color(0xFF7FD8C8) : const Color(0xFF006B5E),
    onPrimary: dark ? const Color(0xFF00382F) : Colors.white,
    primaryContainer: dark ? const Color(0xFF1F5A52) : const Color(0xFFA0F2E1),
    onPrimaryContainer: dark ? const Color(0xFFB6F2E6) : const Color(0xFF00201B),
    onSurface: dark ? const Color(0xFFE3EFED) : const Color(0xFF151D1B),
    onSurfaceVariant: dark ? const Color(0xFFB3C8C5) : const Color(0xFF3F4946),
    outline: dark ? const Color(0xFF86A09C) : const Color(0xFF6F7976),
    tertiaryContainer: dark ? const Color(0xFF33495A) : const Color(0xFFD3E4F0),
    onTertiaryContainer: dark ? const Color(0xFFD3E4F0) : const Color(0xFF0B1D29),
  );
  return ThemeData(useMaterial3: true, colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(elevation: 0, color: scheme.surface,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.zero),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      minimumSize: const Size(44, 48), shape: const StadiumBorder())),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(44, 48), shape: const StadiumBorder())),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 48), shape: const StadiumBorder())),
  );
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.icon,
    required this.child, this.alt = false});
  final String title;
  final IconData icon;
  final Widget child;
  final bool alt;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(32)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned(right: alt ? null : -48, left: alt ? -56 : null,
          top: alt ? null : -48, bottom: alt ? -56 : null,
          child: ExcludeSemantics(child: IgnorePointer(child: Transform.rotate(
            angle: 0.35,
            child: Container(width: 136, height: 136,
              decoration: BoxDecoration(
                color: (alt ? colors.tertiaryContainer : colors.primaryContainer).withValues(alpha: .5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(84), topRight: Radius.circular(52),
                  bottomLeft: Radius.circular(60), bottomRight: Radius.circular(78)))))))),
        Padding(padding: const EdgeInsets.all(19),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42,
                decoration: BoxDecoration(color: colors.primary,
                  borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: colors.onPrimary, size: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 12),
            child,
          ])),
      ]),
    );
  }
}
