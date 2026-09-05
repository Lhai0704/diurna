import 'dart:io';
import 'package:diurna_core/diurna_core.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  for (final version in [1, 4]) {
    test(
      'v$version migration preserves existing rows and pending operations',
      () async {
        final raw = sqlite3.openInMemory();
        raw.execute(File('test/fixtures/v$version.sql').readAsStringSync());
        final db = AppDatabase(NativeDatabase.opened(raw));
        try {
          final inbox = await db.listInboxItems('legacy-user');
          expect(
            inbox.single.content,
            version == 1 ? 'old title\nold note' : 'old capture',
          );
          expect(
            (await db.listDiaryEntries('legacy-user')).single.content,
            'private diary',
          );
          if (version == 1) {
            expect(
              (await db.customSelect('SELECT * FROM local_tasks').get()).single
                  .read<String>('note'),
              'old note',
            );
            expect(
              (await db
                  .customSelect('SELECT * FROM legacy_pending_sync_operations')
                  .get()),
              hasLength(1),
            );
            expect(
              (await db
                  .customSelect('SELECT * FROM legacy_calendar_events')
                  .get()),
              hasLength(1),
            );
            expect(
              (await db.listCalendarEvents('legacy-user')).single.note,
              contains('old location'),
            );
          } else {
            final pending = await db.pendingOperations('legacy-user');
            expect(pending.single.entityId, 'inbox-id');
            expect(pending.single.payloadJson, contains('old capture'));
            expect(pending.single.generation, 'legacy');
          }
          expect(
            (await db.customSelect('PRAGMA user_version').getSingle())
                .data
                .values
                .single,
            5,
          );
        } finally {
          await db.close();
        }
      },
    );
  }
}
