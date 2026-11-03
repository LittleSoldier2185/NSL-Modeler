import '../ddl/ddl_generator.dart';
import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/index_model.dart';
import '../models/project.dart';
import '../models/table_model.dart';
import 'schema_diff.dart';

/// สร้างสคริปต์ migration (ALTER TABLE ฯลฯ) ที่เปลี่ยนฐานข้อมูลจากโครงสร้าง [old] ไปเป็น [neu]
/// ตาม dialect ของ [neu] — บรรทัดที่ขึ้นต้น `-- ⚠` คือจุดที่ข้อมูลอาจหายหรือต้องทำเอง
String generateMigration(Project old, Project neu, {SchemaDiff? diff}) =>
    _Migration(old, neu, diff ?? diffProjects(old, neu)).build();

class _Migration {
  _Migration(this.old, this.neu, this.diff)
      : d = neu.dialect,
        gen = DdlGenerator.forDialect(neu.dialect) {
    oldNames = gen.constraintNames(old);
    newNames = gen.constraintNames(neu);
  }

  final Project old;
  final Project neu;
  final SchemaDiff diff;
  final Dialect d;
  final DdlGenerator gen;
  late final Map<String, String> oldNames;
  late final Map<String, String> newNames;

  final blocks = <String>[];

  String q(String s) => gen.quote(s);
  String lit(String s) => gen.stringLiteral(s);
  String nlit(String s) => "N'${s.replaceAll("'", "''")}'";
  bool get sqlite => d == Dialect.sqlite;

  void section(String title, List<String> stmts) {
    if (stmts.isEmpty) return;
    blocks.add('-- $title\n${stmts.join('\n')}');
  }

  String build() {
    final lines = diff.summary(old, neu);
    if (diff.isEmpty) {
      return '-- ${DdlGenerator.flat(neu.name)} (${d.label}): ไม่มีความแตกต่างของโครงสร้าง — ไม่ต้อง migrate\n';
    }

    // ตารางที่ SQLite ต้องสร้างใหม่ (ALTER ทำไม่ได้)
    final rebuild = sqlite ? _rebuildSet() : <String>{};

    final header = StringBuffer('-- Migration → ${DdlGenerator.flat(neu.name)} (${d.label})\n'
        '-- ${lines.length} การเปลี่ยนแปลง');
    final risky = lines.where((l) => l.destructive).length;
    if (risky > 0) {
      header.write('\n-- ⚠ $risky รายการอาจทำให้ข้อมูลหาย — สำรองฐานข้อมูลก่อนรัน');
    }
    blocks.add(header.toString());

    _dropForeignKeys();
    _dropIndexes(rebuild);
    _dropUniques(rebuild);
    _dropTables();
    _renameTables();
    _createTables();
    _alterTables(rebuild);
    _createIndexes(rebuild);
    _addForeignKeys();
    _comments();

    final body = blocks.join('\n\n');
    if (sqlite && rebuild.isNotEmpty) {
      // ปิด FK ระหว่างสร้างตารางใหม่ (PRAGMA ใช้ไม่ได้ในทรานแซกชัน จึงอยู่นอก BEGIN)
      return 'PRAGMA foreign_keys = OFF;\nBEGIN TRANSACTION;\n\n$body\n\nCOMMIT;\nPRAGMA foreign_key_check;\nPRAGMA foreign_keys = ON;\n';
    }
    return '$body\n';
  }

  // ---------- 1. ลบ FK ----------

  void _dropForeignKeys() {
    if (sqlite) return; // SQLite: ตารางลูกถูกสร้างใหม่ให้เอง
    final dropped = diff.droppedTables.map((t) => t.id).toSet();
    final out = <String>[];
    for (final r in diff.droppedRelations) {
      if (dropped.contains(r.fromTableId)) continue; // ตารางลูกถูกลบทั้งตาราง
      final child = old.tableById(r.fromTableId);
      if (child == null) continue;
      final name = oldNames[r.id]!;
      out.add(d == Dialect.mysql
          ? 'ALTER TABLE ${q(child.name)} DROP FOREIGN KEY ${q(name)};'
          : 'ALTER TABLE ${q(child.name)} DROP CONSTRAINT ${q(name)};');
    }
    section('ลบความสัมพันธ์ FK ที่เลิกใช้/เปลี่ยน', out);
  }

