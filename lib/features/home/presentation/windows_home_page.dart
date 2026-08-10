import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/app/windows_retro_theme.dart';
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
    return Theme(
      data: buildWindowsRetroTheme(Theme.of(context)),
      child: Scaffold(
        body: SafeArea(
          child: ColoredBox(
            color: WindowsRetroColors.desktop,
            child: Padding(
              padding: const EdgeInsets.all(WindowsRetroMetrics.space4),
              child: Row(
                children: const [
                  Expanded(child: RetroPanel(child: _ScheduleMonthPanel())),
                  SizedBox(width: WindowsRetroMetrics.space4),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: RetroPanel(child: _DiaryPanel()),
                        ),
                        SizedBox(height: WindowsRetroMetrics.space4),
                        Expanded(
                          flex: 7,
                          child: RetroPanel(child: _InboxPanel()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      trailing: RetroToolbarButton(
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
      // Keep the selected day in view while leaving room above it for the
      // current month and weekday headers on ordinary desktop window sizes.
      alignment: 0.8,
      duration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final firstMonth = DateTime(today.year, today.month - 3);
    final eventsByDate = <String, List<CalendarEvent>>{};

    for (final event in widget.events) {
      final key = _dateKey(event.scheduledDate);
      eventsByDate.putIfAbsent(key, () => []).add(event);
    }
    for (final events in eventsByDate.values) {
      events.sort((left, right) {
        final completionOrder = (left.isCompleted ? 1 : 0).compareTo(
          right.isCompleted ? 1 : 0,
        );
        if (completionOrder != 0) {
          return completionOrder;
        }
        return left.createdAt.compareTo(right.createdAt);
      });
    }

    // Build all months eagerly so today's cell has a layout context for
    // centering on first open (only 18 months, so this is cheap).
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
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
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RetroBevel(
            child: SizedBox(
              height: 26,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${month.year}年${month.month}月',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 24,
            decoration: const BoxDecoration(
              color: WindowsRetroColors.contentMuted,
              border: Border(
                left: BorderSide(color: WindowsRetroColors.grid),
                right: BorderSide(color: WindowsRetroColors.grid),
                bottom: BorderSide(color: WindowsRetroColors.grid),
              ),
            ),
            child: Row(
              children: weekdays
                  .map(
                    (weekday) => Expanded(
                      child: Center(
                        child: Text(
                          weekday,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: WindowsRetroColors.grid),
                top: BorderSide(color: WindowsRetroColors.grid),
              ),
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: itemCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 122,
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
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: WindowsRetroColors.contentMuted,
        border: Border(
          right: BorderSide(color: WindowsRetroColors.grid),
          bottom: BorderSide(color: WindowsRetroColors.grid),
        ),
      ),
    );
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
    return Material(
      color: WindowsRetroColors.content,
      child: InkWell(
        onTap: () => showEventEditPage(context, initialDate: day),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: WindowsRetroColors.grid),
              bottom: BorderSide(color: WindowsRetroColors.grid),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 22,
                color: isToday
                    ? WindowsRetroColors.activeBlue
                    : WindowsRetroColors.contentMuted,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      '${day.day}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isToday
                            ? WindowsRetroColors.selectedText
                            : WindowsRetroColors.text,
                      ),
                    ),
                    const Spacer(),
                    if (events.length > 5)
                      Text(
                        '+${events.length - 5}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isToday
                              ? WindowsRetroColors.selectedText
                              : WindowsRetroColors.secondaryText,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 3, 3, 2),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: events.length > 5 ? 5 : events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return _CalendarTodoRow(event: event);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarTodoRow extends StatelessWidget {
  const _CalendarTodoRow({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      decoration: event.isCompleted ? TextDecoration.lineThrough : null,
      color: event.isCompleted
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : null,
    );

    return SizedBox(
      height: 18,
      child: InkWell(
        onTap: () => showEventEditPage(context, event: event),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
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
          const SyncStatusIcon(retro: true),
          const SizedBox(width: 2),
          RetroPushButton(
            onPressed: _pickDate,
            minWidth: 112,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_outlined),
                const SizedBox(width: 4),
                Text(AppDateUtils.formatDate(_selectedDate)),
              ],
            ),
          ),
          const SizedBox(width: 2),
          RetroToolbarButton(
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
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: RetroBevel(
                    kind: RetroBevelKind.sunken,
                    depth: 2,
                    color: WindowsRetroColors.content,
                    child: TextField(
                      controller: _contentController,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        filled: false,
                        hintText: '记录今天……',
                        contentPadding: EdgeInsets.all(8),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: RetroPushButton(
                    onPressed: () => _save(entry),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.save_outlined),
                        SizedBox(width: 4),
                        Text('保存日记'),
                      ],
                    ),
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

class _InboxPanel extends StatelessWidget {
  const _InboxPanel();

  @override
  Widget build(BuildContext context) {
    return InboxBoard(
      expanded: false,
      retro: true,
      onExpand: () => showExpandedInbox(context, retro: true),
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
        RetroSectionHeader(title: title, trailing: trailing),
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
