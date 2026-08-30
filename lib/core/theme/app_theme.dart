import 'package:flutter/material.dart';

/// Impeccable design tokens for Omega — distinctive, not default Material.
/// Inspired by editorial + technical: deep ink, warm accent, generous whitespace.
class AppTheme {
  static const _seed = Color(0xFF1A1A2E); // deep ink
  static const accent = Color(0xFFFF6B6B); // warm coral
  static const accent2 = Color(0xFF4ECDC4); // teal
  static const surface = Color(0xFFFAFAF9);
  static const ink = Color(0xFF0F0F23);
  static const muted = Color(0xFF6B7280);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      primary: _seed,
      secondary: accent,
      tertiary: accent2,
      surface: surface,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      useMaterial3: true,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: ink),
        titleLarge: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: ink),
        titleMedium: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: ink),
        bodyMedium: TextStyle(
            fontSize: 14, height: 1.5, color: Color(0xFF374151)),
        labelLarge: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.6),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: _seed.withValues(alpha: 0.08),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: _seed);
          }
          return const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: muted);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _seed);
          }
          return const IconThemeData(color: muted);
        }),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _seed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
