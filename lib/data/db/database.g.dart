// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AccountKind, int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  ).withConverter<AccountKind>($AccountsTable.$converterkind);
  static const VerificationMeta _institutionMeta = const VerificationMeta('institution');
  @override
  late final GeneratedColumn<String> institution = GeneratedColumn<String>(
    'institution',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _last4Meta = const VerificationMeta('last4');
  @override
  late final GeneratedColumn<String> last4 = GeneratedColumn<String>(
    'last4',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta('archived');
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("archived" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, kind, institution, last4, color, archived];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(Insertable<Account> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('institution')) {
      context.handle(_institutionMeta, institution.isAcceptableOrUnknown(data['institution']!, _institutionMeta));
    }
    if (data.containsKey('last4')) {
      context.handle(_last4Meta, last4.isAcceptableOrUnknown(data['last4']!, _last4Meta));
    }
    if (data.containsKey('color')) {
      context.handle(_colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('archived')) {
      context.handle(_archivedMeta, archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      kind: $AccountsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}kind'])!,
      ),
      institution: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}institution']),
      last4: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}last4']),
      color: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}color'])!,
      archived: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}archived'])!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AccountKind, int, int> $converterkind = const EnumIndexConverter<AccountKind>(
    AccountKind.values,
  );
}

class Account extends DataClass implements Insertable<Account> {
  final int id;
  final String name;
  final AccountKind kind;
  final String? institution;

