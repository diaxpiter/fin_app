// Dark theme with one lime accent — same tokens as ../styles.css.

import 'package:flutter/material.dart';

abstract final class Palette {
  static const bg = Color(0xFF0B0B0C);
  static const surface = Color(0xFF141416);
  static const surface2 = Color(0xFF26262B);
  static const line = Color(0xFF1F1F23);
  static const line2 = Color(0xFF2A2A2F);
  static const text = Color(0xFFF2F1ED);
  static const muted = Color(0xFF8A8A90);
  static const soft = Color(0xFFB8B8BD);
  static const accent = Color(0xFFC8F169);
  static const neg = Color(0xFFFF7A64);
  static const warn = Color(0xFFE9B44C);
  static const planned = Color(0xFF3A3A40);
  static const fallbackDot = Color(0xFF9A9AA1);
}

Color hexColor(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

// Monospace with tabular figures so amounts line up in columns.
TextStyle mono({double size = 15, FontWeight weight = FontWeight.w400, Color color = Palette.text}) => TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'SF Mono', 'Consolas', 'Roboto Mono', 'Courier New'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Palette.accent, brightness: Brightness.dark).copyWith(
    primary: Palette.accent,
    onPrimary: Palette.bg,
    secondaryContainer: Palette.surface2,
    onSecondaryContainer: Palette.text,
    surface: Palette.bg,
    onSurface: Palette.text,
    onSurfaceVariant: Palette.muted,
    surfaceContainerLowest: Palette.bg,
    surfaceContainerLow: Palette.surface,
    surfaceContainer: Palette.surface,
    surfaceContainerHigh: Palette.surface,
    surfaceContainerHighest: Palette.surface2,
    surfaceTint: Colors.transparent,
    outline: Palette.line2,
    outlineVariant: Palette.line,
    error: Palette.neg,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.bg,
    dividerColor: Palette.line,
    textTheme: base.textTheme.apply(bodyColor: Palette.text, displayColor: Palette.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.bg,
      foregroundColor: Palette.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.bg,
      indicatorColor: Palette.surface2,
      surfaceTintColor: Colors.transparent,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? Palette.text : Palette.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Palette.text : Palette.muted)),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Palette.bg,
      indicatorColor: Palette.surface2,
      selectedIconTheme: IconThemeData(color: Palette.text),
      unselectedIconTheme: IconThemeData(color: Palette.muted),
      selectedLabelTextStyle: TextStyle(color: Palette.text, fontSize: 13, fontWeight: FontWeight.w500),
      unselectedLabelTextStyle: TextStyle(color: Palette.muted, fontSize: 13, fontWeight: FontWeight.w500),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Palette.accent,
      foregroundColor: Palette.bg,
      elevation: 0,
      highlightElevation: 0,
      shape: CircleBorder(),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.text,
      contentTextStyle: TextStyle(color: Palette.bg, fontSize: 14, fontWeight: FontWeight.w500),
      width: 360,
    ),
  );
}
