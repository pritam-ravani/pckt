import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';

abstract final class AppTheme {
  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    bg: Palette.ink,
    surface: Palette.inkRaised,
    surfaceHigh: Palette.inkHigh,
    line: Palette.inkLine,
    onBg: const Color(0xFFF2F3F5),
    muted: const Color(0xFF8A8F9C),
  );

  static ThemeData light() => _build(
    brightness: Brightness.light,
    bg: Palette.paper,
    surface: Palette.paperRaised,
    surfaceHigh: Palette.paperHigh,
    line: Palette.paperLine,
    onBg: const Color(0xFF15171C),
    muted: const Color(0xFF6B6F78),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surfaceHigh,
    required Color line,
    required Color onBg,
    required Color muted,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: Palette.violet,
      onPrimary: Colors.white,
      secondary: Palette.mint,
      onSecondary: const Color(0xFF052E1C),
      tertiary: Palette.amber,
      onTertiary: Colors.black,
      error: Palette.coral,
      onError: Colors.white,
      surface: bg,
      onSurface: onBg,
      onSurfaceVariant: muted,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      outline: muted,
      outlineVariant: line,
    );

    final base = brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    final body = GoogleFonts.interTextTheme(base.textTheme);
    final display = GoogleFonts.manropeTextTheme(base.textTheme);
    final text = body
        .copyWith(
          displayLarge: display.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5),
          displayMedium: display.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2),
          displaySmall: display.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
          headlineMedium: display.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
          headlineSmall: display.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
          titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: onBg, displayColor: onBg);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: line),
        ),
      ),
      dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: Palette.violet.withValues(alpha: 0.18),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: text.labelLarge,
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Palette.violet.withValues(alpha: 0.2),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? onBg : muted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: line,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: text.titleMedium,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Palette.violet,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
