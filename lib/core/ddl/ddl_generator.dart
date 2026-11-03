import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/index_model.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';
import '../types/type_map.dart';
import 'mysql_generator.dart';
import 'postgres_generator.dart';
import 'sqlite_generator.dart';
import 'sqlserver_generator.dart';
import '../l10n/l10n.dart';

/// สร้างสคริปต์ SQL จากโปรเจกต์ — ผลลัพธ์คงที่ (ไม่มีเวลา/สุ่ม) เพื่อเทียบ diff ได้
///
/// ลำดับในไฟล์: CREATE TABLE ทั้งหมด -> INDEX -> FOREIGN KEY (ALTER TABLE) -> COMMENT
/// แยก FK ไปท้ายไฟล์เสมอ ตารางจึงอ้างอิงวนกลับกันได้
/// ยกเว้น SQLite ที่ ALTER ... ADD FOREIGN KEY ไม่ได้ จึงใส่ FK ใน CREATE TABLE
abstract class DdlGenerator {
  const DdlGenerator();

  factory DdlGenerator.forDialect(Dialect d) => switch (d) {
        Dialect.mysql => const MySqlGenerator(),
        Dialect.postgres => const PostgresGenerator(),
        Dialect.sqlite => const SqliteGenerator(),
        Dialect.mssql => const SqlServerGenerator(),
      };

  Dialect get dialect;

  /// ใส่เครื่องหมายคำพูดรอบชื่อ (escape ตัวปิดที่อยู่ในชื่อด้วย)
  String quote(String id);

  /// FK อยู่ใน CREATE TABLE (SQLite) แทน ALTER TABLE
  bool get fksInline => false;

  // ---------- จุดที่แต่ละ dialect ปรับ ----------

  String columnType(ColumnModel c) => sqlType(c, dialect);

  /// คำสั่งหลังชนิดข้อมูล ก่อน NOT NULL (เช่น IDENTITY(1,1) ของ SQL Server)
  String? identityClause(ColumnModel c) => null;

  /// คำสั่งหลัง NOT NULL (เช่น AUTO_INCREMENT ของ MySQL)
  String? autoIncrementClause(ColumnModel c) => null;

  /// ส่วนต่อท้ายของคอลัมน์ เช่น COMMENT '...' (MySQL)
  String? columnTrailer(ColumnModel c) => null;

  String primaryKeyLine(TableModel t, List<ColumnModel> pk) =>
      'PRIMARY KEY (${pk.map((c) => quote(c.name)).join(', ')})';

  /// ข้อความก่อน CREATE TABLE (เช่น ความเห็นของตารางใน SQLite)
  String tablePrefix(TableModel t) => '';

  /// ข้อความต่อท้าย ")" ก่อน ";"
  String tableSuffix(TableModel t) => '';

  /// ข้อความที่คั่นระหว่างส่วน CREATE TABLE กับส่วนที่เหลือ (GO ของ SQL Server)
  String? get batchSeparator => null;

  /// ส่วนที่ขึ้นต้นสคริปต์ต่อจาก header (เช่น PRAGMA ของ SQLite)
  String? get preamble => null;

  /// คำสั่งใส่ความเห็นหลังสร้างตาราง (PostgreSQL, SQL Server)
  List<String> commentStatements(Project p) => const [];

  String stringLiteral(String s) => "'${s.replaceAll("'", "''")}'";

  String booleanLiteral(bool v) => v ? 'TRUE' : 'FALSE';

  // ---------- ตัวสร้างหลัก ----------

