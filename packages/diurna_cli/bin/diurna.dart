import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:diurna_core/diurna_core.dart';
import 'package:diurna_core/src/core/sync/versioned_sync_store.dart';
import 'package:drift/native.dart';
import 'package:supabase/supabase.dart';
import 'package:diurna_cli/auth_store.dart';
import 'package:diurna_cli/commands.dart';

int errorExit(String code) => switch (code) {
  'INVALID_ARGS' || 'VALIDATION' => 2,
  'AUTH_REQUIRED' => 3,
  'NOT_FOUND' => 4,
  'CONFLICT' => 5,
  'SYNC_FAILED' => 6,
  'BUSY' => 7,
  'UPGRADE_REQUIRED' => 8,
  _ => 1,
};

Future<void> main(List<String> args) async {
  stdout.encoding = utf8;
  stderr.encoding = utf8;
  if (args.contains('--help') || args.isEmpty) {
    stdout.writeln(
      'Diurna CLI v1\n${commandFields.keys.join('\n')}\nUse --json; --input-json reads one strict JSON object from stdin.\nMutations require --version from a prior read. --offline explicitly uses the local cache.\nConfigure SUPABASE_URL and SUPABASE_ANON_KEY before auth login.',
    );
    return;
  }
  final meta = <String, dynamic>{
    'localCommitted': false,
    'syncStatus': 'unknown',
    'stale': false,
    'timezone': 'Asia/Shanghai',
    'today': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .split('T')
        .first,
  };
  RandomAccessFile? lock;
  AppDatabase? database;
  SupabaseClient? client;
  SyncService? sync;
  try {
    final command = Command.parse(
      args,
      stdinJson: args.contains('--input-json')
          ? await stdin.transform(utf8.decoder).join()
          : null,
    );
    final root = Directory(
      Platform.environment['DIURNA_HOME'] ??
          '${Platform.environment['LOCALAPPDATA']}/DiurnaAgent',
    );
    final configFile = File('${root.path}/config.json');
    final config = await configFile.exists()
        ? jsonDecode(await configFile.readAsString()) as Map
        : <String, dynamic>{};
    final url =
        Platform.environment['SUPABASE_URL'] ?? config['url'] as String?;
    final key =
        Platform.environment['SUPABASE_ANON_KEY'] ?? config['key'] as String?;
    if (url == null || key == null) {
      throw const DiurnaException(
        'AUTH_REQUIRED',
        'Set SUPABASE_URL and SUPABASE_ANON_KEY, then run diurna auth login',
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' &&
            uri.host != '127.0.0.1' &&
            uri.host != 'localhost')) {
      throw const DiurnaException('VALIDATION', 'Supabase requires HTTPS');
    }
    if (key.startsWith('sb_secret_')) {
      throw const DiurnaException('VALIDATION', 'Secret keys are prohibited');
    }
    if (key.split('.').length == 3) {
      final claims =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(key.split('.')[1])),
                ),
              )
              as Map;
      if (claims['role'] != 'anon') {
        throw const DiurnaException(
          'VALIDATION',
          'Only anon/publishable keys are accepted',
        );
      }
    } else if (!key.startsWith('sb_publishable_')) {
      throw const DiurnaException(
        'VALIDATION',
        'Expected publishable or anon key',
      );
    }
    final project = sha256
        .convert(utf8.encode(url))
        .toString()
        .substring(0, 24);
    final dir = Directory('${root.path}/$project');
    final auth = AuthStore(dir);
    await auth.secureDirectory();
    lock = await File('${dir.path}/profile.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      throw const DiurnaException(
        'BUSY',
        'Another command is using this profile',
      );
    }
    final saved = await auth.read();
    client = SupabaseClient(
      url,
      key,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final current = client;
    if (command.name == 'auth login') {
      if (!stdin.hasTerminal || args.contains('--input-json')) {
        throw const DiurnaException(
          'AUTH_REQUIRED',
          'Run auth login interactively in a terminal',
        );
      }
      stderr.write('Password: ');
      final echo = stdin.echoMode;
      String? password;
      try {
        stdin.echoMode = false;
        password = stdin.readLineSync();
      } finally {
        stdin.echoMode = echo;
        stderr.writeln();
      }
      if (password == null || password.isEmpty) {
        throw const DiurnaException('AUTH_REQUIRED', 'Password required');
      }
      final response = await current.auth.signInWithPassword(
        email: command.required('email'),
        password: password,
      );
      if (response.session == null) {
        throw const DiurnaException(
          'AUTH_REQUIRED',
          'Login did not return a session',
        );
      }
      await auth.write(response.session!.toJson());
      await configFile.writeAsString(
        jsonEncode({'url': url, 'key': key}),
        flush: true,
      );
      stdout.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'ok': true,
          'data': {'userId': response.user!.id, 'email': response.user!.email},
          'meta': meta,
        }),
      );
      return;
    }
    if (saved == null) {
      throw const DiurnaException('AUTH_REQUIRED', 'Run diurna auth login');
    }
    final storedSession = Session.fromJson(saved);
    if (storedSession == null) {
      throw const DiurnaException(
        'AUTH_REQUIRED',
        'Invalid saved session; log in again',
      );
    }
    var session = storedSession;
    if (!command.offline) {
      try {
        if (storedSession.isExpired) {
          final token = storedSession.refreshToken;
          if (token == null) {
            throw const DiurnaException(
              'AUTH_REQUIRED',
              'Session has no refresh token',
            );
          }
          await current.auth.setSession(token);
        } else {
          await current.auth.recoverSession(jsonEncode(saved));
        }
        if (current.auth.currentSession!.isExpired) {
          await current.auth.refreshSession();
        }
        session = current.auth.currentSession!;
        await auth.write(session.toJson());
      } on AuthException {
        throw const DiurnaException(
          'AUTH_REQUIRED',
          'Session expired or revoked; run auth login',
        );
      }
    }
    if (command.name == 'auth logout') {
      await current.auth.signOut(scope: SignOutScope.local);
      await auth.clear();
      stdout.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'ok': true,
          'data': {'signedOut': true},
          'meta': meta,
        }),
      );
      return;
    }
    if (command.name == 'auth status') {
      stdout.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'ok': true,
          'data': {
            'userId': session.user.id,
            'email': session.user.email,
            'expiresAt': session.expiresAt,
            'profile': project,
          },
          'meta': meta,
        }),
      );
      return;
    }
    final userDir = Directory('${dir.path}/${session.user.id}');
    await userDir.create(recursive: true);
    database = AppDatabase(
      NativeDatabase(File('${userDir.path}/cache.sqlite')),
    );
    final service = DiurnaService(database, session.user.id);
    final remote = SupabaseSyncRemoteDataSource(current);
    sync = SyncService(
      database: database,
      remote: remote,
      userId: session.user.id,
    );
    final syncService = sync;
    final store = VersionedSyncStore(database, session.user.id);
    Future<void> synchronize() async {
      await syncService.syncNow();
      if (syncService.snapshot.phase == SyncPhase.failed) {
        throw DiurnaException(
          syncService.snapshot.errorCode ?? 'SYNC_FAILED',
          'Synchronization failed; local changes are retained',
        );
      }
    }

    if (!command.offline) await synchronize();
    meta['stale'] = command.offline;
    meta['syncStatus'] = command.offline ? 'cached' : 'synced';
    Map<String, dynamic> data;
    if (command.name.startsWith('sync ')) {
      if (command.name == 'sync conflict resolve') {
        if (command.offline) {
          throw const DiurnaException(
            'VALIDATION',
            'Conflict resolution requires a fresh remote snapshot',
          );
        }
        final choice = command.required('use');
        if (!['local', 'remote'].contains(choice)) {
          throw const DiurnaException(
            'VALIDATION',
            'use must be local or remote',
          );
        }
        final snapshot = await remote.fetchSnapshot();
        await store.resolve(
          command.required('id'),
          choice == 'local',
          snapshot.tables,
        );
        await synchronize();
      }
      final conflicts = await store.listConflicts();
      data = {
        'pendingCount': await database.pendingCount(session.user.id),
        'conflicts': conflicts,
      };
      if (command.name == 'sync conflict get') {
        final match = conflicts.where((c) => c['id'] == command.required('id'));
        if (match.isEmpty) {
          throw const DiurnaException('NOT_FOUND', 'Conflict not found');
        }
        data = match.single;
      }
    } else {
      data = await command.execute(service);
      if (command.writes) {
        meta['localCommitted'] = true;
        meta['entityId'] = data['id'];
        meta['syncStatus'] = 'pending';
        final ops = await database.pendingOperations(session.user.id);
        final affected = ops.where((o) => o.entityId == data['id']);
        meta['operationId'] = affected.isEmpty
            ? null
            : affected.first.generation;
        if (!command.offline) {
          await synchronize();
          final conflicts = await store.listConflicts();
          if (conflicts.any(
            (c) => (c['changes'] as List).any((r) => r['id'] == data['id']),
          )) {
            throw const DiurnaException(
              'CONFLICT',
              'Local changes retained; resolve the remote conflict',
            );
          }
          meta['syncStatus'] = 'synced';
          if (data['deleted'] != true) {
            final kind = switch (command.name.split(' ').first) {
              'inbox' => EntityKind.inbox,
              'calendar' => EntityKind.calendar,
              'diary' => EntityKind.diary,
              _ => EntityKind.memos,
            };
            data = await service.get(kind, data['id']);
          }
        }
      }
    }
    stdout.writeln(
      jsonEncode({'schemaVersion': 1, 'ok': true, 'data': data, 'meta': meta}),
    );
  } catch (error) {
    final e = error is DiurnaException
        ? error
        : error is FormatException || error is ArgumentError
        ? const DiurnaException('VALIDATION', 'Invalid input')
        : error is AuthException
        ? const DiurnaException('AUTH_REQUIRED', 'Authentication failed')
        : error is SocketException
        ? const DiurnaException('SYNC_FAILED', 'Network unavailable')
        : const DiurnaException(
            'INTERNAL',
            'Command failed; no sensitive diagnostic data is emitted',
          );
    exitCode = errorExit(e.code);
    stdout.writeln(
      jsonEncode({
        'schemaVersion': 1,
        'ok': false,
        'error': {'code': e.code, 'message': e.message},
        'meta': meta,
      }),
    );
  } finally {
    await sync?.dispose();
    await database?.close();
    await client?.dispose();
    if (lock != null) {
      await lock.close();
    }
  }
}
