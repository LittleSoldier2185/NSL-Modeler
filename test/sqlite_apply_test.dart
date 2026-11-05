import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/ddl/ddl_generator.dart';
import 'package:nsl_dev/core/db/db_session.dart';
import 'package:nsl_dev/core/db/sqlite_apply.dart';
import 'package:nsl_dev/core/db/sqlite_connector.dart';
import 'package:nsl_dev/core/diff/migration.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/ui/migration_dialog.dart';
import 'package:sqlite3/sqlite3.dart';

import 'migration_fixtures.dart';

/// รัน migration กับไฟล์ SQLite จริงบนดิสก์ : สำรองไฟล์ก่อน, ยกเลิกทั้งหมดเมื่อผิดพลาด, อ่านกลับมาตรวจ
void main() {
  late Directory dir;
  late String path;
  final gen = DdlGenerator.forDialect(Dialect.sqlite);

  Project oldP() => base(Dialect.sqlite);
  Project newP() {
    final p = clone(oldP());
    tb(p, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
    return p;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nsl_apply');
    path = '${dir.path}/shop.db';
    final db = sqlite3.open(path);
    db.execute(gen.generate(oldP()));
    db.execute("INSERT INTO users (email, name, age) VALUES ('a@x.com', 'Ann', 30)");
    db.close();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  List<String> columnsOf(String table) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    final r = [for (final row in db.select('PRAGMA table_info("$table")')) row['name'] as String];
    db.close();
    return r;
  }

  test('สำเร็จ: สำรองไฟล์เดิมไว้ไบต์ต่อไบต์ โครงสร้างใหม่ใช้ได้ ข้อมูลเดิมอยู่ครบ', () {
    final before = File(path).readAsBytesSync();
    final script = generateMigration(oldP(), newP());
    final r = applySqliteMigration(path, script, now: DateTime(2026, 11, 4, 15, 30, 45));
    expect(r.backupPath, '$path.bak-20261104-153045');
    expect(File(r.backupPath).readAsBytesSync(), before);
    expect(columnsOf('users'), contains('phone'));
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    expect(db.select('SELECT email FROM users').single['email'], 'a@x.com');
    db.close();
    expect(r.fkViolations, isEmpty);
  });

  test('ผิดพลาดกลางสคริปต์: ROLLBACK ฐานข้อมูลคงเดิม, มีไฟล์สำรอง, ข้อความบอกที่อยู่ไฟล์สำรอง', () {
    const bad = 'BEGIN;\nCREATE TABLE fresh (x INTEGER);\nALTER TABLE users ADD COLUMN ok_col TEXT;\nINSERT INTO no_such_table VALUES (1);\nCOMMIT;\n';
    DbException? err;
    try {
      applySqliteMigration(path, bad, now: DateTime(2026, 1, 2, 3, 4, 5));
    } on DbException catch (e) {
      err = e;
    }
    expect(err, isNotNull);
    expect(err!.message, contains('.bak-20260102-030405'));
    expect(columnsOf('fresh'), isEmpty); // CREATE TABLE ก่อนหน้าถูกยกเลิก
    expect(columnsOf('users'), isNot(contains('ok_col')));
    expect(File('$path.bak-20260102-030405').existsSync(), true);
  });

  test('ไม่มีไฟล์ / สคริปต์ว่าง = ไม่รัน และไม่สร้างไฟล์สำรองเปล่า ๆ', () {
    expect(() => applySqliteMigration('${dir.path}/none.db', 'SELECT 1'), throwsA(isA<DbException>()));
    expect(() => applySqliteMigration(path, '  \n'), throwsA(isA<DbException>()));
    expect(dir.listSync().whereType<File>().where((f) => f.path.contains('.bak-')), isEmpty);
  });

  test('ชื่อไฟล์สำรองไม่ชนของเดิม', () {
    final t = DateTime(2026, 5, 6, 7, 8, 9);
    final first = sqliteBackupPath(path, t);
    File(first).writeAsStringSync('x');
    expect(sqliteBackupPath(path, t), '$first-2');
  });

  test('รายงานแถวที่ละเมิด FK หลังรัน (สคริปต์ commit แล้ว แต่แจ้งเตือน)', () {
    final db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('INSERT INTO orders (user_id, total) VALUES (999, 1)'); // user 999 ไม่มี
    db.close();
    final r = applySqliteMigration(path, 'CREATE TABLE extra (x INTEGER);');
    expect(r.fkViolations, isNotEmpty);
    expect(r.fkViolations.first, contains('orders'));
    expect(columnsOf('extra'), ['x']);
  });

  group('หน้า Migration', () {
    Future<void> openDialog(WidgetTester tester, {String? sqlitePath}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // ฝั่ง "เก่า" อ่านจากไฟล์จริงเหมือนที่กล่องเชื่อมต่อทำ
      late Project old;
      await tester.runAsync(() async {
        final s = await const SqliteConnector().connect(DbConfig(database: path));
        old = (await readSqliteSchema(s, name: 'shop')).import.project;
        await s.close();
      });
      currentLang = Lang.th;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => MigrationDialog(old: old, neu: newP(), oldLabel: 'shop.db', sqlitePath: sqlitePath),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('ไม่ได้มาจากไฟล์ SQLite = ไม่มีปุ่มรัน', (tester) async {
      await openDialog(tester);
      expect(find.byKey(const ValueKey('apply-sqlite')), findsNothing);
    });

    testWidgets('กดรัน > ยืนยัน = สำรองแล้วรัน แสดงผลและยืนยันว่าตรงกับแผนภาพ ; ยกเลิก = ไม่แตะไฟล์', (tester) async {
      await openDialog(tester, sqlitePath: path);
      expect(find.byKey(const ValueKey('apply-sqlite')), findsOneWidget);

      // ยกเลิกก่อน : ไม่มีอะไรเปลี่ยน
      await tester.tap(find.byKey(const ValueKey('apply-sqlite')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(columnsOf('users'), isNot(contains('phone')));
      expect(find.byKey(const ValueKey('apply-result')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('apply-sqlite')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('apply-confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('apply-result')), findsOneWidget);
      expect(find.textContaining('รันสำเร็จ'), findsOneWidget);
      expect(find.textContaining('.bak-'), findsOneWidget);
      expect(columnsOf('users'), contains('phone'));
      expect(dir.listSync().whereType<File>().where((f) => f.path.contains('.bak-')).length, 1);
    });
  });
}
