import 'package:flutter/material.dart';

/// Design tokens for the Windows-only desktop surface.
///
/// The palette deliberately softens the original Win32 system colors while
/// keeping the familiar gray surfaces, navy selection, and beveled controls.
abstract final class WindowsRetroColors {
  static const desktop = Color(0xFFC6C6C6);
  static const panel = Color(0xFFD4D0C8);
  static const content = Color(0xFFFFFFFF);
  static const contentMuted = Color(0xFFF5F5F3);
  static const highlight = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE8E8E8);
  static const shadow = Color(0xFF808080);
  static const darkShadow = Color(0xFF404040);
  static const grid = Color(0xFFB8B8B8);
  static const text = Color(0xFF202020);
  static const secondaryText = Color(0xFF555555);
  static const activeBlue = Color(0xFF173F8A);
  static const selection = Color(0xFFDCE7F6);
  static const selectedText = Color(0xFFFFFFFF);
}

/// Compact four-panel chrome. Retro keeps Win32 bevels; modern keeps the
/// same layout with hairline borders, rounded corners and a slate header.
class DesktopChrome extends ThemeExtension<DesktopChrome> {
  const DesktopChrome({
    required this.bevel,
    required this.panelRadius,
    required this.controlRadius,
    required this.desktop,
    required this.panel,
    required this.content,
    required this.contentMuted,
    required this.highlight,
    required this.lightBorder,
    required this.shadow,
    required this.darkShadow,
    required this.grid,
    required this.text,
    required this.secondaryText,
    required this.header,
    required this.headerText,
    required this.accent,
    required this.selection,
    required this.selectedText,
    required this.border,
    required this.panelShadow,
  });

  static const retro = DesktopChrome(
    bevel: true,
    panelRadius: 0,
    controlRadius: 0,
    desktop: WindowsRetroColors.desktop,
    panel: WindowsRetroColors.panel,
    content: WindowsRetroColors.content,
    contentMuted: WindowsRetroColors.contentMuted,
    highlight: WindowsRetroColors.highlight,
    lightBorder: WindowsRetroColors.lightBorder,
    shadow: WindowsRetroColors.shadow,
    darkShadow: WindowsRetroColors.darkShadow,
    grid: WindowsRetroColors.grid,
    text: WindowsRetroColors.text,
    secondaryText: WindowsRetroColors.secondaryText,
    header: WindowsRetroColors.activeBlue,
    headerText: WindowsRetroColors.selectedText,
    accent: WindowsRetroColors.activeBlue,
    selection: WindowsRetroColors.selection,
    selectedText: WindowsRetroColors.selectedText,
    border: WindowsRetroColors.shadow,
    panelShadow: [],
  );

  static const modern = DesktopChrome(
    bevel: false,
    panelRadius: 10,
    controlRadius: 6,
    desktop: Color(0xFFD5DCE6),
    panel: Color(0xFFF5F7FA),
    content: Color(0xFFFFFFFF),
    contentMuted: Color(0xFFEEF2F7),
    highlight: Color(0xFFFFFFFF),
    lightBorder: Color(0xFFE8EDF4),
    shadow: Color(0xFF94A3B8),
    darkShadow: Color(0xFF64748B),
    grid: Color(0xFFE2E8F0),
    text: Color(0xFF0F172A),
    secondaryText: Color(0xFF64748B),
    header: Color(0xFF1E293B),
    headerText: Color(0xFFF8FAFC),
    accent: Color(0xFF2563EB),
    selection: Color(0xFFDBEAFE),
    selectedText: Color(0xFFFFFFFF),
    border: Color(0xFFC5D0DC),
    panelShadow: [
      BoxShadow(
        color: Color(0x1A0F172A),
        blurRadius: 12,
        offset: Offset(0, 3),
      ),
    ],
  );

  final bool bevel;
  final double panelRadius;
  final double controlRadius;
  final Color desktop;
  final Color panel;
  final Color content;
  final Color contentMuted;
  final Color highlight;
  final Color lightBorder;
  final Color shadow;
  final Color darkShadow;
  final Color grid;
  final Color text;
  final Color secondaryText;
  final Color header;
  final Color headerText;
  final Color accent;
  final Color selection;
  final Color selectedText;
  final Color border;
  final List<BoxShadow> panelShadow;

  static DesktopChrome of(BuildContext context) {
    return Theme.of(context).extension<DesktopChrome>() ?? DesktopChrome.retro;
  }

  BorderRadius get panelBorderRadius => BorderRadius.circular(panelRadius);

  BorderRadius get controlBorderRadius => BorderRadius.circular(controlRadius);

  @override
  DesktopChrome copyWith({
    bool? bevel,
    double? panelRadius,
    double? controlRadius,
    Color? desktop,
    Color? panel,
    Color? content,
    Color? contentMuted,
    Color? highlight,
    Color? lightBorder,
    Color? shadow,
    Color? darkShadow,
    Color? grid,
    Color? text,
    Color? secondaryText,
    Color? header,
    Color? headerText,
    Color? accent,
    Color? selection,
    Color? selectedText,
    Color? border,
    List<BoxShadow>? panelShadow,
  }) {
    return DesktopChrome(
      bevel: bevel ?? this.bevel,
      panelRadius: panelRadius ?? this.panelRadius,
      controlRadius: controlRadius ?? this.controlRadius,
      desktop: desktop ?? this.desktop,
      panel: panel ?? this.panel,
      content: content ?? this.content,
      contentMuted: contentMuted ?? this.contentMuted,
      highlight: highlight ?? this.highlight,
      lightBorder: lightBorder ?? this.lightBorder,
      shadow: shadow ?? this.shadow,
      darkShadow: darkShadow ?? this.darkShadow,
      grid: grid ?? this.grid,
      text: text ?? this.text,
      secondaryText: secondaryText ?? this.secondaryText,
      header: header ?? this.header,
      headerText: headerText ?? this.headerText,
      accent: accent ?? this.accent,
      selection: selection ?? this.selection,
      selectedText: selectedText ?? this.selectedText,
      border: border ?? this.border,
      panelShadow: panelShadow ?? this.panelShadow,
    );
  }

  @override
  DesktopChrome lerp(ThemeExtension<DesktopChrome>? other, double t) {
    if (other is! DesktopChrome) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}
