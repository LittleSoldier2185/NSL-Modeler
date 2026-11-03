// รันสคริปต์ที่สร้างได้บน SQLite จริง เพื่อยืนยันว่า import ได้โดยไม่ error
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/ddl/ddl_generator.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/index_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:sqlite3/sqlite3.dart';

Project shop() => Project(name: 'ร้านค้า', dialect: Dialect.sqlite, tables: [
      TableModel(id: 'tu', name: 'users', comment: 'ผู้ใช้', columns: [
        ColumnModel(id: 'u1', name: 'id', isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'u2', name: 'email', type: DataType.varchar, length: 255, notNull: true, unique: true, comment: 'อีเมล'),
        ColumnModel(id: 'u3', name: 'created_at', type: DataType.datetime, notNull: true, defaultValue: 'now()'),
        ColumnModel(id: 'u4', name: 'active', type: DataType.boolean, notNull: true, defaultValue: 'true'),
      ]),
      TableModel(id: 'to', name: 'order', columns: [
        // ชื่อตารางเป็น reserved word ต้อง quote ได้
        ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'o2', name: 'user_id', notNull: true),
        ColumnModel(id: 'o3', name: 'select', type: DataType.varchar, length: 20, defaultValue: "it's"),
        ColumnModel(id: 'o4', name: 'total', type: DataType.decimal, length: 10, scale: 2, notNull: true, defaultValue: '0'),
      ], indexes: [
        IndexModel(id: 'i1', name: 'idx_order_user', columnIds: ['o2']),
      ]),
    ], relations: [
      RelationModel(
          id: 'r1',
          fromTableId: 'to',
          fromColumnId: 'o2',
          toTableId: 'tu',
          toColumnId: 'u1',
          onDelete: RefAction.cascade),
    ]);

void main() {
  late Database db;
  setUp(() {
    db = sqlite3.openInMemory();
  });
  tearDown(() => db.close());

  test('สคริปต์ SQLite รันบน SQLite จริงได้โดยไม่ error', () {
    final sql = DdlGenerator.forDialect(Dialect.sqlite).generate(shop());
    db.execute(sql);

    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        .map((r) => r['name'])
        .toList();
    expect(tables, ['order', 'users']);
  });

  test('AUTOINCREMENT ทำงานจริง และค่าเริ่มต้นถูกใช้', () {
    db.execute(DdlGenerator.forDialect(Dialect.sqlite).generate(shop()));
    db.execute("INSERT INTO users (email) VALUES ('a@x.com')");
    db.execute("INSERT INTO users (email) VALUES ('b@x.com')");
    final rows = db.select('SELECT id, active, created_at FROM users ORDER BY id');
    expect(rows.map((r) => r['id']), [1, 2]);
    expect(rows.first['active'], 1);
    expect(rows.first['created_at'], isNotNull);
  });

  test('FK ถูกบังคับจริง และ ON DELETE CASCADE ทำงาน', () {
    db.execute(DdlGenerator.forDialect(Dialect.sqlite).generate(shop()));
    db.execute("INSERT INTO users (email) VALUES ('a@x.com')");
    db.execute('INSERT INTO "order" (user_id, total) VALUES (1, 10)');
    expect(() => db.execute('INSERT INTO "order" (user_id, total) VALUES (99, 1)'), throwsA(isA<SqliteException>()));
    db.execute('DELETE FROM users WHERE id = 1');
    expect(db.select('SELECT * FROM "order"'), isEmpty);
  });

  test('ค่าเริ่มต้นที่มี \' ถูก escape ถูกต้อง', () {
    db.execute(DdlGenerator.forDialect(Dialect.sqlite).generate(shop()));
    db.execute("INSERT INTO users (email) VALUES ('a@x.com')");
    db.execute('INSERT INTO "order" (user_id, total) VALUES (1, 5)');
    expect(db.select('SELECT "select" AS s FROM "order"').single['s'], "it's");
  });
}
