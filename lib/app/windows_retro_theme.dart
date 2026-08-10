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

abstract final class WindowsRetroMetrics {
  static const space2 = 2.0;
  static const space4 = 4.0;
  static const space6 = 6.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const panelHeaderHeight = 34.0;
  static const toolbarButtonSize = 26.0;
  static const pushButtonHeight = 28.0;
}

ThemeData buildWindowsRetroTheme(ThemeData base) {
  final colorScheme = base.colorScheme.copyWith(
    primary: WindowsRetroColors.activeBlue,
    onPrimary: WindowsRetroColors.selectedText,
    primaryContainer: WindowsRetroColors.selection,
    onPrimaryContainer: WindowsRetroColors.text,
    secondary: WindowsRetroColors.activeBlue,
    onSecondary: WindowsRetroColors.selectedText,
    secondaryContainer: WindowsRetroColors.selection,
    onSecondaryContainer: WindowsRetroColors.text,
    tertiary: WindowsRetroColors.activeBlue,
    onTertiary: WindowsRetroColors.selectedText,
    tertiaryContainer: WindowsRetroColors.selection,
    onTertiaryContainer: WindowsRetroColors.text,
    surface: WindowsRetroColors.panel,
    onSurface: WindowsRetroColors.text,
    onSurfaceVariant: WindowsRetroColors.secondaryText,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: WindowsRetroColors.content,
    surfaceContainerLow: WindowsRetroColors.contentMuted,
    surfaceContainer: WindowsRetroColors.panel,
    surfaceContainerHigh: WindowsRetroColors.desktop,
    outline: WindowsRetroColors.shadow,
    outlineVariant: WindowsRetroColors.grid,
  );

  TextStyle? compact(TextStyle? style, double size, {FontWeight? weight}) {
    return style?.copyWith(
      fontSize: size,
      fontWeight: weight,
      height: 1.3,
      color: WindowsRetroColors.text,
      letterSpacing: 0,
    );
  }

  final textTheme = base.textTheme.copyWith(
    titleLarge: compact(base.textTheme.titleLarge, 16, weight: FontWeight.w500),
    titleMedium: compact(
      base.textTheme.titleMedium,
      14,
      weight: FontWeight.w500,
    ),
    titleSmall: compact(base.textTheme.titleSmall, 13, weight: FontWeight.w500),
    bodyLarge: compact(base.textTheme.bodyLarge, 14),
    bodyMedium: compact(base.textTheme.bodyMedium, 13),
    bodySmall: compact(
      base.textTheme.bodySmall,
      12,
    )?.copyWith(color: WindowsRetroColors.secondaryText),
    labelLarge: compact(base.textTheme.labelLarge, 13, weight: FontWeight.w500),
    labelMedium: compact(
      base.textTheme.labelMedium,
      12,
    )?.copyWith(color: WindowsRetroColors.secondaryText),
    labelSmall: compact(
      base.textTheme.labelSmall,
      11,
    )?.copyWith(color: WindowsRetroColors.secondaryText),
  );

  const squareShape = RoundedRectangleBorder();
  return base.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: WindowsRetroColors.desktop,
    canvasColor: WindowsRetroColors.content,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    hoverColor: WindowsRetroColors.selection,
    highlightColor: Colors.transparent,
    dividerColor: WindowsRetroColors.shadow,
    dividerTheme: const DividerThemeData(
      color: WindowsRetroColors.shadow,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: WindowsRetroColors.text, size: 18),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.square(26)),
        maximumSize: const WidgetStatePropertyAll(Size.square(28)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(squareShape),
        foregroundColor: const WidgetStatePropertyAll(WindowsRetroColors.text),
        overlayColor: const WidgetStatePropertyAll(
          WindowsRetroColors.selection,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 28)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(squareShape),
        foregroundColor: const WidgetStatePropertyAll(WindowsRetroColors.text),
        backgroundColor: const WidgetStatePropertyAll(WindowsRetroColors.panel),
        side: const WidgetStatePropertyAll(
          BorderSide(color: WindowsRetroColors.shadow),
        ),
        overlayColor: const WidgetStatePropertyAll(
          WindowsRetroColors.selection,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 28)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(squareShape),
        backgroundColor: const WidgetStatePropertyAll(
          WindowsRetroColors.activeBlue,
        ),
        foregroundColor: const WidgetStatePropertyAll(
          WindowsRetroColors.selectedText,
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: WindowsRetroColors.content,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      border: OutlineInputBorder(borderRadius: BorderRadius.zero),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: WindowsRetroColors.shadow),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: WindowsRetroColors.activeBlue),
      ),
    ),
    cardTheme: const CardThemeData(
      color: WindowsRetroColors.content,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: squareShape,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: WindowsRetroColors.panel,
      elevation: 4,
      shape: squareShape,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: WindowsRetroColors.panel,
      elevation: 4,
      menuPadding: EdgeInsets.all(2),
      shape: squareShape,
      textStyle: TextStyle(fontSize: 12, color: WindowsRetroColors.text),
    ),
    checkboxTheme: CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: const RoundedRectangleBorder(),
      side: const BorderSide(color: WindowsRetroColors.darkShadow),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? WindowsRetroColors.activeBlue
            : WindowsRetroColors.content,
      ),
      checkColor: const WidgetStatePropertyAll(WindowsRetroColors.selectedText),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: WindowsRetroColors.activeBlue,
      selectionColor: WindowsRetroColors.selection,
      selectionHandleColor: WindowsRetroColors.activeBlue,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: WindowsRetroColors.activeBlue,
      linearTrackColor: WindowsRetroColors.contentMuted,
      circularTrackColor: WindowsRetroColors.contentMuted,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFE1),
        border: Border.all(color: WindowsRetroColors.darkShadow),
      ),
      textStyle: textTheme.labelSmall?.copyWith(color: WindowsRetroColors.text),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
}