  // ---------- 2. ลบ INDEX ----------

  void _dropIndexes(Set<String> rebuild) {
    final out = <String>[];
    for (final td in diff.modified) {
      if (rebuild.contains(td.neu.id)) continue;
      for (final i in td.droppedIndexes) {
        out.add(d == Dialect.mysql || d == Dialect.mssql
            ? 'DROP INDEX ${q(i.name)} ON ${q(td.old.name)};'
            : 'DROP INDEX ${q(i.name)};');
      }
    }
    section('ลบ INDEX ที่เลิกใช้/เปลี่ยน', out);
  }

  // ---------- 3. เอา UNIQUE ออก ----------

  void _dropUniques(Set<String> rebuild) {
    final out = <String>[];
    for (final td in diff.modified) {
      if (rebuild.contains(td.neu.id)) continue;
      for (final c in td.changedColumns) {
        if (!c.uniqueChanged || c.neu.unique) continue;
        final t = q(td.old.name);
        switch (d) {
          case Dialect.mysql:
            out.add('ALTER TABLE $t DROP INDEX ${q(c.old.name)};'); // ชื่อ index = ชื่อคอลัมน์
          case Dialect.postgres:
            out.add('ALTER TABLE $t DROP CONSTRAINT ${q('${td.old.name}_${c.old.name}_key')};');
          case Dialect.mssql:
            out.add('-- ⚠ ต้องลบ UNIQUE ของ ${td.old.name}.${c.old.name} เอง: SQL Server ตั้งชื่อ constraint อัตโนมัติ '
                '(ดูชื่อด้วย sp_helpconstraint แล้ว ALTER TABLE ... DROP CONSTRAINT)');
          case Dialect.sqlite:
            break;
        }
      }
    }
    section('เอา UNIQUE ออก', out);
  }

  // ---------- 4. ลบตาราง ----------

  void _dropTables() {
    section('ลบตาราง', [
      for (final t in diff.droppedTables) '-- ⚠ ลบตาราง ${DdlGenerator.flat(t.name)} พร้อมข้อมูลทั้งหมด\nDROP TABLE ${q(t.name)};',
    ]);
  }

  // ---------- 5. เปลี่ยนชื่อตาราง ----------

  void _renameTables() {
    final out = <String>[];
    for (final td in diff.modified.where((x) => x.renamed)) {
      final a = td.old.name, b = td.neu.name;
      out.add(switch (d) {
        Dialect.mysql => 'RENAME TABLE ${q(a)} TO ${q(b)};',
        Dialect.mssql => 'EXEC sp_rename ${nlit(a)}, ${nlit(b)};',
        _ => 'ALTER TABLE ${q(a)} RENAME TO ${q(b)};',
      });
    }
    section('เปลี่ยนชื่อตาราง', out);
  }

  // ---------- 6. สร้างตารางใหม่ ----------

  void _createTables() {
    section('สร้างตารางใหม่', [for (final t in diff.addedTables) gen.createTable(neu, t, newNames)]);
  }

  // ---------- 7. แก้ตารางเดิม ----------

  void _alterTables(Set<String> rebuild) {
    for (final td in diff.modified) {
      final n = td.neu;
      final out = <String>[];
      if (rebuild.contains(n.id)) {
        out.addAll(_rebuildTable(td));
      } else {
        out.addAll(_alterOne(td));
      }
      section('แก้ตาราง ${DdlGenerator.flat(n.name)}', out);
    }
    // SQLite: ตารางที่ต้องสร้างใหม่เพราะ FK เปลี่ยนอย่างเดียว (ไม่มีการแก้คอลัมน์)
    final inModified = diff.modified.map((x) => x.neu.id).toSet();
    for (final id in rebuild.where((id) => !inModified.contains(id))) {
      final t = neu.tableById(id);
      if (t != null) {
        section('แก้ตาราง ${DdlGenerator.flat(t.name)}', _rebuildTable(null, plain: t));
      }
    }
  }