  String generate(Project p) {
    final names = constraintNames(p);
    final blocks = <String>[
      tr('-- {0} ({1}) — สร้างโดย NSL Modeler', [flat(p.name), dialect.label]),
    ];
    if (preamble != null) blocks.add(preamble!);

    for (final t in p.tables) {
      blocks.add(createTable(p, t, names));
    }
    if (batchSeparator != null && p.tables.isNotEmpty) blocks.add(batchSeparator!);

    final idx = <String>[
      for (final t in p.tables)
        for (final i in t.indexes) createIndexStatement(t, i),
    ];
    if (idx.isNotEmpty) blocks.add(idx.join('\n'));

    if (!fksInline) {
      final fks = <String>[];
      for (final r in p.relations) {
        final fk = _resolve(p, r);
        if (fk == null) {
          fks.add(tr('-- ข้าม FK: ไม่พบตารางหรือคอลัมน์ที่อ้างถึง'));
          continue;
        }
        fks.add('ALTER TABLE ${quote(fk.child.name)} ADD ${_foreignKeyClause(fk, names[r.id]!)};');
      }
      if (fks.isNotEmpty) blocks.add(fks.join('\n'));
    }

    final comments = commentStatements(p);
    if (comments.isNotEmpty) blocks.add(comments.join('\n'));

    return '${blocks.join('\n\n')}\n';
  }

  /// CREATE INDEX หนึ่งคำสั่ง (หรือคอมเมนต์ข้ามถ้าคอลัมน์หาย)
  String createIndexStatement(TableModel t, IndexModel i) {
    final cols = [for (final id in i.columnIds) t.columnById(id)];
    if (cols.isEmpty || cols.contains(null)) {
      return tr('-- ข้าม INDEX {0}: ไม่พบคอลัมน์', [flat(i.name)]);
    }
    return 'CREATE ${i.unique ? 'UNIQUE ' : ''}INDEX ${quote(i.name)} '
        'ON ${quote(t.name)} (${cols.map((c) => quote(c!.name)).join(', ')});';
  }

  /// ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY หนึ่งคำสั่ง — null ถ้าไม่พบตาราง/คอลัมน์
  /// [names] มาจาก [constraintNames]
  String? addForeignKeyStatement(Project p, RelationModel r, Map<String, String> names) {
    final fk = _resolve(p, r);
    if (fk == null) return null;
    return 'ALTER TABLE ${quote(fk.child.name)} ADD ${_foreignKeyClause(fk, names[r.id]!)};';
  }

  String createTable(Project p, TableModel t, Map<String, String> names) {
    if (t.columns.isEmpty) return tr('-- ข้ามตาราง {0}: ไม่มีคอลัมน์', [flat(t.name)]);

    final pk = t.columns.where((c) => c.isPrimaryKey).toList();
    final items = <String>[
      for (final c in t.columns) columnDef(t, c, pk),
      if (pk.isNotEmpty) primaryKeyLine(t, pk),
    ];
    if (fksInline) {
      for (final r in p.relations.where((r) => r.fromTableId == t.id)) {
        final fk = _resolve(p, r);
        if (fk != null) items.add(_foreignKeyClause(fk, names[r.id]!));
      }
    }
    return '${tablePrefix(t)}CREATE TABLE ${quote(t.name)} (\n'
        '  ${items.join(',\n  ')}\n'
        ')${tableSuffix(t)};';
  }

  String columnDef(TableModel t, ColumnModel c, List<ColumnModel> pk) {
    final ai = c.autoIncrement && isIntegerType(c.type);
    final soleKey = pk.length == 1 && pk.first.id == c.id;
    final parts = <String?>[
      quote(c.name),
      columnType(c),
      if (ai) identityClause(c),
      if (c.notNull || c.isPrimaryKey) 'NOT NULL',
      if (ai) autoIncrementClause(c),
      if (!ai && c.defaultValue != null && c.defaultValue!.trim().isNotEmpty)
        'DEFAULT ${formatDefault(c.defaultValue!, c)}',
      if (c.unique && !soleKey) 'UNIQUE',
      columnTrailer(c),
    ];
    return parts.whereType<String>().join(' ');
  }

