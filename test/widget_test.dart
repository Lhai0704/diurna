import 'package:diurna/app/app.dart';
import 'package:diurna/core/config/env.dart';
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
}
