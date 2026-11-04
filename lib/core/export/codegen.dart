import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';

/// ภาษา/เฟรมเวิร์กที่สร้างโค้ด entity ให้ได้
enum CodegenTarget {
  dart('Dart', 'dart'),
  typescript('TypeScript', 'ts'),
  prisma('Prisma', 'prisma'),
  java('Java (JPA)', 'java'),
  csharp('C# (EF Core)', 'cs');

  const CodegenTarget(this.label, this.ext);
  final String label;
  final String ext;
}

/// สร้างโค้ด entity/model จากโครงสร้างตาราง — ผลลัพธ์คงที่ (ข้อมูลเดิม → ข้อความเดิม) ไม่มีวันที่
String generateCode(Project p, CodegenTarget target) => switch (target) {
      CodegenTarget.dart => _dart(p),
      CodegenTarget.typescript => _typescript(p),
      CodegenTarget.prisma => _prisma(p),
      CodegenTarget.java => _java(p),
      CodegenTarget.csharp => _csharp(p),
    };

/// ชื่อไฟล์แนะนำ (Prisma = schema.prisma ; ที่เหลือใช้ชื่อโปรเจกต์)
String codegenFileName(Project p, CodegenTarget t, String safeBase) =>
    t == CodegenTarget.prisma ? 'schema.prisma' : '${safeBase}_models.${t.ext}';

// ---------- ชื่อ ----------

List<String> _words(String s) {
  final spaced = s
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim();
  return spaced.isEmpty ? <String>[] : spaced.split(' ');
}