  List<String> _alterOne(TableDiff td) {
    final n = td.neu;
    final t = q(n.name);
    final out = <String>[];
    final pk = n.columns.where((c) => c.isPrimaryKey).toList();

    // PK เดิมต้องออกก่อน (ลบคอลัมน์ที่เป็น PK / เปลี่ยน PK)
    final oldPk = td.old.columns.where((c) => c.isPrimaryKey).toList();
    if (td.pkChanged && oldPk.isNotEmpty) {
      out.add(switch (d) {
        Dialect.mysql => 'ALTER TABLE $t DROP PRIMARY KEY;',
        Dialect.postgres => 'ALTER TABLE $t DROP CONSTRAINT ${q('${td.old.name}_pkey')};',
        _ => 'ALTER TABLE $t DROP CONSTRAINT ${q('PK_${td.old.name}')};',
      });
    }

    for (final c in td.droppedColumns) {
      out.add('-- ⚠ ลบคอลัมน์ ${DdlGenerator.flat(n.name)}.${DdlGenerator.flat(c.name)} พร้อมข้อมูล\n'
          'ALTER TABLE $t DROP COLUMN ${q(c.name)};');
    }

    for (final c in td.changedColumns.where((c) => c.renamed)) {
      out.add(d == Dialect.mssql
          ? 'EXEC sp_rename ${nlit('${n.name}.${c.old.name}')}, ${nlit(c.neu.name)}, N\'COLUMN\';'
          : 'ALTER TABLE $t RENAME COLUMN ${q(c.old.name)} TO ${q(c.neu.name)};');
    }

    for (final c in td.addedColumns) {
      if ((c.notNull || c.isPrimaryKey) &&
          !c.autoIncrement &&
          (c.defaultValue ?? '').trim().isEmpty) {
        out.add('-- ⚠ ${DdlGenerator.flat(c.name)} เป็น NOT NULL ไม่มี DEFAULT: ถ้าตารางมีข้อมูลอยู่จะ error (ตั้ง DEFAULT หรือเติมค่าก่อน)');
      }
      final def = gen.columnDef(n, c, pk);
      out.add(d == Dialect.mssql ? 'ALTER TABLE $t ADD $def;' : 'ALTER TABLE $t ADD COLUMN $def;');
    }

    for (final c in td.changedColumns.where((c) => c.definitionChanged)) {
      out.addAll(_modifyColumn(n, c, pk));
    }

    for (final c in td.changedColumns.where((c) => c.uniqueChanged && c.neu.unique)) {
      final col = q(c.neu.name);
      out.add(switch (d) {
        Dialect.mysql => 'ALTER TABLE $t ADD CONSTRAINT ${q(c.neu.name)} UNIQUE ($col);',
        Dialect.postgres => 'ALTER TABLE $t ADD CONSTRAINT ${q('${n.name}_${c.neu.name}_key')} UNIQUE ($col);',
        _ => 'ALTER TABLE $t ADD CONSTRAINT ${q('UQ_${n.name}_${c.neu.name}')} UNIQUE ($col);',
      });
    }

    if (td.pkChanged && pk.isNotEmpty) {
      final cols = pk.map((c) => q(c.name)).join(', ');
      out.add(switch (d) {
        Dialect.mssql => 'ALTER TABLE $t ADD CONSTRAINT ${q('PK_${n.name}')} PRIMARY KEY ($cols);',
        _ => 'ALTER TABLE $t ADD PRIMARY KEY ($cols);',
      });
    }
    return out;
  }

