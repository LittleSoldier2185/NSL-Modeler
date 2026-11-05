import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/db/data_access.dart';
import 'package:nsl_dev/core/db/db_session.dart';
import 'package:nsl_dev/core/db/sqlite_data.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:sqlite3/sqlite3.dart';

/// เปิดดู/แก้ข้อมูลกับไฟล์ SQLite จริงบนดิสก์
void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nsl_data');
    path = '${dir.path}/shop.db';
    final db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE, name TEXT, age INTEGER);
      CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), total REAL);
      CREATE TABLE logs (msg TEXT, at TEXT);
      CREATE TABLE pairs (a INTEGER, b INTEGER, v TEXT, PRIMARY KEY (a, b));
      CREATE TABLE files (id INTEGER PRIMARY KEY, data BLOB);
      INSERT INTO users (email, name, age) VALUES ('a@x.com', 'Ann', 30), ('b@x.com', 'Bob', NULL), ('c@x.com', 'Cat_100%', 22);
      INSERT INTO orders (user_id, total) VALUES (1, 10.5), (1, 3), (2, 7);
      INSERT INTO logs VALUES ('hello', 'now'), ('world', 'later');
      INSERT INTO pairs VALUES (1, 1, 'x'), (1, 2, 'y');
      INSERT INTO files VALUES (1, x'0102030405');
    ''');
    db.close();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<(SqliteDataSession, DbTable)> open(String t, {bool writable = false}) async {
    final s = SqliteDataSession.open(path, writable: writable);
    return (s, await s.table(t));
  }

  List<String> backups() => [for (final f in dir.listSync().whereType<File>()) if (f.path.contains('.bak-')) f.path];

  group('เปิดดู', () {
    test('รายชื่อตาราง ไม่รวมตารางภายใน', () async {
      final s = SqliteDataSession.open(path);
      expect(await s.tableNames(), ['files', 'logs', 'orders', 'pairs', 'users']);
      await s.close();
    });

    test('โครงสร้างตาราง : คีย์หลัก / auto increment / NOT NULL / คีย์ผสม / ไม่มีคีย์ใช้ rowid', () async {
      final s = SqliteDataSession.open(path);
      final u = await s.table('users');
      expect(u.keyColumns, ['id']);
      expect(u.column('id')!.autoIncrement, true);
      expect(u.column('email')!.notNull, true);
      expect(u.usesRowid, false);
      expect((await s.table('pairs')).keyColumns, ['a', 'b']);
      final l = await s.table('logs');
      expect(l.keyColumns, ['rowid']);
      expect((l.usesRowid, l.canEditRows), (true, true));
      await expectLater(s.table('nope'), throwsA(isA<DbException>()));
      await s.close();
    });

    test('แบ่งหน้า / เรียง / นับทั้งหมด', () async {
      final (s, t) = await open('users');
      final p1 = await s.fetch(t, limit: 2);
      expect((p1.total, p1.rows.length), (3, 2));
      expect(p1.rows.first.cells, ['1', 'a@x.com', 'Ann', '30']);
      expect(p1.rows.first.key, {'id': '1'});
      expect(p1.rows[1].cells[3], isNull); // NULL ไม่ใช่ข้อความ 'null'
      final p2 = await s.fetch(t, limit: 2, offset: 2);
      expect(p2.rows.single.cells[1], 'c@x.com');
      final desc = await s.fetch(t, orderBy: 'email', descending: true);
      expect(desc.rows.map((r) => r.cells[1]), ['c@x.com', 'b@x.com', 'a@x.com']);
      // ชื่อคอลัมน์เรียงที่ไม่มีจริง/พยายามฝังคำสั่ง ถูกเมิน ไม่ทำให้พัง
      final bad = await s.fetch(t, orderBy: 'id; DROP TABLE users');
      expect(bad.total, 3);
      await s.close();
    });

    test('ค้นหา : ทุกคอลัมน์ ไม่สนตัวพิมพ์ ; % และ _ เป็นตัวอักษรธรรมดา', () async {
      final (s, t) = await open('users');
      expect((await s.fetch(t, search: 'ann')).rows.single.cells[2], 'Ann');
      expect((await s.fetch(t, search: '@x.com')).total, 3);
      expect((await s.fetch(t, search: '_100%')).rows.single.cells[2], 'Cat_100%');
      expect((await s.fetch(t, search: '%')).rows.single.cells[2], 'Cat_100%'); // ไม่ใช่ wildcard จับทุกแถว
      expect((await s.fetch(t, search: "x' OR '1'='1")).total, 0);
      await s.close();
    });

    test('ตารางไม่มีคีย์หลักได้ rowid เป็นคีย์ ; BLOB แสดงเป็นข้อความสรุป', () async {
      final (s, lt) = await open('logs');
      final p = await s.fetch(lt);
      expect(p.rows.map((r) => r.key['rowid']), ['1', '2']);
      final ft = await s.table('files');
      expect((await s.fetch(ft)).rows.single.cells[1], '[BLOB 5 bytes]');
      await s.close();
    });
  });

  group('อ่านอย่างเดียวจริง', () {
    test('เปิดแบบไม่เขียน : apply ถูกปฏิเสธ ไฟล์ไม่เปลี่ยน ไม่มีไฟล์สำรอง', () async {
      final before = File(path).readAsBytesSync();
      final (s, t) = await open('users');
      expect(s.writable, false);
      await expectLater(s.apply(t, [const RowDelete({'id': '1'})]), throwsA(isA<DbException>()));
      await s.close();
      expect(File(path).readAsBytesSync(), before);
      expect(backups(), isEmpty);
    });
  });

  group('แก้ไขข้อมูล', () {
    test('เพิ่ม/แก้/ลบ ในทรานแซกชันเดียว + สำรองไฟล์เดิมก่อนเขียน', () async {
      final before = File(path).readAsBytesSync();
      final (s, t) = await open('users', writable: true);
      final r = await s.apply(t, [
        const RowInsert({'email': 'd@x.com', 'name': 'Dan'}),
        const RowUpdate({'id': '1'}, {'name': 'Ann2', 'age': null}),
        const RowDelete({'id': '3'}),
      ]);
      expect(r.statements, 3);
      expect(File(r.backupPath!).readAsBytesSync(), before);
      final p = await s.fetch(t, orderBy: 'id');
      expect(p.rows.map((x) => x.cells[2]), ['Ann2', 'Bob', 'Dan']);
      expect(p.rows.first.cells[3], isNull);
      expect(p.rows.last.cells[0], '4'); // AUTOINCREMENT ไม่ใช้เลขที่ลบไปแล้วซ้ำ
      await s.close();
    });

    test('ผิดกฎ (UNIQUE ซ้ำ) กลางชุด = ยกเลิกทั้งหมด ไม่มีอะไรเปลี่ยน', () async {
      final (s, t) = await open('users', writable: true);
      await expectLater(
        s.apply(t, [
          const RowUpdate({'id': '1'}, {'name': 'CHANGED'}),
          const RowInsert({'email': 'b@x.com'}), // ซ้ำ
        ]),
        throwsA(isA<DbException>()),
      );
      final p = await s.fetch(t, orderBy: 'id');
      expect(p.rows.first.cells[2], 'Ann'); // ข้อแรกถูกยกเลิกด้วย
      expect(p.total, 3);
      // ยังเขียนต่อได้ปกติหลังล้มเหลว (ทรานแซกชันไม่ค้าง)
      await s.apply(t, [const RowUpdate({'id': '1'}, {'name': 'OK'})]);
      expect((await s.fetch(t, orderBy: 'id')).rows.first.cells[2], 'OK');
      await s.close();
    });

    test('ลบแถวที่ถูก FK อ้างอยู่ = ฐานข้อมูลปฏิเสธ (foreign_keys เปิด)', () async {
      final (s, t) = await open('users', writable: true);
      await expectLater(s.apply(t, [const RowDelete({'id': '1'})]), throwsA(isA<DbException>()));
      expect((await s.fetch(t)).total, 3);
      await s.close();
    });

    test('แก้/ลบแถวที่ไม่มีอยู่แล้ว (กระทบ 0 แถว) = ยกเลิก ไม่เงียบ ๆ', () async {
      final (s, t) = await open('users', writable: true);
      await expectLater(
        s.apply(t, [const RowUpdate({'id': '2'}, {'name': 'x'}), const RowDelete({'id': '999'})]),
        throwsA(isA<DbException>().having((e) => e.message, 'message', contains('กระทบ'))),
      );
      expect((await s.fetch(t, orderBy: 'id')).rows[1].cells[2], 'Bob');
      await s.close();
    });

    test('คีย์ผสม + ตารางไม่มีคีย์ (rowid) แก้ได้ตรงแถว', () async {
      final (s, pt) = await open('pairs', writable: true);
      await s.apply(pt, [const RowUpdate({'a': '1', 'b': '2'}, {'v': 'Y!'})]);
      final p = await s.fetch(pt, orderBy: 'b');
      expect(p.rows.map((r) => r.cells[2]), ['x', 'Y!']);
      final lt = await s.table('logs');
      final lp = await s.fetch(lt);
      await s.apply(lt, [RowUpdate(lp.rows[1].key, {'msg': 'edited'}), RowDelete(lp.rows[0].key)]);
      expect((await s.fetch(lt)).rows.map((r) => r.cells[0]), ['edited']);
      await s.close();
    });

    test('ค่าที่มีเครื่องหมายคำพูด/ภาษาไทย/คำสั่ง SQL ถูกเก็บเป็นข้อมูล ไม่ถูกรัน', () async {
      final (s, t) = await open('users', writable: true);
      const nasty = "x'); DROP TABLE users; --";
      await s.apply(t, [const RowInsert({'email': 'e@x.com', 'name': nasty}), const RowInsert({'email': 'f@x.com', 'name': 'ภาษาไทย "quote"'})]);
      final p = await s.fetch(t, orderBy: 'id');
      expect(p.rows.map((r) => r.cells[2]), containsAll([nasty, 'ภาษาไทย "quote"']));
      expect(await s.tableNames(), contains('users'));
      await s.close();
    });

    test('ไบนารีแก้ไม่ได้ ; คอลัมน์ไม่มีจริง ; ชุดว่าง ; ตารางไม่มีวิธีระบุแถว', () async {
      final (s, ft) = await open('files', writable: true);
      await expectLater(s.apply(ft, [const RowUpdate({'id': '1'}, {'data': 'x'})]), throwsA(isA<DbException>()));
      final u = await s.table('users');
      await expectLater(s.apply(u, [const RowUpdate({'id': '1'}, {'nope': 'x'})]), throwsA(isA<DbException>()));
      await expectLater(s.apply(u, [const RowUpdate({}, {'name': 'x'})]), throwsA(isA<DbException>())); // คีย์ไม่ครบ
      expect((await s.apply(u, const [])).statements, 0);
      expect(backups(), isEmpty); // คำสั่งไม่ถูกต้อง/ว่าง = ไม่สำรองและไม่เขียน
      await s.close();
    });

    test('สำรองไฟล์ครั้งเดียวต่อเซสชัน แม้บันทึกหลายครั้ง', () async {
      final (s, t) = await open('users', writable: true);
      await s.apply(t, [const RowUpdate({'id': '1'}, {'name': 'a'})]);
      await s.apply(t, [const RowUpdate({'id': '1'}, {'name': 'b'})]);
      expect(backups().length, 1);
      await s.close();
    });
  });

  group('buildEditStatement / buildSearch (ไม่ต้องใช้ฐานข้อมูล)', () {
    const t = DbTable('t', [DbColumn('id', 'INT', isPk: true), DbColumn('n', 'TEXT')], ['id']);

    test('ใช้ ? แทนค่าเสมอ ชื่อถูก quote ตาม dialect', () {
      final my = buildEditStatement(Dialect.mysql, t, const RowUpdate({'id': '5'}, {'n': "o'k"}));
      expect(my.sql, 'UPDATE `t` SET `n` = ? WHERE `id` = ?');
      expect(my.params, ["o'k", '5']);
      expect(my.sql, isNot(contains("o'k")));
      final sq = buildEditStatement(Dialect.sqlite, t, const RowDelete({'id': '5'}));
      expect(sq.sql, 'DELETE FROM "t" WHERE "id" = ?');
      expect(buildEditStatement(Dialect.mysql, t, const RowInsert({})).sql, 'INSERT INTO `t` () VALUES ()');
      expect(buildEditStatement(Dialect.sqlite, t, const RowInsert({})).sql, 'INSERT INTO "t" DEFAULT VALUES');
    });

    test('preview แทนค่าให้อ่านง่าย (ใช้แสดงเท่านั้น)', () {
      final s = buildEditStatement(Dialect.sqlite, t, const RowUpdate({'id': '5'}, {'n': null}));
      expect(s.preview(), 'UPDATE "t" SET "n" = NULL WHERE "id" = \'5\'');
    });

    test('ชื่อ backtick/ฟันหนูในชื่อตารางถูก escape', () {
      expect(quoteIdent(Dialect.mysql, 'we`ird'), '`we``ird`');
      expect(quoteIdent(Dialect.sqlite, 'we"ird'), '"we""ird"');
    });

    test('ค้นหา MySQL ใช้ ESCAPE ของ MySQL ; ค้นหาว่าง = ไม่มีเงื่อนไข', () {
      expect(buildSearch(Dialect.mysql, t, '').where, '');
      expect(buildSearch(Dialect.mysql, t, 'a').where, contains(r"ESCAPE '\\'"));
      expect(buildSearch(Dialect.sqlite, t, 'a').where, contains(r"ESCAPE '\'"));
    });
  });
}
