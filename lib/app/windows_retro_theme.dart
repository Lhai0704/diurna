import 'package:diurna/app/desktop_chrome.dart';
import 'package:flutter/material.dart';

export 'package:diurna/app/desktop_chrome.dart';

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
  return buildDesktopTheme(base, DesktopChrome.retro);
}

ThemeData buildModernDesktopTheme(ThemeData base) {
  return buildDesktopTheme(base, DesktopChrome.modern);
}

ThemeData buildDesktopTheme(ThemeData base, DesktopChrome chrome) {
  final colorScheme = base.colorScheme.copyWith(
    primary: chrome.accent,
    onPrimary: chrome.selectedText,
    primaryContainer: chrome.selection,
    onPrimaryContainer: chrome.text,
    secondary: chrome.accent,
    onSecondary: chrome.selectedText,
    secondaryContainer: chrome.selection,
    onSecondaryContainer: chrome.text,
    tertiary: chrome.accent,
    onTertiary: chrome.selectedText,
    tertiaryContainer: chrome.selection,
    onTertiaryContainer: chrome.text,
    surface: chrome.panel,
    onSurface: chrome.text,
    onSurfaceVariant: chrome.secondaryText,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: chrome.content,
    surfaceContainerLow: chrome.contentMuted,
    surfaceContainer: chrome.panel,
    surfaceContainerHigh: chrome.desktop,
    outline: chrome.border,
    outlineVariant: chrome.grid,
  );

  TextStyle? compact(TextStyle? style, double size, {FontWeight? weight}) {
    return style?.copyWith(
      fontSize: size,
      fontWeight: weight,
      height: 1.3,
      color: chrome.text,
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
    )?.copyWith(color: chrome.secondaryText),
    labelLarge: compact(base.textTheme.labelLarge, 13, weight: FontWeight.w500),
    labelMedium: compact(
      base.textTheme.labelMedium,
      12,
    )?.copyWith(color: chrome.secondaryText),
    labelSmall: compact(
      base.textTheme.labelSmall,
      11,
    )?.copyWith(color: chrome.secondaryText),
  );

  final shape = RoundedRectangleBorder(
    borderRadius: chrome.controlBorderRadius,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: chrome.controlBorderRadius,
    borderSide: BorderSide(color: chrome.border),
  );
  return base.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: chrome.desktop,
    canvasColor: chrome.content,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: chrome.bevel
        ? NoSplash.splashFactory
        : InkRipple.splashFactory,
    hoverColor: chrome.selection,
    highlightColor: Colors.transparent,
    dividerColor: chrome.border,
    dividerTheme: DividerThemeData(
      color: chrome.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: chrome.text, size: 18),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.square(26)),
        maximumSize: const WidgetStatePropertyAll(Size.square(28)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(shape),
        foregroundColor: WidgetStatePropertyAll(chrome.text),
        overlayColor: WidgetStatePropertyAll(chrome.selection),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 28)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(shape),
        foregroundColor: WidgetStatePropertyAll(chrome.text),
        backgroundColor: WidgetStatePropertyAll(chrome.panel),
        side: WidgetStatePropertyAll(BorderSide(color: chrome.border)),
        overlayColor: WidgetStatePropertyAll(chrome.selection),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 28)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(shape),
        backgroundColor: WidgetStatePropertyAll(chrome.accent),
        foregroundColor: WidgetStatePropertyAll(chrome.selectedText),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: chrome.content,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: chrome.controlBorderRadius,
        borderSide: BorderSide(color: chrome.accent),
      ),
    ),
    cardTheme: CardThemeData(
      color: chrome.content,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: chrome.panel,
      elevation: chrome.bevel ? 4 : 8,
      shape: RoundedRectangleBorder(borderRadius: chrome.panelBorderRadius),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: chrome.panel,
      elevation: chrome.bevel ? 4 : 8,
      menuPadding: const EdgeInsets.all(2),
      shape: shape,
      textStyle: TextStyle(fontSize: 12, color: chrome.text),
    ),
    checkboxTheme: CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.bevel ? 0 : 4),
      ),
      side: BorderSide(color: chrome.darkShadow),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? chrome.accent
            : chrome.content,
      ),
      checkColor: WidgetStatePropertyAll(chrome.selectedText),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: chrome.accent,
      selectionColor: chrome.selection,
      selectionHandleColor: chrome.accent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: chrome.accent,
      linearTrackColor: chrome.contentMuted,
      circularTrackColor: chrome.contentMuted,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: chrome.bevel
          ? BoxDecoration(
              color: const Color(0xFFFFFFE1),
              border: Border.all(color: chrome.darkShadow),
            )
          : BoxDecoration(
              color: chrome.header,
              borderRadius: chrome.controlBorderRadius,
            ),
      textStyle: textTheme.labelSmall?.copyWith(
        color: chrome.bevel ? chrome.text : chrome.headerText,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    extensions: [chrome],
  );
}