  List<String> _modifyColumn(TableModel n, ColumnChange ch, List<ColumnModel> pk) {
    final t = q(n.name);
    final c = ch.neu;
    final col = q(c.name);
    final out = <String>[];

    switch (d) {
      case Dialect.mysql:
        // MODIFY ต้องบอกนิยามเต็ม; UNIQUE จัดการแยกต่างหาก
        final copy = c.copy()..unique = false;
        if (ch.typeChanged) out.add('-- ⚠ เปลี่ยนชนิด $t.$col: ข้อมูลเดิมอาจถูกตัด/แปลงไม่ได้');
        out.add('ALTER TABLE $t MODIFY COLUMN ${gen.columnDef(n, copy, pk)};');
      case Dialect.postgres:
        final noAi = c.copy()..autoIncrement = false;
        if (ch.typeChanged) {
          final type = gen.columnType(noAi);
          out.add('-- ⚠ เปลี่ยนชนิด $t.$col: ข้อมูลเดิมอาจแปลงไม่ได้ (ใช้ USING แปลงให้)');
          out.add('ALTER TABLE $t ALTER COLUMN $col TYPE $type USING $col::$type;');
        }
        if (ch.nullChanged) {
          out.add('ALTER TABLE $t ALTER COLUMN $col ${c.notNull || c.isPrimaryKey ? 'SET' : 'DROP'} NOT NULL;');
        }
        if (ch.defaultChanged) {
          final v = (c.defaultValue ?? '').trim();
          out.add(v.isEmpty
              ? 'ALTER TABLE $t ALTER COLUMN $col DROP DEFAULT;'
              : 'ALTER TABLE $t ALTER COLUMN $col SET DEFAULT ${gen.formatDefault(v, c)};');
        }
        if (ch.autoIncrementChanged) {
          out.add('-- ⚠ ${c.autoIncrement ? 'เปิด' : 'ปิด'} AUTO INCREMENT ของ $t.$col ต้องจัดการ SEQUENCE เอง '
              '(เช่น ALTER COLUMN ... ADD GENERATED BY DEFAULT AS IDENTITY)');
        }
        if (ch.commentChanged) {
          out.add('COMMENT ON COLUMN $t.$col IS ${c.comment.isEmpty ? 'NULL' : lit(c.comment)};');
        }
      case Dialect.mssql:
        if (ch.typeChanged || ch.nullChanged) {
          if (ch.typeChanged) out.add('-- ⚠ เปลี่ยนชนิด $t.$col: ข้อมูลเดิมอาจแปลงไม่ได้');
          out.add('ALTER TABLE $t ALTER COLUMN $col ${gen.columnType(c)} '
              '${c.notNull || c.isPrimaryKey ? 'NOT NULL' : 'NULL'};');
        }
        if (ch.defaultChanged) {
          out.add('-- ⚠ เปลี่ยนค่าเริ่มต้นของ $t.$col เป็น ${(c.defaultValue ?? '').trim().isEmpty ? '(ไม่มี)' : c.defaultValue} '
              'ต้องทำเอง: DEFAULT constraint ของ SQL Server มีชื่ออัตโนมัติ (ลบของเดิมแล้ว ADD CONSTRAINT ... DEFAULT ... FOR $col)');
        }
        if (ch.autoIncrementChanged) {
          out.add('-- ⚠ SQL Server เปลี่ยน IDENTITY ของ $t.$col ตรง ๆ ไม่ได้ ต้องสร้างคอลัมน์/ตารางใหม่');
        }
        if (ch.commentChanged) out.addAll(_mssqlColumnComment(n.name, c.name, ch.old.comment, c.comment));
      case Dialect.sqlite:
        break; // ไปทางสร้างตารางใหม่
    }
    return out;
  }

  // ---------- SQLite: สร้างตารางใหม่แทน ALTER ----------

