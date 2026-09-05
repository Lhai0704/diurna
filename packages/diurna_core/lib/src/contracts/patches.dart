import 'errors.dart';
import '../features/inbox/data/inbox_item.dart';

class InboxPatch {
  const InboxPatch({
    this.content,
    this.type = const Field.absent(),
    this.isTopic,
    this.dueDate = const Field.absent(),
    this.priority = const Field.absent(),
    this.completed,
    this.pinned,
  });
  final String? content;
  final Field<InboxItemType> type;
  final bool? isTopic, completed, pinned;
  final Field<DateTime> dueDate;
  final Field<int> priority;
}

class CalendarPatch {
  const CalendarPatch({
    this.title,
    this.date,
    this.note = const Field.absent(),
    this.remindAt = const Field.absent(),
  });
  final String? title;
  final DateTime? date;
  final Field<String> note;
  final Field<DateTime> remindAt;
}

class MemoPatch {
  const MemoPatch({this.title, this.content, this.appendContent});
  final String? title, content, appendContent;
}

class DiaryPatch {
  const DiaryPatch({
    this.title,
    this.content,
    this.date,
    this.mood = const Field.absent(),
    this.tags,
  });
  final String? title, content;
  final DateTime? date;
  final Field<String> mood;
  final List<String>? tags;
}
