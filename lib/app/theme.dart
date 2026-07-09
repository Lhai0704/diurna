import 'package:flutter/material.dart';

/// Shared type scale for the whole app.
///
/// Chinese UI fonts often only ship Regular/Bold, so mixed Material weights
/// (w400/w500/w700) look uneven. Keep hierarchy by size and color, with at
/// most two weights: regular for body, medium for titles.
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2563EB),
    brightness: Brightness.light,
  );

  // Prefer clear CJK system fonts on Windows, then common cross-platform fallbacks.
  const fontFamily = 'Microsoft YaHei UI';
  const fontFamilyFallback = <String>[
    'Microsoft YaHei',
    'Noto Sans SC',
    'PingFang SC',
    'Segoe UI',
    'sans-serif',
  ];

  TextStyle style(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: 0,
    );
  }

  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

  final textTheme = TextTheme(
    displayLarge: style(28, weight: FontWeight.w500, height: 1.3, color: onSurface),
    displayMedium: style(24, weight: FontWeight.w500, height: 1.3, color: onSurface),
    displaySmall: style(22, weight: FontWeight.w500, height: 1.3, color: onSurface),
    headlineLarge: style(22, weight: FontWeight.w500, height: 1.3, color: onSurface),
    headlineMedium: style(20, weight: FontWeight.w500, height: 1.3, color: onSurface),
    headlineSmall: style(18, weight: FontWeight.w500, height: 1.35, color: onSurface),
    titleLarge: style(17, weight: FontWeight.w500, height: 1.35, color: onSurface),
    titleMedium: style(15, weight: FontWeight.w500, height: 1.35, color: onSurface),
    titleSmall: style(14, weight: FontWeight.w500, height: 1.35, color: onSurface),
    bodyLarge: style(15, height: 1.55, color: onSurface),
    bodyMedium: style(14, height: 1.5, color: onSurface),
    bodySmall: style(12, height: 1.45, color: onSurfaceVariant),
    labelLarge: style(14, weight: FontWeight.w500, height: 1.35, color: onSurface),
    labelMedium: style(12, height: 1.35, color: onSurfaceVariant),
    labelSmall: style(11, height: 1.3, color: onSurfaceVariant),
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    appBarTheme: AppBarTheme(
      titleTextStyle: textTheme.titleLarge,
      toolbarTextStyle: textTheme.bodyMedium,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: textTheme.bodyLarge,
      subtitleTextStyle: textTheme.bodySmall,
    ),
  );
}
