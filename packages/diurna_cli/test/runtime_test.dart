import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:diurna_cli/auth_store.dart';
import 'package:test/test.dart';

void main() {
  test(
    'compiled CLI online CRUD, search, refresh, offline queue and lock',
    () async {
      if (!Platform.isWindows) return;
      final home = await Directory.systemTemp.createTemp(
        'diurna-runtime-test-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      const user = '10000000-0000-0000-0000-000000000001';
      final url = 'http://127.0.0.1:${server.port}';
      final project = sha256
          .convert(utf8.encode(url))
          .toString()
          .substring(0, 24);
      final auth = AuthStore(Directory('${home.path}/$project'));
      await auth.secureDirectory();
      Map<String, dynamic> session(int expiration) {
        final token =
            '${base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'role': 'authenticated', 'exp': expiration}))).replaceAll('=', '')}.test';
        return {
          'access_token': token,
          'refresh_token': 'test-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at': expiration,
          'user': {
            'id': user,
            'aud': 'authenticated',
            'email': 'test@example.invalid',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-01-01T00:00:00Z',
          },
        };
      }

      await auth.write(
        session(DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10),
      );
      final tables = {
        for (final name in [
          'memos',
          'inbox_items',
          'calendar_events',
          'diary_entries',
        ])
          name: <String, Map<String, dynamic>>{},
      };
      var generation = 0, refreshes = 0;
      var failWrites = false;
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final input = body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(body) as Map<String, dynamic>;
        Object response;
        if (request.uri.path == '/auth/v1/token') {
          refreshes++;
          response = session(
            DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          );
        } else if (request.uri.path == '/rest/v1/rpc/diurna_snapshot_v2') {
          response = {
            'protocol': 2,
            'complete': true,
            'user_id': user,
            'generation': generation,
            'tombstones': [],
            for (final t in tables.entries) t.key: t.value.values.toList(),
          };
        } else if (request.uri.path.startsWith('/rest/v1/rpc/diurna_sync_')) {
          if (failWrites) {
            request.response.statusCode = 503;
            response = {'message': 'test outage'};
          } else {
            final module = request.uri.path
                .split('diurna_sync_')
                .last
                .split('_v2')
                .first;
            final table =
                tables[switch (module) {
                  'calendar' => 'calendar_events',
                  'inbox' => 'inbox_items',
                  'diary' => 'diary_entries',
                  _ => 'memos',
                }]!;
            final changes = (input['changes'] as List)
                .cast<Map<String, dynamic>>();
            if (changes.any(
              (c) =>
                  (table[c['id']]?['revision'] ?? 0) != c['expected_revision'],
            )) {
              response = {
                'ok': false,
                'code': 'CONFLICT',
                'remote': table.values.toList(),
              };
            } else {
              final revisions = <Map<String, dynamic>>[];
              for (final c in changes) {
                final revision = (table[c['id']]?['revision'] as int? ?? 0) + 1;
                if (c['operation'] == 'delete') {
                  table.remove(c['id']);
                } else {
                  table[c['id']] = {
                    ...c['payload'] as Map<String, dynamic>,
                    'revision': revision,
                  };
                }
                generation++;
                revisions.add({'id': c['id'], 'revision': revision});
              }
              response = {'ok': true, 'revisions': revisions};
            }
          }
        } else {
          request.response.statusCode = 404;
          response = {'message': 'Unexpected test endpoint'};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      Future<Map<String, dynamic>> run(
        List<String> args, {
        int code = 0,
      }) async {
        final result = await Process.run(
          File('build/bundle/bin/diurna.exe').absolute.path,
          [...args, '--json'],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
          environment: {
            'DIURNA_HOME': home.path,
            'SUPABASE_URL': url,
            'SUPABASE_ANON_KEY': 'sb_publishable_test',
          },
        );
        expect(
          result.exitCode,
          code,
          reason: '${result.stdout}\n${result.stderr}',
        );
        return jsonDecode(result.stdout as String) as Map<String, dynamic>;
      }

      try {
        final created = await run([
          'memo',
          'create',
          '--title',
          'MCP Architecture',
          '--content',
          'CLI → MCP → Skill',
        ]);
        expect(refreshes, 1);
        expect(created['meta']['syncStatus'], 'synced');
        final memo = created['data'];
        final updated = await run([
          'memo',
          'update',
          memo['id'],
          '--version',
          memo['version'],
          '--append-content',
          '\nauthentication',
        ]);
        expect(updated['data']['content'], 'CLI → MCP → Skill\nauthentication');
        expect(
          (await run(['search', 'MCP']))['data']['memos']['items'],
          hasLength(1),
        );
        final calendar = await run([
          'calendar',
          'create',
          '--title',
          '研究 Diurna MCP',
          '--date',
          '2026-09-06',
        ]);
        final event = calendar['data'];
        await run([
          'calendar',
          'complete',
          event['id'],
          '--version',
          event['version'],
        ]);
        final today = await run(['calendar', 'list', '--date', '2026-09-06']);
        expect(today['data']['items'][0]['is_completed'], true);
        await run([
          'diary',
          'create',
          '--title',
          '今天',
          '--content',
          '研究 MCP',
          '--date',
          '2026-09-05',
        ]);
        expect(
          (await run([
            'diary',
            'list',
            '--from',
            '2026-08-30',
            '--to',
            '2026-09-05',
          ]))['data']['items'],
          hasLength(1),
        );
        failWrites = true;
        final failure = await run([
          'memo',
          'create',
          '--title',
          'pending',
        ], code: 6);
        expect(failure['meta']['localCommitted'], true);
        expect(failure['meta']['entityId'], isA<String>());
        expect(
          (await run(['memo', 'list', '--offline']))['meta']['stale'],
          true,
        );
        final lock = await File(
          '${auth.directory.path}/profile.lock',
        ).open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        try {
          await run(['memo', 'list'], code: 7);
        } finally {
          await lock.close();
        }
        failWrites = false;
        await run(['sync', 'now']);
      } finally {
        await server.close(force: true);
        await home.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
