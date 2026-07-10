// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalTasksTable extends LocalTasks
    with TableInfo<$LocalTasksTable, LocalTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isCompletedMeta = const VerificationMeta(
    'isCompleted',
  );
  @override
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
    'is_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _itemTypeMeta = const VerificationMeta(
    'itemType',
  );
  @override
  late final GeneratedColumn<String> itemType = GeneratedColumn<String>(
    'item_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inboxColumnMeta = const VerificationMeta(
    'inboxColumn',
  );
  @override
  late final GeneratedColumn<String> inboxColumn = GeneratedColumn<String>(
    'inbox_column',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<double> sortOrder = GeneratedColumn<double>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isTopicMeta = const VerificationMeta(
    'isTopic',
  );
  @override
  late final GeneratedColumn<bool> isTopic = GeneratedColumn<bool>(
    'is_topic',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_topic" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    title,
    note,
    dueDate,
    priority,
    isCompleted,
    itemType,
    inboxColumn,
    sortOrder,
    isArchived,
    isPinned,
    isTopic,
    parentId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('is_completed')) {
      context.handle(
        _isCompletedMeta,
        isCompleted.isAcceptableOrUnknown(
          data['is_completed']!,
          _isCompletedMeta,
        ),
      );
    }
    if (data.containsKey('item_type')) {
      context.handle(
        _itemTypeMeta,
        itemType.isAcceptableOrUnknown(data['item_type']!, _itemTypeMeta),
      );
    }
    if (data.containsKey('inbox_column')) {
      context.handle(
        _inboxColumnMeta,
        inboxColumn.isAcceptableOrUnknown(
          data['inbox_column']!,
          _inboxColumnMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('is_topic')) {
      context.handle(
        _isTopicMeta,
        isTopic.isAcceptableOrUnknown(data['is_topic']!, _isTopicMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTask(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      ),
      isCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_completed'],
      )!,
      itemType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_type'],
      ),
      inboxColumn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inbox_column'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sort_order'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      isTopic: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_topic'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalTasksTable createAlias(String alias) {
    return $LocalTasksTable(attachedDatabase, alias);
  }
}

class LocalTask extends DataClass implements Insertable<LocalTask> {
  final String id;
  final String userId;
  final String title;
  final String? note;
  final DateTime? dueDate;
  final int? priority;
  final bool isCompleted;
  final String? itemType;
  final String inboxColumn;
  final double sortOrder;
  final bool isArchived;
  final bool isPinned;
  final bool isTopic;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalTask({
    required this.id,
    required this.userId,
    required this.title,
    this.note,
    this.dueDate,
    this.priority,
    required this.isCompleted,
    this.itemType,
    required this.inboxColumn,
    required this.sortOrder,
    required this.isArchived,
    required this.isPinned,
    required this.isTopic,
    this.parentId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || priority != null) {
      map['priority'] = Variable<int>(priority);
    }
    map['is_completed'] = Variable<bool>(isCompleted);
    if (!nullToAbsent || itemType != null) {
      map['item_type'] = Variable<String>(itemType);
    }
    map['inbox_column'] = Variable<String>(inboxColumn);
    map['sort_order'] = Variable<double>(sortOrder);
    map['is_archived'] = Variable<bool>(isArchived);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_topic'] = Variable<bool>(isTopic);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalTasksCompanion toCompanion(bool nullToAbsent) {
    return LocalTasksCompanion(
      id: Value(id),
      userId: Value(userId),
      title: Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      priority: priority == null && nullToAbsent
          ? const Value.absent()
          : Value(priority),
      isCompleted: Value(isCompleted),
      itemType: itemType == null && nullToAbsent
          ? const Value.absent()
          : Value(itemType),
      inboxColumn: Value(inboxColumn),
      sortOrder: Value(sortOrder),
      isArchived: Value(isArchived),
      isPinned: Value(isPinned),
      isTopic: Value(isTopic),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTask(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      title: serializer.fromJson<String>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      priority: serializer.fromJson<int?>(json['priority']),
      isCompleted: serializer.fromJson<bool>(json['isCompleted']),
      itemType: serializer.fromJson<String?>(json['itemType']),
      inboxColumn: serializer.fromJson<String>(json['inboxColumn']),
      sortOrder: serializer.fromJson<double>(json['sortOrder']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isTopic: serializer.fromJson<bool>(json['isTopic']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'title': serializer.toJson<String>(title),
      'note': serializer.toJson<String?>(note),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'priority': serializer.toJson<int?>(priority),
      'isCompleted': serializer.toJson<bool>(isCompleted),
      'itemType': serializer.toJson<String?>(itemType),
      'inboxColumn': serializer.toJson<String>(inboxColumn),
      'sortOrder': serializer.toJson<double>(sortOrder),
      'isArchived': serializer.toJson<bool>(isArchived),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isTopic': serializer.toJson<bool>(isTopic),
      'parentId': serializer.toJson<String?>(parentId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalTask copyWith({
    String? id,
    String? userId,
    String? title,
    Value<String?> note = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    Value<int?> priority = const Value.absent(),
    bool? isCompleted,
    Value<String?> itemType = const Value.absent(),
    String? inboxColumn,
    double? sortOrder,
    bool? isArchived,
    bool? isPinned,
    bool? isTopic,
    Value<String?> parentId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LocalTask(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    title: title ?? this.title,
    note: note.present ? note.value : this.note,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    priority: priority.present ? priority.value : this.priority,
    isCompleted: isCompleted ?? this.isCompleted,
    itemType: itemType.present ? itemType.value : this.itemType,
    inboxColumn: inboxColumn ?? this.inboxColumn,
    sortOrder: sortOrder ?? this.sortOrder,
    isArchived: isArchived ?? this.isArchived,
    isPinned: isPinned ?? this.isPinned,
    isTopic: isTopic ?? this.isTopic,
    parentId: parentId.present ? parentId.value : this.parentId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalTask copyWithCompanion(LocalTasksCompanion data) {
    return LocalTask(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      priority: data.priority.present ? data.priority.value : this.priority,
      isCompleted: data.isCompleted.present
          ? data.isCompleted.value
          : this.isCompleted,
      itemType: data.itemType.present ? data.itemType.value : this.itemType,
      inboxColumn: data.inboxColumn.present
          ? data.inboxColumn.value
          : this.inboxColumn,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isTopic: data.isTopic.present ? data.isTopic.value : this.isTopic,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTask(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('dueDate: $dueDate, ')
          ..write('priority: $priority, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('itemType: $itemType, ')
          ..write('inboxColumn: $inboxColumn, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isArchived: $isArchived, ')
          ..write('isPinned: $isPinned, ')
          ..write('isTopic: $isTopic, ')
          ..write('parentId: $parentId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    title,
    note,
    dueDate,
    priority,
    isCompleted,
    itemType,
    inboxColumn,
    sortOrder,
    isArchived,
    isPinned,
    isTopic,
    parentId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTask &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.title == this.title &&
          other.note == this.note &&
          other.dueDate == this.dueDate &&
          other.priority == this.priority &&
          other.isCompleted == this.isCompleted &&
          other.itemType == this.itemType &&
          other.inboxColumn == this.inboxColumn &&
          other.sortOrder == this.sortOrder &&
          other.isArchived == this.isArchived &&
          other.isPinned == this.isPinned &&
          other.isTopic == this.isTopic &&
          other.parentId == this.parentId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalTasksCompanion extends UpdateCompanion<LocalTask> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> title;
  final Value<String?> note;
  final Value<DateTime?> dueDate;
  final Value<int?> priority;
  final Value<bool> isCompleted;
  final Value<String?> itemType;
  final Value<String> inboxColumn;
  final Value<double> sortOrder;
  final Value<bool> isArchived;
  final Value<bool> isPinned;
  final Value<bool> isTopic;
  final Value<String?> parentId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalTasksCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.priority = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.itemType = const Value.absent(),
    this.inboxColumn = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isTopic = const Value.absent(),
    this.parentId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTasksCompanion.insert({
    required String id,
    required String userId,
    required String title,
    this.note = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.priority = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.itemType = const Value.absent(),
    this.inboxColumn = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isTopic = const Value.absent(),
    this.parentId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalTask> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? title,
    Expression<String>? note,
    Expression<DateTime>? dueDate,
    Expression<int>? priority,
    Expression<bool>? isCompleted,
    Expression<String>? itemType,
    Expression<String>? inboxColumn,
    Expression<double>? sortOrder,
    Expression<bool>? isArchived,
    Expression<bool>? isPinned,
    Expression<bool>? isTopic,
    Expression<String>? parentId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (dueDate != null) 'due_date': dueDate,
      if (priority != null) 'priority': priority,
      if (isCompleted != null) 'is_completed': isCompleted,
      if (itemType != null) 'item_type': itemType,
      if (inboxColumn != null) 'inbox_column': inboxColumn,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isArchived != null) 'is_archived': isArchived,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isTopic != null) 'is_topic': isTopic,
      if (parentId != null) 'parent_id': parentId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? title,
    Value<String?>? note,
    Value<DateTime?>? dueDate,
    Value<int?>? priority,
    Value<bool>? isCompleted,
    Value<String?>? itemType,
    Value<String>? inboxColumn,
    Value<double>? sortOrder,
    Value<bool>? isArchived,
    Value<bool>? isPinned,
    Value<bool>? isTopic,
    Value<String?>? parentId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalTasksCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      note: note ?? this.note,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      itemType: itemType ?? this.itemType,
      inboxColumn: inboxColumn ?? this.inboxColumn,
      sortOrder: sortOrder ?? this.sortOrder,
      isArchived: isArchived ?? this.isArchived,
      isPinned: isPinned ?? this.isPinned,
      isTopic: isTopic ?? this.isTopic,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    if (itemType.present) {
      map['item_type'] = Variable<String>(itemType.value);
    }
    if (inboxColumn.present) {
      map['inbox_column'] = Variable<String>(inboxColumn.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<double>(sortOrder.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isTopic.present) {
      map['is_topic'] = Variable<bool>(isTopic.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTasksCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('dueDate: $dueDate, ')
          ..write('priority: $priority, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('itemType: $itemType, ')
          ..write('inboxColumn: $inboxColumn, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isArchived: $isArchived, ')
          ..write('isPinned: $isPinned, ')
          ..write('isTopic: $isTopic, ')
          ..write('parentId: $parentId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalDiaryEntriesTable extends LocalDiaryEntries
    with TableInfo<$LocalDiaryEntriesTable, LocalDiaryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalDiaryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryDateMeta = const VerificationMeta(
    'entryDate',
  );
  @override
  late final GeneratedColumn<DateTime> entryDate = GeneratedColumn<DateTime>(
    'entry_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<String> mood = GeneratedColumn<String>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    entryDate,
    title,
    content,
    mood,
    tagsJson,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_diary_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalDiaryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entry_date')) {
      context.handle(
        _entryDateMeta,
        entryDate.isAcceptableOrUnknown(data['entry_date']!, _entryDateMeta),
      );
    } else if (isInserting) {
      context.missing(_entryDateMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalDiaryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalDiaryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entryDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}entry_date'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mood'],
      ),
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalDiaryEntriesTable createAlias(String alias) {
    return $LocalDiaryEntriesTable(attachedDatabase, alias);
  }
}

class LocalDiaryEntry extends DataClass implements Insertable<LocalDiaryEntry> {
  final String id;
  final String userId;
  final DateTime entryDate;
  final String title;
  final String content;
  final String? mood;
  final String tagsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalDiaryEntry({
    required this.id,
    required this.userId,
    required this.entryDate,
    required this.title,
    required this.content,
    this.mood,
    required this.tagsJson,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['entry_date'] = Variable<DateTime>(entryDate);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<String>(mood);
    }
    map['tags_json'] = Variable<String>(tagsJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalDiaryEntriesCompanion toCompanion(bool nullToAbsent) {
    return LocalDiaryEntriesCompanion(
      id: Value(id),
      userId: Value(userId),
      entryDate: Value(entryDate),
      title: Value(title),
      content: Value(content),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      tagsJson: Value(tagsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalDiaryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalDiaryEntry(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      entryDate: serializer.fromJson<DateTime>(json['entryDate']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      mood: serializer.fromJson<String?>(json['mood']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'entryDate': serializer.toJson<DateTime>(entryDate),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'mood': serializer.toJson<String?>(mood),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalDiaryEntry copyWith({
    String? id,
    String? userId,
    DateTime? entryDate,
    String? title,
    String? content,
    Value<String?> mood = const Value.absent(),
    String? tagsJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LocalDiaryEntry(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    entryDate: entryDate ?? this.entryDate,
    title: title ?? this.title,
    content: content ?? this.content,
    mood: mood.present ? mood.value : this.mood,
    tagsJson: tagsJson ?? this.tagsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalDiaryEntry copyWithCompanion(LocalDiaryEntriesCompanion data) {
    return LocalDiaryEntry(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      entryDate: data.entryDate.present ? data.entryDate.value : this.entryDate,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      mood: data.mood.present ? data.mood.value : this.mood,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalDiaryEntry(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('entryDate: $entryDate, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('mood: $mood, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    entryDate,
    title,
    content,
    mood,
    tagsJson,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDiaryEntry &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.entryDate == this.entryDate &&
          other.title == this.title &&
          other.content == this.content &&
          other.mood == this.mood &&
          other.tagsJson == this.tagsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalDiaryEntriesCompanion extends UpdateCompanion<LocalDiaryEntry> {
  final Value<String> id;
  final Value<String> userId;
  final Value<DateTime> entryDate;
  final Value<String> title;
  final Value<String> content;
  final Value<String?> mood;
  final Value<String> tagsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalDiaryEntriesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.entryDate = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.mood = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalDiaryEntriesCompanion.insert({
    required String id,
    required String userId,
    required DateTime entryDate,
    required String title,
    required String content,
    this.mood = const Value.absent(),
    this.tagsJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       entryDate = Value(entryDate),
       title = Value(title),
       content = Value(content),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalDiaryEntry> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<DateTime>? entryDate,
    Expression<String>? title,
    Expression<String>? content,
    Expression<String>? mood,
    Expression<String>? tagsJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (entryDate != null) 'entry_date': entryDate,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (mood != null) 'mood': mood,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalDiaryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<DateTime>? entryDate,
    Value<String>? title,
    Value<String>? content,
    Value<String?>? mood,
    Value<String>? tagsJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalDiaryEntriesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      entryDate: entryDate ?? this.entryDate,
      title: title ?? this.title,
      content: content ?? this.content,
      mood: mood ?? this.mood,
      tagsJson: tagsJson ?? this.tagsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entryDate.present) {
      map['entry_date'] = Variable<DateTime>(entryDate.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (mood.present) {
      map['mood'] = Variable<String>(mood.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalDiaryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('entryDate: $entryDate, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('mood: $mood, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCalendarEventsTable extends LocalCalendarEvents
    with TableInfo<$LocalCalendarEventsTable, LocalCalendarEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCalendarEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledDateMeta = const VerificationMeta(
    'scheduledDate',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledDate =
      GeneratedColumn<DateTime>(
        'scheduled_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _isCompletedMeta = const VerificationMeta(
    'isCompleted',
  );
  @override
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
    'is_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remindAtMeta = const VerificationMeta(
    'remindAt',
  );
  @override
  late final GeneratedColumn<DateTime> remindAt = GeneratedColumn<DateTime>(
    'remind_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    title,
    scheduledDate,
    isCompleted,
    note,
    remindAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_calendar_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCalendarEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('scheduled_date')) {
      context.handle(
        _scheduledDateMeta,
        scheduledDate.isAcceptableOrUnknown(
          data['scheduled_date']!,
          _scheduledDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledDateMeta);
    }
    if (data.containsKey('is_completed')) {
      context.handle(
        _isCompletedMeta,
        isCompleted.isAcceptableOrUnknown(
          data['is_completed']!,
          _isCompletedMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('remind_at')) {
      context.handle(
        _remindAtMeta,
        remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalCalendarEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCalendarEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      scheduledDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_date'],
      )!,
      isCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_completed'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      remindAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}remind_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalCalendarEventsTable createAlias(String alias) {
    return $LocalCalendarEventsTable(attachedDatabase, alias);
  }
}

class LocalCalendarEvent extends DataClass
    implements Insertable<LocalCalendarEvent> {
  final String id;
  final String userId;
  final String title;
  final DateTime scheduledDate;
  final bool isCompleted;
  final String? note;
  final DateTime? remindAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalCalendarEvent({
    required this.id,
    required this.userId,
    required this.title,
    required this.scheduledDate,
    required this.isCompleted,
    this.note,
    this.remindAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['title'] = Variable<String>(title);
    map['scheduled_date'] = Variable<DateTime>(scheduledDate);
    map['is_completed'] = Variable<bool>(isCompleted);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || remindAt != null) {
      map['remind_at'] = Variable<DateTime>(remindAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalCalendarEventsCompanion toCompanion(bool nullToAbsent) {
    return LocalCalendarEventsCompanion(
      id: Value(id),
      userId: Value(userId),
      title: Value(title),
      scheduledDate: Value(scheduledDate),
      isCompleted: Value(isCompleted),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      remindAt: remindAt == null && nullToAbsent
          ? const Value.absent()
          : Value(remindAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalCalendarEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCalendarEvent(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      title: serializer.fromJson<String>(json['title']),
      scheduledDate: serializer.fromJson<DateTime>(json['scheduledDate']),
      isCompleted: serializer.fromJson<bool>(json['isCompleted']),
      note: serializer.fromJson<String?>(json['note']),
      remindAt: serializer.fromJson<DateTime?>(json['remindAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'title': serializer.toJson<String>(title),
      'scheduledDate': serializer.toJson<DateTime>(scheduledDate),
      'isCompleted': serializer.toJson<bool>(isCompleted),
      'note': serializer.toJson<String?>(note),
      'remindAt': serializer.toJson<DateTime?>(remindAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalCalendarEvent copyWith({
    String? id,
    String? userId,
    String? title,
    DateTime? scheduledDate,
    bool? isCompleted,
    Value<String?> note = const Value.absent(),
    Value<DateTime?> remindAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LocalCalendarEvent(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    title: title ?? this.title,
    scheduledDate: scheduledDate ?? this.scheduledDate,
    isCompleted: isCompleted ?? this.isCompleted,
    note: note.present ? note.value : this.note,
    remindAt: remindAt.present ? remindAt.value : this.remindAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalCalendarEvent copyWithCompanion(LocalCalendarEventsCompanion data) {
    return LocalCalendarEvent(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      title: data.title.present ? data.title.value : this.title,
      scheduledDate: data.scheduledDate.present
          ? data.scheduledDate.value
          : this.scheduledDate,
      isCompleted: data.isCompleted.present
          ? data.isCompleted.value
          : this.isCompleted,
      note: data.note.present ? data.note.value : this.note,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCalendarEvent(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('scheduledDate: $scheduledDate, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('note: $note, ')
          ..write('remindAt: $remindAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    title,
    scheduledDate,
    isCompleted,
    note,
    remindAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCalendarEvent &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.title == this.title &&
          other.scheduledDate == this.scheduledDate &&
          other.isCompleted == this.isCompleted &&
          other.note == this.note &&
          other.remindAt == this.remindAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalCalendarEventsCompanion extends UpdateCompanion<LocalCalendarEvent> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> title;
  final Value<DateTime> scheduledDate;
  final Value<bool> isCompleted;
  final Value<String?> note;
  final Value<DateTime?> remindAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalCalendarEventsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.title = const Value.absent(),
    this.scheduledDate = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.note = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCalendarEventsCompanion.insert({
    required String id,
    required String userId,
    required String title,
    required DateTime scheduledDate,
    this.isCompleted = const Value.absent(),
    this.note = const Value.absent(),
    this.remindAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       title = Value(title),
       scheduledDate = Value(scheduledDate),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalCalendarEvent> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? title,
    Expression<DateTime>? scheduledDate,
    Expression<bool>? isCompleted,
    Expression<String>? note,
    Expression<DateTime>? remindAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (title != null) 'title': title,
      if (scheduledDate != null) 'scheduled_date': scheduledDate,
      if (isCompleted != null) 'is_completed': isCompleted,
      if (note != null) 'note': note,
      if (remindAt != null) 'remind_at': remindAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCalendarEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? title,
    Value<DateTime>? scheduledDate,
    Value<bool>? isCompleted,
    Value<String?>? note,
    Value<DateTime?>? remindAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalCalendarEventsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      isCompleted: isCompleted ?? this.isCompleted,
      note: note ?? this.note,
      remindAt: remindAt ?? this.remindAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (scheduledDate.present) {
      map['scheduled_date'] = Variable<DateTime>(scheduledDate.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<DateTime>(remindAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCalendarEventsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('scheduledDate: $scheduledDate, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('note: $note, ')
          ..write('remindAt: $remindAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingSyncOperationsTable extends PendingSyncOperations
    with TableInfo<$PendingSyncOperationsTable, PendingSyncOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    userId,
    entityType,
    entityId,
    operation,
    payloadJson,
    createdAt,
    attemptCount,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_sync_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingSyncOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  PendingSyncOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingSyncOperation(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $PendingSyncOperationsTable createAlias(String alias) {
    return $PendingSyncOperationsTable(attachedDatabase, alias);
  }
}

class PendingSyncOperation extends DataClass
    implements Insertable<PendingSyncOperation> {
  final String key;
  final String userId;
  final String entityType;
  final String entityId;
  final String operation;
  final String? payloadJson;
  final DateTime createdAt;
  final int attemptCount;
  final String? lastError;
  const PendingSyncOperation({
    required this.key,
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.payloadJson,
    required this.createdAt,
    required this.attemptCount,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  PendingSyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return PendingSyncOperationsCompanion(
      key: Value(key),
      userId: Value(userId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
      createdAt: Value(createdAt),
      attemptCount: Value(attemptCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory PendingSyncOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingSyncOperation(
      key: serializer.fromJson<String>(json['key']),
      userId: serializer.fromJson<String>(json['userId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'userId': serializer.toJson<String>(userId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payloadJson': serializer.toJson<String?>(payloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  PendingSyncOperation copyWith({
    String? key,
    String? userId,
    String? entityType,
    String? entityId,
    String? operation,
    Value<String?> payloadJson = const Value.absent(),
    DateTime? createdAt,
    int? attemptCount,
    Value<String?> lastError = const Value.absent(),
  }) => PendingSyncOperation(
    key: key ?? this.key,
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
    attemptCount: attemptCount ?? this.attemptCount,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  PendingSyncOperation copyWithCompanion(PendingSyncOperationsCompanion data) {
    return PendingSyncOperation(
      key: data.key.present ? data.key.value : this.key,
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSyncOperation(')
          ..write('key: $key, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    key,
    userId,
    entityType,
    entityId,
    operation,
    payloadJson,
    createdAt,
    attemptCount,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingSyncOperation &&
          other.key == this.key &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt &&
          other.attemptCount == this.attemptCount &&
          other.lastError == this.lastError);
}

class PendingSyncOperationsCompanion
    extends UpdateCompanion<PendingSyncOperation> {
  final Value<String> key;
  final Value<String> userId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String?> payloadJson;
  final Value<DateTime> createdAt;
  final Value<int> attemptCount;
  final Value<String?> lastError;
  final Value<int> rowid;
  const PendingSyncOperationsCompanion({
    this.key = const Value.absent(),
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingSyncOperationsCompanion.insert({
    required String key,
    required String userId,
    required String entityType,
    required String entityId,
    required String operation,
    this.payloadJson = const Value.absent(),
    required DateTime createdAt,
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       userId = Value(userId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       createdAt = Value(createdAt);
  static Insertable<PendingSyncOperation> custom({
    Expression<String>? key,
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAt,
    Expression<int>? attemptCount,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingSyncOperationsCompanion copyWith({
    Value<String>? key,
    Value<String>? userId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String?>? payloadJson,
    Value<DateTime>? createdAt,
    Value<int>? attemptCount,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return PendingSyncOperationsCompanion(
      key: key ?? this.key,
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSyncOperationsCompanion(')
          ..write('key: $key, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalTasksTable localTasks = $LocalTasksTable(this);
  late final $LocalDiaryEntriesTable localDiaryEntries =
      $LocalDiaryEntriesTable(this);
  late final $LocalCalendarEventsTable localCalendarEvents =
      $LocalCalendarEventsTable(this);
  late final $PendingSyncOperationsTable pendingSyncOperations =
      $PendingSyncOperationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localTasks,
    localDiaryEntries,
    localCalendarEvents,
    pendingSyncOperations,
  ];
}

typedef $$LocalTasksTableCreateCompanionBuilder =
    LocalTasksCompanion Function({
      required String id,
      required String userId,
      required String title,
      Value<String?> note,
      Value<DateTime?> dueDate,
      Value<int?> priority,
      Value<bool> isCompleted,
      Value<String?> itemType,
      Value<String> inboxColumn,
      Value<double> sortOrder,
      Value<bool> isArchived,
      Value<bool> isPinned,
      Value<bool> isTopic,
      Value<String?> parentId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalTasksTableUpdateCompanionBuilder =
    LocalTasksCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> title,
      Value<String?> note,
      Value<DateTime?> dueDate,
      Value<int?> priority,
      Value<bool> isCompleted,
      Value<String?> itemType,
      Value<String> inboxColumn,
      Value<double> sortOrder,
      Value<bool> isArchived,
      Value<bool> isPinned,
      Value<bool> isTopic,
      Value<String?> parentId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalTasksTableFilterComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inboxColumn => $composableBuilder(
    column: $table.inboxColumn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTopic => $composableBuilder(
    column: $table.isTopic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inboxColumn => $composableBuilder(
    column: $table.inboxColumn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTopic => $composableBuilder(
    column: $table.isTopic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemType =>
      $composableBuilder(column: $table.itemType, builder: (column) => column);

  GeneratedColumn<String> get inboxColumn => $composableBuilder(
    column: $table.inboxColumn,
    builder: (column) => column,
  );

  GeneratedColumn<double> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get isTopic =>
      $composableBuilder(column: $table.isTopic, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalTasksTable,
          LocalTask,
          $$LocalTasksTableFilterComposer,
          $$LocalTasksTableOrderingComposer,
          $$LocalTasksTableAnnotationComposer,
          $$LocalTasksTableCreateCompanionBuilder,
          $$LocalTasksTableUpdateCompanionBuilder,
          (
            LocalTask,
            BaseReferences<_$AppDatabase, $LocalTasksTable, LocalTask>,
          ),
          LocalTask,
          PrefetchHooks Function()
        > {
  $$LocalTasksTableTableManager(_$AppDatabase db, $LocalTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int?> priority = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<String?> itemType = const Value.absent(),
                Value<String> inboxColumn = const Value.absent(),
                Value<double> sortOrder = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isTopic = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTasksCompanion(
                id: id,
                userId: userId,
                title: title,
                note: note,
                dueDate: dueDate,
                priority: priority,
                isCompleted: isCompleted,
                itemType: itemType,
                inboxColumn: inboxColumn,
                sortOrder: sortOrder,
                isArchived: isArchived,
                isPinned: isPinned,
                isTopic: isTopic,
                parentId: parentId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String title,
                Value<String?> note = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int?> priority = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<String?> itemType = const Value.absent(),
                Value<String> inboxColumn = const Value.absent(),
                Value<double> sortOrder = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isTopic = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalTasksCompanion.insert(
                id: id,
                userId: userId,
                title: title,
                note: note,
                dueDate: dueDate,
                priority: priority,
                isCompleted: isCompleted,
                itemType: itemType,
                inboxColumn: inboxColumn,
                sortOrder: sortOrder,
                isArchived: isArchived,
                isPinned: isPinned,
                isTopic: isTopic,
                parentId: parentId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalTasksTable,
      LocalTask,
      $$LocalTasksTableFilterComposer,
      $$LocalTasksTableOrderingComposer,
      $$LocalTasksTableAnnotationComposer,
      $$LocalTasksTableCreateCompanionBuilder,
      $$LocalTasksTableUpdateCompanionBuilder,
      (LocalTask, BaseReferences<_$AppDatabase, $LocalTasksTable, LocalTask>),
      LocalTask,
      PrefetchHooks Function()
    >;
typedef $$LocalDiaryEntriesTableCreateCompanionBuilder =
    LocalDiaryEntriesCompanion Function({
      required String id,
      required String userId,
      required DateTime entryDate,
      required String title,
      required String content,
      Value<String?> mood,
      Value<String> tagsJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalDiaryEntriesTableUpdateCompanionBuilder =
    LocalDiaryEntriesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<DateTime> entryDate,
      Value<String> title,
      Value<String> content,
      Value<String?> mood,
      Value<String> tagsJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalDiaryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalDiaryEntriesTable> {
  $$LocalDiaryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalDiaryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalDiaryEntriesTable> {
  $$LocalDiaryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalDiaryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalDiaryEntriesTable> {
  $$LocalDiaryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get entryDate =>
      $composableBuilder(column: $table.entryDate, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalDiaryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalDiaryEntriesTable,
          LocalDiaryEntry,
          $$LocalDiaryEntriesTableFilterComposer,
          $$LocalDiaryEntriesTableOrderingComposer,
          $$LocalDiaryEntriesTableAnnotationComposer,
          $$LocalDiaryEntriesTableCreateCompanionBuilder,
          $$LocalDiaryEntriesTableUpdateCompanionBuilder,
          (
            LocalDiaryEntry,
            BaseReferences<
              _$AppDatabase,
              $LocalDiaryEntriesTable,
              LocalDiaryEntry
            >,
          ),
          LocalDiaryEntry,
          PrefetchHooks Function()
        > {
  $$LocalDiaryEntriesTableTableManager(
    _$AppDatabase db,
    $LocalDiaryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalDiaryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalDiaryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalDiaryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<DateTime> entryDate = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> mood = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDiaryEntriesCompanion(
                id: id,
                userId: userId,
                entryDate: entryDate,
                title: title,
                content: content,
                mood: mood,
                tagsJson: tagsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required DateTime entryDate,
                required String title,
                required String content,
                Value<String?> mood = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalDiaryEntriesCompanion.insert(
                id: id,
                userId: userId,
                entryDate: entryDate,
                title: title,
                content: content,
                mood: mood,
                tagsJson: tagsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalDiaryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalDiaryEntriesTable,
      LocalDiaryEntry,
      $$LocalDiaryEntriesTableFilterComposer,
      $$LocalDiaryEntriesTableOrderingComposer,
      $$LocalDiaryEntriesTableAnnotationComposer,
      $$LocalDiaryEntriesTableCreateCompanionBuilder,
      $$LocalDiaryEntriesTableUpdateCompanionBuilder,
      (
        LocalDiaryEntry,
        BaseReferences<_$AppDatabase, $LocalDiaryEntriesTable, LocalDiaryEntry>,
      ),
      LocalDiaryEntry,
      PrefetchHooks Function()
    >;
typedef $$LocalCalendarEventsTableCreateCompanionBuilder =
    LocalCalendarEventsCompanion Function({
      required String id,
      required String userId,
      required String title,
      required DateTime scheduledDate,
      Value<bool> isCompleted,
      Value<String?> note,
      Value<DateTime?> remindAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalCalendarEventsTableUpdateCompanionBuilder =
    LocalCalendarEventsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> title,
      Value<DateTime> scheduledDate,
      Value<bool> isCompleted,
      Value<String?> note,
      Value<DateTime?> remindAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalCalendarEventsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalCalendarEventsTable> {
  $$LocalCalendarEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCalendarEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalCalendarEventsTable> {
  $$LocalCalendarEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCalendarEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalCalendarEventsTable> {
  $$LocalCalendarEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalCalendarEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalCalendarEventsTable,
          LocalCalendarEvent,
          $$LocalCalendarEventsTableFilterComposer,
          $$LocalCalendarEventsTableOrderingComposer,
          $$LocalCalendarEventsTableAnnotationComposer,
          $$LocalCalendarEventsTableCreateCompanionBuilder,
          $$LocalCalendarEventsTableUpdateCompanionBuilder,
          (
            LocalCalendarEvent,
            BaseReferences<
              _$AppDatabase,
              $LocalCalendarEventsTable,
              LocalCalendarEvent
            >,
          ),
          LocalCalendarEvent,
          PrefetchHooks Function()
        > {
  $$LocalCalendarEventsTableTableManager(
    _$AppDatabase db,
    $LocalCalendarEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCalendarEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCalendarEventsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalCalendarEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DateTime> scheduledDate = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime?> remindAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCalendarEventsCompanion(
                id: id,
                userId: userId,
                title: title,
                scheduledDate: scheduledDate,
                isCompleted: isCompleted,
                note: note,
                remindAt: remindAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String title,
                required DateTime scheduledDate,
                Value<bool> isCompleted = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime?> remindAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalCalendarEventsCompanion.insert(
                id: id,
                userId: userId,
                title: title,
                scheduledDate: scheduledDate,
                isCompleted: isCompleted,
                note: note,
                remindAt: remindAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCalendarEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalCalendarEventsTable,
      LocalCalendarEvent,
      $$LocalCalendarEventsTableFilterComposer,
      $$LocalCalendarEventsTableOrderingComposer,
      $$LocalCalendarEventsTableAnnotationComposer,
      $$LocalCalendarEventsTableCreateCompanionBuilder,
      $$LocalCalendarEventsTableUpdateCompanionBuilder,
      (
        LocalCalendarEvent,
        BaseReferences<
          _$AppDatabase,
          $LocalCalendarEventsTable,
          LocalCalendarEvent
        >,
      ),
      LocalCalendarEvent,
      PrefetchHooks Function()
    >;
typedef $$PendingSyncOperationsTableCreateCompanionBuilder =
    PendingSyncOperationsCompanion Function({
      required String key,
      required String userId,
      required String entityType,
      required String entityId,
      required String operation,
      Value<String?> payloadJson,
      required DateTime createdAt,
      Value<int> attemptCount,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$PendingSyncOperationsTableUpdateCompanionBuilder =
    PendingSyncOperationsCompanion Function({
      Value<String> key,
      Value<String> userId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String?> payloadJson,
      Value<DateTime> createdAt,
      Value<int> attemptCount,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$PendingSyncOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingSyncOperationsTable> {
  $$PendingSyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingSyncOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingSyncOperationsTable> {
  $$PendingSyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingSyncOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingSyncOperationsTable> {
  $$PendingSyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$PendingSyncOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingSyncOperationsTable,
          PendingSyncOperation,
          $$PendingSyncOperationsTableFilterComposer,
          $$PendingSyncOperationsTableOrderingComposer,
          $$PendingSyncOperationsTableAnnotationComposer,
          $$PendingSyncOperationsTableCreateCompanionBuilder,
          $$PendingSyncOperationsTableUpdateCompanionBuilder,
          (
            PendingSyncOperation,
            BaseReferences<
              _$AppDatabase,
              $PendingSyncOperationsTable,
              PendingSyncOperation
            >,
          ),
          PendingSyncOperation,
          PrefetchHooks Function()
        > {
  $$PendingSyncOperationsTableTableManager(
    _$AppDatabase db,
    $PendingSyncOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingSyncOperationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PendingSyncOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PendingSyncOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSyncOperationsCompanion(
                key: key,
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payloadJson: payloadJson,
                createdAt: createdAt,
                attemptCount: attemptCount,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String userId,
                required String entityType,
                required String entityId,
                required String operation,
                Value<String?> payloadJson = const Value.absent(),
                required DateTime createdAt,
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSyncOperationsCompanion.insert(
                key: key,
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payloadJson: payloadJson,
                createdAt: createdAt,
                attemptCount: attemptCount,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingSyncOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingSyncOperationsTable,
      PendingSyncOperation,
      $$PendingSyncOperationsTableFilterComposer,
      $$PendingSyncOperationsTableOrderingComposer,
      $$PendingSyncOperationsTableAnnotationComposer,
      $$PendingSyncOperationsTableCreateCompanionBuilder,
      $$PendingSyncOperationsTableUpdateCompanionBuilder,
      (
        PendingSyncOperation,
        BaseReferences<
          _$AppDatabase,
          $PendingSyncOperationsTable,
          PendingSyncOperation
        >,
      ),
      PendingSyncOperation,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalTasksTableTableManager get localTasks =>
      $$LocalTasksTableTableManager(_db, _db.localTasks);
  $$LocalDiaryEntriesTableTableManager get localDiaryEntries =>
      $$LocalDiaryEntriesTableTableManager(_db, _db.localDiaryEntries);
  $$LocalCalendarEventsTableTableManager get localCalendarEvents =>
      $$LocalCalendarEventsTableTableManager(_db, _db.localCalendarEvents);
  $$PendingSyncOperationsTableTableManager get pendingSyncOperations =>
      $$PendingSyncOperationsTableTableManager(_db, _db.pendingSyncOperations);
}
