import 'dart:convert';
import 'package:diurna_core/diurna_core.dart';

const _read = {
  'id',
  'query',
  'date',
  'from',
  'to',
  'limit',
  'offset',
  'archived',
  'completed',
  'column',
  'type',
  'topicId',
};
const commandFields = <String, Set<String>>{
  'search': {
    'query',
    'modules',
    'from',
    'to',
    'includeArchived',
    'limit',
    'offset',
  },
  'auth login': {'email'},
  'auth status': {},
  'auth logout': {},
  'sync now': {},
  'sync status': {},
  'sync conflicts': {},
  'sync conflict get': {'id'},
  'sync conflict resolve': {'id', 'use'},
  'inbox list': _read,
  'inbox get': {'id'},
  'inbox search': _read,
  'inbox create': {'content', 'requestId'},
  'inbox update': {
    'id',
    'version',
    'content',
    'type',
    'isTopic',
    'dueDate',
    'priority',
    'completed',
    'pinned',
  },
  'inbox complete': {'id', 'version', 'completed'},
  'inbox archive': {'id', 'version', 'archived'},
  'inbox restore': {'id', 'version'},
  'inbox pin': {'id', 'version', 'pinned'},
  'inbox move': {'id', 'version', 'column', 'beforeId'},
  'inbox assign-topic': {'id', 'version', 'topicId'},
  'inbox delete': {'id', 'version', 'confirmDelete'},
  'calendar list': {'id', 'date', 'from', 'to', 'completed', 'limit', 'offset'},
  'calendar get': {'id'},
  'calendar search': {'query', 'from', 'to', 'limit', 'offset'},
  'calendar create': {'title', 'date', 'note', 'remindAt', 'requestId'},
  'calendar update': {'id', 'version', 'title', 'date', 'note', 'remindAt'},
  'calendar complete': {'id', 'version', 'completed'},
  'calendar delete': {'id', 'version', 'confirmDelete'},
  'memo list': {'limit', 'offset'},
  'memo get': {'id'},
  'memo search': {'query', 'limit', 'offset'},
  'memo create': {'title', 'content', 'requestId'},
  'memo update': {'id', 'version', 'title', 'content', 'appendContent'},
  'memo reorder': {'id', 'version', 'beforeId'},
  'memo delete': {'id', 'version', 'confirmDelete'},
  'diary list': {'from', 'to', 'limit', 'offset'},
  'diary get': {'id'},
  'diary search': {'query', 'from', 'to', 'limit', 'offset'},
  'diary create': {'title', 'content', 'date', 'mood', 'tags', 'requestId'},
  'diary update': {'id', 'version', 'title', 'content', 'date', 'mood', 'tags'},
  'diary delete': {'id', 'version', 'confirmDelete'},
};
const booleans = {
  'archived',
  'completed',
  'isTopic',
  'pinned',
  'includeArchived',
};
const integers = {'priority', 'limit', 'offset'};
const lists = {'tags', 'modules'};
const nullable = {
  'type',
  'dueDate',
  'priority',
  'note',
  'remindAt',
  'mood',
  'topicId',
  'beforeId',
};
String camel(String value) =>
    value.replaceAllMapped(RegExp(r'-([a-z])'), (m) => m[1]!.toUpperCase());