String _cap(String w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';

/// ตัวระบุที่ขึ้นต้นด้วยตัวเลขไม่ได้ ; ชื่อที่แปลงแล้วว่าง (เช่นชื่อภาษาไทยล้วน) ใช้ [fallback]
String _safeIdent(String s, String fallback) {
  if (s.isEmpty) return fallback;
  return RegExp(r'^[0-9]').hasMatch(s) ? '_$s' : s;
}

String _pascal(String s, {String fallback = 'Entity'}) =>
    _safeIdent(_words(s).map(_cap).join(), fallback);

String _camel(String s, {String fallback = 'field'}) {
  final w = _words(s);
  if (w.isEmpty) return fallback;
  return _safeIdent(w.first.toLowerCase() + w.skip(1).map(_cap).join(), fallback);
}

/// ทำคำสุดท้ายเป็นเอกพจน์แบบง่าย ๆ (users → user, categories → category, addresses → address)
String _singular(String word) {
  final w = word.toLowerCase();
  if (w.length > 3 && w.endsWith('ies')) return '${word.substring(0, word.length - 3)}${_keepCase(word, 'y')}';
  if (w.length > 3 && RegExp(r'(ss|us|is)es$|(x|ch|sh)es$|sses$').hasMatch(w)) return word.substring(0, word.length - 2);
  if (w.length > 2 && w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us') && !w.endsWith('is')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

String _keepCase(String sample, String s) => sample == sample.toUpperCase() ? s.toUpperCase() : s;

/// ชื่อ class ของตาราง (เอกพจน์ PascalCase) — ชื่อซ้ำกันจะต่อเลขท้าย
Map<String, String> _classNames(Project p) {
  final used = <String>{};
  final out = <String, String>{};
  for (final t in p.tables) {
    final w = _words(t.name);
    final base = w.isEmpty
        ? 'Entity'
        : _safeIdent([...w.take(w.length - 1).map(_cap), _cap(_singular(w.last))].join(), 'Entity');
    var name = base;
    for (var n = 2; !used.add(name); n++) {
      name = '$base$n';
    }
    out[t.id] = name;
  }
  return out;
}

/// ชื่อ field ของคอลัมน์ (camelCase) — ซ้ำกันในตารางเดียวกันจะต่อเลขท้าย
Map<String, String> _fieldNames(TableModel t, {Set<String> reserved = const {}}) {
  final used = {...reserved};
  final out = <String, String>{};
  for (final c in t.columns) {
    final base = _camel(c.name);
    var name = base;
    for (var n = 2; !used.add(name); n++) {
      name = '$base$n';
    }
    out[c.id] = name;
  }
  return out;
}

bool _nullable(ColumnModel c) => !(c.notNull || c.isPrimaryKey);

String _lineComment(String s) => s.replaceAll(RegExp(r'\s*\r?\n\s*'), ' ').trim();

String _header(Project p, String c) => '$c สร้างโดย NSL Modeler จากโปรเจกต์ "${_lineComment(p.name)}" — ไม่มีวันที่เพื่อให้ diff ใน git อ่านง่าย';

// ---------- Dart ----------

String _dartType(ColumnModel c) => switch (c.type) {
      DataType.integer || DataType.bigint || DataType.smallint => 'int',
      DataType.varchar || DataType.text || DataType.uuid => 'String',
      DataType.decimal || DataType.float => 'double',
      DataType.boolean => 'bool',
      DataType.date || DataType.datetime || DataType.timestamp => 'DateTime',
      DataType.blob => 'List<int>',
      DataType.json => 'Map<String, dynamic>',
    };

String _dartFromJson(ColumnModel c, String expr) {
  final nullable = _nullable(c);
  final type = _dartType(c);
  switch (c.type) {
    case DataType.decimal:
    case DataType.float:
      return nullable ? '($expr as num?)?.toDouble()' : '($expr as num).toDouble()';
    case DataType.date:
    case DataType.datetime:
    case DataType.timestamp:
      return nullable ? "$expr == null ? null : DateTime.parse($expr as String)" : 'DateTime.parse($expr as String)';
    case DataType.blob:
      return nullable ? '($expr as List?)?.cast<int>()' : '($expr as List).cast<int>()';
    default:
      return '$expr as $type${nullable ? '?' : ''}';
  }
}

String _dartToJson(ColumnModel c, String f) {
  switch (c.type) {
    case DataType.date:
    case DataType.datetime:
    case DataType.timestamp:
      return _nullable(c) ? '$f?.toIso8601String()' : '$f.toIso8601String()';
    default:
      return f;
  }
}

String _dart(Project p) {
  final cls = _classNames(p);
  final b = StringBuffer()
    ..writeln(_header(p, '//'))
    ..writeln();
  var first = true;
  for (final t in p.tables) {
    if (t.columns.isEmpty) continue;
    if (!first) b.writeln();
    first = false;
    final name = cls[t.id]!;
    final f = _fieldNames(t);
    if (t.comment.isNotEmpty) b.writeln('/// ${_lineComment(t.comment)}');
    b.writeln('class $name {');
    b.writeln('  const $name({');
    for (final c in t.columns) {
      b.writeln('    ${_nullable(c) ? '' : 'required '}this.${f[c.id]},');
    }
    b.writeln('  });');
    b.writeln();
    for (final c in t.columns) {
      if (c.comment.isNotEmpty) b.writeln('  /// ${_lineComment(c.comment)}');
      b.writeln('  final ${_dartType(c)}${_nullable(c) ? '?' : ''} ${f[c.id]};');
    }
    b.writeln();
    b.writeln('  factory $name.fromJson(Map<String, dynamic> json) => $name(');
    for (final c in t.columns) {
      b.writeln("        ${f[c.id]}: ${_dartFromJson(c, "json['${_esc(c.name)}']")},");
    }
    b.writeln('      );');
    b.writeln();
    b.writeln('  Map<String, dynamic> toJson() => {');
    for (final c in t.columns) {
      b.writeln("        '${_esc(c.name)}': ${_dartToJson(c, f[c.id]!)},");
    }
    b.writeln('      };');
    b.writeln('}');
  }
  if (first) b.writeln('// ยังไม่มีตารางที่มีคอลัมน์');
  return b.toString();
}

String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

// ---------- TypeScript ----------

String _tsType(ColumnModel c) => switch (c.type) {
      DataType.integer || DataType.smallint || DataType.decimal || DataType.float => 'number',
      DataType.bigint => 'string', // เกินช่วงของ number ได้ — ไลบรารีส่วนใหญ่ส่งเป็นสตริง
      DataType.varchar || DataType.text || DataType.uuid => 'string',
      DataType.boolean => 'boolean',
      DataType.date || DataType.datetime || DataType.timestamp => 'Date',
      DataType.blob => 'Uint8Array',
      DataType.json => 'unknown',
    };

String _typescript(Project p) {
  final cls = _classNames(p);
  final b = StringBuffer()
    ..writeln(_header(p, '//'))
    ..writeln();
  var first = true;
  for (final t in p.tables) {
    if (t.columns.isEmpty) continue;
    if (!first) b.writeln();
    first = false;
    final f = _fieldNames(t);
    final out = [for (final r in p.relations) if (r.fromTableId == t.id) r];
    if (t.comment.isNotEmpty) b.writeln('/** ${_lineComment(t.comment).replaceAll('*/', '* /')} */');
    b.writeln('export interface ${cls[t.id]} {');
    for (final c in t.columns) {
      if (c.comment.isNotEmpty) b.writeln('  /** ${_lineComment(c.comment).replaceAll('*/', '* /')} */');
      final fk = out.where((r) => r.fromColumnId == c.id).firstOrNull;
      final ref = fk == null ? '' : ' // → ${p.tableById(fk.toTableId)?.name}.${p.tableById(fk.toTableId)?.columnById(fk.toColumnId)?.name}';
      b.writeln('  ${f[c.id]}${_nullable(c) ? '?' : ''}: ${_tsType(c)}${_nullable(c) ? ' | null' : ''};$ref');
    }
    b.writeln('}');
  }
  if (first) b.writeln('// ยังไม่มีตารางที่มีคอลัมน์');
  return b.toString();
}

// ---------- Prisma ----------

String _prismaType(ColumnModel c) => switch (c.type) {
      DataType.integer || DataType.smallint => 'Int',
      DataType.bigint => 'BigInt',
      DataType.varchar || DataType.text || DataType.uuid => 'String',
      DataType.decimal => 'Decimal',
      DataType.float => 'Float',
      DataType.boolean => 'Boolean',
      DataType.date || DataType.datetime || DataType.timestamp => 'DateTime',
      DataType.blob => 'Bytes',
      DataType.json => 'Json',
    };

String? _prismaNative(ColumnModel c) {
  switch (c.type) {
    case DataType.varchar:
      return '@db.VarChar(${c.length ?? 255})';
    case DataType.decimal:
      return '@db.Decimal(${c.length ?? 10}, ${c.scale ?? 2})';
    case DataType.smallint:
      return '@db.SmallInt';
    case DataType.date:
      return '@db.Date';
    case DataType.uuid:
      return '@db.Uuid';
    default:
      return null;
  }
}

String _prismaAction(RefAction a) => switch (a) {
      RefAction.noAction => 'NoAction',
      RefAction.cascade => 'Cascade',
      RefAction.restrict => 'Restrict',
      RefAction.setNull => 'SetNull',
    };

String? _prismaDefault(ColumnModel c) {
  if (c.autoIncrement && (c.type == DataType.integer || c.type == DataType.bigint || c.type == DataType.smallint)) {
    return '@default(autoincrement())';
  }
  final raw = (c.defaultValue ?? '').trim();
  if (raw.isEmpty) return null;
  final up = raw.toUpperCase();
  if (up == 'CURRENT_TIMESTAMP' || up == 'NOW()' || up.startsWith('CURRENT_TIMESTAMP(')) return '@default(now())';
  if (up == 'NULL') return null;
  switch (c.type) {
    case DataType.integer:
    case DataType.bigint:
    case DataType.smallint:
    case DataType.decimal:
    case DataType.float:
      return num.tryParse(raw) == null ? '@default(dbgenerated("${raw.replaceAll('"', '\\"')}"))' : '@default($raw)';
    case DataType.boolean:
      if (up == 'TRUE' || raw == '1') return '@default(true)';
      if (up == 'FALSE' || raw == '0') return '@default(false)';
      return null;
    case DataType.varchar:
    case DataType.text:
    case DataType.uuid:
      final unq = raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'") ? raw.substring(1, raw.length - 1) : raw;
      return '@default("${unq.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}")';
    default:
      return '@default(dbgenerated("${raw.replaceAll('"', '\\"')}"))';
  }
}

String _prisma(Project p) {
  final cls = _classNames(p);
  final b = StringBuffer()
    ..writeln(_header(p, '//'))
    ..writeln('datasource db {')
    ..writeln('  provider = "${switch (p.dialect) {
      Dialect.mysql => 'mysql',
      Dialect.postgres => 'postgresql',
      Dialect.sqlite => 'sqlite',
      Dialect.mssql => 'sqlserver',
    }}"')
    ..writeln('  url      = env("DATABASE_URL")')
    ..writeln('}')
    ..writeln()
    ..writeln('generator client {')
    ..writeln('  provider = "prisma-client-js"')
    ..writeln('}');

  final tables = [for (final t in p.tables) if (t.columns.isNotEmpty) t];
  final tableIds = {for (final t in tables) t.id};
  // FK ที่ใช้ได้: ทั้งสองฝั่งอยู่ในตารางที่สร้าง model และเป็นคอลัมน์ที่มีอยู่จริง
  final rels = [
    for (final r in p.relations)
      if (tableIds.contains(r.fromTableId) &&
          tableIds.contains(r.toTableId) &&
          p.tableById(r.fromTableId)!.columnById(r.fromColumnId) != null &&
          p.tableById(r.toTableId)!.columnById(r.toColumnId) != null)
        r,
  ];

  // ชื่อ field ที่ใช้แล้วต่อ model (คอลัมน์ + field ความสัมพันธ์ที่เพิ่มทีหลัง)
  final fields = {for (final t in tables) t.id: _fieldNames(t)};
  final taken = {for (final t in tables) t.id: {...fields[t.id]!.values}};
  String uniq(String tableId, String base) {
    var n = base;
    for (var i = 2; !taken[tableId]!.add(n); i++) {
      n = '$base$i';
    }
    return n;
  }

  // field ความสัมพันธ์ต่อ model : (บรรทัด)
  final relLines = {for (final t in tables) t.id: <String>[]};
  // จำนวน FK ระหว่างคู่ตารางเดียวกัน > 1 ต้องตั้งชื่อ relation
  int pairCount(RelationModel r) =>
      rels.where((o) => o.fromTableId == r.fromTableId && o.toTableId == r.toTableId).length;
  for (final r in rels) {
    final child = p.tableById(r.fromTableId)!, parent = p.tableById(r.toTableId)!;
    final fromCol = child.columnById(r.fromColumnId)!;
    final multi = pairCount(r) > 1;
    final relName = multi ? '"${cls[child.id]}_${fields[child.id]![fromCol.id]}"' : null;
    final base = _camel(_words(fromCol.name).length > 1 && fromCol.name.toLowerCase().endsWith('_id')
        ? fromCol.name.substring(0, fromCol.name.length - 3)
        : cls[parent.id]!);
    final childField = uniq(child.id, base);
    final optional = _nullable(fromCol);
    final args = [
      if (relName != null) 'name: $relName',
      'fields: [${fields[child.id]![fromCol.id]}]',
      'references: [${fields[parent.id]![r.toColumnId]}]',
      if (r.onDelete != RefAction.noAction) 'onDelete: ${_prismaAction(r.onDelete)}',
      if (r.onUpdate != RefAction.noAction) 'onUpdate: ${_prismaAction(r.onUpdate)}',
    ];
    relLines[child.id]!.add('$childField ${cls[parent.id]}${optional ? '?' : ''} @relation(${args.join(', ')})');
    // ฝั่งแม่: list ของลูก (self-reference ใช้ชื่อ relation เสมอเพื่อไม่กำกวม)
    final backBase = _camel(child.name);
    final backField = uniq(parent.id, backBase == childField && child.id == parent.id ? '${backBase}Children' : backBase);
    final needName = relName ?? (child.id == parent.id ? '"${cls[child.id]}_${fields[child.id]![fromCol.id]}"' : null);
    if (needName != null && relName == null) {
      // เติมชื่อให้ฝั่งลูกด้วย
      final i = relLines[child.id]!.length - 1;
      relLines[child.id]![i] =
          relLines[child.id]![i].replaceFirst('@relation(', '@relation(name: $needName, ');
    }
    relLines[parent.id]!.add('$backField ${cls[child.id]}[]${needName == null ? '' : ' @relation($needName)'}');
  }

  for (final t in tables) {
    final f = fields[t.id]!;
    final pk = t.columns.where((c) => c.isPrimaryKey).toList();
    b.writeln();
    if (t.comment.isNotEmpty) b.writeln('/// ${_lineComment(t.comment)}');
    b.writeln('model ${cls[t.id]} {');
    final lines = <(String, String, String)>[];
    for (final c in t.columns) {
      final attrs = <String>[
        if (pk.length == 1 && c.isPrimaryKey) '@id',
        ?_prismaDefault(c),
        if (c.unique && !c.isPrimaryKey) '@unique',
        ?_prismaNative(c),
        if (f[c.id] != c.name) '@map("${c.name.replaceAll('"', '\\"')}")',
      ];
      lines.add((f[c.id]!, '${_prismaType(c)}${_nullable(c) ? '?' : ''}', attrs.join(' ')));
    }
    final w1 = lines.fold<int>(0, (m, l) => l.$1.length > m ? l.$1.length : m);
    final w2 = lines.fold<int>(0, (m, l) => l.$2.length > m ? l.$2.length : m);
    for (var i = 0; i < t.columns.length; i++) {
      final c = t.columns[i];
      final l = lines[i];
      if (c.comment.isNotEmpty) b.writeln('  /// ${_lineComment(c.comment)}');
      b.writeln('  ${l.$1.padRight(w1)} ${l.$3.isEmpty ? l.$2 : l.$2.padRight(w2)}${l.$3.isEmpty ? '' : ' ${l.$3}'}');
    }
    if (relLines[t.id]!.isNotEmpty) {
      b.writeln();
      for (final l in relLines[t.id]!) {
        b.writeln('  $l');
      }
    }
    b.writeln();
    if (pk.length > 1) {
      b.writeln('  @@id([${pk.map((c) => f[c.id]).join(', ')}])');
    } else if (pk.isEmpty) {
      b.writeln('  // ⚠ Prisma ต้องมี @id หรือ @unique อย่างน้อยหนึ่งคอลัมน์ — ตารางนี้ยังไม่มีคีย์หลัก');
    }
    for (final i in t.indexes) {
      final cols = [for (final id in i.columnIds) if (f[id] != null) f[id]!];
      if (cols.isEmpty) continue;
      b.writeln('  @@${i.unique ? 'unique' : 'index'}([${cols.join(', ')}], map: "${i.name.replaceAll('"', '\\"')}")');
    }
    if (_pascal(t.name) != t.name || cls[t.id] != t.name) b.writeln('  @@map("${t.name.replaceAll('"', '\\"')}")');
    b.writeln('}');
  }
  return b.toString();
}

// ---------- Java (JPA) ----------

String _javaType(ColumnModel c, {required bool boxed}) {
  final nullable = _nullable(c);
  final b = boxed || nullable;
  return switch (c.type) {
    DataType.integer => b ? 'Integer' : 'int',
    DataType.smallint => b ? 'Short' : 'short',
    DataType.bigint => b ? 'Long' : 'long',
    DataType.varchar || DataType.text => 'String',
    DataType.uuid => 'java.util.UUID',
    DataType.decimal => 'java.math.BigDecimal',
    DataType.float => b ? 'Double' : 'double',
    DataType.boolean => b ? 'Boolean' : 'boolean',
    DataType.date => 'java.time.LocalDate',
    DataType.datetime => 'java.time.LocalDateTime',
    DataType.timestamp => 'java.time.Instant',
    DataType.blob => 'byte[]',
    DataType.json => 'String',
  };
}

String _javaStr(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

String _java(Project p) {
  final cls = _classNames(p);
  final b = StringBuffer()
    ..writeln(_header(p, '//'))
    ..writeln('import jakarta.persistence.*;');
  final tables = [for (final t in p.tables) if (t.columns.isNotEmpty) t];
  for (final t in tables) {
    final f = _fieldNames(t, reserved: _javaReserved);
    final pk = t.columns.where((c) => c.isPrimaryKey).toList();
    b.writeln();
    if (t.comment.isNotEmpty) b.writeln('/** ${_lineComment(t.comment).replaceAll('*/', '* /')} */');
    b.writeln('@Entity');
    b.writeln('@Table(name = "${_javaStr(t.name)}")');
    b.writeln('public class ${cls[t.id]} {');
    for (final c in t.columns) {
      b.writeln();
      if (c.comment.isNotEmpty) b.writeln('    /** ${_lineComment(c.comment).replaceAll('*/', '* /')} */');
      if (c.isPrimaryKey) {
        b.writeln('    @Id');
        if (c.autoIncrement && pk.length == 1) b.writeln('    @GeneratedValue(strategy = GenerationType.IDENTITY)');
      }
      final args = [
        'name = "${_javaStr(c.name)}"',
        if (!_nullable(c)) 'nullable = false',
        if (c.unique && !c.isPrimaryKey) 'unique = true',
        if (c.type == DataType.varchar) 'length = ${c.length ?? 255}',
        if (c.type == DataType.decimal) 'precision = ${c.length ?? 10}, scale = ${c.scale ?? 2}',
        if (c.type == DataType.text) 'columnDefinition = "TEXT"',
        if (c.type == DataType.json) 'columnDefinition = "JSON"',
      ];
      b.writeln('    @Column(${args.join(', ')})');
      b.writeln('    private ${_javaType(c, boxed: false)} ${f[c.id]};');
    }
    for (final c in t.columns) {
      final type = _javaType(c, boxed: false);
      final name = f[c.id]!;
      final cap = name[0].toUpperCase() + name.substring(1);
      b.writeln();
      b.writeln('    public $type ${type == 'boolean' ? 'is' : 'get'}$cap() { return $name; }');
      b.writeln('    public void set$cap($type $name) { this.$name = $name; }');
    }
    b.writeln('}');
  }
  if (tables.isEmpty) b.writeln('// ยังไม่มีตารางที่มีคอลัมน์');
  return b.toString();
}

const _javaReserved = {
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const', 'continue',
  'default', 'do', 'double', 'else', 'enum', 'extends', 'final', 'finally', 'float', 'for', 'goto', 'if',
  'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'package', 'private',
  'protected', 'public', 'return', 'short', 'static', 'strictfp', 'super', 'switch', 'synchronized', 'this',
  'throw', 'throws', 'transient', 'try', 'void', 'volatile', 'while',
};

// ---------- C# (EF Core) ----------

String _csType(ColumnModel c) {
  final nullable = _nullable(c);
  final base = switch (c.type) {
    DataType.integer => 'int',
    DataType.smallint => 'short',
    DataType.bigint => 'long',
    DataType.varchar || DataType.text => 'string',
    DataType.uuid => 'Guid',
    DataType.decimal => 'decimal',
    DataType.float => 'double',
    DataType.boolean => 'bool',
    DataType.date || DataType.datetime || DataType.timestamp => 'DateTime',
    DataType.blob => 'byte[]',
    DataType.json => 'string',
  };
  return nullable ? '$base?' : base;
}

String _csStr(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

String _csharp(Project p) {
  final cls = _classNames(p);
  final b = StringBuffer()
    ..writeln(_header(p, '//'))
    ..writeln('using System;')
    ..writeln('using System.ComponentModel.DataAnnotations;')
    ..writeln('using System.ComponentModel.DataAnnotations.Schema;');
  final tables = [for (final t in p.tables) if (t.columns.isNotEmpty) t];
  for (final t in tables) {
    final f = {for (final e in _fieldNames(t).entries) e.key: _pascal(t.columns.firstWhere((c) => c.id == e.key).name, fallback: 'Field')};
    // ชื่อซ้ำหลังแปลงเป็น PascalCase
    final used = <String>{cls[t.id]!};
    for (final k in f.keys.toList()) {
      var n = f[k]!;
      for (var i = 2; !used.add(n); i++) {
        n = '${f[k]}$i';
      }
      f[k] = n;
    }
    final pk = t.columns.where((c) => c.isPrimaryKey).toList();
    b.writeln();
    if (t.comment.isNotEmpty) b.writeln('/// <summary>${_xml(_lineComment(t.comment))}</summary>');
    b.writeln('[Table("${_csStr(t.name)}")]');
    b.writeln('public class ${cls[t.id]}');
    b.writeln('{');
    for (var i = 0; i < t.columns.length; i++) {
      final c = t.columns[i];
      if (i > 0) b.writeln();
      if (c.comment.isNotEmpty) b.writeln('    /// <summary>${_xml(_lineComment(c.comment))}</summary>');
      if (c.isPrimaryKey) {
        b.writeln('    [Key]');
        if (pk.length > 1) b.writeln('    [Column(Order = ${pk.indexOf(c)})]');
        if (pk.length == 1) {
          b.writeln('    [DatabaseGenerated(DatabaseGeneratedOption.${c.autoIncrement ? 'Identity' : 'None'})]');
        }
      }
      if (c.type == DataType.varchar) b.writeln('    [MaxLength(${c.length ?? 255})]');
      if (c.type == DataType.decimal) b.writeln('    [Column(TypeName = "decimal(${c.length ?? 10},${c.scale ?? 2})")]');
      if (f[c.id] != c.name && !(c.isPrimaryKey && pk.length > 1)) b.writeln('    [Column("${_csStr(c.name)}")]');
      final required = !_nullable(c) && c.type == DataType.varchar;
      if (required) b.writeln('    [Required]');
      b.writeln('    public ${_csType(c)} ${f[c.id]} { get; set; }');
    }
    b.writeln('}');
  }
  if (tables.isEmpty) b.writeln('// ยังไม่มีตารางที่มีคอลัมน์');
  return b.toString();
}

String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