  /// Last 3–4 digits of account / card number, used to match messages.
  final String? last4;
  final int color;
  final bool archived;
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    this.institution,
    this.last4,
    required this.color,
    required this.archived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    {
      map['kind'] = Variable<int>($AccountsTable.$converterkind.toSql(kind));
    }
    if (!nullToAbsent || institution != null) {
      map['institution'] = Variable<String>(institution);
    }
    if (!nullToAbsent || last4 != null) {
      map['last4'] = Variable<String>(last4);
    }
    map['color'] = Variable<int>(color);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      institution: institution == null && nullToAbsent ? const Value.absent() : Value(institution),
      last4: last4 == null && nullToAbsent ? const Value.absent() : Value(last4),
      color: Value(color),
      archived: Value(archived),
    );
  }

  factory Account.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: $AccountsTable.$converterkind.fromJson(serializer.fromJson<int>(json['kind'])),
      institution: serializer.fromJson<String?>(json['institution']),
      last4: serializer.fromJson<String?>(json['last4']),
      color: serializer.fromJson<int>(json['color']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<int>($AccountsTable.$converterkind.toJson(kind)),
      'institution': serializer.toJson<String?>(institution),
      'last4': serializer.toJson<String?>(last4),
      'color': serializer.toJson<int>(color),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  Account copyWith({
    int? id,
    String? name,
    AccountKind? kind,
    Value<String?> institution = const Value.absent(),
    Value<String?> last4 = const Value.absent(),
    int? color,
    bool? archived,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    institution: institution.present ? institution.value : this.institution,
    last4: last4.present ? last4.value : this.last4,
    color: color ?? this.color,
    archived: archived ?? this.archived,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      institution: data.institution.present ? data.institution.value : this.institution,
      last4: data.last4.present ? data.last4.value : this.last4,
      color: data.color.present ? data.color.value : this.color,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('institution: $institution, ')
          ..write('last4: $last4, ')
          ..write('color: $color, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, kind, institution, last4, color, archived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.institution == this.institution &&
          other.last4 == this.last4 &&
          other.color == this.color &&
          other.archived == this.archived);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<int> id;
  final Value<String> name;
  final Value<AccountKind> kind;
  final Value<String?> institution;
  final Value<String?> last4;
  final Value<int> color;
  final Value<bool> archived;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.institution = const Value.absent(),
    this.last4 = const Value.absent(),
    this.color = const Value.absent(),
    this.archived = const Value.absent(),
  });
  AccountsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required AccountKind kind,
    this.institution = const Value.absent(),
    this.last4 = const Value.absent(),
    required int color,
    this.archived = const Value.absent(),
  }) : name = Value(name),
       kind = Value(kind),
       color = Value(color);
  static Insertable<Account> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? kind,
    Expression<String>? institution,
    Expression<String>? last4,
    Expression<int>? color,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (institution != null) 'institution': institution,
      if (last4 != null) 'last4': last4,
      if (color != null) 'color': color,
      if (archived != null) 'archived': archived,
    });
  }

  AccountsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<AccountKind>? kind,
    Value<String?>? institution,
    Value<String?>? last4,
    Value<int>? color,
    Value<bool>? archived,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      institution: institution ?? this.institution,
      last4: last4 ?? this.last4,
      color: color ?? this.color,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>($AccountsTable.$converterkind.toSql(kind.value));
    }
    if (institution.present) {
      map['institution'] = Variable<String>(institution.value);
    }
    if (last4.present) {
      map['last4'] = Variable<String>(last4.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('institution: $institution, ')
          ..write('last4: $last4, ')
          ..write('color: $color, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isIncomeMeta = const VerificationMeta('isIncome');
  @override
  late final GeneratedColumn<bool> isIncome = GeneratedColumn<bool>(
    'is_income',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("is_income" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _seedNameMeta = const VerificationMeta('seedName');
  @override
  late final GeneratedColumn<String> seedName = GeneratedColumn<String>(
    'seed_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, icon, color, isIncome, sortOrder, seedName];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(Insertable<Category> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(_iconMeta, icon.isAcceptableOrUnknown(data['icon']!, _iconMeta));
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('color')) {
      context.handle(_colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('is_income')) {
      context.handle(_isIncomeMeta, isIncome.isAcceptableOrUnknown(data['is_income']!, _isIncomeMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta, sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('seed_name')) {
      context.handle(_seedNameMeta, seedName.isAcceptableOrUnknown(data['seed_name']!, _seedNameMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      icon: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}icon'])!,
      color: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}color'])!,
      isIncome: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}is_income'])!,
      sortOrder: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      seedName: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}seed_name']),
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final int id;
  final String name;

  /// Key into [CategoryIcons]; stored as text so icon sets can change.
  final String icon;
  final int color;
  final bool isIncome;
  final int sortOrder;

  /// Name of the seed category this row was created from (null for
  /// user-made ones). Keeps keyword rules working after a rename.
  final String? seedName;
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.isIncome,
    required this.sortOrder,
    this.seedName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['color'] = Variable<int>(color);
    map['is_income'] = Variable<bool>(isIncome);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || seedName != null) {
      map['seed_name'] = Variable<String>(seedName);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      color: Value(color),
      isIncome: Value(isIncome),
      sortOrder: Value(sortOrder),
      seedName: seedName == null && nullToAbsent ? const Value.absent() : Value(seedName),
    );
  }

  factory Category.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      color: serializer.fromJson<int>(json['color']),
      isIncome: serializer.fromJson<bool>(json['isIncome']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      seedName: serializer.fromJson<String?>(json['seedName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'color': serializer.toJson<int>(color),
      'isIncome': serializer.toJson<bool>(isIncome),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'seedName': serializer.toJson<String?>(seedName),
    };
  }

  Category copyWith({
    int? id,
    String? name,
    String? icon,
    int? color,
    bool? isIncome,
    int? sortOrder,
    Value<String?> seedName = const Value.absent(),
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    isIncome: isIncome ?? this.isIncome,
    sortOrder: sortOrder ?? this.sortOrder,
    seedName: seedName.present ? seedName.value : this.seedName,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      isIncome: data.isIncome.present ? data.isIncome.value : this.isIncome,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      seedName: data.seedName.present ? data.seedName.value : this.seedName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('isIncome: $isIncome, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('seedName: $seedName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, icon, color, isIncome, sortOrder, seedName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.isIncome == this.isIncome &&
          other.sortOrder == this.sortOrder &&
          other.seedName == this.seedName);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<int> color;
  final Value<bool> isIncome;
  final Value<int> sortOrder;
  final Value<String?> seedName;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.isIncome = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.seedName = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String icon,
    required int color,
    this.isIncome = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.seedName = const Value.absent(),
  }) : name = Value(name),
       icon = Value(icon),
       color = Value(color);
  static Insertable<Category> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<int>? color,
    Expression<bool>? isIncome,
    Expression<int>? sortOrder,
    Expression<String>? seedName,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (isIncome != null) 'is_income': isIncome,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (seedName != null) 'seed_name': seedName,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? icon,
    Value<int>? color,
    Value<bool>? isIncome,
    Value<int>? sortOrder,
    Value<String?>? seedName,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isIncome: isIncome ?? this.isIncome,
      sortOrder: sortOrder ?? this.sortOrder,
      seedName: seedName ?? this.seedName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (isIncome.present) {
      map['is_income'] = Variable<bool>(isIncome.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (seedName.present) {
      map['seed_name'] = Variable<String>(seedName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('isIncome: $isIncome, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('seedName: $seedName')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta('amountMinor');
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TxnDirection, int> direction = GeneratedColumn<int>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  ).withConverter<TxnDirection>($TransactionsTable.$converterdirection);
  static const VerificationMeta _occurredAtMeta = const VerificationMeta('occurredAt');
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _merchantMeta = const VerificationMeta('merchant');
  @override
  late final GeneratedColumn<String> merchant = GeneratedColumn<String>(
    'merchant',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _counterpartyMeta = const VerificationMeta('counterparty');
  @override
  late final GeneratedColumn<String> counterparty = GeneratedColumn<String>(
    'counterparty',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _categoryIdMeta = const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES categories (id)'),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES accounts (id)'),
  );
  static const VerificationMeta _accountHintMeta = const VerificationMeta('accountHint');
  @override
  late final GeneratedColumn<String> accountHint = GeneratedColumn<String>(
    'account_hint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PaymentMode, int> mode = GeneratedColumn<int>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  ).withConverter<PaymentMode>($TransactionsTable.$convertermode);
  static const VerificationMeta _referenceMeta = const VerificationMeta('reference');
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TxnStatus, int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  ).withConverter<TxnStatus>($TransactionsTable.$converterstatus);
  static const VerificationMeta _isTransferMeta = const VerificationMeta('isTransfer');
  @override
  late final GeneratedColumn<bool> isTransfer = GeneratedColumn<bool>(
    'is_transfer',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("is_transfer" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _categoryLockedMeta = const VerificationMeta('categoryLocked');
  @override
  late final GeneratedColumn<bool> categoryLocked = GeneratedColumn<bool>(
    'category_locked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("category_locked" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _duplicateOfIdMeta = const VerificationMeta('duplicateOfId');
  @override
  late final GeneratedColumn<int> duplicateOfId = GeneratedColumn<int>(
    'duplicate_of_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    amountMinor,
    direction,
    occurredAt,
    merchant,
    counterparty,
    note,
    categoryId,
    accountId,
    accountHint,
    mode,
    reference,
    status,
    isTransfer,
    categoryLocked,
    duplicateOfId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(Insertable<Transaction> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('amount_minor')) {
      context.handle(_amountMinorMeta, amountMinor.isAcceptableOrUnknown(data['amount_minor']!, _amountMinorMeta));
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(_occurredAtMeta, occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta));
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('merchant')) {
      context.handle(_merchantMeta, merchant.isAcceptableOrUnknown(data['merchant']!, _merchantMeta));
    }
    if (data.containsKey('counterparty')) {
      context.handle(_counterpartyMeta, counterparty.isAcceptableOrUnknown(data['counterparty']!, _counterpartyMeta));
    }
    if (data.containsKey('note')) {
      context.handle(_noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(_categoryIdMeta, categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta, accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    }
    if (data.containsKey('account_hint')) {
      context.handle(_accountHintMeta, accountHint.isAcceptableOrUnknown(data['account_hint']!, _accountHintMeta));
    }
    if (data.containsKey('reference')) {
      context.handle(_referenceMeta, reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta));
    }
    if (data.containsKey('is_transfer')) {
      context.handle(_isTransferMeta, isTransfer.isAcceptableOrUnknown(data['is_transfer']!, _isTransferMeta));
    }
    if (data.containsKey('category_locked')) {
      context.handle(
        _categoryLockedMeta,
        categoryLocked.isAcceptableOrUnknown(data['category_locked']!, _categoryLockedMeta),
      );
    }
    if (data.containsKey('duplicate_of_id')) {
      context.handle(
        _duplicateOfIdMeta,
        duplicateOfId.isAcceptableOrUnknown(data['duplicate_of_id']!, _duplicateOfIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta, createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      amountMinor: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}amount_minor'])!,
      direction: $TransactionsTable.$converterdirection.fromSql(
        attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}direction'])!,
      ),
      occurredAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}occurred_at'])!,
      merchant: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}merchant']),
      counterparty: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}counterparty']),
      note: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}note']),
      categoryId: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      accountId: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}account_id']),
      accountHint: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}account_hint']),
      mode: $TransactionsTable.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}mode'])!,
      ),
      reference: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}reference']),
      status: $TransactionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      ),
      isTransfer: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}is_transfer'])!,
      categoryLocked: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}category_locked'])!,
      duplicateOfId: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}duplicate_of_id']),
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TxnDirection, int, int> $converterdirection = const EnumIndexConverter<TxnDirection>(
    TxnDirection.values,
  );
  static JsonTypeConverter2<PaymentMode, int, int> $convertermode = const EnumIndexConverter<PaymentMode>(
    PaymentMode.values,
  );
  static JsonTypeConverter2<TxnStatus, int, int> $converterstatus = const EnumIndexConverter<TxnStatus>(
    TxnStatus.values,
  );
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final int id;

  /// Stored in paise to avoid floating point drift.
  final int amountMinor;
  final TxnDirection direction;
  final DateTime occurredAt;
  final String? merchant;

  /// VPA / raw counterparty string as it appeared in the message.
  final String? counterparty;
  final String? note;
  final int? categoryId;
  final int? accountId;
  final String? accountHint;
  final PaymentMode mode;

  /// UPI ref / RRN / bank reference. The strongest dedup signal.
  final String? reference;
  final TxnStatus status;

  /// Self-transfers between own accounts are excluded from spend.
  final bool isTransfer;
  final bool categoryLocked;

  /// Set when dedup found a borderline match the user should confirm.
  final int? duplicateOfId;
  final DateTime createdAt;
  const Transaction({
    required this.id,
    required this.amountMinor,
    required this.direction,
    required this.occurredAt,
    this.merchant,
    this.counterparty,
    this.note,
    this.categoryId,
    this.accountId,
    this.accountHint,
    required this.mode,
    this.reference,
    required this.status,
    required this.isTransfer,
    required this.categoryLocked,
    this.duplicateOfId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['amount_minor'] = Variable<int>(amountMinor);
    {
      map['direction'] = Variable<int>($TransactionsTable.$converterdirection.toSql(direction));
    }
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    if (!nullToAbsent || merchant != null) {
      map['merchant'] = Variable<String>(merchant);
    }
    if (!nullToAbsent || counterparty != null) {
      map['counterparty'] = Variable<String>(counterparty);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<int>(accountId);
    }
    if (!nullToAbsent || accountHint != null) {
      map['account_hint'] = Variable<String>(accountHint);
    }
    {
      map['mode'] = Variable<int>($TransactionsTable.$convertermode.toSql(mode));
    }
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    {
      map['status'] = Variable<int>($TransactionsTable.$converterstatus.toSql(status));
    }
    map['is_transfer'] = Variable<bool>(isTransfer);
    map['category_locked'] = Variable<bool>(categoryLocked);
    if (!nullToAbsent || duplicateOfId != null) {
      map['duplicate_of_id'] = Variable<int>(duplicateOfId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      amountMinor: Value(amountMinor),
      direction: Value(direction),
      occurredAt: Value(occurredAt),
      merchant: merchant == null && nullToAbsent ? const Value.absent() : Value(merchant),
      counterparty: counterparty == null && nullToAbsent ? const Value.absent() : Value(counterparty),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      categoryId: categoryId == null && nullToAbsent ? const Value.absent() : Value(categoryId),
      accountId: accountId == null && nullToAbsent ? const Value.absent() : Value(accountId),
      accountHint: accountHint == null && nullToAbsent ? const Value.absent() : Value(accountHint),
      mode: Value(mode),
      reference: reference == null && nullToAbsent ? const Value.absent() : Value(reference),
      status: Value(status),
      isTransfer: Value(isTransfer),
      categoryLocked: Value(categoryLocked),
      duplicateOfId: duplicateOfId == null && nullToAbsent ? const Value.absent() : Value(duplicateOfId),
      createdAt: Value(createdAt),
    );
  }

  factory Transaction.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<int>(json['id']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      direction: $TransactionsTable.$converterdirection.fromJson(serializer.fromJson<int>(json['direction'])),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      merchant: serializer.fromJson<String?>(json['merchant']),
      counterparty: serializer.fromJson<String?>(json['counterparty']),
      note: serializer.fromJson<String?>(json['note']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      accountId: serializer.fromJson<int?>(json['accountId']),
      accountHint: serializer.fromJson<String?>(json['accountHint']),
      mode: $TransactionsTable.$convertermode.fromJson(serializer.fromJson<int>(json['mode'])),
      reference: serializer.fromJson<String?>(json['reference']),
      status: $TransactionsTable.$converterstatus.fromJson(serializer.fromJson<int>(json['status'])),
      isTransfer: serializer.fromJson<bool>(json['isTransfer']),
      categoryLocked: serializer.fromJson<bool>(json['categoryLocked']),
      duplicateOfId: serializer.fromJson<int?>(json['duplicateOfId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'direction': serializer.toJson<int>($TransactionsTable.$converterdirection.toJson(direction)),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'merchant': serializer.toJson<String?>(merchant),
      'counterparty': serializer.toJson<String?>(counterparty),
      'note': serializer.toJson<String?>(note),
      'categoryId': serializer.toJson<int?>(categoryId),
      'accountId': serializer.toJson<int?>(accountId),
      'accountHint': serializer.toJson<String?>(accountHint),
      'mode': serializer.toJson<int>($TransactionsTable.$convertermode.toJson(mode)),
      'reference': serializer.toJson<String?>(reference),
      'status': serializer.toJson<int>($TransactionsTable.$converterstatus.toJson(status)),
      'isTransfer': serializer.toJson<bool>(isTransfer),
      'categoryLocked': serializer.toJson<bool>(categoryLocked),
      'duplicateOfId': serializer.toJson<int?>(duplicateOfId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Transaction copyWith({
    int? id,
    int? amountMinor,
    TxnDirection? direction,
    DateTime? occurredAt,
    Value<String?> merchant = const Value.absent(),
    Value<String?> counterparty = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<int?> categoryId = const Value.absent(),
    Value<int?> accountId = const Value.absent(),
    Value<String?> accountHint = const Value.absent(),
    PaymentMode? mode,
    Value<String?> reference = const Value.absent(),
    TxnStatus? status,
    bool? isTransfer,
    bool? categoryLocked,
    Value<int?> duplicateOfId = const Value.absent(),
    DateTime? createdAt,
  }) => Transaction(
    id: id ?? this.id,
    amountMinor: amountMinor ?? this.amountMinor,
    direction: direction ?? this.direction,
    occurredAt: occurredAt ?? this.occurredAt,
    merchant: merchant.present ? merchant.value : this.merchant,
    counterparty: counterparty.present ? counterparty.value : this.counterparty,
    note: note.present ? note.value : this.note,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    accountId: accountId.present ? accountId.value : this.accountId,
    accountHint: accountHint.present ? accountHint.value : this.accountHint,
    mode: mode ?? this.mode,
    reference: reference.present ? reference.value : this.reference,
    status: status ?? this.status,
    isTransfer: isTransfer ?? this.isTransfer,
    categoryLocked: categoryLocked ?? this.categoryLocked,
    duplicateOfId: duplicateOfId.present ? duplicateOfId.value : this.duplicateOfId,
    createdAt: createdAt ?? this.createdAt,
  );
  Transaction copyWithCompanion(TransactionsCompanion data) {
    return Transaction(
      id: data.id.present ? data.id.value : this.id,
      amountMinor: data.amountMinor.present ? data.amountMinor.value : this.amountMinor,
      direction: data.direction.present ? data.direction.value : this.direction,
      occurredAt: data.occurredAt.present ? data.occurredAt.value : this.occurredAt,
      merchant: data.merchant.present ? data.merchant.value : this.merchant,
      counterparty: data.counterparty.present ? data.counterparty.value : this.counterparty,
      note: data.note.present ? data.note.value : this.note,
      categoryId: data.categoryId.present ? data.categoryId.value : this.categoryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      accountHint: data.accountHint.present ? data.accountHint.value : this.accountHint,
      mode: data.mode.present ? data.mode.value : this.mode,
      reference: data.reference.present ? data.reference.value : this.reference,
      status: data.status.present ? data.status.value : this.status,
      isTransfer: data.isTransfer.present ? data.isTransfer.value : this.isTransfer,
      categoryLocked: data.categoryLocked.present ? data.categoryLocked.value : this.categoryLocked,
      duplicateOfId: data.duplicateOfId.present ? data.duplicateOfId.value : this.duplicateOfId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('direction: $direction, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('merchant: $merchant, ')
          ..write('counterparty: $counterparty, ')
          ..write('note: $note, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('accountHint: $accountHint, ')
          ..write('mode: $mode, ')
          ..write('reference: $reference, ')
          ..write('status: $status, ')
          ..write('isTransfer: $isTransfer, ')
          ..write('categoryLocked: $categoryLocked, ')
          ..write('duplicateOfId: $duplicateOfId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    amountMinor,
    direction,
    occurredAt,
    merchant,
    counterparty,
    note,
    categoryId,
    accountId,
    accountHint,
    mode,
    reference,
    status,
    isTransfer,
    categoryLocked,
    duplicateOfId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.amountMinor == this.amountMinor &&
          other.direction == this.direction &&
          other.occurredAt == this.occurredAt &&
          other.merchant == this.merchant &&
          other.counterparty == this.counterparty &&
          other.note == this.note &&
          other.categoryId == this.categoryId &&
          other.accountId == this.accountId &&
          other.accountHint == this.accountHint &&
          other.mode == this.mode &&
          other.reference == this.reference &&
          other.status == this.status &&
          other.isTransfer == this.isTransfer &&
          other.categoryLocked == this.categoryLocked &&
          other.duplicateOfId == this.duplicateOfId &&
          other.createdAt == this.createdAt);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<int> id;
  final Value<int> amountMinor;
  final Value<TxnDirection> direction;
  final Value<DateTime> occurredAt;
  final Value<String?> merchant;
  final Value<String?> counterparty;
  final Value<String?> note;
  final Value<int?> categoryId;
  final Value<int?> accountId;
  final Value<String?> accountHint;
  final Value<PaymentMode> mode;
  final Value<String?> reference;
  final Value<TxnStatus> status;
  final Value<bool> isTransfer;
  final Value<bool> categoryLocked;
  final Value<int?> duplicateOfId;
  final Value<DateTime> createdAt;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.direction = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.merchant = const Value.absent(),
    this.counterparty = const Value.absent(),
    this.note = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.accountHint = const Value.absent(),
    this.mode = const Value.absent(),
    this.reference = const Value.absent(),
    this.status = const Value.absent(),
    this.isTransfer = const Value.absent(),
    this.categoryLocked = const Value.absent(),
    this.duplicateOfId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TransactionsCompanion.insert({
    this.id = const Value.absent(),
    required int amountMinor,
    required TxnDirection direction,
    required DateTime occurredAt,
    this.merchant = const Value.absent(),
    this.counterparty = const Value.absent(),
    this.note = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.accountHint = const Value.absent(),
    required PaymentMode mode,
    this.reference = const Value.absent(),
    required TxnStatus status,
    this.isTransfer = const Value.absent(),
    this.categoryLocked = const Value.absent(),
    this.duplicateOfId = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : amountMinor = Value(amountMinor),
       direction = Value(direction),
       occurredAt = Value(occurredAt),
       mode = Value(mode),
       status = Value(status);
  static Insertable<Transaction> custom({
    Expression<int>? id,
    Expression<int>? amountMinor,
    Expression<int>? direction,
    Expression<DateTime>? occurredAt,
    Expression<String>? merchant,
    Expression<String>? counterparty,
    Expression<String>? note,
    Expression<int>? categoryId,
    Expression<int>? accountId,
    Expression<String>? accountHint,
    Expression<int>? mode,
    Expression<String>? reference,
    Expression<int>? status,
    Expression<bool>? isTransfer,
    Expression<bool>? categoryLocked,
    Expression<int>? duplicateOfId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (direction != null) 'direction': direction,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (merchant != null) 'merchant': merchant,
      if (counterparty != null) 'counterparty': counterparty,
      if (note != null) 'note': note,
      if (categoryId != null) 'category_id': categoryId,
      if (accountId != null) 'account_id': accountId,
      if (accountHint != null) 'account_hint': accountHint,
      if (mode != null) 'mode': mode,
      if (reference != null) 'reference': reference,
      if (status != null) 'status': status,
      if (isTransfer != null) 'is_transfer': isTransfer,
      if (categoryLocked != null) 'category_locked': categoryLocked,
      if (duplicateOfId != null) 'duplicate_of_id': duplicateOfId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TransactionsCompanion copyWith({
    Value<int>? id,
    Value<int>? amountMinor,
    Value<TxnDirection>? direction,
    Value<DateTime>? occurredAt,
    Value<String?>? merchant,
    Value<String?>? counterparty,
    Value<String?>? note,
    Value<int?>? categoryId,
    Value<int?>? accountId,
    Value<String?>? accountHint,
    Value<PaymentMode>? mode,
    Value<String?>? reference,
    Value<TxnStatus>? status,
    Value<bool>? isTransfer,
    Value<bool>? categoryLocked,
    Value<int?>? duplicateOfId,
    Value<DateTime>? createdAt,
  }) {
    return TransactionsCompanion(
      id: id ?? this.id,
      amountMinor: amountMinor ?? this.amountMinor,
      direction: direction ?? this.direction,
      occurredAt: occurredAt ?? this.occurredAt,
      merchant: merchant ?? this.merchant,
      counterparty: counterparty ?? this.counterparty,
      note: note ?? this.note,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      accountHint: accountHint ?? this.accountHint,
      mode: mode ?? this.mode,
      reference: reference ?? this.reference,
      status: status ?? this.status,
      isTransfer: isTransfer ?? this.isTransfer,
      categoryLocked: categoryLocked ?? this.categoryLocked,
      duplicateOfId: duplicateOfId ?? this.duplicateOfId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (direction.present) {
      map['direction'] = Variable<int>($TransactionsTable.$converterdirection.toSql(direction.value));
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (merchant.present) {
      map['merchant'] = Variable<String>(merchant.value);
    }
    if (counterparty.present) {
      map['counterparty'] = Variable<String>(counterparty.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (accountHint.present) {
      map['account_hint'] = Variable<String>(accountHint.value);
    }
    if (mode.present) {
      map['mode'] = Variable<int>($TransactionsTable.$convertermode.toSql(mode.value));
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (status.present) {
      map['status'] = Variable<int>($TransactionsTable.$converterstatus.toSql(status.value));
    }
    if (isTransfer.present) {
      map['is_transfer'] = Variable<bool>(isTransfer.value);
    }
    if (categoryLocked.present) {
      map['category_locked'] = Variable<bool>(categoryLocked.value);
    }
    if (duplicateOfId.present) {
      map['duplicate_of_id'] = Variable<int>(duplicateOfId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('direction: $direction, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('merchant: $merchant, ')
          ..write('counterparty: $counterparty, ')
          ..write('note: $note, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('accountHint: $accountHint, ')
          ..write('mode: $mode, ')
          ..write('reference: $reference, ')
          ..write('status: $status, ')
          ..write('isTransfer: $isTransfer, ')
          ..write('categoryLocked: $categoryLocked, ')
          ..write('duplicateOfId: $duplicateOfId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $RawMessagesTable extends RawMessages with TableInfo<$RawMessagesTable, RawMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RawMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<SourceKind, int> source = GeneratedColumn<int>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  ).withConverter<SourceKind>($RawMessagesTable.$convertersource);
  static const VerificationMeta _externalIdMeta = const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
    'sender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta('receivedAt');
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ParseStatus, int> parseStatus = GeneratedColumn<int>(
    'parse_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  ).withConverter<ParseStatus>($RawMessagesTable.$converterparseStatus);
  static const VerificationMeta _ignoreReasonMeta = const VerificationMeta('ignoreReason');
  @override
  late final GeneratedColumn<String> ignoreReason = GeneratedColumn<String>(
    'ignore_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transactionIdMeta = const VerificationMeta('transactionId');
  @override
  late final GeneratedColumn<int> transactionId = GeneratedColumn<int>(
    'transaction_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES transactions (id) ON DELETE SET NULL'),
  );
  static const VerificationMeta _mergeScoreMeta = const VerificationMeta('mergeScore');
  @override
  late final GeneratedColumn<double> mergeScore = GeneratedColumn<double>(
    'merge_score',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    source,
    externalId,
    sender,
    body,
    receivedAt,
    parseStatus,
    ignoreReason,
    transactionId,
    mergeScore,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_messages';
  @override
  VerificationContext validateIntegrity(Insertable<RawMessage> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('external_id')) {
      context.handle(_externalIdMeta, externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta));
    } else if (isInserting) {
      context.missing(_externalIdMeta);
    }
    if (data.containsKey('sender')) {
      context.handle(_senderMeta, sender.isAcceptableOrUnknown(data['sender']!, _senderMeta));
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('body')) {
      context.handle(_bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(_receivedAtMeta, receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta));
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    if (data.containsKey('ignore_reason')) {
      context.handle(_ignoreReasonMeta, ignoreReason.isAcceptableOrUnknown(data['ignore_reason']!, _ignoreReasonMeta));
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
        _transactionIdMeta,
        transactionId.isAcceptableOrUnknown(data['transaction_id']!, _transactionIdMeta),
      );
    }
    if (data.containsKey('merge_score')) {
      context.handle(_mergeScoreMeta, mergeScore.isAcceptableOrUnknown(data['merge_score']!, _mergeScoreMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {source, externalId},
  ];
  @override
  RawMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawMessage(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      source: $RawMessagesTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}source'])!,
      ),
      externalId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}external_id'])!,
      sender: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}sender'])!,
      body: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}body'])!,
      receivedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}received_at'])!,
      parseStatus: $RawMessagesTable.$converterparseStatus.fromSql(
        attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}parse_status'])!,
      ),
      ignoreReason: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}ignore_reason']),
      transactionId: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}transaction_id']),
      mergeScore: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}merge_score']),
    );
  }

  @override
  $RawMessagesTable createAlias(String alias) {
    return $RawMessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SourceKind, int, int> $convertersource = const EnumIndexConverter<SourceKind>(
    SourceKind.values,
  );
  static JsonTypeConverter2<ParseStatus, int, int> $converterparseStatus = const EnumIndexConverter<ParseStatus>(
    ParseStatus.values,
  );
}

class RawMessage extends DataClass implements Insertable<RawMessage> {
  final int id;
  final SourceKind source;

  /// Provider-side id (SMS _id, Gmail message id) — unique per source.
  final String externalId;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final ParseStatus parseStatus;
  final String? ignoreReason;
  final int? transactionId;

  /// Dedup score that linked this message to an existing transaction.
  final double? mergeScore;
  const RawMessage({
    required this.id,
    required this.source,
    required this.externalId,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.parseStatus,
    this.ignoreReason,
    this.transactionId,
    this.mergeScore,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['source'] = Variable<int>($RawMessagesTable.$convertersource.toSql(source));
    }
    map['external_id'] = Variable<String>(externalId);
    map['sender'] = Variable<String>(sender);
    map['body'] = Variable<String>(body);
    map['received_at'] = Variable<DateTime>(receivedAt);
    {
      map['parse_status'] = Variable<int>($RawMessagesTable.$converterparseStatus.toSql(parseStatus));
    }
    if (!nullToAbsent || ignoreReason != null) {
      map['ignore_reason'] = Variable<String>(ignoreReason);
    }
    if (!nullToAbsent || transactionId != null) {
      map['transaction_id'] = Variable<int>(transactionId);
    }
    if (!nullToAbsent || mergeScore != null) {
      map['merge_score'] = Variable<double>(mergeScore);
    }
    return map;
  }

  RawMessagesCompanion toCompanion(bool nullToAbsent) {
    return RawMessagesCompanion(
      id: Value(id),
      source: Value(source),
      externalId: Value(externalId),
      sender: Value(sender),
      body: Value(body),
      receivedAt: Value(receivedAt),
      parseStatus: Value(parseStatus),
      ignoreReason: ignoreReason == null && nullToAbsent ? const Value.absent() : Value(ignoreReason),
      transactionId: transactionId == null && nullToAbsent ? const Value.absent() : Value(transactionId),
      mergeScore: mergeScore == null && nullToAbsent ? const Value.absent() : Value(mergeScore),
    );
  }

  factory RawMessage.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawMessage(
      id: serializer.fromJson<int>(json['id']),
      source: $RawMessagesTable.$convertersource.fromJson(serializer.fromJson<int>(json['source'])),
      externalId: serializer.fromJson<String>(json['externalId']),
      sender: serializer.fromJson<String>(json['sender']),
      body: serializer.fromJson<String>(json['body']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
      parseStatus: $RawMessagesTable.$converterparseStatus.fromJson(serializer.fromJson<int>(json['parseStatus'])),
      ignoreReason: serializer.fromJson<String?>(json['ignoreReason']),
      transactionId: serializer.fromJson<int?>(json['transactionId']),
      mergeScore: serializer.fromJson<double?>(json['mergeScore']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'source': serializer.toJson<int>($RawMessagesTable.$convertersource.toJson(source)),
      'externalId': serializer.toJson<String>(externalId),
      'sender': serializer.toJson<String>(sender),
      'body': serializer.toJson<String>(body),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
      'parseStatus': serializer.toJson<int>($RawMessagesTable.$converterparseStatus.toJson(parseStatus)),
      'ignoreReason': serializer.toJson<String?>(ignoreReason),
      'transactionId': serializer.toJson<int?>(transactionId),
      'mergeScore': serializer.toJson<double?>(mergeScore),
    };
  }

  RawMessage copyWith({
    int? id,
    SourceKind? source,
    String? externalId,
    String? sender,
    String? body,
    DateTime? receivedAt,
    ParseStatus? parseStatus,
    Value<String?> ignoreReason = const Value.absent(),
    Value<int?> transactionId = const Value.absent(),
    Value<double?> mergeScore = const Value.absent(),
  }) => RawMessage(
    id: id ?? this.id,
    source: source ?? this.source,
    externalId: externalId ?? this.externalId,
    sender: sender ?? this.sender,
    body: body ?? this.body,
    receivedAt: receivedAt ?? this.receivedAt,
    parseStatus: parseStatus ?? this.parseStatus,
    ignoreReason: ignoreReason.present ? ignoreReason.value : this.ignoreReason,
    transactionId: transactionId.present ? transactionId.value : this.transactionId,
    mergeScore: mergeScore.present ? mergeScore.value : this.mergeScore,
  );
  RawMessage copyWithCompanion(RawMessagesCompanion data) {
    return RawMessage(
      id: data.id.present ? data.id.value : this.id,
      source: data.source.present ? data.source.value : this.source,
      externalId: data.externalId.present ? data.externalId.value : this.externalId,
      sender: data.sender.present ? data.sender.value : this.sender,
      body: data.body.present ? data.body.value : this.body,
      receivedAt: data.receivedAt.present ? data.receivedAt.value : this.receivedAt,
      parseStatus: data.parseStatus.present ? data.parseStatus.value : this.parseStatus,
      ignoreReason: data.ignoreReason.present ? data.ignoreReason.value : this.ignoreReason,
      transactionId: data.transactionId.present ? data.transactionId.value : this.transactionId,
      mergeScore: data.mergeScore.present ? data.mergeScore.value : this.mergeScore,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawMessage(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('sender: $sender, ')
          ..write('body: $body, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('parseStatus: $parseStatus, ')
          ..write('ignoreReason: $ignoreReason, ')
          ..write('transactionId: $transactionId, ')
          ..write('mergeScore: $mergeScore')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    source,
    externalId,
    sender,
    body,
    receivedAt,
    parseStatus,
    ignoreReason,
    transactionId,
    mergeScore,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawMessage &&
          other.id == this.id &&
          other.source == this.source &&
          other.externalId == this.externalId &&
          other.sender == this.sender &&
          other.body == this.body &&
          other.receivedAt == this.receivedAt &&
          other.parseStatus == this.parseStatus &&
          other.ignoreReason == this.ignoreReason &&
          other.transactionId == this.transactionId &&
          other.mergeScore == this.mergeScore);
}

class RawMessagesCompanion extends UpdateCompanion<RawMessage> {
  final Value<int> id;
  final Value<SourceKind> source;
  final Value<String> externalId;
  final Value<String> sender;
  final Value<String> body;
  final Value<DateTime> receivedAt;
  final Value<ParseStatus> parseStatus;
  final Value<String?> ignoreReason;
  final Value<int?> transactionId;
  final Value<double?> mergeScore;
  const RawMessagesCompanion({
    this.id = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.sender = const Value.absent(),
    this.body = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.parseStatus = const Value.absent(),
    this.ignoreReason = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.mergeScore = const Value.absent(),
  });
  RawMessagesCompanion.insert({
    this.id = const Value.absent(),
    required SourceKind source,
    required String externalId,
    required String sender,
    required String body,
    required DateTime receivedAt,
    required ParseStatus parseStatus,
    this.ignoreReason = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.mergeScore = const Value.absent(),
  }) : source = Value(source),
       externalId = Value(externalId),
       sender = Value(sender),
       body = Value(body),
       receivedAt = Value(receivedAt),
       parseStatus = Value(parseStatus);
  static Insertable<RawMessage> custom({
    Expression<int>? id,
    Expression<int>? source,
    Expression<String>? externalId,
    Expression<String>? sender,
    Expression<String>? body,
    Expression<DateTime>? receivedAt,
    Expression<int>? parseStatus,
    Expression<String>? ignoreReason,
    Expression<int>? transactionId,
    Expression<double>? mergeScore,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (source != null) 'source': source,
      if (externalId != null) 'external_id': externalId,
      if (sender != null) 'sender': sender,
      if (body != null) 'body': body,
      if (receivedAt != null) 'received_at': receivedAt,
      if (parseStatus != null) 'parse_status': parseStatus,
      if (ignoreReason != null) 'ignore_reason': ignoreReason,
      if (transactionId != null) 'transaction_id': transactionId,
      if (mergeScore != null) 'merge_score': mergeScore,
    });
  }

  RawMessagesCompanion copyWith({
    Value<int>? id,
    Value<SourceKind>? source,
    Value<String>? externalId,
    Value<String>? sender,
    Value<String>? body,
    Value<DateTime>? receivedAt,
    Value<ParseStatus>? parseStatus,
    Value<String?>? ignoreReason,
    Value<int?>? transactionId,
    Value<double?>? mergeScore,
  }) {
    return RawMessagesCompanion(
      id: id ?? this.id,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      sender: sender ?? this.sender,
      body: body ?? this.body,
      receivedAt: receivedAt ?? this.receivedAt,
      parseStatus: parseStatus ?? this.parseStatus,
      ignoreReason: ignoreReason ?? this.ignoreReason,
      transactionId: transactionId ?? this.transactionId,
      mergeScore: mergeScore ?? this.mergeScore,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (source.present) {
      map['source'] = Variable<int>($RawMessagesTable.$convertersource.toSql(source.value));
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    if (parseStatus.present) {
      map['parse_status'] = Variable<int>($RawMessagesTable.$converterparseStatus.toSql(parseStatus.value));
    }
    if (ignoreReason.present) {
      map['ignore_reason'] = Variable<String>(ignoreReason.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<int>(transactionId.value);
    }
    if (mergeScore.present) {
      map['merge_score'] = Variable<double>(mergeScore.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawMessagesCompanion(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('sender: $sender, ')
          ..write('body: $body, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('parseStatus: $parseStatus, ')
          ..write('ignoreReason: $ignoreReason, ')
          ..write('transactionId: $transactionId, ')
          ..write('mergeScore: $mergeScore')
          ..write(')'))
        .toString();
  }
}

class $MerchantRulesTable extends MerchantRules with TableInfo<$MerchantRulesTable, MerchantRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MerchantRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _patternMeta = const VerificationMeta('pattern');
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES categories (id) ON DELETE CASCADE'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, pattern, categoryId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'merchant_rules';
  @override
  VerificationContext validateIntegrity(Insertable<MerchantRule> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('pattern')) {
      context.handle(_patternMeta, pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta));
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(_categoryIdMeta, categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta));
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MerchantRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MerchantRule(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      pattern: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}pattern'])!,
      categoryId: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}category_id'])!,
    );
  }

  @override
  $MerchantRulesTable createAlias(String alias) {
    return $MerchantRulesTable(attachedDatabase, alias);
  }
}

class MerchantRule extends DataClass implements Insertable<MerchantRule> {
  final int id;
  final String pattern;
  final int categoryId;
  const MerchantRule({required this.id, required this.pattern, required this.categoryId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['pattern'] = Variable<String>(pattern);
    map['category_id'] = Variable<int>(categoryId);
    return map;
  }

  MerchantRulesCompanion toCompanion(bool nullToAbsent) {
    return MerchantRulesCompanion(id: Value(id), pattern: Value(pattern), categoryId: Value(categoryId));
  }

  factory MerchantRule.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MerchantRule(
      id: serializer.fromJson<int>(json['id']),
      pattern: serializer.fromJson<String>(json['pattern']),
      categoryId: serializer.fromJson<int>(json['categoryId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'pattern': serializer.toJson<String>(pattern),
      'categoryId': serializer.toJson<int>(categoryId),
    };
  }

  MerchantRule copyWith({int? id, String? pattern, int? categoryId}) =>
      MerchantRule(id: id ?? this.id, pattern: pattern ?? this.pattern, categoryId: categoryId ?? this.categoryId);
  MerchantRule copyWithCompanion(MerchantRulesCompanion data) {
    return MerchantRule(
      id: data.id.present ? data.id.value : this.id,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      categoryId: data.categoryId.present ? data.categoryId.value : this.categoryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MerchantRule(')
          ..write('id: $id, ')
          ..write('pattern: $pattern, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, pattern, categoryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MerchantRule &&
          other.id == this.id &&
          other.pattern == this.pattern &&
          other.categoryId == this.categoryId);
}

class MerchantRulesCompanion extends UpdateCompanion<MerchantRule> {
  final Value<int> id;
  final Value<String> pattern;
  final Value<int> categoryId;
  const MerchantRulesCompanion({
    this.id = const Value.absent(),
    this.pattern = const Value.absent(),
    this.categoryId = const Value.absent(),
  });
  MerchantRulesCompanion.insert({this.id = const Value.absent(), required String pattern, required int categoryId})
    : pattern = Value(pattern),
      categoryId = Value(categoryId);
  static Insertable<MerchantRule> custom({
    Expression<int>? id,
    Expression<String>? pattern,
    Expression<int>? categoryId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pattern != null) 'pattern': pattern,
      if (categoryId != null) 'category_id': categoryId,
    });
  }

  MerchantRulesCompanion copyWith({Value<int>? id, Value<String>? pattern, Value<int>? categoryId}) {
    return MerchantRulesCompanion(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      categoryId: categoryId ?? this.categoryId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MerchantRulesCompanion(')
          ..write('id: $id, ')
          ..write('pattern: $pattern, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }
}

class $BudgetsTable extends Budgets with TableInfo<$BudgetsTable, Budget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES categories (id) ON DELETE CASCADE'),
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta('amountMinor');
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("active" IN (0, 1))'),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, categoryId, amountMinor, active, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets';
  @override
  VerificationContext validateIntegrity(Insertable<Budget> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(_categoryIdMeta, categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('amount_minor')) {
      context.handle(_amountMinorMeta, amountMinor.isAcceptableOrUnknown(data['amount_minor']!, _amountMinorMeta));
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('active')) {
      context.handle(_activeMeta, active.isAcceptableOrUnknown(data['active']!, _activeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta, createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Budget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Budget(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      categoryId: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      amountMinor: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}amount_minor'])!,
      active: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}active'])!,
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $BudgetsTable createAlias(String alias) {
    return $BudgetsTable(attachedDatabase, alias);
  }
}

class Budget extends DataClass implements Insertable<Budget> {
  final int id;
  final int? categoryId;

  /// Limit per month, in paise.
  final int amountMinor;
  final bool active;
  final DateTime createdAt;
  const Budget({
    required this.id,
    this.categoryId,
    required this.amountMinor,
    required this.active,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['amount_minor'] = Variable<int>(amountMinor);
    map['active'] = Variable<bool>(active);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BudgetsCompanion toCompanion(bool nullToAbsent) {
    return BudgetsCompanion(
      id: Value(id),
      categoryId: categoryId == null && nullToAbsent ? const Value.absent() : Value(categoryId),
      amountMinor: Value(amountMinor),
      active: Value(active),
      createdAt: Value(createdAt),
    );
  }

  factory Budget.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Budget(
      id: serializer.fromJson<int>(json['id']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      active: serializer.fromJson<bool>(json['active']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'categoryId': serializer.toJson<int?>(categoryId),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'active': serializer.toJson<bool>(active),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Budget copyWith({
    int? id,
    Value<int?> categoryId = const Value.absent(),
    int? amountMinor,
    bool? active,
    DateTime? createdAt,
  }) => Budget(
    id: id ?? this.id,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    amountMinor: amountMinor ?? this.amountMinor,
    active: active ?? this.active,
    createdAt: createdAt ?? this.createdAt,
  );
  Budget copyWithCompanion(BudgetsCompanion data) {
    return Budget(
      id: data.id.present ? data.id.value : this.id,
      categoryId: data.categoryId.present ? data.categoryId.value : this.categoryId,
      amountMinor: data.amountMinor.present ? data.amountMinor.value : this.amountMinor,
      active: data.active.present ? data.active.value : this.active,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Budget(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('active: $active, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, categoryId, amountMinor, active, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Budget &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.amountMinor == this.amountMinor &&
          other.active == this.active &&
          other.createdAt == this.createdAt);
}

class BudgetsCompanion extends UpdateCompanion<Budget> {
  final Value<int> id;
  final Value<int?> categoryId;
  final Value<int> amountMinor;
  final Value<bool> active;
  final Value<DateTime> createdAt;
  const BudgetsCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.active = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  BudgetsCompanion.insert({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    required int amountMinor,
    this.active = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : amountMinor = Value(amountMinor);
  static Insertable<Budget> custom({
    Expression<int>? id,
    Expression<int>? categoryId,
    Expression<int>? amountMinor,
    Expression<bool>? active,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (active != null) 'active': active,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  BudgetsCompanion copyWith({
    Value<int>? id,
    Value<int?>? categoryId,
    Value<int>? amountMinor,
    Value<bool>? active,
    Value<DateTime>? createdAt,
  }) {
    return BudgetsCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      amountMinor: amountMinor ?? this.amountMinor,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('active: $active, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $RawMessagesTable rawMessages = $RawMessagesTable(this);
  late final $MerchantRulesTable merchantRules = $MerchantRulesTable(this);
  late final $BudgetsTable budgets = $BudgetsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accounts,
    categories,
    transactions,
    rawMessages,
    merchantRules,
    budgets,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName('transactions', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('raw_messages', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName('categories', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('merchant_rules', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName('categories', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('budgets', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$AccountsTableCreateCompanionBuilder = AccountsCompanion Function({
  Value<int> id,
  required String name,
  required AccountKind kind,
  Value<String?> institution,
  Value<String?> last4,
  required int color,
  Value<bool> archived,
});
typedef $$AccountsTableUpdateCompanionBuilder = AccountsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<AccountKind> kind,
  Value<String?> institution,
  Value<String?> last4,
  Value<int> color,
  Value<bool> archived,
});

final class $$AccountsTableReferences extends BaseReferences<_$AppDatabase, $AccountsTable, Account> {
  $$AccountsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TransactionsTable, List<Transaction>> _transactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.transactions, aliasName: 'accounts__id__transactions__account_id');

  $$TransactionsTableProcessedTableManager get transactionsRefs {
    final manager = $$TransactionsTableTableManager(
      $_db,
      $_db.transactions,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_transactionsRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$AccountsTableFilterComposer extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<AccountKind, AccountKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get institution =>
      $composableBuilder(column: $table.institution, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get last4 =>
      $composableBuilder(column: $table.last4, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get color => $composableBuilder(column: $table.color, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => ColumnFilters(column));

  Expression<bool> transactionsRefs(Expression<bool> Function($$TransactionsTableFilterComposer f) f) {
    final $$TransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.accountId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$TransactionsTableFilterComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableOrderingComposer extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get institution =>
      $composableBuilder(column: $table.institution, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get last4 =>
      $composableBuilder(column: $table.last4, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => ColumnOrderings(column));
}

class $$AccountsTableAnnotationComposer extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name => $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AccountKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get institution =>
      $composableBuilder(column: $table.institution, builder: (column) => column);

  GeneratedColumn<String> get last4 => $composableBuilder(column: $table.last4, builder: (column) => column);

  GeneratedColumn<int> get color => $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get archived => $composableBuilder(column: $table.archived, builder: (column) => column);

  Expression<T> transactionsRefs<T extends Object>(Expression<T> Function($$TransactionsTableAnnotationComposer a) f) {
    final $$TransactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.accountId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$TransactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, $$AccountsTableReferences),
          Account,
          PrefetchHooks Function({bool transactionsRefs})
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<AccountKind> kind = const Value.absent(),
                Value<String?> institution = const Value.absent(),
                Value<String?> last4 = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                name: name,
                kind: kind,
                institution: institution,
                last4: last4,
                color: color,
                archived: archived,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required AccountKind kind,
                Value<String?> institution = const Value.absent(),
                Value<String?> last4 = const Value.absent(),
                required int color,
                Value<bool> archived = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                institution: institution,
                last4: last4,
                color: color,
                archived: archived,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable<$AccountsTable, Account>(table), $$AccountsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({transactionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (transactionsRefs) db.transactions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (transactionsRefs)
                    await $_getPrefetchedData<Account, $AccountsTable, Transaction>(
                      currentTable: table,
                      referencedTable: $$AccountsTableReferences._transactionsRefsTable(db),
                      managerFromTypedResult: (p0) => $$AccountsTableReferences(db, table, p0).transactionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.accountId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, $$AccountsTableReferences),
      Account,
      PrefetchHooks Function({bool transactionsRefs})
    >;
typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  required String name,
  required String icon,
  required int color,
  Value<bool> isIncome,
  Value<int> sortOrder,
  Value<String?> seedName,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> icon,
  Value<int> color,
  Value<bool> isIncome,
  Value<int> sortOrder,
  Value<String?> seedName,
});

final class $$CategoriesTableReferences extends BaseReferences<_$AppDatabase, $CategoriesTable, Category> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TransactionsTable, List<Transaction>> _transactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.transactions, aliasName: 'categories__id__transactions__category_id');

  $$TransactionsTableProcessedTableManager get transactionsRefs {
    final manager = $$TransactionsTableTableManager(
      $_db,
      $_db.transactions,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_transactionsRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$MerchantRulesTable, List<MerchantRule>> _merchantRulesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.merchantRules, aliasName: 'categories__id__merchant_rules__category_id');

  $$MerchantRulesTableProcessedTableManager get merchantRulesRefs {
    final manager = $$MerchantRulesTableTableManager(
      $_db,
      $_db.merchantRules,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_merchantRulesRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$BudgetsTable, List<Budget>> _budgetsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.budgets, aliasName: 'categories__id__budgets__category_id');

  $$BudgetsTableProcessedTableManager get budgetsRefs {
    final manager = $$BudgetsTableTableManager(
      $_db,
      $_db.budgets,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_budgetsRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$CategoriesTableFilterComposer extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get icon => $composableBuilder(column: $table.icon, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get color => $composableBuilder(column: $table.color, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isIncome =>
      $composableBuilder(column: $table.isIncome, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get seedName =>
      $composableBuilder(column: $table.seedName, builder: (column) => ColumnFilters(column));

  Expression<bool> transactionsRefs(Expression<bool> Function($$TransactionsTableFilterComposer f) f) {
    final $$TransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.categoryId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$TransactionsTableFilterComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> merchantRulesRefs(Expression<bool> Function($$MerchantRulesTableFilterComposer f) f) {
    final $$MerchantRulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.merchantRules,
      getReferencedColumn: (t) => t.categoryId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$MerchantRulesTableFilterComposer(
            $db: $db,
            $table: $db.merchantRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> budgetsRefs(Expression<bool> Function($$BudgetsTableFilterComposer f) f) {
    final $$BudgetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.budgets,
      getReferencedColumn: (t) => t.categoryId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$BudgetsTableFilterComposer(
            $db: $db,
            $table: $db.budgets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isIncome =>
      $composableBuilder(column: $table.isIncome, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get seedName =>
      $composableBuilder(column: $table.seedName, builder: (column) => ColumnOrderings(column));
}

class $$CategoriesTableAnnotationComposer extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name => $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon => $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get color => $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get isIncome => $composableBuilder(column: $table.isIncome, builder: (column) => column);

  GeneratedColumn<int> get sortOrder => $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get seedName => $composableBuilder(column: $table.seedName, builder: (column) => column);

  Expression<T> transactionsRefs<T extends Object>(Expression<T> Function($$TransactionsTableAnnotationComposer a) f) {
    final $$TransactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.categoryId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$TransactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> merchantRulesRefs<T extends Object>(
    Expression<T> Function($$MerchantRulesTableAnnotationComposer a) f,
  ) {
    final $$MerchantRulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.merchantRules,
      getReferencedColumn: (t) => t.categoryId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$MerchantRulesTableAnnotationComposer(
            $db: $db,
            $table: $db.merchantRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> budgetsRefs<T extends Object>(Expression<T> Function($$BudgetsTableAnnotationComposer a) f) {
    final $$BudgetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.budgets,
      getReferencedColumn: (t) => t.categoryId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$BudgetsTableAnnotationComposer(
            $db: $db,
            $table: $db.budgets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, $$CategoriesTableReferences),
          Category,
          PrefetchHooks Function({bool transactionsRefs, bool merchantRulesRefs, bool budgetsRefs})
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<bool> isIncome = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> seedName = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                icon: icon,
                color: color,
                isIncome: isIncome,
                sortOrder: sortOrder,
                seedName: seedName,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String icon,
                required int color,
                Value<bool> isIncome = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> seedName = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                icon: icon,
                color: color,
                isIncome: isIncome,
                sortOrder: sortOrder,
                seedName: seedName,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable<$CategoriesTable, Category>(table), $$CategoriesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({transactionsRefs = false, merchantRulesRefs = false, budgetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (transactionsRefs) db.transactions,
                if (merchantRulesRefs) db.merchantRules,
                if (budgetsRefs) db.budgets,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (transactionsRefs)
                    await $_getPrefetchedData<Category, $CategoriesTable, Transaction>(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences._transactionsRefsTable(db),
                      managerFromTypedResult: (p0) => $$CategoriesTableReferences(db, table, p0).transactionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                  if (merchantRulesRefs)
                    await $_getPrefetchedData<Category, $CategoriesTable, MerchantRule>(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences._merchantRulesRefsTable(db),
                      managerFromTypedResult: (p0) => $$CategoriesTableReferences(db, table, p0).merchantRulesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                  if (budgetsRefs)
                    await $_getPrefetchedData<Category, $CategoriesTable, Budget>(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences._budgetsRefsTable(db),
                      managerFromTypedResult: (p0) => $$CategoriesTableReferences(db, table, p0).budgetsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, $$CategoriesTableReferences),
      Category,
      PrefetchHooks Function({bool transactionsRefs, bool merchantRulesRefs, bool budgetsRefs})
    >;
typedef $$TransactionsTableCreateCompanionBuilder = TransactionsCompanion Function({
  Value<int> id,
  required int amountMinor,
  required TxnDirection direction,
  required DateTime occurredAt,
  Value<String?> merchant,
  Value<String?> counterparty,
  Value<String?> note,
  Value<int?> categoryId,
  Value<int?> accountId,
  Value<String?> accountHint,
  required PaymentMode mode,
  Value<String?> reference,
  required TxnStatus status,
  Value<bool> isTransfer,
  Value<bool> categoryLocked,
  Value<int?> duplicateOfId,
  Value<DateTime> createdAt,
});
typedef $$TransactionsTableUpdateCompanionBuilder = TransactionsCompanion Function({
  Value<int> id,
  Value<int> amountMinor,
  Value<TxnDirection> direction,
  Value<DateTime> occurredAt,
  Value<String?> merchant,
  Value<String?> counterparty,
  Value<String?> note,
  Value<int?> categoryId,
  Value<int?> accountId,
  Value<String?> accountHint,
  Value<PaymentMode> mode,
  Value<String?> reference,
  Value<TxnStatus> status,
  Value<bool> isTransfer,
  Value<bool> categoryLocked,
  Value<int?> duplicateOfId,
  Value<DateTime> createdAt,
});

final class $$TransactionsTableReferences extends BaseReferences<_$AppDatabase, $TransactionsTable, Transaction> {
  $$TransactionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('transactions__category_id__categories__id');

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<int>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager($_db, $_db.categories).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }

  static $AccountsTable _accountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('transactions__account_id__accounts__id');

  $$AccountsTableProcessedTableManager? get accountId {
    final $_column = $_itemColumn<int>('account_id');
    if ($_column == null) return null;
    final manager = $$AccountsTableTableManager($_db, $_db.accounts).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$RawMessagesTable, List<RawMessage>> _rawMessagesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.rawMessages, aliasName: 'transactions__id__raw_messages__transaction_id');

  $$RawMessagesTableProcessedTableManager get rawMessagesRefs {
    final manager = $$RawMessagesTableTableManager(
      $_db,
      $_db.rawMessages,
    ).filter((f) => f.transactionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_rawMessagesRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$TransactionsTableFilterComposer extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amountMinor =>
      $composableBuilder(column: $table.amountMinor, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<TxnDirection, TxnDirection, int> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<DateTime> get occurredAt =>
      $composableBuilder(column: $table.occurredAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get merchant =>
      $composableBuilder(column: $table.merchant, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get counterparty =>
      $composableBuilder(column: $table.counterparty, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountHint =>
      $composableBuilder(column: $table.accountHint, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<PaymentMode, PaymentMode, int> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<TxnStatus, TxnStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<bool> get isTransfer =>
      $composableBuilder(column: $table.isTransfer, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get categoryLocked =>
      $composableBuilder(column: $table.categoryLocked, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get duplicateOfId =>
      $composableBuilder(column: $table.duplicateOfId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> rawMessagesRefs(Expression<bool> Function($$RawMessagesTableFilterComposer f) f) {
    final $$RawMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawMessages,
      getReferencedColumn: (t) => t.transactionId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$RawMessagesTableFilterComposer(
            $db: $db,
            $table: $db.rawMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TransactionsTableOrderingComposer extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amountMinor =>
      $composableBuilder(column: $table.amountMinor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get occurredAt =>
      $composableBuilder(column: $table.occurredAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get merchant =>
      $composableBuilder(column: $table.merchant, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get counterparty =>
      $composableBuilder(column: $table.counterparty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountHint =>
      $composableBuilder(column: $table.accountHint, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isTransfer =>
      $composableBuilder(column: $table.isTransfer, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get categoryLocked =>
      $composableBuilder(column: $table.categoryLocked, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get duplicateOfId =>
      $composableBuilder(column: $table.duplicateOfId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionsTableAnnotationComposer extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(column: $table.amountMinor, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TxnDirection, int> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt =>
      $composableBuilder(column: $table.occurredAt, builder: (column) => column);

  GeneratedColumn<String> get merchant => $composableBuilder(column: $table.merchant, builder: (column) => column);

  GeneratedColumn<String> get counterparty =>
      $composableBuilder(column: $table.counterparty, builder: (column) => column);

  GeneratedColumn<String> get note => $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get accountHint =>
      $composableBuilder(column: $table.accountHint, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PaymentMode, int> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get reference => $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TxnStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isTransfer => $composableBuilder(column: $table.isTransfer, builder: (column) => column);

  GeneratedColumn<bool> get categoryLocked =>
      $composableBuilder(column: $table.categoryLocked, builder: (column) => column);

  GeneratedColumn<int> get duplicateOfId =>
      $composableBuilder(column: $table.duplicateOfId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> rawMessagesRefs<T extends Object>(Expression<T> Function($$RawMessagesTableAnnotationComposer a) f) {
    final $$RawMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawMessages,
      getReferencedColumn: (t) => t.transactionId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$RawMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.rawMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionsTable,
          Transaction,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (Transaction, $$TransactionsTableReferences),
          Transaction,
          PrefetchHooks Function({bool categoryId, bool accountId, bool rawMessagesRefs})
        > {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<TxnDirection> direction = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String?> merchant = const Value.absent(),
                Value<String?> counterparty = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int?> accountId = const Value.absent(),
                Value<String?> accountHint = const Value.absent(),
                Value<PaymentMode> mode = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<TxnStatus> status = const Value.absent(),
                Value<bool> isTransfer = const Value.absent(),
                Value<bool> categoryLocked = const Value.absent(),
                Value<int?> duplicateOfId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                amountMinor: amountMinor,
                direction: direction,
                occurredAt: occurredAt,
                merchant: merchant,
                counterparty: counterparty,
                note: note,
                categoryId: categoryId,
                accountId: accountId,
                accountHint: accountHint,
                mode: mode,
                reference: reference,
                status: status,
                isTransfer: isTransfer,
                categoryLocked: categoryLocked,
                duplicateOfId: duplicateOfId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int amountMinor,
                required TxnDirection direction,
                required DateTime occurredAt,
                Value<String?> merchant = const Value.absent(),
                Value<String?> counterparty = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int?> accountId = const Value.absent(),
                Value<String?> accountHint = const Value.absent(),
                required PaymentMode mode,
                Value<String?> reference = const Value.absent(),
                required TxnStatus status,
                Value<bool> isTransfer = const Value.absent(),
                Value<bool> categoryLocked = const Value.absent(),
                Value<int?> duplicateOfId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                amountMinor: amountMinor,
                direction: direction,
                occurredAt: occurredAt,
                merchant: merchant,
                counterparty: counterparty,
                note: note,
                categoryId: categoryId,
                accountId: accountId,
                accountHint: accountHint,
                mode: mode,
                reference: reference,
                status: status,
                isTransfer: isTransfer,
                categoryLocked: categoryLocked,
                duplicateOfId: duplicateOfId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable<$TransactionsTable, Transaction>(table), $$TransactionsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false, accountId = false, rawMessagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (rawMessagesRefs) db.rawMessages],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.categoryId,
                        referencedTable: $$TransactionsTableReferences._categoryIdTable(db),
                        referencedColumn: $$TransactionsTableReferences._categoryIdTable(db).id,
                      ) as T;
                    }
                    if (accountId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.accountId,
                        referencedTable: $$TransactionsTableReferences._accountIdTable(db),
                        referencedColumn: $$TransactionsTableReferences._accountIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (rawMessagesRefs)
                    await $_getPrefetchedData<Transaction, $TransactionsTable, RawMessage>(
                      currentTable: table,
                      referencedTable: $$TransactionsTableReferences._rawMessagesRefsTable(db),
                      managerFromTypedResult: (p0) => $$TransactionsTableReferences(db, table, p0).rawMessagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.transactionId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionsTable,
      Transaction,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (Transaction, $$TransactionsTableReferences),
      Transaction,
      PrefetchHooks Function({bool categoryId, bool accountId, bool rawMessagesRefs})
    >;
typedef $$RawMessagesTableCreateCompanionBuilder = RawMessagesCompanion Function({
  Value<int> id,
  required SourceKind source,
  required String externalId,
  required String sender,
  required String body,
  required DateTime receivedAt,
  required ParseStatus parseStatus,
  Value<String?> ignoreReason,
  Value<int?> transactionId,
  Value<double?> mergeScore,
});
typedef $$RawMessagesTableUpdateCompanionBuilder = RawMessagesCompanion Function({
  Value<int> id,
  Value<SourceKind> source,
  Value<String> externalId,
  Value<String> sender,
  Value<String> body,
  Value<DateTime> receivedAt,
  Value<ParseStatus> parseStatus,
  Value<String?> ignoreReason,
  Value<int?> transactionId,
  Value<double?> mergeScore,
});

final class $$RawMessagesTableReferences extends BaseReferences<_$AppDatabase, $RawMessagesTable, RawMessage> {
  $$RawMessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TransactionsTable _transactionIdTable(_$AppDatabase db) =>
      db.transactions.createAlias('raw_messages__transaction_id__transactions__id');

  $$TransactionsTableProcessedTableManager? get transactionId {
    final $_column = $_itemColumn<int>('transaction_id');
    if ($_column == null) return null;
    final manager = $$TransactionsTableTableManager($_db, $_db.transactions).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_transactionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$RawMessagesTableFilterComposer extends Composer<_$AppDatabase, $RawMessagesTable> {
  $$RawMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<SourceKind, SourceKind, int> get source =>
      $composableBuilder(column: $table.source, builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get externalId =>
      $composableBuilder(column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get body => $composableBuilder(column: $table.body, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get receivedAt =>
      $composableBuilder(column: $table.receivedAt, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<ParseStatus, ParseStatus, int> get parseStatus =>
      $composableBuilder(column: $table.parseStatus, builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get ignoreReason =>
      $composableBuilder(column: $table.ignoreReason, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mergeScore =>
      $composableBuilder(column: $table.mergeScore, builder: (column) => ColumnFilters(column));

  $$TransactionsTableFilterComposer get transactionId {
    final $$TransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.transactionId,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$TransactionsTableFilterComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RawMessagesTableOrderingComposer extends Composer<_$AppDatabase, $RawMessagesTable> {
  $$RawMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get source =>
      $composableBuilder(column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId =>
      $composableBuilder(column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get receivedAt =>
      $composableBuilder(column: $table.receivedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get parseStatus =>
      $composableBuilder(column: $table.parseStatus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ignoreReason =>
      $composableBuilder(column: $table.ignoreReason, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mergeScore =>
      $composableBuilder(column: $table.mergeScore, builder: (column) => ColumnOrderings(column));

  $$TransactionsTableOrderingComposer get transactionId {
    final $$TransactionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.transactionId,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$TransactionsTableOrderingComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RawMessagesTableAnnotationComposer extends Composer<_$AppDatabase, $RawMessagesTable> {
  $$RawMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SourceKind, int> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(column: $table.externalId, builder: (column) => column);

  GeneratedColumn<String> get sender => $composableBuilder(column: $table.sender, builder: (column) => column);

  GeneratedColumn<String> get body => $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get receivedAt =>
      $composableBuilder(column: $table.receivedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ParseStatus, int> get parseStatus =>
      $composableBuilder(column: $table.parseStatus, builder: (column) => column);

  GeneratedColumn<String> get ignoreReason =>
      $composableBuilder(column: $table.ignoreReason, builder: (column) => column);

  GeneratedColumn<double> get mergeScore => $composableBuilder(column: $table.mergeScore, builder: (column) => column);

  $$TransactionsTableAnnotationComposer get transactionId {
    final $$TransactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.transactionId,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$TransactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RawMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RawMessagesTable,
          RawMessage,
          $$RawMessagesTableFilterComposer,
          $$RawMessagesTableOrderingComposer,
          $$RawMessagesTableAnnotationComposer,
          $$RawMessagesTableCreateCompanionBuilder,
          $$RawMessagesTableUpdateCompanionBuilder,
          (RawMessage, $$RawMessagesTableReferences),
          RawMessage,
          PrefetchHooks Function({bool transactionId})
        > {
  $$RawMessagesTableTableManager(_$AppDatabase db, $RawMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$RawMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$RawMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$RawMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<SourceKind> source = const Value.absent(),
                Value<String> externalId = const Value.absent(),
                Value<String> sender = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<ParseStatus> parseStatus = const Value.absent(),
                Value<String?> ignoreReason = const Value.absent(),
                Value<int?> transactionId = const Value.absent(),
                Value<double?> mergeScore = const Value.absent(),
              }) => RawMessagesCompanion(
                id: id,
                source: source,
                externalId: externalId,
                sender: sender,
                body: body,
                receivedAt: receivedAt,
                parseStatus: parseStatus,
                ignoreReason: ignoreReason,
                transactionId: transactionId,
                mergeScore: mergeScore,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required SourceKind source,
                required String externalId,
                required String sender,
                required String body,
                required DateTime receivedAt,
                required ParseStatus parseStatus,
                Value<String?> ignoreReason = const Value.absent(),
                Value<int?> transactionId = const Value.absent(),
                Value<double?> mergeScore = const Value.absent(),
              }) => RawMessagesCompanion.insert(
                id: id,
                source: source,
                externalId: externalId,
                sender: sender,
                body: body,
                receivedAt: receivedAt,
                parseStatus: parseStatus,
                ignoreReason: ignoreReason,
                transactionId: transactionId,
                mergeScore: mergeScore,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (e.readTable<$RawMessagesTable, RawMessage>(table), $$RawMessagesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({transactionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (transactionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.transactionId,
                        referencedTable: $$RawMessagesTableReferences._transactionIdTable(db),
                        referencedColumn: $$RawMessagesTableReferences._transactionIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RawMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RawMessagesTable,
      RawMessage,
      $$RawMessagesTableFilterComposer,
      $$RawMessagesTableOrderingComposer,
      $$RawMessagesTableAnnotationComposer,
      $$RawMessagesTableCreateCompanionBuilder,
      $$RawMessagesTableUpdateCompanionBuilder,
      (RawMessage, $$RawMessagesTableReferences),
      RawMessage,
      PrefetchHooks Function({bool transactionId})
    >;
typedef $$MerchantRulesTableCreateCompanionBuilder = MerchantRulesCompanion Function({
  Value<int> id,
  required String pattern,
  required int categoryId,
});
typedef $$MerchantRulesTableUpdateCompanionBuilder = MerchantRulesCompanion Function({
  Value<int> id,
  Value<String> pattern,
  Value<int> categoryId,
});

final class $$MerchantRulesTableReferences extends BaseReferences<_$AppDatabase, $MerchantRulesTable, MerchantRule> {
  $$MerchantRulesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('merchant_rules__category_id__categories__id');

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<int>('category_id')!;

    final manager = $$CategoriesTableTableManager($_db, $_db.categories).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MerchantRulesTableFilterComposer extends Composer<_$AppDatabase, $MerchantRulesTable> {
  $$MerchantRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => ColumnFilters(column));

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MerchantRulesTableOrderingComposer extends Composer<_$AppDatabase, $MerchantRulesTable> {
  $$MerchantRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => ColumnOrderings(column));

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MerchantRulesTableAnnotationComposer extends Composer<_$AppDatabase, $MerchantRulesTable> {
  $$MerchantRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pattern => $composableBuilder(column: $table.pattern, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MerchantRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MerchantRulesTable,
          MerchantRule,
          $$MerchantRulesTableFilterComposer,
          $$MerchantRulesTableOrderingComposer,
          $$MerchantRulesTableAnnotationComposer,
          $$MerchantRulesTableCreateCompanionBuilder,
          $$MerchantRulesTableUpdateCompanionBuilder,
          (MerchantRule, $$MerchantRulesTableReferences),
          MerchantRule,
          PrefetchHooks Function({bool categoryId})
        > {
  $$MerchantRulesTableTableManager(_$AppDatabase db, $MerchantRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$MerchantRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$MerchantRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$MerchantRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> pattern = const Value.absent(),
            Value<int> categoryId = const Value.absent(),
          }) => MerchantRulesCompanion(id: id, pattern: pattern, categoryId: categoryId),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String pattern,
            required int categoryId,
          }) => MerchantRulesCompanion.insert(id: id, pattern: pattern, categoryId: categoryId),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MerchantRulesTable, MerchantRule>(table),
                  $$MerchantRulesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.categoryId,
                        referencedTable: $$MerchantRulesTableReferences._categoryIdTable(db),
                        referencedColumn: $$MerchantRulesTableReferences._categoryIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MerchantRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MerchantRulesTable,
      MerchantRule,
      $$MerchantRulesTableFilterComposer,
      $$MerchantRulesTableOrderingComposer,
      $$MerchantRulesTableAnnotationComposer,
      $$MerchantRulesTableCreateCompanionBuilder,
      $$MerchantRulesTableUpdateCompanionBuilder,
      (MerchantRule, $$MerchantRulesTableReferences),
      MerchantRule,
      PrefetchHooks Function({bool categoryId})
    >;
typedef $$BudgetsTableCreateCompanionBuilder = BudgetsCompanion Function({
  Value<int> id,
  Value<int?> categoryId,
  required int amountMinor,
  Value<bool> active,
  Value<DateTime> createdAt,
});
typedef $$BudgetsTableUpdateCompanionBuilder = BudgetsCompanion Function({
  Value<int> id,
  Value<int?> categoryId,
  Value<int> amountMinor,
  Value<bool> active,
  Value<DateTime> createdAt,
});

final class $$BudgetsTableReferences extends BaseReferences<_$AppDatabase, $BudgetsTable, Budget> {
  $$BudgetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('budgets__category_id__categories__id');

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<int>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager($_db, $_db.categories).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$BudgetsTableFilterComposer extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amountMinor =>
      $composableBuilder(column: $table.amountMinor, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableOrderingComposer extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amountMinor =>
      $composableBuilder(column: $table.amountMinor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableAnnotationComposer extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(column: $table.amountMinor, builder: (column) => column);

  GeneratedColumn<bool> get active => $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetsTable,
          Budget,
          $$BudgetsTableFilterComposer,
          $$BudgetsTableOrderingComposer,
          $$BudgetsTableAnnotationComposer,
          $$BudgetsTableCreateCompanionBuilder,
          $$BudgetsTableUpdateCompanionBuilder,
          (Budget, $$BudgetsTableReferences),
          Budget,
          PrefetchHooks Function({bool categoryId})
        > {
  $$BudgetsTableTableManager(_$AppDatabase db, $BudgetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$BudgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$BudgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$BudgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => BudgetsCompanion(
                id: id,
                categoryId: categoryId,
                amountMinor: amountMinor,
                active: active,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                required int amountMinor,
                Value<bool> active = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => BudgetsCompanion.insert(
                id: id,
                categoryId: categoryId,
                amountMinor: amountMinor,
                active: active,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable<$BudgetsTable, Budget>(table), $$BudgetsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({categoryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.categoryId,
                        referencedTable: $$BudgetsTableReferences._categoryIdTable(db),
                        referencedColumn: $$BudgetsTableReferences._categoryIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BudgetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetsTable,
      Budget,
      $$BudgetsTableFilterComposer,
      $$BudgetsTableOrderingComposer,
      $$BudgetsTableAnnotationComposer,
      $$BudgetsTableCreateCompanionBuilder,
      $$BudgetsTableUpdateCompanionBuilder,
      (Budget, $$BudgetsTableReferences),
      Budget,
      PrefetchHooks Function({bool categoryId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AccountsTableTableManager get accounts => $$AccountsTableTableManager(_db, _db.accounts);
  $$CategoriesTableTableManager get categories => $$CategoriesTableTableManager(_db, _db.categories);
  $$TransactionsTableTableManager get transactions => $$TransactionsTableTableManager(_db, _db.transactions);
  $$RawMessagesTableTableManager get rawMessages => $$RawMessagesTableTableManager(_db, _db.rawMessages);
  $$MerchantRulesTableTableManager get merchantRules => $$MerchantRulesTableTableManager(_db, _db.merchantRules);
  $$BudgetsTableTableManager get budgets => $$BudgetsTableTableManager(_db, _db.budgets);
}
