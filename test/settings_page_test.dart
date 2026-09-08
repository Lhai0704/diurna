import 'package:diurna/app/app.dart';
import 'package:diurna/app/visual_style.dart';
import 'package:diurna/app/windows_retro_theme.dart';
import 'package:diurna/core/config/env.dart';
import 'package:diurna/features/settings/presentation/settings_page.dart';
import 'package:diurna/features/settings/providers/visual_style_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryVisualStyleStore extends VisualStyleStore {
  _MemoryVisualStyleStore(this._style);

  AppVisualStyle? _style;

  @override
  AppVisualStyle? read() => _style;

  @override
  Future<void> write(AppVisualStyle style) async {
    _style = style;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows theme options and external connections', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsPage())),
    );

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('复古'), findsOneWidget);
    expect(find.text('现代风格'), findsOneWidget);
    expect(find.text('Web 风格'), findsOneWidget);
    expect(find.text('外部连接'), findsOneWidget);
    expect(find.text('Notion、Google Calendar'), findsOneWidget);
  });

  testWidgets('selecting Web style updates the visual style', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsPage())),
    );

    await tester.tap(find.text('Web 风格'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(container.read(visualStyleProvider), AppVisualStyle.web);
  });

  testWidgets('external connections opens the nested settings route', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
          routes: [
            GoRoute(
              path: 'integrations',
              builder: (context, state) =>
                  const Scaffold(body: Text('integrations-stub')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('外部连接'));
    await tester.pumpAndSettle();

    expect(find.text('integrations-stub'), findsOneWidget);
    expect(find.text('主题'), findsNothing);
  });

  test('visual style store round-trips the saved value', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = VisualStyleStore(prefs);

    expect(store.read(), isNull);
    await store.write(AppVisualStyle.web);
    expect(store.read(), AppVisualStyle.web);
    await store.write(AppVisualStyle.modern);
    expect(store.read(), AppVisualStyle.modern);
    await store.write(AppVisualStyle.retro);
    expect(store.read(), AppVisualStyle.retro);
  });

  test('legacy material preference maps to Web style', () async {
    SharedPreferences.setMockInitialValues({
      VisualStyleStore.storageKey: 'material',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(VisualStyleStore(prefs).read(), AppVisualStyle.web);
  });

  test('windows retro and modern use the desktop layout', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(
      shouldUseDesktopLayout(style: AppVisualStyle.retro, wide: false),
      isTrue,
    );
    expect(
      shouldUseDesktopLayout(style: AppVisualStyle.modern, wide: false),
      isTrue,
    );
    expect(
      shouldUseDesktopLayout(style: AppVisualStyle.web, wide: true),
      isFalse,
    );
  });

  test('non-windows VM tests keep web navigation', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(
      shouldUseDesktopLayout(style: AppVisualStyle.retro, wide: true),
      isFalse,
    );
    expect(
      shouldUseDesktopLayout(style: AppVisualStyle.modern, wide: true),
      isFalse,
    );
  });

  testWidgets('DiurnaApp applies retro or Material theme from the store', (
    tester,
  ) async {
    await AppEnv.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          visualStyleStoreProvider.overrideWithValue(
            _MemoryVisualStyleStore(AppVisualStyle.retro),
          ),
        ],
        child: const DiurnaApp(),
      ),
    );
    await tester.pump();

    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.scaffoldBackgroundColor, WindowsRetroColors.desktop);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          visualStyleStoreProvider.overrideWithValue(
            _MemoryVisualStyleStore(AppVisualStyle.web),
          ),
        ],
        child: const DiurnaApp(),
      ),
    );
    await tester.pump();

    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.useMaterial3, isTrue);
    expect(
      app.theme?.scaffoldBackgroundColor,
      isNot(WindowsRetroColors.desktop),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          visualStyleStoreProvider.overrideWithValue(
            _MemoryVisualStyleStore(AppVisualStyle.modern),
          ),
        ],
        child: const DiurnaApp(),
      ),
    );
    await tester.pump();

    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.scaffoldBackgroundColor, DesktopChrome.modern.desktop);
    expect(app.theme?.extension<DesktopChrome>()?.bevel, isFalse);
  });
}