  /// ตาราง (id ใหม่) ที่ SQLite ต้องสร้างใหม่เพราะ ALTER ทำไม่ได้
  Set<String> _rebuildSet() {
    final s = <String>{};
    for (final td in diff.modified) {
      var need = td.pkChanged || td.droppedColumns.isNotEmpty;
      for (final c in td.changedColumns) {
        if (c.typeChanged || c.nullChanged || c.defaultChanged || c.autoIncrementChanged || c.uniqueChanged) {
          need = true;
        }
      }
      for (final c in td.addedColumns) {
        // ADD COLUMN ของ SQLite เติม PRIMARY KEY/UNIQUE ไม่ได้ และ NOT NULL ต้องมี DEFAULT
        final noDefault = (c.defaultValue ?? '').trim().isEmpty;
        if (c.isPrimaryKey || c.unique || ((c.notNull) && noDefault)) need = true;
      }
      if (need) s.add(td.neu.id);
    }
    // FK เพิ่ม/ลบ -> ตารางลูกต้องสร้างใหม่ (ตารางลูกที่ถูกลบ/เพิ่มทั้งตารางไม่ต้อง)
    final added = diff.addedTables.map((t) => t.id).toSet();
    for (final r in diff.addedRelations) {
      if (!added.contains(r.fromTableId)) s.add(r.fromTableId);
    }
    final dropped = diff.droppedTables.map((t) => t.id).toSet();
    for (final r in diff.droppedRelations) {
      if (dropped.contains(r.fromTableId)) continue;
      final nid = diff.tableMap[r.fromTableId];
      if (nid != null) s.add(nid);
    }
    return s;
  }

  List<String> _rebuildTable(TableDiff? td, {TableModel? plain}) {
    final n = td?.neu ?? plain!;
    final tmp = '${n.name}__new';
    final out = <String>[
      '-- SQLite แก้โครงสร้างตารางตรง ๆ ไม่ได้: สร้างตารางใหม่ → คัดลอกข้อมูล → แทนที่ของเดิม',
    ];
    final copy = TableModel(
      id: n.id,
      name: tmp,
      comment: n.comment,
      x: n.x,
      y: n.y,
      width: n.width,
      columns: n.columns,
      indexes: const [],
    );
    out.add(gen.createTable(neu, copy, newNames));

    // คอลัมน์ที่จับคู่กับของเดิมได้ -> คัดลอก; คอลัมน์ใหม่ใช้ DEFAULT
    final pairs = <(String neuName, String oldName)>[];
    if (td != null) {
      // ใช้การจับคู่ของ diff โดยตรง (id หรือชื่อ) เพื่อให้ตรงกับที่สรุปให้ผู้ใช้เห็น
      final oldOf = {for (final e in td.matched.entries) e.value: e.key};
      for (final c in n.columns) {
        final o = oldOf[c];
        if (o != null) pairs.add((c.name, o.name));
      }
      for (final c in td.addedColumns) {
        if ((c.notNull || c.isPrimaryKey) && !c.autoIncrement && (c.defaultValue ?? '').trim().isEmpty) {
          out.add('-- ⚠ คอลัมน์ใหม่ ${DdlGenerator.flat(c.name)} เป็น NOT NULL ไม่มี DEFAULT: ถ้าตารางมีข้อมูลอยู่ INSERT ด้านล่างจะ error');
        }
      }
      for (final c in td.changedColumns.where((c) => c.typeChanged)) {
        out.add('-- ⚠ ชนิดของ ${DdlGenerator.flat(c.neu.name)} เปลี่ยน — SQLite จะเก็บค่าเดิมตามที่เป็น');
      }
    } else {
      for (final c in n.columns) {
        pairs.add((c.name, c.name));
      }
    }
    final oldName = td?.neu.name ?? n.name; // เปลี่ยนชื่อตารางไปแล้วในขั้นก่อนหน้า
    if (pairs.isNotEmpty) {
      out.add('INSERT INTO ${q(tmp)} (${pairs.map((p) => q(p.$1)).join(', ')})\n'
          '  SELECT ${pairs.map((p) => q(p.$2)).join(', ')} FROM ${q(oldName)};');
    }
    out.add('DROP TABLE ${q(oldName)};');
    out.add('ALTER TABLE ${q(tmp)} RENAME TO ${q(n.name)};');
    return out;
  }

