import 'package:diurna/app/router.dart';
import 'package:diurna/app/theme.dart';
import 'package:diurna/app/visual_style.dart';
import 'package:diurna/app/windows_retro_theme.dart';
import 'package:diurna/core/constants/app_constants.dart';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/features/integrations/providers/integration_providers.dart';
import 'package:diurna/features/settings/providers/visual_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiurnaApp extends ConsumerStatefulWidget {
  const DiurnaApp({super.key});

  @override
  ConsumerState<DiurnaApp> createState() => _DiurnaAppState();
}

class _DiurnaAppState extends ConsumerState<DiurnaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(syncServiceProvider)
        ?.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider)?.syncNow();
      ref.invalidate(integrationConnectionsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncServiceProvider);
    ref.watch(externalExportSchedulerProvider);
    final visualStyle = ref.watch(visualStyleProvider);
    final baseTheme = buildAppTheme();
    return MaterialApp.router(
      title: AppConstants.appName,
      theme: switch (visualStyle) {
        AppVisualStyle.retro => buildWindowsRetroTheme(baseTheme),
        AppVisualStyle.modern => buildModernDesktopTheme(baseTheme),
        AppVisualStyle.web => baseTheme,
      },
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
