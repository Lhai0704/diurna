import 'package:diurna/app/app.dart';
import 'package:diurna/core/config/env.dart';
import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('shows setup message when Supabase is not configured', (
    tester,
  ) async {
    await AppEnv.load();
    await tester.pumpWidget(const ProviderScope(child: DiurnaApp()));

    expect(find.text('登录 Diurna'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });

  testWidgets('shows registration as disabled with a strikethrough', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            AuthRepository.notConfigured(),
          ),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );

    final registrationText = tester.widget<Text>(
      find.text('没有账号？注册'),
    );
    final registrationButton = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('没有账号？注册'),
        matching: find.byType(TextButton),
      ),
    );

    expect(registrationText.style?.decoration, TextDecoration.lineThrough);
    expect(registrationButton.onPressed, isNull);
  });
}
