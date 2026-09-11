import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

class AppTheme {
  static const Color bg = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF1E293B);
  static const Color inkSoft = Color(0xFF64748B);
  static const Color accent = Color(0xFFAD0210);
  static const Color accentDark = Color(0xFF8E000C);
  static const Color line = Color(0xFFE2E8F0);
  static const Color debt = Color(0xFFDC2626);
  static const Color debtBg = Color(0xFFFEE2E2);
  static const Color paid = Color(0xFF16A34A);
  static const Color paidBg = Color(0xFFDCFCE7);
  static const Color lunas = Color(0xFF2563EB);
  static const Color lunasBg = Color(0xFFDBEAFE);
  static const Color cardBg = Colors.white;
  static const Color sidebarBg = Color(0xFF6B000A);
  static const Color sidebarActive = Color(0xFFF0444F);

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      primary: accent,
      secondary: accentDark,
      error: debt,
      surface: surface,
    ),
    fontFamily: 'Segoe UI',
    appBarTheme: const AppBarTheme(
      backgroundColor: sidebarBg,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: line, width: 1.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );

  static double gridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 2;
    if (width < 1024) return 3;
    if (width < 1440) return 4;
    return 5;
  }

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1024;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  static bool isHandheld(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static bool isCompact(BuildContext context) =>
      isMobile(context) || (isTablet(context) && isHandheld(context));
}
