// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF7353CD);
  static const Color primaryLight = Color(0xFF9580E8);
  static const Color primaryDark = Color(0xFF5538A0);
  static const Color secondaryColor = Color(0xFFF5F5FA);
  static const Color accentColor = Color(0xFF9580E8);

  static const List<Color> primaryGradient = [
    Color(0xFF7353CD),
    Color(0xFF7E60DB),
    Color(0xFF9580E8),
  ];

  static const Color accent1 = Color(0xFF7353CD);
  static const Color accent2 = Color(0xFF7E60DB);
  static const Color accent3 = Color(0xFF9580E8);

  static const Color darkBackground = Color(0xFF14131A);
  static const Color darkSurface = Color(0xFF1D1C24);
  static const Color darkCard = Color(0xFF1D1C24);
  static const Color darkCardHover = Color(0xFF302F3B);
  static const Color darkText = Color(0xFFECECF3);
  static const Color darkTextSecondary = Color(0xFFC7C6D1);
  static const Color darkTextMuted = Color(0xFF9E9DAA);
  static const Color darkBorder = Color(0xFF302F3B);

  static const Color lightBackground = Color(0xFFFBFAFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1D1C24);
  static const Color lightTextSecondary = Color(0xFF575665);
  static const Color lightTextMuted = Color(0xFF686775);
  static const Color lightBorder = Color(0xFFDCDBE4);

  static const Color success = Color(0xFF1D9D77);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFF43F5E);
  static const Color info = Color(0xFF3B82F6);

  static const Color primary = primaryColor;
  static const Color secondary = secondaryColor;
  static const Color error = danger;
  static const Color blue = Color(0xFF3B82F6);
  static const Color green = Color(0xFF10B981);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color gray = Color(0xFF71717A);
  static const Color orange = Color(0xFFF97316);
  static const Color red = Color(0xFFEF4444);
  static const Color yellow = Color(0xFFFACC15);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color pink = Color(0xFFEC4899);
  static const Color rose = Color(0xFFF43F5E);
  static const Color amber = Color(0xFFF59E0B);
  static const Color emerald = Color(0xFF10B981);
  static const Color indigo = Color(0xFF4F46E5);

  static const Color trainingColor = Color(0xFFEC4899);
  static const Color projectsColor = Color(0xFF8B5CF6);
  static const Color knowledgeColor = Color(0xFF06B6D4);
  static const Color emailColor = Color(0xFFEF4444);
  static const Color pomodoroColor = Color(0xFFF97316);
  static const Color reviewColor = Color(0xFF10B981);
  static const Color schoolColor = Color(0xFF3B82F6);
  static const Color calendarColor = Color(0xFF6366F1);
  static const Color notesColor = Color(0xFFFACC15);

  static const Color glassLight = Color(0x66FFFFFF);
  static const Color glassDark = Color(0x66000000);
  static const Color glassBorderLight = Color(0x33FFFFFF);
  static const Color glassBorderDark = Color(0x1AFFFFFF);
  static const Color glassShadowLight = Color(0x1A000000);
  static const Color glassShadowDark = Color(0x4D000000);

  static const double glassBlurLight = 10.0;
  static const double glassBlurMedium = 12.0;
  static const double glassBlurStrong = 20.0;

  static Widget gradientText(String text, {double fontSize = 36, FontWeight fontWeight = FontWeight.w900, TextAlign? textAlign}) {
    return Builder(builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: isDark
              ? [Colors.white, const Color(0xFFC7C6D1)]
              : [const Color(0xFF1D1C24), const Color(0xFF686775)],
        ).createShader(bounds),
        child: Text(
          text,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: Colors.white,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
      );
    });
  }

  static InputDecoration styledInput({
    String? hint,
    String? label,
    Widget? prefixIcon,
    Widget? suffixIcon,
    required bool isDark,
  }) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark
          ? const Color(0xFF302F3B).withValues(alpha: 0.5)
          : const Color(0xFFECECF3).withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      hintStyle: TextStyle(
        color: isDark ? darkTextMuted : lightTextMuted,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelStyle: TextStyle(
        color: isDark ? darkTextMuted : lightTextMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  static TextStyle sectionLabel(bool isDark) {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: isDark ? darkTextMuted : lightTextMuted,
      letterSpacing: 0.8,
    );
  }

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: darkBackground,
    fontFamily: 'Inter',
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: primaryLight,
      tertiary: success,
      surface: darkSurface,
      onSurface: darkText,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: darkText,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        fontFamily: 'Inter',
      ),
      iconTheme: IconThemeData(color: darkText),
    ),
    cardTheme: CardThemeData(
      color: darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: darkBorder, width: 1),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkSurface,
      indicatorColor: primaryColor.withValues(alpha: 0.1),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          );
        }
        return const TextStyle(
          color: darkTextMuted,
          fontSize: 12,
          fontFamily: 'Inter',
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryColor);
        }
        return const IconThemeData(color: darkTextMuted);
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF302F3B).withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      hintStyle: const TextStyle(color: darkTextMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: darkText, fontWeight: FontWeight.w900, fontSize: 36, letterSpacing: -0.5),
      headlineMedium: TextStyle(color: darkText, fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.3),
      headlineSmall: TextStyle(color: darkText, fontWeight: FontWeight.w600, fontSize: 20),
      titleLarge: TextStyle(color: darkText, fontWeight: FontWeight.w600, fontSize: 18),
      titleMedium: TextStyle(color: darkText, fontWeight: FontWeight.w500, fontSize: 16),
      titleSmall: TextStyle(color: darkTextSecondary, fontSize: 14),
      bodyLarge: TextStyle(color: darkText, fontWeight: FontWeight.w500, fontSize: 16),
      bodyMedium: TextStyle(color: darkTextSecondary, fontWeight: FontWeight.w500, fontSize: 14),
      bodySmall: TextStyle(color: darkTextMuted, fontSize: 12),
      labelSmall: TextStyle(color: darkTextMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
    ),
    dividerColor: darkBorder,
    dialogTheme: DialogThemeData(
      backgroundColor: darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkCard,
      contentTextStyle: const TextStyle(color: darkText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return Colors.transparent;
      }),
      side: const BorderSide(color: darkBorder, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return darkTextMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return darkBorder;
      }),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      titleTextStyle: TextStyle(color: darkText, fontSize: 16, fontFamily: 'Inter'),
      subtitleTextStyle: TextStyle(color: darkTextSecondary, fontSize: 14, fontFamily: 'Inter'),
    ),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: lightBackground,
    fontFamily: 'Inter',
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      secondary: primaryLight,
      tertiary: success,
      surface: lightSurface,
      onSurface: lightText,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: lightText,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        fontFamily: 'Inter',
      ),
      iconTheme: IconThemeData(color: lightText),
    ),
    cardTheme: CardThemeData(
      color: lightCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: lightBorder, width: 1),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: lightSurface,
      indicatorColor: primaryColor.withValues(alpha: 0.1),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          );
        }
        return const TextStyle(
          color: lightTextMuted,
          fontSize: 12,
          fontFamily: 'Inter',
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryColor);
        }
        return const IconThemeData(color: lightTextMuted);
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFECECF3).withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      hintStyle: const TextStyle(color: lightTextMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: lightText, fontWeight: FontWeight.w900, fontSize: 36, letterSpacing: -0.5),
      headlineMedium: TextStyle(color: lightText, fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.3),
      headlineSmall: TextStyle(color: lightText, fontWeight: FontWeight.w600, fontSize: 20),
      titleLarge: TextStyle(color: lightText, fontWeight: FontWeight.w600, fontSize: 18),
      titleMedium: TextStyle(color: lightText, fontWeight: FontWeight.w500, fontSize: 16),
      titleSmall: TextStyle(color: lightTextSecondary, fontSize: 14),
      bodyLarge: TextStyle(color: lightText, fontWeight: FontWeight.w500, fontSize: 16),
      bodyMedium: TextStyle(color: lightTextSecondary, fontWeight: FontWeight.w500, fontSize: 14),
      bodySmall: TextStyle(color: lightTextMuted, fontSize: 12),
      labelSmall: TextStyle(color: lightTextMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
    ),
    dividerColor: lightBorder,
    dialogTheme: DialogThemeData(
      backgroundColor: lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: lightCard,
      contentTextStyle: const TextStyle(color: lightText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return Colors.transparent;
      }),
      side: const BorderSide(color: lightBorder, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return lightTextMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return lightBorder;
      }),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      titleTextStyle: TextStyle(color: lightText, fontSize: 16, fontFamily: 'Inter'),
      subtitleTextStyle: TextStyle(color: lightTextSecondary, fontSize: 14, fontFamily: 'Inter'),
    ),
  );
}

class GradientDecoration extends BoxDecoration {
  const GradientDecoration({
    super.borderRadius,
  }) : super(
          gradient: const LinearGradient(
            colors: AppTheme.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
}
