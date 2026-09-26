// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

class AppPalette {
  AppPalette._();

  static const Color pine = Color(0xFF2E3A2F);
  static const Color pineRaised = Color(0xFF3A4E37);
  static const Color pineBright = Color(0xFF5A7F5E);
  static const Color pineMist = Color(0xFF7C9C80);
  static const Color chalk = Color(0xFFF8F6EE);
  static const Color sand = Color(0xFFE7C694);
  static const Color sandDeep = Color(0xFFD4AE76);
  static const Color sage = Color(0xFF6B7F5B);
  static const Color sageDark = Color(0xFF86A36F);
  static const Color sageInk = Color(0xFF4A633E);
  static const Color sageSoft = Color(0xFFE2ECD6);
  static const Color sageSoftDark = Color(0xFF283B29);
  static const Color terracotta = Color(0xFFC96F4F);
  static const Color terracottaDark = Color(0xFFDD8461);
  static const Color terracottaInk = Color(0xFF944730);
  static const Color terracottaSoft = Color(0xFFFDEFE7);
  static const Color terracottaSoftDark = Color(0xFF41261C);
  static const Color amber = Color(0xFFEBB353);
  static const Color amberSoft = Color(0xFFF8EED7);
  static const Color lake = Color(0xFF2A7B9F);