class Command {
  Command(this.name, this.input, {this.offline = false});
  final String name;
  final Map<String, dynamic> input;
  final bool offline;
  bool get writes =>
      !name.startsWith('auth ') &&
      !name.startsWith('sync ') &&
      name != 'search' &&
      !['list', 'get', 'search'].contains(name.split(' ').last);
  static Command parse(List<String> args, {String? stdinJson}) {
    final words = <String>[];
    final flags = <String, dynamic>{};
    var offline = false;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--json' || a == '--input-json') continue;
      if (a == '--offline') {
        offline = true;
        continue;
      }
      if (a.startsWith('--')) {
        final parts = a.substring(2).split('=');
        final key = camel(parts.first);
        if (flags.containsKey(key)) {
          throw const DiurnaException('INVALID_ARGS', 'Duplicate option');
        }
        String raw;
        if (parts.length > 1) {
          raw = parts.skip(1).join('=');
        } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          raw = args[++i];
        } else if (booleans.contains(key)) {
          raw = 'true';
        } else {
          throw const DiurnaException(
            'INVALID_ARGS',
            'Option requires a value',
          );
        }
        flags[key] = raw == 'null' && nullable.contains(key)
            ? null
            : booleans.contains(key)
            ? switch (raw) {
                'true' => true,
                'false' => false,
                _ => throw const DiurnaException(
                  'INVALID_ARGS',
                  'Boolean must be true or false',
                ),
              }
            : integers.contains(key)
            ? int.tryParse(raw) ??
                  (throw const DiurnaException(
                    'INVALID_ARGS',
                    'Integer required',
                  ))
            : lists.contains(key)
            ? raw.split(',')
            : raw;
      } else {
        words.add(a);
      }
    }
    var size = words.isNotEmpty && words.first == 'search' ? 1 : 2;
    if (words.length >= 2 && words[0] == 'sync' && words[1] == 'conflict') {
      size = 3;
    }
    if (words.length < size) {
      throw const DiurnaException(
        'INVALID_ARGS',
        'Specify a module and command; use --help',
      );
    }
    final name = words.take(size).join(' ');
    final allowed = commandFields[name];
    if (allowed == null) {
      throw const DiurnaException('INVALID_ARGS', 'Unknown command');
    }
    if (stdinJson != null) {
      if (flags.isNotEmpty || words.length > size) {
        throw const DiurnaException(
          'INVALID_ARGS',
          'JSON input cannot be combined with field arguments',
        );
      }
      final decoded = jsonDecode(stdinJson);
      if (decoded is! Map<String, dynamic>) {
        throw const DiurnaException('INVALID_ARGS', 'JSON object required');
      }
      flags.addAll(decoded);
    } else if (words.length > size) {
      if (words.length != size + 1) {
        throw const DiurnaException(
          'INVALID_ARGS',
          'Too many positional arguments',
        );
      }
      final key = name == 'search' || name.endsWith(' search')
          ? 'query'
          : name == 'inbox create'
          ? 'content'
          : 'id';
      if (flags.containsKey(key)) {
        throw const DiurnaException(
          'INVALID_ARGS',
          'Duplicate positional field',
        );
      }
      flags[key] = words.last;
    }
    for (final e in flags.entries) {
      if (!allowed.contains(e.key)) {
        throw DiurnaException('INVALID_ARGS', 'Unknown field: ${e.key}');
      }
      if (e.value == null) {
        if (!nullable.contains(e.key)) {
          throw DiurnaException('VALIDATION', '${e.key} cannot be null');
        }
        continue;
      }
      final valid = booleans.contains(e.key)
          ? e.value is bool
          : integers.contains(e.key)
          ? e.value is int
          : lists.contains(e.key)
          ? e.value is List && (e.value as List).every((v) => v is String)
          : e.value is String;
      if (!valid) {
        throw DiurnaException('VALIDATION', 'Invalid type for ${e.key}');
      }
      if ({
            'id',
            'beforeId',
            'topicId',
            'confirmDelete',
            'requestId',
          }.contains(e.key) &&
          !RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(e.value as String)) {
        throw DiurnaException('VALIDATION', '${e.key} must be a UUID');
      }
    }
    if (flags['date'] != null &&
        (flags['from'] != null || flags['to'] != null)) {
      throw const DiurnaException(
        'INVALID_ARGS',
        'date cannot be combined with from/to',
      );
    }
    for (final key in ['date', 'from', 'to', 'dueDate']) {
      if (flags[key] != null) parseDate(flags[key]);
    }
    if (flags['remindAt'] != null) {
      timestamp(flags['remindAt']);
    }
    for (final key in ['column', 'type']) {
      if (flags[key] != null &&
          !(key == 'column'
                  ? ['pending', 'focus']
                  : ['idea', 'action', 'research', 'resource'])
              .contains(flags[key])) {
        throw DiurnaException('VALIDATION', 'Invalid $key');
      }
    }
    if (flags['priority'] != null &&
        (flags['priority'] < 1 || flags['priority'] > 3)) {
      throw const DiurnaException('VALIDATION', 'Priority must be 1..3');
    }
    final requiredFields = <String>{};
    final action = name.split(' ').last;
    if (name == 'search' || action == 'search') requiredFields.add('query');
    if (name == 'auth login') requiredFields.add('email');
    if (action == 'get' || name == 'sync conflict resolve') {
      requiredFields.add('id');
    }
    if (action == 'create') {
      requiredFields.addAll(switch (name) {
        'inbox create' => {'content'},
        'memo create' => {'title'},
        'calendar create' => {'title', 'date'},
        _ => {'title', 'content', 'date'},
      });
    }
    if (!name.startsWith('auth ') &&
        !name.startsWith('sync ') &&
        name != 'search' &&
        !{'list', 'get', 'search', 'create'}.contains(action)) {
      requiredFields.addAll({'id', 'version'});
    }
    if (name == 'inbox move') requiredFields.add('column');
    if (name == 'inbox assign-topic') requiredFields.add('topicId');
    if (name == 'sync conflict resolve') requiredFields.add('use');
    for (final key in requiredFields) {
      if (!flags.containsKey(key)) {
        throw DiurnaException('INVALID_ARGS', 'Missing $key');
      }
    }
    if (flags['version'] != null &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(flags['version'])) {
      throw const DiurnaException(
        'VALIDATION',
        'Use the exact version returned by a prior read',
      );
    }
    if (action == 'update' &&
        flags.keys.every((k) => k == 'id' || k == 'version')) {
      throw const DiurnaException(
        'VALIDATION',
        'Specify at least one update field',
      );
    }
    if (flags.containsKey('content') && flags.containsKey('appendContent')) {
      throw const DiurnaException(
        'VALIDATION',
        'content and appendContent are mutually exclusive',
      );
    }
    if (flags['limit'] != null &&
            (flags['limit'] < 1 || flags['limit'] > 200) ||
        flags['offset'] != null && flags['offset'] < 0) {
      throw const DiurnaException('VALIDATION', 'Invalid pagination');
    }
    if (flags['from'] != null &&
        flags['to'] != null &&
        parseDate(flags['from']).isAfter(parseDate(flags['to']))) {
      throw const DiurnaException('VALIDATION', 'from must not follow to');
    }
    if (flags['modules'] != null &&
        (flags['modules'] as List).any(
          (m) => !{'inbox', 'calendar', 'diary', 'memos'}.contains(m),
        )) {
      throw const DiurnaException('VALIDATION', 'Unknown module');
    }
    if (flags['use'] != null && !{'local', 'remote'}.contains(flags['use'])) {
      throw const DiurnaException('VALIDATION', 'use must be local or remote');
    }
    if (offline &&
        (name == 'sync now' ||
            name == 'sync conflict resolve' ||
            name == 'auth login')) {
      throw const DiurnaException(
        'INVALID_ARGS',
        'This command requires an online session',
      );
    }
    return Command(name, flags, offline: offline);
  }

  static DateTime timestamp(String value) {
    if (!RegExp(r'T.*(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const DiurnaException(
        'VALIDATION',
        'Timestamp requires a timezone',
      );
    }
    return DateTime.tryParse(value)?.toUtc() ??
        (throw const DiurnaException('VALIDATION', 'Invalid timestamp'));
  }

  String required(String key) =>
      input[key] as String? ??
      (throw DiurnaException('INVALID_ARGS', 'Missing $key'));

  Future<Map<String, dynamic>> execute(DiurnaService s) async {
    final p = input;
    DateTime? date(String key) => p[key] == null ? null : parseDate(p[key]);
    Field<T> field<T>(String key, T? Function(dynamic) convert) =>
        p.containsKey(key)
        ? Field.set(p[key] == null ? null : convert(p[key]))
        : Field.absent();
    if (name == 'search') {
      return s.search(
        required('query'),
        modules: (p['modules'] as List?)
            ?.map(
              (v) => EntityKind.values.firstWhere(
                (k) => k.name == v,
                orElse: () =>
                    throw const DiurnaException('VALIDATION', 'Unknown module'),
              ),
            )
            .toList(),
        from: date('from'),
        to: date('to'),
        includeArchived: p['includeArchived'] ?? false,
        limit: p['limit'] ?? 50,
        offset: p['offset'] ?? 0,
      );
    }
    final parts = name.split(' ');
    final action = parts.last;
    final kind = switch (parts.first) {
      'inbox' => EntityKind.inbox,
      'calendar' => EntityKind.calendar,
      'diary' => EntityKind.diary,
      'memo' => EntityKind.memos,
      _ => throw const DiurnaException('INVALID_ARGS', 'Not a data command'),
    };
    if (action == 'get') return s.get(kind, required('id'));
    if (action == 'list' || action == 'search') {
      return s.list(
        kind,
        id: p['id'],
        query: action == 'search' ? required('query') : p['query'],
        from: date('date') ?? date('from'),
        to: date('date') ?? date('to'),
        limit: p['limit'] ?? 50,
        offset: p['offset'] ?? 0,
        archived: kind == EntityKind.inbox ? (p['archived'] ?? false) : null,
        completed: p['completed'],
        column: p['column'] == null
            ? null
            : InboxColumn.values.byName(p['column']),
        itemType: p['type'] == null
            ? null
            : InboxItemType.values.byName(p['type']),
        topicId: p['topicId'],
      );
    }
    if (action == 'create') {
      return switch (kind) {
        EntityKind.inbox => s.createInbox(
          required('content'),
          requestId: p['requestId'],
        ),
        EntityKind.calendar => s.createCalendar(
          title: required('title'),
          date: parseDate(required('date')),
          note: p['note'],
          remindAt: p['remindAt'] == null ? null : timestamp(p['remindAt']),
          requestId: p['requestId'],
        ),
        EntityKind.memos => s.createMemo(
          title: required('title'),
          content: p['content'] ?? '',
          requestId: p['requestId'],
        ),
        EntityKind.diary => s.createDiary(
          title: required('title'),
          content: required('content'),
          date: parseDate(required('date')),
          mood: p['mood'],
          tags: (p['tags'] as List? ?? []).cast<String>(),
          requestId: p['requestId'],
        ),
      };
    }
    final id = required('id'), version = required('version');
    if (action == 'delete') {
      if (p['confirmDelete'] != id) {
        throw const DiurnaException(
          'VALIDATION',
          'Repeat the exact ID in --confirm-delete',
        );
      }
      await s.delete(kind, id, version);
      return {'id': id, 'deleted': true};
    }
    if (name == 'inbox archive' || name == 'inbox restore') {
      return s.archiveInbox(
        id,
        version,
        name == 'inbox restore' ? false : p['archived'] ?? true,
      );
    }
    if (name == 'inbox move') {
      return s.moveInbox(
        id,
        version,
        InboxColumn.values.byName(required('column')),
        p['beforeId'],
      );
    }
    if (name == 'inbox assign-topic') {
      if (!p.containsKey('topicId')) {
        throw const DiurnaException(
          'INVALID_ARGS',
          'topicId is required; use null to detach',
        );
      }
      return s.assignInbox(id, version, p['topicId']);
    }
    if (name == 'calendar complete') {
      return s.completeCalendar(id, version, p['completed'] ?? true);
    }
    if (name == 'memo reorder') {
      return s.reorderMemo(id, version, p['beforeId']);
    }
    return switch (kind) {
      EntityKind.inbox => s.updateInbox(
        id,
        version,
        InboxPatch(
          content: p['content'],
          type: field('type', (v) => InboxItemType.values.byName(v)),
          isTopic: p['isTopic'],
          dueDate: field('dueDate', (v) => parseDate(v)),
          priority: field('priority', (v) => v as int),
          completed: name == 'inbox complete'
              ? p['completed'] ?? true
              : p['completed'],
          pinned: name == 'inbox pin' ? p['pinned'] ?? true : p['pinned'],
        ),
      ),
      EntityKind.calendar => s.updateCalendar(
        id,
        version,
        CalendarPatch(
          title: p['title'],
          date: date('date'),
          note: field('note', (v) => v as String),
          remindAt: field('remindAt', (v) => timestamp(v)),
        ),
      ),
      EntityKind.memos => s.updateMemo(
        id,
        version,
        MemoPatch(
          title: p['title'],
          content: p['content'],
          appendContent: p['appendContent'],
        ),
      ),
      EntityKind.diary => s.updateDiary(
        id,
        version,
        DiaryPatch(
          title: p['title'],
          content: p['content'],
          date: date('date'),
          mood: field('mood', (v) => v as String),
          tags: (p['tags'] as List?)?.cast<String>(),
        ),
      ),
    };
  }
}
