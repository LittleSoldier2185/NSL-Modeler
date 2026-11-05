// รัน migration บน SQLite จริง: โครงสร้างหลัง migrate ต้องเหมือนสร้างใหม่จากโครงสร้างใหม่ และข้อมูลเดิมต้องไม่หาย
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/ddl/ddl_generator.dart';
import 'package:nsl_dev/core/diff/migration.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/index_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:sqlite3/sqlite3.dart';

import 'migration_fixtures.dart';

/// โครงสร้างของ DB แบบเทียบได้ (ไม่สนลำดับคอลัมน์/ชื่อ index ที่ SQLite ตั้งเอง)
String schemaOf(Database db) {
  final b = StringBuffer();
  final tables = db
      .select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
      .map((r) => r['name'] as String);
  for (final t in tables) {
    b.writeln('T $t');
    final cols = [
      for (final r in db.select('PRAGMA table_info("$t")'))
        '  C ${r['name']} ${r['type']} nn=${r['notnull']} def=${r['dflt_value']} pk=${r['pk']}'
    ]..sort();
    cols.forEach(b.writeln);
    final fks = [
      for (final r in db.select('PRAGMA foreign_key_list("$t")'))
        '  F ${r['from']} -> ${r['table']}.${r['to']} upd=${r['on_update']} del=${r['on_delete']}'
    ]..sort();
    fks.forEach(b.writeln);
    final idx = <String>[];
    for (final i in db.select('PRAGMA index_list("$t")')) {
      final origin = i['origin'];
      if (origin == 'pk') continue;
      final cs = db.select('PRAGMA index_info("${i['name']}")').map((r) => r['name']).join(',');
      // UNIQUE ในนิยามคอลัมน์ (origin u) ชื่อ index ถูกตั้งอัตโนมัติ จึงไม่เทียบชื่อ
      idx.add(origin == 'u' ? '  U ($cs)' : '  I ${i['name']} unique=${i['unique']} ($cs)');
    }
    idx.sort();
    idx.forEach(b.writeln);
  }
  return b.toString();
}

void seed(Database db) {
  db.execute('''
INSERT INTO users (email, name, age) VALUES ('a@x.com', 'Ann', 30), ('b@x.com', 'Bob', NULL);
INSERT INTO orders (user_id, total, note) VALUES (1, 10.5, 'hi'), (2, 3, NULL);
''');
}

class Run {
  Run(this.script, this.migrated, this.fresh);
  final String script;
  final Database migrated;
  final Database fresh;
}

final gen = DdlGenerator.forDialect(Dialect.sqlite);

Run migrate(Project a, Project b, {void Function(Database)? seeder = seed}) {
  final db = sqlite3.openInMemory();
  db.execute(gen.generate(a));
  seeder?.call(db);
  final script = generateMigration(a, b);
  db.execute(script);
  final fresh = sqlite3.openInMemory();
  fresh.execute(gen.generate(b));
  return Run(script, db, fresh);
}

void expectSame(Run r) {
  expect(schemaOf(r.migrated), schemaOf(r.fresh), reason: r.script);
  expect(r.migrated.select('PRAGMA foreign_key_check'), isEmpty, reason: r.script);
  expect(r.migrated.select('PRAGMA integrity_check').single.values.first, 'ok');
}

List<Object?> rows(Database db, String sql) => db.select(sql).map((r) => r.values.toList()).toList();

Project a0() {
  final p = base(Dialect.sqlite);
  // ใช้ตารางมีคอลัมน์ int เพิ่มสำหรับทดสอบ FK ใหม่
  tb(p, 'to').columns.add(col('o5', 'coupon_id'));
  return p;
}

