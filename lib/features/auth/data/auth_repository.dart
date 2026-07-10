import 'package:diurna/core/config/env.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (!AppEnv.isSupabaseConfigured) {
    throw StateError('请先在项目根目录 .env 中配置 Supabase URL 和 anon key。');
  }
  try {
    return Supabase.instance.client;
  } on Object {
    throw StateError('Supabase is not initialized.');
  }
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!AppEnv.isSupabaseConfigured) {
    return AuthRepository.notConfigured();
  }
  try {
    return AuthRepository(ref.watch(supabaseClientProvider));
  } on Object {
    return AuthRepository.notConfigured();
  }
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUser?.id;
});

class AuthRepository {
  AuthRepository(this._client) : _configured = true;

  AuthRepository.notConfigured() : _client = null, _configured = false;

  final SupabaseClient? _client;
  final bool _configured;

  bool get isConfigured => _configured;

  User? get currentUser => _client?.auth.currentUser;

  Stream<AuthState> get authStateChanges {
    final client = _client;
    if (client == null) {
      return const Stream.empty();
    }
    return client.auth.onAuthStateChange;
  }

  Future<void> signIn({required String email, required String password}) async {
    _requireClient();
    await _client!.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({required String email, required String password}) async {
    _requireClient();
    await _client!.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() async {
    _requireClient();
    await _client!.auth.signOut();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase 尚未配置。');
    }
    return client;
  }
}
