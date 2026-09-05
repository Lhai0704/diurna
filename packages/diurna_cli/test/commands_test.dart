import 'dart:convert';
import 'dart:io';
import 'package:diurna_cli/commands.dart';
import 'package:diurna_cli/auth_store.dart';
import 'package:diurna_core/diurna_core.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('strict JSON validation and date conventions', () {
    expect(
      () => Command.parse([
        'memo',
        'update',
        '--input-json',
      ], stdinJson: '{"sql":"delete"}'),
      throwsA(isA<DiurnaException>()),
    );
    expect(
      () => Command.parse(['calendar', 'list', '--date', '2026-02-30']),
      throwsA(isA<DiurnaException>()),
    );
    expect(
      () => Command.parse([
        'calendar',
        'list',
        '--date',
        '2026-09-05',
        '--from',
        '2026-09-01',
      ]),
      throwsA(isA<DiurnaException>()),
    );
    expect(
      () => Command.parse(['memo', 'get', 'fuzzy']),
      throwsA(isA<DiurnaException>()),
    );
  });
  test('command to service create, append, search and delete', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final s = DiurnaService(db, 'user');
    final memo = await Command.parse([
      'memo',
      'create',
      '--title',
      'MCP',
      '--content',
      'line\n  中文',
    ]).execute(s);
    final updated = await Command.parse(
      ['memo', 'update', '--input-json'],
      stdinJson: jsonEncode({
        'id': memo['id'],
        'version': memo['version'],
        'appendContent': '\nauth',
      }),
    ).execute(s);
    expect(updated['content'], 'line\n  中文\nauth');
    final found = await Command.parse(['search', 'MCP']).execute(s);
    expect(found['memos']['items'], hasLength(1));
    await expectLater(
      Command.parse([
        'memo',
        'delete',
        memo['id'],
        '--version',
        updated['version'],
      ]).execute(s),
      throwsA(isA<DiurnaException>()),
    );
  });
  test(
    'real child process returns JSON and invalid-argument exit code',
    () async {
      final result = await Process.run(
        File('build/bundle/bin/diurna.exe').absolute.path,
        ['not-a-command', 'list', '--json'],
      );
      expect(result.exitCode, 2);
      final json = jsonDecode(result.stdout as String);
      expect(json['schemaVersion'], 1);
      expect(json['ok'], false);
      expect(json['error']['code'], 'INVALID_ARGS');
    },
  );
  test('DPAPI credential encryption roundtrip', () async {
    if (!Platform.isWindows) return;
    final raw = utf8.encode('test-only session');
    final cipher = await AuthStore.crypt(raw, protect: true);
    expect(cipher, isNot(raw));
    expect(await AuthStore.crypt(cipher, protect: false), raw);
  });
}