void main() {
  tearDown(() {});

  test('ไม่มีอะไรเปลี่ยน: สคริปต์รันได้และไม่แตะอะไร', () {
    final a = a0();
    final r = migrate(a, clone(a));
    expectSame(r);
    expect(rows(r.migrated, 'SELECT COUNT(*) FROM users'), [
      [2]
    ]);
  });

  test('เพิ่มคอลัมน์ (ALTER ตรง ๆ) ข้อมูลอยู่ครบ', () {
    final b = clone(a0());
    tb(b, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
    tb(b, 'tu').columns.add(col('u10', 'level', nn: true, def: '1'));
    final r = migrate(a0(), b);
    expect(r.script, isNot(contains('__new')));
    expectSame(r);
    expect(rows(r.migrated, 'SELECT email, phone, level FROM users ORDER BY id'), [
      ['a@x.com', null, 1],
      ['b@x.com', null, 1],
    ]);
  });

  test('เปลี่ยนชื่อคอลัมน์ ข้อมูลตามไปด้วย', () {
    final b = clone(a0());
    cl(b, 'tu', 'u3').name = 'full_name';
    final r = migrate(a0(), b);
    expectSame(r);
    expect(rows(r.migrated, 'SELECT full_name FROM users ORDER BY id'), [
      ['Ann'],
      ['Bob']
    ]);
  });

  test('เปลี่ยนชนิด/NULL/DEFAULT (สร้างตารางใหม่) ข้อมูลอยู่ครบ', () {
    final b = clone(a0());
    final t = cl(b, 'to', 'o3');
    t.notNull = false;
    t.defaultValue = '9';
    cl(b, 'tu', 'u3').type = DataType.text;
    final r = migrate(a0(), b);
    expect(r.script, contains('orders__new'));
    expectSame(r);
    expect(rows(r.migrated, 'SELECT total FROM orders ORDER BY id'), [
      [10.5],
      [3.0]
    ]);
    // ค่าเริ่มต้นใหม่ใช้ได้
    r.migrated.execute('INSERT INTO orders (user_id) VALUES (1)');
    expect(rows(r.migrated, 'SELECT total FROM orders WHERE id = 3'), [
      [9]
    ]);
  });

  test('ลบคอลัมน์', () {
    final b = clone(a0());
    tb(b, 'tu').columns.removeWhere((c) => c.id == 'u4');
    final r = migrate(a0(), b);
    expectSame(r);
    expect(rows(r.migrated, 'SELECT email, name FROM users ORDER BY id'), [
      ['a@x.com', 'Ann'],
      ['b@x.com', 'Bob']
    ]);
  });

  test('เปลี่ยนชื่อตาราง: FK ของตารางอื่นตามไปด้วย', () {
    final b = clone(a0());
    tb(b, 'tu').name = 'members';
    final r = migrate(a0(), b);
    expectSame(r);
    expect(rows(r.migrated, 'SELECT COUNT(*) FROM members'), [
      [2]
    ]);
    expect(rows(r.migrated, 'SELECT "table" FROM pragma_foreign_key_list(\'orders\')'), [
      ['members']
    ]);
  });

  test('เพิ่มตารางใหม่ที่มี FK ไปตารางเดิม', () {
    final b = clone(a0());
    b.tables.add(TableModel(id: 'tn', name: 'logs', columns: [
      col('n1', 'id', pk: true, ai: true),
      col('n2', 'user_id', nn: true),
      col('n3', 'msg', type: DataType.text),
    ], indexes: [
      IndexModel(id: 'in', name: 'idx_logs_user', columnIds: ['n2']),
    ]));
    b.relations.add(RelationModel(
        id: 'rn', fromTableId: 'tn', fromColumnId: 'n2', toTableId: 'tu', toColumnId: 'u1', onDelete: RefAction.cascade));
    final r = migrate(a0(), b);
    expectSame(r);
    r.migrated.execute("INSERT INTO logs (user_id, msg) VALUES (1, 'x')");
    expect(() => r.migrated.execute("INSERT INTO logs (user_id) VALUES (99)"), throwsA(isA<SqliteException>()));
  });

  test('เพิ่ม FK ให้ตารางเดิม (สร้างตารางลูกใหม่) และ FK ถูกบังคับจริง', () {
    final a = a0();
    final b = clone(a);
    b.tables.add(TableModel(id: 'tc', name: 'coupons', columns: [col('c1', 'id', pk: true, ai: true)]));
    b.relations.add(RelationModel(
        id: 'rc',
        fromTableId: 'to',
        fromColumnId: 'o5',
        toTableId: 'tc',
        toColumnId: 'c1',
        onDelete: RefAction.setNull));
    final r = migrate(a, b);
    expectSame(r);
    expect(() => r.migrated.execute('INSERT INTO orders (user_id, total, coupon_id) VALUES (1, 1, 77)'),
        throwsA(isA<SqliteException>()));
    // ตารางลูกเดิมยังมี FK เก่า, INDEX เก่า และข้อมูล
    expect(rows(r.migrated, 'SELECT COUNT(*) FROM orders'), [
      [2]
    ]);
  });

  test('ลบ FK', () {
    final b = clone(a0());
    b.relations.clear();
    final r = migrate(a0(), b);
    expectSame(r);
    r.migrated.execute('INSERT INTO orders (user_id, total) VALUES (99, 1)'); // ไม่ถูกบังคับแล้ว
  });

  test('เปลี่ยน action ของ FK (CASCADE -> SET NULL)', () {
    final b = clone(a0());
    b.relations.single.onDelete = RefAction.setNull;
    cl(b, 'to', 'o2').notNull = false;
    final r = migrate(a0(), b);
    expectSame(r);
    r.migrated.execute('DELETE FROM users WHERE id = 1');
    expect(rows(r.migrated, 'SELECT user_id FROM orders WHERE id = 1'), [
      [null]
    ]);
  });

  test('เปลี่ยน Primary Key', () {
    // ย้าย PK ของ orders (ไม่มีตารางไหนอ้างถึง) จาก id ไป user_id
    final b = clone(a0());
    cl(b, 'to', 'o1').isPrimaryKey = false;
    cl(b, 'to', 'o1').autoIncrement = false;
    cl(b, 'to', 'o2').isPrimaryKey = true;
    final r = migrate(a0(), b);
    expectSame(r);
    expect(rows(r.migrated, 'SELECT COUNT(*) FROM orders'), [
      [2]
    ]);
    expect(() => r.migrated.execute('INSERT INTO orders (id, user_id, total) VALUES (9, 1, 1)'),
        throwsA(isA<SqliteException>())); // user_id ซ้ำ = ละเมิด PK ใหม่
  });

  test('เพิ่ม/ลบ/เปลี่ยน INDEX', () {
    final b = clone(a0());
    tb(b, 'to').indexes.clear();
    tb(b, 'to').indexes.add(IndexModel(id: 'i9', name: 'ux_orders_total', columnIds: ['o3'], unique: true));
    tb(b, 'tu').indexes.add(IndexModel(id: 'i8', name: 'idx_users_name', columnIds: ['u3', 'u4']));
    final r = migrate(a0(), b);
    expect(r.script, isNot(contains('__new')));
    expectSame(r);
  });

  test('เพิ่ม/เอา UNIQUE ออก', () {
    final b = clone(a0());
    cl(b, 'tu', 'u3').unique = true;
    cl(b, 'tu', 'u2').unique = false;
    final r = migrate(a0(), b);
    expectSame(r);
    r.migrated.execute("INSERT INTO users (email, name) VALUES ('a@x.com', 'Zed')"); // email ซ้ำได้แล้ว
    expect(() => r.migrated.execute("INSERT INTO users (email, name) VALUES ('c@x.com', 'Ann')"),
        throwsA(isA<SqliteException>()));
  });

  test('ลบตาราง (พร้อม FK ที่ชี้มา)', () {
    final b = clone(a0());
    b.tables.removeWhere((t) => t.id == 'to');
    b.relations.clear();
    final r = migrate(a0(), b);
    expectSame(r);
    expect(rows(r.migrated, "SELECT COUNT(*) FROM sqlite_master WHERE name='orders'"), [
      [0]
    ]);
  });

  test('ลบตารางแม่ที่ตารางลูกอ้างอยู่ แล้วตารางลูกเลิกอ้าง', () {
    final b = clone(a0());
    b.tables.removeWhere((t) => t.id == 'tu');
    b.relations.clear();
    cl(b, 'to', 'o2').notNull = false;
    final r = migrate(a0(), b);
    expectSame(r);
  });

  test('หลายอย่างพร้อมกัน', () {
    final b = clone(a0());
    tb(b, 'tu').name = 'members';
    cl(b, 'tu', 'u3').name = 'full_name';
    tb(b, 'tu').columns.removeWhere((c) => c.id == 'u4');
    cl(b, 'to', 'o3').length = 12;
    cl(b, 'to', 'o4').type = DataType.varchar;
    tb(b, 'to').indexes.clear();
    b.tables.add(TableModel(id: 'tc', name: 'coupons', columns: [
      col('c1', 'id', pk: true, ai: true),
      col('c2', 'code', type: DataType.varchar, len: 20, uq: true),
    ]));
    b.relations.add(RelationModel(
        id: 'rc', fromTableId: 'to', fromColumnId: 'o5', toTableId: 'tc', toColumnId: 'c1'));
    final r = migrate(a0(), b);
    expectSame(r);
    expect(rows(r.migrated, 'SELECT full_name FROM members ORDER BY id'), [
      ['Ann'],
      ['Bob']
    ]);
    expect(rows(r.migrated, 'SELECT total FROM orders ORDER BY id'), [
      [10.5],
      [3.0]
    ]);
  });

  test('ย้อนกลับ: migrate ไป-กลับ ได้โครงสร้างเดิม', () {
    final a = a0();
    final b = clone(a);
    tb(b, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
    cl(b, 'to', 'o3').notNull = false;
    final there = migrate(a, b);
    there.migrated.execute(generateMigration(b, a));
    expect(schemaOf(there.migrated), schemaOf(sqlite3.openInMemory()..execute(gen.generate(a))));
  });
}
