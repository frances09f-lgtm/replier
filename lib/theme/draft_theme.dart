import 'package:flutter/material.dart';

/// Design tokens from the approved Replier UI draft (pally.site draft).
/// Light + Dusk palettes, Outfit display font, Figtree body font.
class DraftColors {
  final Color bg, s1, s2, pri, onpri, pc, onpc, tx, mut, out, err, errc, oerr, tc, otc;
  const DraftColors({
    required this.bg, required this.s1, required this.s2,
    required this.pri, required this.onpri, required this.pc, required this.onpc,
    required this.tx, required this.mut, required this.out,
    required this.err, required this.errc, required this.oerr,
    required this.tc, required this.otc,
  });

  static const light = DraftColors(
    bg: Color(0xFFF4FBF8), s1: Color(0xFFE6F1ED), s2: Color(0xFFD6E6E1),
    pri: Color(0xFF006B5E), onpri: Color(0xFFFFFFFF),
    pc: Color(0xFFA0F2E1), onpc: Color(0xFF00201B),
    tx: Color(0xFF151D1B), mut: Color(0xFF3F4946), out: Color(0xFF6F7976),
    err: Color(0xFFBA1A1A), errc: Color(0xFFFFDAD6), oerr: Color(0xFF410002),
    tc: Color(0xFFD3E4F0), otc: Color(0xFF0B1D29),
  );

  static const dusk = DraftColors(
    bg: Color(0xFF1C2B2D), s1: Color(0xFF26383A), s2: Color(0xFF324A4C),
    pri: Color(0xFF7FD8C8), onpri: Color(0xFF00382F),
    pc: Color(0xFF1F5A52), onpc: Color(0xFFB6F2E6),
    tx: Color(0xFFE3EFED), mut: Color(0xFFB3C8C5), out: Color(0xFF86A09C),
    err: Color(0xFFFFB4AB), errc: Color(0xFF5C1A16), oerr: Color(0xFFFFDAD6),
    tc: Color(0xFF33495A), otc: Color(0xFFD3E4F0),
  );

  static DraftColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dusk : light;
}

class DraftText {
  static TextStyle display(double size, Color color,
          {FontWeight weight = FontWeight.w600}) =>
      TextStyle(fontFamily: 'Outfit', fontSize: size, fontWeight: weight, color: color, height: 1.15);

  static TextStyle body(double size, Color color,
          {FontWeight weight = FontWeight.w400}) =>
      TextStyle(fontFamily: 'Figtree', fontSize: size, fontWeight: weight, color: color, height: 1.45);

  static TextStyle eyebrow(Color color) => TextStyle(
      fontFamily: 'Figtree', fontSize: 12.5, fontWeight: FontWeight.w700,
      letterSpacing: 1.6, color: color);
}

ThemeData buildDraftTheme({required bool dark}) {
  final c = dark ? DraftColors.dusk : DraftColors.light;
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Figtree',
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: c.pri, onPrimary: c.onpri,
      primaryContainer: c.pc, onPrimaryContainer: c.onpc,
      secondary: c.s2, onSecondary: c.tx,
      secondaryContainer: c.s1, onSecondaryContainer: c.tx,
      tertiary: c.tc, onTertiary: c.otc,
      tertiaryContainer: c.tc, onTertiaryContainer: c.otc,
      error: c.err, onError: c.onpri,
      errorContainer: c.errc, onErrorContainer: c.oerr,
      surface: c.bg, onSurface: c.tx,
      surfaceContainerHighest: c.s1,
      outline: c.out,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: c.s1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: DraftText.display(22, c.tx),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFFE3EFED) : const Color(0xFF151D1B),
      contentTextStyle: DraftText.body(13.5, dark ? const Color(0xFF151D1B) : Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.bg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.out, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.out, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.pri, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.err, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.err, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onpri : c.s1),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.pri : c.s2),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.pri : c.out),
    ),
    dividerTheme: DividerThemeData(color: c.s2, thickness: 1),
    listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 4)),
  );
}
