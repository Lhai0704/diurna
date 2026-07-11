import 'package:diurna/features/inbox/data/inbox_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InboxItem', () {
    test('parses an untyped pending capture', () {
      final item = InboxItem.fromMap({
        'id': 'item-1',
        'user_id': 'user-1',
        'content': '记录一个想法',
        'item_type': null,
        'inbox_column': 'pending',
        'position': -1,
        'is_archived': false,
        'is_pinned': false,
        'is_topic': false,
        'is_completed': false,
        'due_date': null,
        'priority': null,
        'parent_id': null,
        'created_at': '2026-07-11T06:00:00Z',
        'updated_at': '2026-07-11T06:00:00Z',
      });

      expect(item.content, '记录一个想法');
      expect(item.type, isNull);
      expect(item.column, InboxColumn.pending);
      expect(item.isAction, isFalse);
    });

    test('only action items expose action semantics', () {
      final item = InboxItem.fromMap({
        'id': 'item-2',
        'user_id': 'user-1',
        'content': '完成项目原型',
        'item_type': 'action',
        'inbox_column': 'focus',
        'position': 1,
        'is_archived': false,
        'is_pinned': true,
        'is_topic': false,
        'is_completed': true,
        'due_date': '2026-07-20',
        'priority': 2,
        'parent_id': null,
        'created_at': '2026-07-11T06:00:00Z',
        'updated_at': '2026-07-11T06:00:00Z',
      });

      expect(item.type, InboxItemType.action);
      expect(item.column, InboxColumn.focus);
      expect(item.isAction, isTrue);
      expect(item.priority, 2);
      expect(item.dueDate, DateTime(2026, 7, 20));
    });
  });
}
