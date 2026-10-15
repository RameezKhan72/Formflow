import 'package:flutter/material.dart';

/// Design tokens (PRD 3.4). Violet is the brand accent; green is reserved
/// for correct form and red only for corrections (IMP-07).
class FF {
  static const bg = Color(0xFF080B1A);
  static const surface = Color(0xFF141933);
  static const surface2 = Color(0xFF1C2344);
  static const outline = Color(0xFF2A3260);
  static const accent = Color(0xFF7C6CFF);
  static const accentSoft = Color(0xFF2D2870);
  static const good = Color(0xFF2FD27A);
  static const warn = Color(0xFFFFB547);
  static const bad = Color(0xFFFF4D5E);
  static const muscle = Color(0xFFFF6B4A);
  static const text = Color(0xFFEDEFFC);
  static const muted = Color(0xFF959BC2);
  static const bodyFill = Color(0xFFCFD3E6);
  static const bodyShade = Color(0xFF8E94B4);

  static const radius = 16.0;

  static Color scoreColor(double score) => score >= 80 ? good : (score >= 50 ? warn : bad);
  static IconData scoreIcon(double score) =>
      score >= 80 ? Icons.check_circle : (score >= 50 ? Icons.remove_circle : Icons.error);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      surface: surface,
      onSurface: text,
      error: bad,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0C1024),
        indicatorColor: accentSoft,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.selected) ? accent : muted,
            )),
        iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(color: s.contains(WidgetState.selected) ? accent : muted)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(48, 44),
          side: const BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface2,
        selectedColor: accentSoft,
        side: const BorderSide(color: outline),
        labelStyle: const TextStyle(color: text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        labelStyle: const TextStyle(color: muted),
      ),
      dividerTheme: const DividerThemeData(color: outline, thickness: 1),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
      dialogTheme: const DialogThemeData(backgroundColor: surface),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  static const tabular = [FontFeature.tabularFigures()];
}
