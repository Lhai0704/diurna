import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/calendar/data/calendar_event_model.dart';
import 'package:diurna/features/calendar/presentation/event_edit_page.dart';
import 'package:diurna/features/calendar/providers/calendar_providers.dart';
import 'package:diurna/features/diary/data/diary_model.dart';
import 'package:diurna/features/diary/providers/diary_providers.dart';
import 'package:diurna/features/inbox/presentation/inbox_board.dart';
import 'package:diurna/features/inbox/presentation/inbox_page.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:diurna/shared/widgets/sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WindowsHomePage extends ConsumerWidget {
  const WindowsHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: const [
            Expanded(child: _ScheduleMonthPanel()),
            VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _DiaryPanel()),
                  Divider(height: 1),
                  Expanded(child: _TaskPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleMonthPanel extends ConsumerWidget {
  const _ScheduleMonthPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(calendarEventsProvider);

    return _Panel(
      title: '日程安排',
      trailing: IconButton(
        tooltip: '新增日程',
        onPressed: () => showEventEditPage(context),
        icon: const Icon(Icons.add),
      ),
      child: events.when(
        data: (items) => _ScrollableMonthCalendar(
          events: items,
          onRefresh: () => triggerSync(ref),
        ),
        error: (error, stackTrace) => EmptyView(message: error.toString()),
        loading: () => const LoadingView(),
      ),
    );
  }
}

class _ScrollableMonthCalendar extends StatefulWidget {
  const _ScrollableMonthCalendar({
    required this.events,
    required this.onRefresh,
  });

  final List<CalendarEvent> events;
  final Future<void> Function() onRefresh;

  @override
  State<_ScrollableMonthCalendar> createState() =>
      _ScrollableMonthCalendarState();
}

class _ScrollableMonthCalendarState extends State<_ScrollableMonthCalendar> {
  final GlobalKey _todayKey = GlobalKey();
  bool _didCenterToday = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerToday());
  }

  void _centerToday() {
    if (_didCenterToday || !mounted) {
      return;
    }

    final todayContext = _todayKey.currentContext;
    if (todayContext == null) {
      // Layout may not be ready yet; retry on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerToday());
      return;
    }

    _didCenterToday = true;
    Scrollable.ensureVisible(
      todayContext,
      alignment: 0.5,
      duration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final firstMonth = DateTime(today.year, today.month - 3);
    final eventsByDate = <String, List<CalendarEvent>>{};

    for (final event in widget.events) {
      final key = _dateKey(event.startsAt);
      eventsByDate.putIfAbsent(key, () => []).add(event);
    }

    // Build all months eagerly so today's cell has a layout context for
    // centering on first open (only 18 months, so this is cheap).
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            for (var index = 0; index < 18; index++)
              _MonthSection(
                month: DateTime(firstMonth.year, firstMonth.month + index),
                today: today,
                todayKey: _todayKey,
                eventsByDate: eventsByDate,
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.month,
    required this.today,
    required this.todayKey,
    required this.eventsByDate,
  });

  final DateTime month;
  final DateTime today;
  final GlobalKey todayKey;
  final Map<String, List<CalendarEvent>> eventsByDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstDay = DateTime(month.year, month.month);
    final leadingEmptyDays = firstDay.weekday - DateTime.monday;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final itemCount = ((leadingEmptyDays + daysInMonth + 6) ~/ 7) * 7;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${month.year}年${month.month}月',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Row(
            children: weekdays
                .map(
                  (weekday) => Expanded(
                    child: Center(
                      child: Text(weekday, style: theme.textTheme.labelMedium),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final dayNumber = index - leadingEmptyDays + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const _EmptyDayCell();
              }
              final day = DateTime(month.year, month.month, dayNumber);
              final isToday = _sameDate(day, today);
              return _DayCell(
                key: isToday ? todayKey : null,
                day: day,
                isToday: isToday,
                events: eventsByDate[_dateKey(day)] ?? const [],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyDayCell extends StatelessWidget {
  const _EmptyDayCell();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.isToday,
    required this.events,
  });

  final DateTime day;
  final bool isToday;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = isToday
        ? colorScheme.primary
        : colorScheme.outlineVariant;

    return Card(
      margin: const EdgeInsets.all(3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: borderColor, width: isToday ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showEventEditPage(context, initialDate: day),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${day.day}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isToday ? colorScheme.primary : null,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: events.length > 3 ? 3 : events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    );
                  },
                ),
              ),
              if (events.length > 3)
                Text(
                  '+${events.length - 3}',
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiaryPanel extends ConsumerStatefulWidget {
  const _DiaryPanel();

  @override
  ConsumerState<_DiaryPanel> createState() => _DiaryPanelState();
}

class _DiaryPanelState extends ConsumerState<_DiaryPanel> {
  late DateTime _selectedDate;
  late final TextEditingController _contentController;
  bool _dirty = false;
  bool _syncingText = false;
  String? _loadedKey;

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(DateTime.now());
    _contentController = TextEditingController();
    _contentController.addListener(() {
      if (!_syncingText) {
        _dirty = true;
      }
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _selectedDate,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _selectedDate = _dateOnly(picked);
      _dirty = false;
      _loadedKey = null;
    });
  }

  Future<void> _save(DiaryEntry? entry) async {
    final selectedDateLabel = AppDateUtils.formatDate(_selectedDate);
    await ref
        .read(diaryRepositoryProvider)
        .save(
          id: entry?.id,
          entryDate: _selectedDate,
          title: entry?.title.isNotEmpty == true
              ? entry!.title
              : selectedDateLabel,
          content: _contentController.text,
          mood: entry?.mood,
          tags: entry?.tags ?? const [],
        );
    _dirty = false;
  }

  void _syncText(DiaryEntry? entry) {
    final key = [
      _dateKey(_selectedDate),
      entry?.id ?? 'new',
      entry?.updatedAt.toIso8601String() ?? '',
    ].join('|');

    if (_loadedKey == key || _dirty) {
      return;
    }

    _syncingText = true;
    _contentController.text = entry?.content ?? '';
    _contentController.selection = TextSelection.collapsed(
      offset: _contentController.text.length,
    );
    _syncingText = false;
    _loadedKey = key;
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(diaryEntriesProvider);

    return _Panel(
      title: '日记',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SyncStatusIcon(),
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(AppDateUtils.formatDate(_selectedDate)),
          ),
          IconButton(
            tooltip: '退出登录',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      child: entries.when(
        data: (items) {
          final entry = _entryForDate(items, _selectedDate);
          _syncText(entry);

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: '正文',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _save(entry),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存日记'),
                  ),
                ),
              ],
            ),
          );
        },
        error: (error, stackTrace) => EmptyView(message: error.toString()),
        loading: () => const LoadingView(),
      ),
    );
  }
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel();

  @override
  Widget build(BuildContext context) {
    return InboxBoard(
      expanded: false,
      onExpand: () => showExpandedInbox(context),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

DiaryEntry? _entryForDate(List<DiaryEntry> entries, DateTime date) {
  for (final entry in entries) {
    if (_sameDate(entry.entryDate, date)) {
      return entry;
    }
  }
  return null;
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _dateKey(DateTime value) => AppDateUtils.formatDate(_dateOnly(value));

bool _sameDate(DateTime a, DateTime b) => _dateKey(a) == _dateKey(b);
