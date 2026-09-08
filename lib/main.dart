import 'package:diurna/app/app.dart';
import 'package:diurna/app/visual_style.dart';
import 'package:diurna/core/config/env.dart';
import 'package:diurna/features/settings/providers/visual_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppEnv.load();

  if (AppEnv.isSupabaseConfigured) {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      publishableKey: AppEnv.supabaseAnonKey,
    );
  }

  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        visualStyleStoreProvider.overrideWithValue(VisualStyleStore(prefs)),
      ],
      child: const DiurnaApp(),
    ),
  );
}