  String _foreignKeyClause(_Fk fk, String name) {
    final b = StringBuffer('CONSTRAINT ${quote(name)} FOREIGN KEY (${quote(fk.childCol.name)}) '
        'REFERENCES ${quote(fk.parent.name)} (${quote(fk.parentCol.name)})');
    if (fk.rel.onDelete != RefAction.noAction) b.write(' ON DELETE ${fk.rel.onDelete.sql}');
    if (fk.rel.onUpdate != RefAction.noAction) b.write(' ON UPDATE ${fk.rel.onUpdate.sql}');
    return b.toString();
  }

  /// แปลงค่าที่ผู้ใช้พิมพ์ในช่อง "ค่าเริ่มต้น" เป็น literal ของ SQL
  ///
  /// - ตัวเลข / NULL / TRUE / FALSE / CURRENT_* -> ใช้ตามนั้น (NOW() -> CURRENT_TIMESTAMP)
  /// - เรียกฟังก์ชัน เช่น uuid() -> ครอบวงเล็บ `(uuid())` ตามที่ MySQL 8 และ SQLite บังคับ
  /// - ข้อความที่ผู้ใช้ใส่ '...' มาแล้ว -> ใช้ตามนั้น
  /// - อย่างอื่น -> เป็นสตริง
  String formatDefault(String raw, ColumnModel c) {
    final s = raw.trim();
    final up = s.toUpperCase();
    const textual = {
      DataType.varchar,
      DataType.text,
      DataType.uuid,
      DataType.json,
      DataType.date,
      DataType.datetime,
      DataType.timestamp,
    };
    if (up == 'NULL') return 'NULL';
    // BOOLEAN ของ PostgreSQL ไม่รับ DEFAULT 1/0 (ต้องเป็น TRUE/FALSE)
    if (c.type == DataType.boolean && (s == '0' || s == '1')) return booleanLiteral(s == '1');
    if (up == 'TRUE' || up == 'FALSE') return booleanLiteral(up == 'TRUE');
    if (up == 'NOW()') return 'CURRENT_TIMESTAMP';
    if (const {'CURRENT_TIMESTAMP', 'CURRENT_DATE', 'CURRENT_TIME'}.contains(up)) return up;
    if (!textual.contains(c.type) && RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(s)) return s;
    if (s.length >= 2 && s.startsWith("'") && s.endsWith("'")) return s;
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\(.*\)$').hasMatch(s)) return '($s)';
    return stringLiteral(s);
  }

  // ---------- ตัวช่วย ----------

  /// ทำให้ข้อความอยู่บรรทัดเดียว (ใช้ในคอมเมนต์ `--`)
  static String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  _Fk? _resolve(Project p, RelationModel r) {
    final child = p.tableById(r.fromTableId);
    final parent = p.tableById(r.toTableId);
    final cc = child?.columnById(r.fromColumnId);
    final pc = parent?.columnById(r.toColumnId);
    if (child == null || parent == null || cc == null || pc == null) return null;
    return _Fk(r, child, cc, parent, pc);
  }

  /// ชื่อ FK ที่ไม่ซ้ำกันทั้งสคริปต์ (SQL Server บังคับไม่ซ้ำทั้ง schema)
  Map<String, String> constraintNames(Project p) {
    final used = <String>{};
    final out = <String, String>{};
    for (final r in p.relations) {
      final child = p.tableById(r.fromTableId);
      final col = child?.columnById(r.fromColumnId);
      var base = r.name?.trim().isNotEmpty == true
          ? r.name!.trim()
          : 'fk_${child?.name ?? 'x'}_${col?.name ?? 'x'}';
      var name = base;
      var i = 2;
      while (!used.add(name.toLowerCase())) {
        name = '${base}_${i++}';
      }
      out[r.id] = name;
    }
    return out;
  }
}

class _Fk {
  _Fk(this.rel, this.child, this.childCol, this.parent, this.parentCol);
  final RelationModel rel;
  final TableModel child;
  final ColumnModel childCol;
  final TableModel parent;
  final ColumnModel parentCol;
}
