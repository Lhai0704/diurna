import 'package:diurna/app/visual_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final visualStyleStoreProvider = Provider<VisualStyleStore>((ref) {
  return const VisualStyleStore();
});

class VisualStyleNotifier extends Notifier<AppVisualStyle> {
  @override
  AppVisualStyle build() {
    return ref.watch(visualStyleStoreProvider).read() ?? defaultAppVisualStyle;
  }

  Future<void> setStyle(AppVisualStyle style) async {
    if (state == style) {
      return;
    }
    state = style;
    await ref.read(visualStyleStoreProvider).write(style);
  }
}

final visualStyleProvider =
    NotifierProvider<VisualStyleNotifier, AppVisualStyle>(
      VisualStyleNotifier.new,
    );