enum RetroBevelKind { raised, sunken }

class RetroBevel extends StatelessWidget {
  const RetroBevel({
    required this.child,
    this.kind = RetroBevelKind.raised,
    this.color = WindowsRetroColors.panel,
    this.depth = 1,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final RetroBevelKind kind;
  final Color color;
  final int depth;
  final EdgeInsetsGeometry padding;

  Border _border({required bool inner}) {
    final raised = kind == RetroBevelKind.raised;
    final topLeft = raised
        ? (inner
              ? WindowsRetroColors.lightBorder
              : WindowsRetroColors.highlight)
        : (inner ? WindowsRetroColors.darkShadow : WindowsRetroColors.shadow);
    final bottomRight = raised
        ? (inner ? WindowsRetroColors.shadow : WindowsRetroColors.darkShadow)
        : (inner
              ? WindowsRetroColors.highlight
              : WindowsRetroColors.lightBorder);
    return Border(
      left: BorderSide(color: topLeft),
      top: BorderSide(color: topLeft),
      right: BorderSide(color: bottomRight),
      bottom: BorderSide(color: bottomRight),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget result = Padding(padding: padding, child: child);
    if (depth > 1) {
      result = DecoratedBox(
        decoration: BoxDecoration(color: color, border: _border(inner: true)),
        child: Padding(padding: const EdgeInsets.all(1), child: result),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: color, border: _border(inner: false)),
      child: Padding(padding: const EdgeInsets.all(1), child: result),
    );
  }
}

class RetroPanel extends StatelessWidget {
  const RetroPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RetroBevel(
      child: ColoredBox(color: WindowsRetroColors.panel, child: child),
    );
  }
}

class RetroSectionHeader extends StatelessWidget {
  const RetroSectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WindowsRetroMetrics.panelHeaderHeight,
      child: ColoredBox(
        color: WindowsRetroColors.activeBlue,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: WindowsRetroColors.selectedText,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class RetroToolbarButton extends StatefulWidget {
  const RetroToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.alwaysRaised = true,
    this.size = WindowsRetroMetrics.toolbarButtonSize,
    super.key,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool alwaysRaised;
  final double size;

  @override
  State<RetroToolbarButton> createState() => _RetroToolbarButtonState();
}

class _RetroToolbarButtonState extends State<RetroToolbarButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final showBevel = widget.alwaysRaised || _hovered || _focused || _pressed;
    final chrome = showBevel
        ? RetroBevel(
            kind: _pressed ? RetroBevelKind.sunken : RetroBevelKind.raised,
            color: WindowsRetroColors.panel,
            child: Center(child: widget.icon),
          )
        : Center(child: widget.icon);

    return Tooltip(
      message: widget.tooltip,
      child: SizedBox.square(
        dimension: widget.size,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: enabled,
            onTap: widget.onPressed,
            onHover: enabled
                ? (value) => setState(() => _hovered = value)
                : null,
            onFocusChange: enabled
                ? (value) => setState(() => _focused = value)
                : null,
            onHighlightChanged: enabled
                ? (value) => setState(() => _pressed = value)
                : null,
            child: IconTheme.merge(
              data: IconThemeData(
                size: 16,
                color: enabled
                    ? WindowsRetroColors.text
                    : WindowsRetroColors.shadow,
              ),
              child: chrome,
            ),
          ),
        ),
      ),
    );
  }
}

class RetroPushButton extends StatefulWidget {
  const RetroPushButton({
    required this.onPressed,
    required this.child,
    this.minWidth = 78,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double minWidth;

  @override
  State<RetroPushButton> createState() => _RetroPushButtonState();
}

class _RetroPushButtonState extends State<RetroPushButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minWidth,
          minHeight: WindowsRetroMetrics.pushButtonHeight,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: enabled,
            onTap: widget.onPressed,
            onHighlightChanged: enabled
                ? (value) => setState(() => _pressed = value)
                : null,
            child: RetroBevel(
              kind: _pressed ? RetroBevelKind.sunken : RetroBevelKind.raised,
              color: WindowsRetroColors.panel,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: enabled
                      ? WindowsRetroColors.text
                      : WindowsRetroColors.shadow,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 15,
                    color: enabled
                        ? WindowsRetroColors.text
                        : WindowsRetroColors.shadow,
                  ),
                  child: Center(child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