  // ---------- 8. สร้าง INDEX ----------

  void _createIndexes(Set<String> rebuild) {
    final out = <String>[];
    void add(TableModel t, IndexModel i) => out.add(gen.createIndexStatement(t, i));
    for (final t in diff.addedTables) {
      for (final i in t.indexes) {
        add(t, i);
      }
    }
    for (final td in diff.modified) {
      if (rebuild.contains(td.neu.id)) {
        for (final i in td.neu.indexes) {
          add(td.neu, i); // ตารางใหม่ไม่มี index ติดมา
        }
      } else {
        for (final i in td.addedIndexes) {
          add(td.neu, i);
        }
      }
    }
    // ตารางที่สร้างใหม่เพราะ FK เปลี่ยนอย่างเดียว (ไม่อยู่ใน modified)
    final inModified = diff.modified.map((x) => x.neu.id).toSet();
    for (final id in rebuild) {
      if (inModified.contains(id)) continue;
      final t = neu.tableById(id);
      if (t == null) continue;
      for (final i in t.indexes) {
        add(t, i);
      }
    }
    section('สร้าง INDEX', out);
  }

  // ---------- 9. เพิ่ม FK ----------

  void _addForeignKeys() {
    if (sqlite) return; // อยู่ใน CREATE TABLE แล้ว
    final out = <String>[];
    for (final r in diff.addedRelations) {
      final s = gen.addForeignKeyStatement(neu, r, newNames);
      if (s != null) out.add(s);
    }
    section('เพิ่มความสัมพันธ์ FK', out);
  }

  // ---------- 10. หมายเหตุ ----------

  void _comments() {
    final out = <String>[];
    // ตารางใหม่ (MySQL ใส่ใน CREATE TABLE แล้ว; SQLite ไม่มีหมายเหตุ)
    out.addAll(gen.commentStatements(Project(dialect: d, tables: diff.addedTables)));
    for (final td in diff.modified.where((x) => x.commentChanged)) {
      final n = td.neu;
      final t = q(n.name);
      switch (d) {
        case Dialect.mysql:
          out.add('ALTER TABLE $t COMMENT = ${lit(n.comment)};');
        case Dialect.postgres:
          out.add('COMMENT ON TABLE $t IS ${n.comment.isEmpty ? 'NULL' : lit(n.comment)};');
        case Dialect.mssql:
          out.addAll(_mssqlTableComment(n.name, td.old.comment, n.comment));
        case Dialect.sqlite:
          break;
      }
    }
    section('หมายเหตุ (COMMENT)', out);
  }

  List<String> _mssqlTableComment(String table, String from, String to) {
    final where = "N'SCHEMA', N'dbo', N'TABLE', ${nlit(table)}";
    if (to.isEmpty) return ["EXEC sp_dropextendedproperty N'MS_Description', $where;"];
    return ["EXEC ${from.isEmpty ? 'sp_addextendedproperty' : 'sp_updateextendedproperty'} "
        "N'MS_Description', ${nlit(to)}, $where;"];
  }

  List<String> _mssqlColumnComment(String table, String col, String from, String to) {
    final where = "N'SCHEMA', N'dbo', N'TABLE', ${nlit(table)}, N'COLUMN', ${nlit(col)}";
    if (to.isEmpty) return ["EXEC sp_dropextendedproperty N'MS_Description', $where;"];
    return ["EXEC ${from.isEmpty ? 'sp_addextendedproperty' : 'sp_updateextendedproperty'} "
        "N'MS_Description', ${nlit(to)}, $where;"];
  }
}
