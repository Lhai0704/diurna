import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppVisualStyle {
  retro,
  modern,
  web;

  String get label => switch (this) {
    AppVisualStyle.retro => '复古',
    AppVisualStyle.modern => '现代风格',
    AppVisualStyle.web => 'Web 风格',
  };

  String get description => switch (this) {
    AppVisualStyle.retro => '经典灰色面板与立体按钮',
    AppVisualStyle.modern => '同样的四宫格桌面，圆角与浅色表面',
    AppVisualStyle.web => '分页导航，适合浏览器',
  };

  bool get usesDesktopLayout =>
      this == AppVisualStyle.retro || this == AppVisualStyle.modern;
}

bool get isWindowsDesktop {
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
}

bool get showMemoNavigation {
  return kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
}

AppVisualStyle get defaultAppVisualStyle {
  return isWindowsDesktop ? AppVisualStyle.retro : AppVisualStyle.web;
}

bool shouldUseDesktopLayout({
  required AppVisualStyle style,
  required bool wide,
}) {
  if (!style.usesDesktopLayout) {
    return false;
  }
  if (isWindowsDesktop) {
    return true;
  }
  return kIsWeb && wide;
}

class VisualStyleStore {
  const VisualStyleStore([this._prefs]);

  static const storageKey = 'app_visual_style';

  final SharedPreferences? _prefs;

  AppVisualStyle? read() {
    final name = _prefs?.getString(storageKey);
    if (name == null) {
      return null;
    }
    if (name == 'material') {
      return AppVisualStyle.web;
    }
    for (final value in AppVisualStyle.values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }

  Future<void> write(AppVisualStyle style) async {
    await _prefs?.setString(storageKey, style.name);
  }
}
