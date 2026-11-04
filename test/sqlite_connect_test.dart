import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/db/db_session.dart';
import 'package:nsl_modeler/core/db/sqlite_connector.dart';
import 'package:sqlite3/sqlite3.dart';

/// ฐานข้อมูล SQLite จริงในไฟล์ชั่วคราว (ไม่ใช่ของปลอม) : ทดสอบตัวอ่านโครงสร้างและความเป็น "อ่านอย่างเดียว"
void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nsl_sqlite');
    path = '${dir.path}/shop.db';
    final db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email VARCHAR(255) NOT NULL UNIQUE,
        name VARCHAR(100)
      );
      CREATE TABLE "order items" (
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        total DECIMAL(12,2) NOT NULL DEFAULT 0,
        note TEXT
      );
      CREATE INDEX idx_items_user ON "order items"(user_id);
      CREATE VIEW v_users AS SELECT id FROM users;
      INSERT INTO users(email, name) VALUES ('a@x.com', 'A');
    ''');
    db.close();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  DbConfig cfg([String? p]) => DbConfig(database: p ?? path);

  test('อ่านตาราง/คอลัมน์/คีย์/FK/ดัชนีจากไฟล์จริง และไม่นับ VIEW', () async {
    final s = await const SqliteConnector().connect(cfg());
    final r = await readSqliteSchema(s, name: 'shop');
    await s.close();
    expect(r.tableCount, 2);
    final p = r.import.project;
    expect(p.tables.map((t) => t.name).toSet(), {'users', 'order items'});
    final users = p.tables.firstWhere((t) => t.name == 'users');
    expect(users.columns.firstWhere((c) => c.name == 'id').isPrimaryKey, true);
    expect(users.columns.firstWhere((c) => c.name == 'email').length, 255);
    expect(p.relations.length, 1);
    expect(p.tables.firstWhere((t) => t.name == 'order items').indexes.length, 1);
  });

  test('อ่านอย่างเดียวจริง: คำสั่งเขียนถูกปฏิเสธ ไฟล์ไม่เปลี่ยนแม้แต่ไบต์เดียว', () async {
    final before = File(path).readAsBytesSync();
    final s = await const SqliteConnector().connect(cfg());
    for (final bad in [
      'DELETE FROM users',
      'DROP TABLE users',
      "INSERT INTO users(email) VALUES ('z')",
      'SELECT 1; DROP TABLE users',
      'PRAGMA writable_schema = 1',
    ]) {
      expect(() => s.query(bad), throwsA(isA<DbException>()), reason: bad);
    }
    expect((await s.query('SELECT count(*) AS n FROM users')).single['n'], '1');
    await readSqliteSchema(s, name: 'x');
    await s.close();
    expect(File(path).readAsBytesSync(), before);
  });

  test('ไฟล์ไม่มี / ไม่ใช่ SQLite / path ว่าง = ข้อความผิดพลาดที่อ่านเข้าใจ', () async {
    await expectLater(const SqliteConnector().connect(cfg('${dir.path}/none.db')), throwsA(isA<DbException>()));
    final junk = File('${dir.path}/junk.db')..writeAsStringSync('this is not a database' * 50);
    await expectLater(const SqliteConnector().connect(cfg(junk.path)), throwsA(isA<DbException>()));
    await expectLater(const SqliteConnector().connect(cfg('  ')), throwsA(isA<DbException>()));
  });

  test('ฐานข้อมูลว่าง = 0 ตาราง', () async {
    final empty = '${dir.path}/empty.db';
    sqlite3.open(empty).close();
    final s = await const SqliteConnector().connect(cfg(empty));
    final r = await readSqliteSchema(s, name: 'empty');
    await s.close();
    expect(r.tableCount, 0);
    expect(r.import.project.tables, isEmpty);
  });
}
