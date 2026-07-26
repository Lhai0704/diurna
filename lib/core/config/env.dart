import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  const AppEnv._();

  static const _buildSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _buildSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } on Exception {
      // The app can still start and show a setup message when .env is missing.
    }
  }

  static String get supabaseUrl {
    final buildValue = _buildSupabaseUrl.trim();
    return buildValue.isNotEmpty
        ? buildValue
        : dotenv.env['SUPABASE_URL']?.trim() ?? '';
  }

  static String get supabaseAnonKey {
    final buildValue = _buildSupabaseAnonKey.trim();
    return buildValue.isNotEmpty
        ? buildValue
        : dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
  }

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