  static const Color canvas = Color(0xFFF8F6EE);
  static const Color surface = Color(0xFFFCFCF9);
  static const Color sunken = Color(0xFFF2EFE6);
  static const Color press = Color(0xFFECE8DE);
  static const Color overlay = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE4DFD4);
  static const Color lineSoft = Color(0xFFECE8DE);
  static const Color lineStrong = Color(0xFFD1CEC1);
  static const Color ink = Color(0xFF2E3A2F);
  static const Color inkSoft = Color(0xFF4C564A);
  static const Color inkMuted = Color(0xFF5E665B);
  static const Color ring = Color(0xFF7D8276);

  static const Color canvasDark = Color(0xFF0F1410);
  static const Color surfaceDark = Color(0xFF131914);
  static const Color sunkenDark = Color(0xFF0F1410);
  static const Color hoverDark = Color(0xFF242B24);
  static const Color pressDark = Color(0xFF2C322C);
  static const Color overlayDark = Color(0xFF242B24);
  static const Color lineDark = Color(0xFF2C322C);
  static const Color lineSoftDark = Color(0xFF242B24);
  static const Color lineStrongDark = Color(0xFF3E453D);
  static const Color inkDark = Color(0xFFEDEBE4);
  static const Color inkSoftDark = Color(0xFFD3D1C8);
  static const Color inkMutedDark = Color(0xFFB8B8AF);
  static const Color ringDark = Color(0xFF777C72);
  static const Color heroDark = Color(0xFF28402F);
  static const Color brandDark = Color(0xFF2A3D2D);

  static const Color rose = Color(0xFFC1657E);
  static const Color ochre = Color(0xFF9A6A1E);
  static const Color olive = Color(0xFF6E6D0A);
  static const Color moss = Color(0xFF669649);
  static const Color jade = Color(0xFF0D7C59);
  static const Color teal = Color(0xFF139999);
  static const Color lakeHue = Color(0xFF0C7491);
  static const Color slate = Color(0xFF5188CD);
  static const Color iris = Color(0xFF635DAB);
  static const Color orchid = Color(0xFF984979);
  static const Color brick = Color(0xFFA34943);
  static const Color plum = Color(0xFFA16FB8);
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Bricolage Grotesque';

  static bool _dark = false;

  static void useBrightness(Brightness brightness) => _dark = brightness == Brightness.dark;

  static Color get primaryColor => _dark ? AppPalette.pineBright : AppPalette.pine;
  static Color get primaryLight => _dark ? AppPalette.pineMist : AppPalette.pineRaised;
  static Color get primaryDark => _dark ? AppPalette.brandDark : AppPalette.pine;
  static Color get accentColor => primaryLight;
  static Color get primary => primaryColor;
  static Color get accent1 => primaryColor;
  static Color get accent2 => primaryLight;
  static Color get accent3 => primaryLight;
  static List<Color> get primaryGradient => [primaryColor, primaryColor];

  static const Color secondaryColor = AppPalette.sunken;
  static const Color secondary = secondaryColor;

  static const Color darkBackground = AppPalette.canvasDark;
  static const Color darkSurface = AppPalette.surfaceDark;
  static const Color darkCard = AppPalette.surfaceDark;
  static const Color darkCardHover = AppPalette.hoverDark;
  static const Color darkText = AppPalette.inkDark;
  static const Color darkTextSecondary = AppPalette.inkSoftDark;
  static const Color darkTextMuted = AppPalette.inkMutedDark;
  static const Color darkBorder = AppPalette.lineDark;

  static const Color lightBackground = AppPalette.canvas;
  static const Color lightSurface = AppPalette.surface;
  static const Color lightCard = AppPalette.surface;
  static const Color lightText = AppPalette.ink;
  static const Color lightTextSecondary = AppPalette.inkSoft;
  static const Color lightTextMuted = AppPalette.inkMuted;
  static const Color lightBorder = AppPalette.line;

  static const Color success = AppPalette.sage;
  static const Color warning = AppPalette.amber;
  static const Color danger = AppPalette.terracotta;
  static const Color info = AppPalette.lake;
  static const Color error = danger;

  static const Color blue = AppPalette.slate;
  static const Color green = AppPalette.sage;
  static const Color purple = AppPalette.iris;
  static const Color gray = AppPalette.ring;
  static const Color orange = AppPalette.ochre;
  static const Color red = AppPalette.terracotta;
  static const Color yellow = AppPalette.sand;
  static const Color cyan = AppPalette.teal;
  static const Color pink = AppPalette.rose;
  static const Color rose = AppPalette.rose;
  static const Color amber = AppPalette.amber;
  static const Color emerald = AppPalette.jade;
  static const Color indigo = AppPalette.iris;

  static const Color trainingColor = AppPalette.rose;
  static const Color projectsColor = AppPalette.plum;
  static const Color emailColor = AppPalette.brick;
  static const Color pomodoroColor = AppPalette.ochre;
  static const Color reviewColor = AppPalette.moss;
  static const Color schoolColor = AppPalette.slate;
  static const Color calendarColor = AppPalette.lakeHue;
  static const Color notesColor = AppPalette.sandDeep;

  static const Color glassLight = AppPalette.surface;
  static const Color glassDark = AppPalette.surfaceDark;
  static const Color glassBorderLight = AppPalette.line;
  static const Color glassBorderDark = AppPalette.lineDark;
  static const Color glassShadowLight = Color(0x00000000);
  static const Color glassShadowDark = Color(0x00000000);

  static const double glassBlurLight = 0;
  static const double glassBlurMedium = 0;
  static const double glassBlurStrong = 0;

  static Widget gradientText(String text, {double fontSize = 36, FontWeight fontWeight = FontWeight.w700, TextAlign? textAlign}) {
    return Builder(builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Text(
        text,
        textAlign: textAlign,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize >= 34 ? 30 : fontSize,
          fontWeight: fontWeight.value > 700 ? FontWeight.w700 : fontWeight,
          color: isDark ? darkText : lightText,
          letterSpacing: -0.4,
          height: 1.15,
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
    final line = isDark ? AppPalette.lineDark : AppPalette.line;
    return InputDecoration(
      hintText: hint,
      labelText: label,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? AppPalette.surfaceDark : AppPalette.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? AppPalette.inkDark : AppPalette.ink, width: 1.5),
      ),
      hintStyle: TextStyle(color: isDark ? darkTextMuted : lightTextMuted, fontSize: 15, fontWeight: FontWeight.w400),
      labelStyle: TextStyle(color: isDark ? darkTextMuted : lightTextMuted, fontSize: 13, fontWeight: FontWeight.w500),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  static TextStyle sectionLabel(bool isDark) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: isDark ? darkTextMuted : lightTextMuted,
    );
  }

  static final ThemeData darkTheme = _build(Brightness.dark);
  static final ThemeData lightTheme = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? AppPalette.canvasDark : AppPalette.canvas;
    final surface = dark ? AppPalette.surfaceDark : AppPalette.surface;
    final overlay = dark ? AppPalette.overlayDark : AppPalette.overlay;
    final sunken = dark ? AppPalette.sunkenDark : AppPalette.sunken;
    final line = dark ? AppPalette.lineDark : AppPalette.line;
    final lineSoft = dark ? AppPalette.lineSoftDark : AppPalette.lineSoft;
    final ink = dark ? AppPalette.inkDark : AppPalette.ink;
    final inkSoft = dark ? AppPalette.inkSoftDark : AppPalette.inkSoft;
    final inkMuted = dark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
    final brand = dark ? AppPalette.brandDark : AppPalette.pine;
    final onBrand = dark ? AppPalette.inkDark : AppPalette.chalk;
    final accent = dark ? AppPalette.pineBright : AppPalette.pine;
    final done = dark ? AppPalette.sageDark : AppPalette.sage;
    final urgent = dark ? AppPalette.terracottaDark : AppPalette.terracotta;
    final ring = dark ? AppPalette.ringDark : AppPalette.ring;
    const pill = StadiumBorder();

    TextStyle t(double size, FontWeight weight, Color color, {double height = 1.4, double spacing = 0}) =>
        TextStyle(fontFamily: fontFamily, fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: dark ? Colors.white : AppPalette.chalk,
      primaryContainer: dark ? AppPalette.heroDark : AppPalette.sageSoft,
      onPrimaryContainer: ink,
      secondary: dark ? AppPalette.sand : AppPalette.pineRaised,
      onSecondary: dark ? AppPalette.pine : AppPalette.chalk,
      secondaryContainer: dark ? AppPalette.hoverDark : AppPalette.sunken,
      onSecondaryContainer: ink,
      tertiary: done,
      onTertiary: dark ? AppPalette.canvasDark : Colors.white,
      tertiaryContainer: dark ? AppPalette.sageSoftDark : AppPalette.sageSoft,
      onTertiaryContainer: dark ? const Color(0xFFAFC798) : AppPalette.sageInk,
      error: urgent,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      surfaceContainerLowest: canvas,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: sunken,
      surfaceContainerHighest: dark ? AppPalette.pressDark : AppPalette.press,
      outline: dark ? AppPalette.lineStrongDark : AppPalette.lineStrong,
      outlineVariant: line,
      inverseSurface: dark ? AppPalette.inkDark : AppPalette.pine,
      onInverseSurface: dark ? AppPalette.canvasDark : AppPalette.chalk,
      inversePrimary: dark ? AppPalette.pine : AppPalette.sand,
      shadow: const Color(0xFF14201A),
      scrim: const Color(0xFF0B120D),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      primaryColor: accent,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      fontFamily: fontFamily,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: lineSoft,
      dividerTheme: DividerThemeData(color: lineSoft, thickness: 1, space: 1),
      textTheme: TextTheme(
        displayLarge: t(44, FontWeight.w700, ink, height: 1.1, spacing: -0.8),
        displayMedium: t(44, FontWeight.w700, ink, height: 1.1, spacing: -0.8),
        displaySmall: t(30, FontWeight.w700, ink, height: 1.15, spacing: -0.5),
        headlineLarge: t(30, FontWeight.w700, ink, height: 1.15, spacing: -0.5),
        headlineMedium: t(22, FontWeight.w600, ink, height: 1.25, spacing: -0.3),
        headlineSmall: t(18, FontWeight.w600, ink, height: 1.3, spacing: -0.2),
        titleLarge: t(18, FontWeight.w600, ink, height: 1.3, spacing: -0.2),
        titleMedium: t(15, FontWeight.w600, ink),
        titleSmall: t(13, FontWeight.w500, inkSoft),
        bodyLarge: t(15, FontWeight.w400, ink, height: 1.5),
        bodyMedium: t(15, FontWeight.w400, inkSoft, height: 1.5),
        bodySmall: t(13, FontWeight.w400, inkMuted),
        labelLarge: t(15, FontWeight.w600, ink),
        labelMedium: t(13, FontWeight.w500, inkSoft),
        labelSmall: t(12, FontWeight.w500, inkMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: t(22, FontWeight.w600, ink, height: 1.25, spacing: -0.3),
        iconTheme: IconThemeData(color: ink),
        actionsIconTheme: IconThemeData(color: inkSoft),
      ),
      iconTheme: IconThemeData(color: inkSoft),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: line)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark ? AppPalette.hoverDark : AppPalette.sunken,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected)
            ? t(12, FontWeight.w600, ink)
            : t(12, FontWeight.w500, inkMuted)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(color: states.contains(WidgetState.selected) ? ink : inkMuted)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: onBrand,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: pill,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: onBrand,
          shape: pill,
          textStyle: t(15, FontWeight.w600, onBrand),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: onBrand,
          elevation: 0,
          shape: pill,
          textStyle: t(15, FontWeight.w600, onBrand),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: line),
          shape: pill,
          textStyle: t(15, FontWeight.w600, ink),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink, shape: pill, textStyle: t(15, FontWeight.w600, ink)),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: inkSoft)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ink, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: urgent)),
        hintStyle: t(15, FontWeight.w400, inkMuted),
        labelStyle: t(15, FontWeight.w500, inkMuted),
        floatingLabelStyle: t(13, FontWeight.w500, inkSoft),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: dark ? AppPalette.hoverDark : AppPalette.sunken,
        side: BorderSide(color: line),
        shape: pill,
        labelStyle: t(13, FontWeight.w500, inkSoft),
        secondaryLabelStyle: t(13, FontWeight.w600, ink),
        checkmarkColor: ink,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: inkMuted,
        indicatorColor: ink,
        dividerColor: Colors.transparent,
        labelStyle: t(15, FontWeight.w600, ink),
        unselectedLabelStyle: t(15, FontWeight.w500, inkMuted),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: overlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: t(18, FontWeight.w600, ink, height: 1.3),
        contentTextStyle: t(15, FontWeight.w400, inkSoft, height: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: line)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: overlay,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: overlay,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        dragHandleColor: dark ? AppPalette.lineStrongDark : AppPalette.lineStrong,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: overlay,
        surfaceTintColor: Colors.transparent,
        textStyle: t(15, FontWeight.w400, ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: line)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? AppPalette.inkDark : AppPalette.pine,
        contentTextStyle: t(15, FontWeight.w500, dark ? AppPalette.canvasDark : AppPalette.chalk),
        actionTextColor: dark ? AppPalette.pine : AppPalette.sand,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? done : Colors.transparent),
        checkColor: WidgetStateProperty.all(dark ? AppPalette.canvasDark : Colors.white),
        side: BorderSide(color: ring, width: 1.5),
        shape: const CircleBorder(),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? ink : ring)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? onBrand : (dark ? AppPalette.inkMutedDark : Colors.white)),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? (dark ? AppPalette.pineBright : AppPalette.pine) : (dark ? AppPalette.pressDark : AppPalette.lineStrong)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(activeTrackColor: accent, thumbColor: accent, inactiveTrackColor: line, overlayColor: accent.withValues(alpha: .12)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: done, linearTrackColor: line, circularTrackColor: line),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: inkSoft,
        textColor: ink,
        titleTextStyle: t(15, FontWeight.w500, ink),
        subtitleTextStyle: t(13, FontWeight.w400, inkMuted),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: dark ? AppPalette.inkDark : AppPalette.pine, borderRadius: BorderRadius.circular(8)),
        textStyle: t(13, FontWeight.w500, dark ? AppPalette.canvasDark : AppPalette.chalk),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ink,
        selectionColor: dark ? const Color(0x59BFAE95) : const Color(0x99D9C9B2),
        selectionHandleColor: ink,
      ),
    );
  }
}

class GradientDecoration extends BoxDecoration {
  GradientDecoration({super.borderRadius}) : super(color: AppTheme.primaryColor);
}