enum RetroBevelKind { raised, sunken }

class RetroBevel extends StatelessWidget {
  const RetroBevel({
    required this.child,
    this.kind = RetroBevelKind.raised,
    this.color,
    this.depth = 1,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final RetroBevelKind kind;
  final Color? color;
  final int depth;
  final EdgeInsetsGeometry padding;

  Border _border(DesktopChrome chrome, {required bool inner}) {
    final raised = kind == RetroBevelKind.raised;
    final topLeft = raised
        ? (inner ? chrome.lightBorder : chrome.highlight)
        : (inner ? chrome.darkShadow : chrome.shadow);
    final bottomRight = raised
        ? (inner ? chrome.shadow : chrome.darkShadow)
        : (inner ? chrome.highlight : chrome.lightBorder);
    return Border(
      left: BorderSide(color: topLeft),
      top: BorderSide(color: topLeft),
      right: BorderSide(color: bottomRight),
      bottom: BorderSide(color: bottomRight),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chrome = DesktopChrome.of(context);
    final fill = color ?? chrome.panel;
    if (!chrome.bevel) {
      final sunken = kind == RetroBevelKind.sunken;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: chrome.controlBorderRadius,
          border: Border.all(color: chrome.border),
          boxShadow: sunken
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x140F172A),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
        ),
        child: Padding(
          padding: padding.add(const EdgeInsets.all(1)),
          child: child,
        ),
      );
    }

    Widget result = Padding(padding: padding, child: child);
    if (depth > 1) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          border: _border(chrome, inner: true),
        ),
        child: Padding(padding: const EdgeInsets.all(1), child: result),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: _border(chrome, inner: false),
      ),
      child: Padding(padding: const EdgeInsets.all(1), child: result),
    );
  }
}

class RetroPanel extends StatelessWidget {
  const RetroPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = DesktopChrome.of(context);
    if (!chrome.bevel) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: chrome.panel,
          borderRadius: chrome.panelBorderRadius,
          border: Border.all(color: chrome.border),
          boxShadow: chrome.panelShadow,
        ),
        child: ClipRRect(
          borderRadius: chrome.panelBorderRadius,
          child: ColoredBox(color: chrome.panel, child: child),
        ),
      );
    }
    return RetroBevel(
      child: ColoredBox(color: chrome.panel, child: child),
    );
  }
}

class RetroSectionHeader extends StatelessWidget {
  const RetroSectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final chrome = DesktopChrome.of(context);
    return SizedBox(
      height: WindowsRetroMetrics.panelHeaderHeight,
      child: ColoredBox(
        color: chrome.header,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: chrome.headerText),
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
    final chrome = DesktopChrome.of(context);
    final enabled = widget.onPressed != null;
    final showBevel = widget.alwaysRaised || _hovered || _focused || _pressed;
    final buttonChrome = showBevel
        ? RetroBevel(
            kind: _pressed ? RetroBevelKind.sunken : RetroBevelKind.raised,
            color: chrome.panel,
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
                color: enabled ? chrome.text : chrome.shadow,
              ),
              child: buttonChrome,
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
    final chrome = DesktopChrome.of(context);
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
              color: chrome.panel,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: enabled ? chrome.text : chrome.shadow,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 15,
                    color: enabled ? chrome.text : chrome.shadow,
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
