import 'package:diurna/app/router.dart';
import 'package:diurna/app/theme.dart';
import 'package:diurna/core/constants/app_constants.dart';
import 'package:diurna/core/sync/sync_providers.dart';
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
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider)?.syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncServiceProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
