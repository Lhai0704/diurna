import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/core/database/database_providers.dart';
import 'package:diurna/features/calendar/data/calendar_event_model.dart';
import 'package:diurna/features/calendar/data/calendar_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final todayOnlyProvider = NotifierProvider<TodayOnlyNotifier, bool>(
  TodayOnlyNotifier.new,
);

class TodayOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    throw StateError('请先登录。');
  }
  return CalendarRepository(ref.watch(appDatabaseProvider), userId);
});

final calendarEventsProvider = StreamProvider.autoDispose<List<CalendarEvent>>((
  ref,
) {
  final todayOnly = ref.watch(todayOnlyProvider);
  return ref.watch(calendarRepositoryProvider).watch(todayOnly: todayOnly);
});
