import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/index_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/core/validate/issue.dart';
import 'package:nsl_modeler/core/validate/validator.dart';

ColumnModel col(String id, String name,
        {DataType type = DataType.integer,
        bool pk = false,
        bool nn = false,
        bool uq = false,
        bool ai = false,
        int? len,
        int? scale,
        String? def}) =>
    ColumnModel(
        id: id,
        name: name,
        type: type,
        isPrimaryKey: pk,
        notNull: nn,
        unique: uq,
        autoIncrement: ai,
        length: len,
        scale: scale,
        defaultValue: def);

TableModel tbl(String id, String name, List<ColumnModel> cols, {List<IndexModel>? idx}) =>
    TableModel(id: id, name: name, columns: cols, indexes: idx);

RelationModel rel(String id, String ft, String fc, String tt, String tc,
        {RefAction del = RefAction.noAction, RefAction upd = RefAction.noAction}) =>
    RelationModel(
        id: id,
        fromTableId: ft,
        fromColumnId: fc,
        toTableId: tt,
        toColumnId: tc,
        onDelete: del,
        onUpdate: upd);

List<String> codes(Project p, [Severity? s]) =>
    validateProject(p).where((i) => s == null || i.severity == s).map((i) => i.code).toList();

Project clean([Dialect d = Dialect.mysql]) => Project(dialect: d, tables: [
      tbl('u', 'users', [col('u1', 'id', pk: true, ai: true), col('u2', 'email', type: DataType.varchar, len: 255, uq: true)]),
      tbl('o', 'orders', [col('o1', 'id', pk: true, ai: true), col('o2', 'user_id')],
          idx: [IndexModel(id: 'i', name: 'idx_o_user', columnIds: ['o2'])]),
    ], relations: [
      rel('r', 'o', 'o2', 'u', 'u1'),
    ]);

void main() {
  test('schema ที่ถูกต้องไม่มี issue ในทุก dialect', () {
    for (final d in Dialect.values) {
      expect(validateProject(clean(d)), isEmpty, reason: d.label);
    }
  });

  test('เรียงผลลัพธ์ error -> warning -> info', () {
    final p = clean();
    p.tables[1].indexes.clear(); // info: fk_no_index
    p.tables.add(tbl('x', 'nopk', [col('x1', 'a')])); // warning: no_pk
    p.tables.add(tbl('e', 'empty', [])); // error: no_columns
    final sev = validateProject(p).map((i) => i.severity).toList();
    expect(sev, [...sev]..sort((a, b) => a.index.compareTo(b.index)));
    expect(sev.toSet(), {Severity.error, Severity.warning, Severity.info});
  });

  group('ชื่อ', () {
    test('ตารางชื่อซ้ำ (ไม่สนตัวพิมพ์)', () {
      final p = clean()..tables.add(tbl('d', 'USERS', [col('d1', 'id', pk: true)]));
      expect(codes(p, Severity.error), ['dup_table']);
    });
    test('คอลัมน์ชื่อซ้ำ', () {
      final p = Project(tables: [tbl('t', 't', [col('a', 'x', pk: true), col('b', 'X')])]);
      expect(codes(p, Severity.error), ['dup_column']);
    });
    test('ชื่อว่าง', () {
      final p = Project(tables: [tbl('t', ' ', [col('a', '', pk: true)])]);
      expect(codes(p, Severity.error), ['empty_name', 'empty_name']);
    });
    test('reserved word เป็น warning ตาม dialect', () {
      Project one(Dialect d, String n) => Project(dialect: d, tables: [tbl('t', n, [col('a', 'id', pk: true)])]);
      expect(codes(one(Dialect.mysql, 'order'), Severity.warning), ['reserved_word']);
      expect(codes(one(Dialect.mysql, 'user'), Severity.warning), isEmpty); // MySQL ไม่สงวน user
      expect(codes(one(Dialect.postgres, 'user'), Severity.warning), ['reserved_word']);
      expect(codes(one(Dialect.mssql, 'user'), Severity.warning), ['reserved_word']);
    });
    test('ชื่อยาวเกินตาม dialect', () {
      final name = 'a' * 65; // MySQL จำกัด 64, PostgreSQL 63
      Project one(Dialect d) => Project(dialect: d, tables: [tbl('t', name, [col('a', 'id', pk: true)])]);
      expect(codes(one(Dialect.mysql), Severity.error), ['name_too_long']);
      expect(codes(one(Dialect.postgres), Severity.error), ['name_too_long']); // 63
      expect(codes(one(Dialect.mssql), Severity.error), isEmpty);
      expect(codes(one(Dialect.sqlite), Severity.error), isEmpty);
    });
  });

  group('PK / ตาราง', () {
    test('ไม่มี PK = warning', () {
      final p = Project(tables: [tbl('t', 't', [col('a', 'x')])]);
      expect(codes(p), ['no_pk']);
    });
    test('ตารางไม่มีคอลัมน์ = error และไม่ซ้ำด้วย no_pk', () {
      final p = Project(tables: [tbl('t', 't', [])]);
      expect(codes(p), ['no_columns']);
    });
  });

  group('FK', () {
    test('ชนิดข้อมูลไม่ตรง = warning', () {
      final p = clean();
      p.tables[1].columns[1].type = DataType.bigint;
      expect(codes(p, Severity.warning), ['fk_type_mismatch']);
    });

    test('ชี้ไปคอลัมน์ที่ไม่ unique: error (PG) / warning (MySQL)', () {
      Project p(Dialect d) {
        final x = clean(d);
        x.relations.single.toColumnId = 'u2';
        x.tables[0].columns[1].unique = false;
        x.tables[1].columns[1]
          ..type = DataType.varchar // ให้ชนิดตรงกัน จะได้ทดสอบเฉพาะเรื่อง unique
          ..length = 255;
        return x;
      }

      expect(codes(p(Dialect.postgres), Severity.error), ['fk_target_not_unique']);
      expect(codes(p(Dialect.mysql), Severity.error), isEmpty);
      expect(codes(p(Dialect.mysql), Severity.warning), ['fk_target_not_unique']);
    });

    test('unique index คอลัมน์เดียวนับว่า unique', () {
      final x = clean(Dialect.postgres);
      x.relations.single.toColumnId = 'u2';
      x.tables[0].columns[1].unique = false;
      x.tables[0].indexes.add(IndexModel(id: 'ux', name: 'ux_email', columnIds: ['u2'], unique: true));
      expect(codes(x, Severity.error), isEmpty);
    });

    test('PK หลายคอลัมน์: คอลัมน์ใดคอลัมน์หนึ่งไม่ unique เดี่ยว ๆ', () {
      final x = Project(dialect: Dialect.postgres, tables: [
        tbl('a', 'a', [col('a1', 'k1', pk: true), col('a2', 'k2', pk: true)]),
        tbl('b', 'b', [col('b1', 'id', pk: true), col('b2', 'k1')]),
      ], relations: [
        rel('r', 'b', 'b2', 'a', 'a1'),
      ]);
      expect(codes(x, Severity.error), ['fk_target_not_unique']);
    });

    test('SET NULL กับคอลัมน์ NOT NULL = error', () {
      final x = clean();
      x.tables[1].columns[1].notNull = true;
      x.relations.single.onDelete = RefAction.setNull;
      expect(codes(x, Severity.error), ['fk_set_null_notnull']);
      x.tables[1].columns[1].notNull = false;
      expect(codes(x, Severity.error), isEmpty);
    });

    test('FK ชี้ตาราง/คอลัมน์ที่ไม่มี = error', () {
      final x = clean();
      x.tables.removeWhere((t) => t.id == 'u');
      expect(codes(x, Severity.error), ['fk_dangling']);
    });

    test('FK ไม่มี index = info ที่ชี้ column และ relation', () {
      final x = clean();
      x.tables[1].indexes.clear();
      final i = validateProject(x).single;
      expect(i.code, 'fk_no_index');
      expect(i.severity, Severity.info);
      expect(i.columnId, 'o2');
      expect(i.relationId, 'r');
    });

    test('FK เป็นคอลัมน์แรกของ PK ถือว่ามี index แล้ว', () {
      final x = clean();
      x.tables[1].indexes.clear();
      x.tables[1].columns[0].isPrimaryKey = false;
      x.tables[1].columns[1].isPrimaryKey = true;
      expect(codes(x, Severity.info), isEmpty);
    });
  });

  group('AUTO INCREMENT', () {
    test('ชนิดที่ไม่ใช่จำนวนเต็ม', () {
      final p = Project(tables: [tbl('t', 't', [col('a', 'id', type: DataType.varchar, pk: true, ai: true)])]);
      expect(codes(p, Severity.error), ['ai_type']);
    });

    test('MySQL: ต้องเป็น key', () {
      final p = Project(tables: [tbl('t', 't', [col('a', 'id', pk: true), col('b', 'n', ai: true)])]);
      expect(codes(p, Severity.error), ['ai_key']);
      p.tables.single.indexes.add(IndexModel(id: 'i', name: 'i1', columnIds: ['b']));
      expect(codes(p, Severity.error), isEmpty);
    });

    test('PostgreSQL ไม่บังคับ key', () {
      final p = Project(dialect: Dialect.postgres, tables: [tbl('t', 't', [col('a', 'id', pk: true), col('b', 'n', ai: true)])]);
      expect(codes(p, Severity.error), isEmpty);
    });

    test('หลายคอลัมน์ในตารางเดียว (MySQL/MSSQL)', () {
      List<ColumnModel> two() => [col('a', 'x', pk: true, ai: true), col('b', 'y', uq: true, ai: true)];
      expect(codes(Project(tables: [tbl('t', 't', two())]), Severity.error), contains('ai_multiple'));
      expect(codes(Project(dialect: Dialect.mssql, tables: [tbl('t', 't', two())]), Severity.error), contains('ai_multiple'));
      expect(codes(Project(dialect: Dialect.postgres, tables: [tbl('t', 't', two())]), Severity.error), isEmpty);
    });

    test('SQLite: PK หลายคอลัมน์ -> AUTOINCREMENT ถูกข้าม (warning)', () {
      final p = Project(dialect: Dialect.sqlite, tables: [tbl('t', 't', [col('a', 'x', pk: true, ai: true), col('b', 'y', pk: true)])]);
      expect(codes(p, Severity.warning), ['ai_ignored']);
    });

    test('มี DEFAULT ร่วมด้วย = warning', () {
      final p = Project(tables: [tbl('t', 't', [col('a', 'id', pk: true, ai: true, def: '5')])]);
      expect(codes(p, Severity.warning), ['ai_default']);
    });
  });

  group('ชนิดข้อมูลและค่าเริ่มต้น', () {
    Project one(Dialect d, ColumnModel c) => Project(dialect: d, tables: [tbl('t', 't', [col('k', 'id', pk: true), c])]);

    test('VARCHAR ยาวเกินตาม dialect', () {
      expect(codes(one(Dialect.mssql, col('a', 'v', type: DataType.varchar, len: 5000)), Severity.error), ['bad_length']);
      expect(codes(one(Dialect.mysql, col('a', 'v', type: DataType.varchar, len: 20000)), Severity.error), ['bad_length']);
      expect(codes(one(Dialect.postgres, col('a', 'v', type: DataType.varchar, len: 20000)), Severity.error), isEmpty);
      expect(codes(one(Dialect.mysql, col('a', 'v', type: DataType.varchar, len: 0)), Severity.error), ['bad_length']);
    });

    test('DECIMAL: scale > precision, precision เกิน', () {
      expect(codes(one(Dialect.mysql, col('a', 'v', type: DataType.decimal, len: 5, scale: 6)), Severity.error), ['bad_precision']);
      expect(codes(one(Dialect.mssql, col('a', 'v', type: DataType.decimal, len: 40, scale: 2)), Severity.error), ['bad_precision']);
      expect(codes(one(Dialect.mssql, col('a', 'v', type: DataType.decimal, len: 38, scale: 2)), Severity.error), isEmpty);
    });

    test('ค่าเริ่มต้นที่ไม่ใช่ตัวเลขกับคอลัมน์ตัวเลข', () {
      expect(codes(one(Dialect.mysql, col('a', 'n', def: 'abc')), Severity.error), ['bad_default']);
      expect(codes(one(Dialect.mysql, col('a', 'n', def: '12')), Severity.error), isEmpty);
      expect(codes(one(Dialect.mysql, col('a', 'n', def: 'NULL')), Severity.error), isEmpty);
    });

    test('BOOLEAN รับเฉพาะ true/false/0/1', () {
      expect(codes(one(Dialect.postgres, col('a', 'b', type: DataType.boolean, def: 'yes')), Severity.error), ['bad_default']);
      expect(codes(one(Dialect.postgres, col('a', 'b', type: DataType.boolean, def: 'TRUE')), Severity.error), isEmpty);
    });

    test('MySQL: TEXT ห้ามมี DEFAULT ค่าคงที่ (ฟังก์ชันได้)', () {
      expect(codes(one(Dialect.mysql, col('a', 't', type: DataType.text, def: 'x')), Severity.error), ['mysql_blob_default']);
      expect(codes(one(Dialect.mysql, col('a', 't', type: DataType.text, def: 'uuid()')), Severity.error), isEmpty);
      expect(codes(one(Dialect.postgres, col('a', 't', type: DataType.text, def: 'x')), Severity.error), isEmpty);
    });
  });

  group('INDEX', () {
    test('อ้างคอลัมน์ที่ไม่มี', () {
      final p = clean();
      p.tables[1].indexes.add(IndexModel(id: 'b', name: 'bad', columnIds: ['zzz']));
      expect(codes(p, Severity.error), ['index_missing_column']);
    });

    test('ชื่อซ้ำข้ามตาราง: error เฉพาะ PG/SQLite', () {
      Project p(Dialect d) {
        final x = clean(d);
        x.tables[0].indexes.add(IndexModel(id: 'i2', name: 'IDX_O_USER', columnIds: ['u2']));
        return x;
      }

      expect(codes(p(Dialect.postgres), Severity.error), ['dup_index']);
      expect(codes(p(Dialect.sqlite), Severity.error), ['dup_index']);
      expect(codes(p(Dialect.mysql), Severity.error), isEmpty);
      expect(codes(p(Dialect.mssql), Severity.error), isEmpty);
    });

    test('ชื่อซ้ำในตารางเดียวกัน error ทุก dialect', () {
      for (final d in Dialect.values) {
        final x = clean(d);
        x.tables[1].indexes.add(IndexModel(id: 'i2', name: 'idx_o_user', columnIds: ['o1']));
        expect(codes(x, Severity.error), ['dup_index'], reason: d.label);
      }
    });
  });

  group('SQL Server cascade paths', () {
    Project diamond(Dialect d, {RefAction last = RefAction.cascade}) {
      // a <- b, a <- c, b <- d, c <- d  (ลบ a ลามถึง d สองทาง)
      ColumnModel fk(String id) => col(id, 'fk', nn: false);
      return Project(dialect: d, tables: [
        tbl('a', 'a', [col('a1', 'id', pk: true)]),
        tbl('b', 'b', [col('b1', 'id', pk: true), fk('b2')]),
        tbl('c', 'c', [col('c1', 'id', pk: true), fk('c2')]),
        tbl('d', 'd', [col('d1', 'id', pk: true), fk('d2'), fk('d3')]),
      ], relations: [
        rel('r1', 'b', 'b2', 'a', 'a1', del: RefAction.cascade),
        rel('r2', 'c', 'c2', 'a', 'a1', del: RefAction.cascade),
        rel('r3', 'd', 'd2', 'b', 'b1', del: last),
        rel('r4', 'd', 'd3', 'c', 'c1', del: last),
      ]);
    }

    test('ทางลามซ้ำ (diamond) = error เฉพาะ SQL Server', () {
      final ms = validateProject(diamond(Dialect.mssql)).where((i) => i.code == 'mssql_cascade_paths');
      expect(ms, isNotEmpty);
      expect(ms.every((i) => i.severity == Severity.error && i.relationId != null), true);
      expect(codes(diamond(Dialect.postgres)), isNot(contains('mssql_cascade_paths')));
    });

    test('ตั้งเส้นท้ายเป็น NO ACTION แล้วผ่าน', () {
      expect(codes(diamond(Dialect.mssql, last: RefAction.noAction)), isNot(contains('mssql_cascade_paths')));
    });

    test('cascade ตัวเอง (self-reference) = error', () {
      final p = Project(dialect: Dialect.mssql, tables: [
        tbl('t', 'emp', [col('t1', 'id', pk: true), col('t2', 'boss_id')]),
      ], relations: [
        rel('r', 't', 't2', 't', 't1', del: RefAction.cascade),
      ]);
      expect(codes(p), contains('mssql_cascade_paths'));
    });

    test('สายยาวทางเดียวไม่ผิด', () {
      final p = Project(dialect: Dialect.mssql, tables: [
        tbl('a', 'a', [col('a1', 'id', pk: true)]),
        tbl('b', 'b', [col('b1', 'id', pk: true), col('b2', 'a_id')]),
        tbl('c', 'c', [col('c1', 'id', pk: true), col('c2', 'b_id')]),
      ], relations: [
        rel('r1', 'b', 'b2', 'a', 'a1', del: RefAction.cascade),
        rel('r2', 'c', 'c2', 'b', 'b1', del: RefAction.cascade),
      ]);
      expect(codes(p), isNot(contains('mssql_cascade_paths')));
    });
  });
}
