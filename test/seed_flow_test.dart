import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/diff/migration.dart';
import 'package:nsl_dev/core/diff/schema_diff.dart';
import 'package:nsl_dev/core/export/seed_csv.dart';
import 'package:nsl_dev/core/export/seed_data.dart';
import 'package:nsl_dev/core/export/sql_export.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/ui/migration_dialog.dart';
import 'package:nsl_dev/ui/seed_data_dialog.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'migration_fixtures.dart';

TableModel roles() => TableModel(id: 'tr', name: 'roles', columns: [
      ColumnModel(id: 'r1', name: 'id', isPrimaryKey: true),
      ColumnModel(id: 'r2', name: 'name', type: DataType.varchar, length: 30, notNull: true),
      ColumnModel(id: 'r3', name: 'label', type: DataType.varchar, length: 30),
    ]);

Project proj(Dialect d, {List<Map<String, String?>> rows = const []}) {
  final t = roles()..seedRows = rows.map((r) => Map<String, String?>.of(r)).toList();
  return Project(name: 'app', dialect: d, tables: [t]);
}

void main() {
  group('CSV', () {
    test('แยกคอลัมน์ด้วยจุลภาค/เซมิโคลอน/แท็บ และเครื่องหมายคำพูด', () {
      expect(parseCsv('a,b,c\n1,2,3'), [['a', 'b', 'c'], ['1', '2', '3']]);
      expect(parseCsv('a;b\n1;2'), [['a', 'b'], ['1', '2']]);
      expect(parseCsv('a\tb\n1\t2'), [['a', 'b'], ['1', '2']]);
      expect(parseCsv('"x,y","he said ""hi""","line\nbreak"'), [['x,y', 'he said "hi"', 'line\nbreak']]);
    });

    test('ข้ามบรรทัดว่าง รองรับ CRLF และบรรทัดสุดท้ายไม่มีขึ้นบรรทัดใหม่', () {
      expect(parseCsv('a,b\r\n\r\n1,2\r\n3,4'), [['a', 'b'], ['1', '2'], ['3', '4']]);
      expect(parseCsv(''), isEmpty);
    });

    test('มีหัวคอลัมน์ = จับคู่ตามชื่อ (ไม่สนตัวพิมพ์) ข้ามคอลัมน์ที่ไม่รู้จัก', () {
      final t = roles();
      final r = csvToSeedRows(t, 'NAME,Id,ghost\nadmin,1,x\nuser,2,y');
      expect(r.usedHeader, true);
      expect(r.unknownColumns, ['ghost']);
      expect(r.rows, [
        {'r2': 'admin', 'r1': '1'},
        {'r2': 'user', 'r1': '2'},
      ]);
    });

    test('ไม่มีหัวคอลัมน์ = จับคู่ตามลำดับคอลัมน์ของตาราง; ว่างและ NULL = NULL', () {
      final r = csvToSeedRows(roles(), '1,admin,\n2,user,NULL');
      expect(r.usedHeader, false);
      expect(r.rows[0], {'r1': '1', 'r2': 'admin', 'r3': null});
      expect(r.rows[1]['r3'], isNull);
      expect(r.rows[1].containsKey('r3'), true);
    });

    test('ข้ามแถวว่างทั้งแถว และคืนว่างเมื่อไม่มีข้อมูล', () {
      final r = csvToSeedRows(roles(), 'id,name\n,\n1,a');
      expect(r.rows.length, 1);
      expect(r.skippedRows, 1);
      expect(csvToSeedRows(roles(), '').rows, isEmpty);
    });
  });

  group('buildExportSql', () {
    test('ไม่รวมข้อมูลตั้งต้นโดยค่าเริ่มต้น และรวมเมื่อสั่ง', () {
      final p = proj(Dialect.sqlite, rows: [
        {'r1': '1', 'r2': 'admin', 'r3': null}
      ]);
      expect(buildExportSql(p), isNot(contains('INSERT')));
      final withSeed = buildExportSql(p, includeSeed: true);
      expect(withSeed, contains('CREATE TABLE'));
      expect(withSeed.indexOf('CREATE TABLE'), lessThan(withSeed.indexOf('INSERT INTO')));
    });

    test('ข้อมูลตั้งต้นผิด = โยน SeedException (ไม่ปล่อย SQL ผิดออกไป); ไม่มีข้อมูล = เท่ากับ DDL ล้วน', () {
      final bad = proj(Dialect.sqlite, rows: [
        {'r1': 'x', 'r2': 'a'}
      ]);
      expect(() => buildExportSql(bad, includeSeed: true), throwsA(isA<SeedException>()));
      final none = proj(Dialect.sqlite);
      expect(buildExportSql(none, includeSeed: true), buildExportSql(none));
    });

    test('seedSummary นับแถวและตาราง', () {
      final p = proj(Dialect.mysql, rows: [
        {'r1': '1', 'r2': 'a'},
        {'r1': '2', 'r2': 'b'}
      ]);
      expect((seedSummary(p).rows, seedSummary(p).tables), (2, 1));
    });
  });

  group('migration: ข้อมูลตั้งต้น (เพิ่มเฉพาะแถวใหม่ ไม่แตะแถวเดิม)', () {
    Project clonep(Project p) => Project.fromJson(p.toJson());

    test('เพิ่มแถวใหม่ = INSERT แบบรันซ้ำได้เฉพาะแถวใหม่ (แถวเดิมไม่ถูกสร้างซ้ำ)', () {
      final old = proj(Dialect.mysql, rows: [
        {'r1': '1', 'r2': 'admin'}
      ]);
      final neu = clonep(old);
      neu.tableById('tr')!.seedRows.add({'r1': '2', 'r2': 'user'});
      final sql = generateMigration(old, neu);
      expect(sql, contains('INSERT IGNORE INTO `roles`'));
      expect(sql, contains("'user'"));
      expect(sql, isNot(contains("'admin'"))); // แถวเดิมไม่ถูกใส่ซ้ำ
      expect(RegExp(r'^\s*UPDATE\b', multiLine: true).hasMatch(sql), false); // คำสั่งจริง (ไม่นับข้อความเตือน)
      expect(RegExp(r'^\s*DELETE\b', multiLine: true).hasMatch(sql), false);
    });

    test('โครงสร้างเหมือนเดิมแต่ข้อมูลตั้งต้นเปลี่ยน = ยังสร้างสคริปต์ (ไม่ใช่ "ไม่ต้อง migrate")', () {
      final old = proj(Dialect.postgres);
      final neu = clonep(old);
      neu.tableById('tr')!.seedRows = [
        {'r1': '1', 'r2': 'admin'}
      ];
      final diff = diffProjects(old, neu);
      expect(diff.isEmpty, false);
      final sql = generateMigration(old, neu, diff: diff);
      expect(sql, contains('ON CONFLICT DO NOTHING'));
      expect(sql, isNot(contains('ไม่ต้อง migrate')));
    });

    test('แก้ค่า/ลบแถว = ไม่สร้าง UPDATE/DELETE แต่เตือนให้ทำเอง และนับในสรุป', () {
      final old = proj(Dialect.mysql, rows: [
        {'r1': '1', 'r2': 'admin'},
        {'r1': '2', 'r2': 'user'},
        {'r1': '3', 'r2': 'guest'},
      ]);
      final neu = clonep(old);
      neu.tableById('tr')!.seedRows
        ..removeLast() // ลบ guest
        ..[0] = {'r1': '1', 'r2': 'ADMIN!'}; // แก้ admin
      final diff = diffProjects(old, neu);
      final sql = generateMigration(old, neu, diff: diff);
      expect(sql, contains('ไม่ถูกแตะ'));
      expect(sql, contains('roles: แก้ 1 แถว / ลบ 1 แถว'));
      expect(RegExp(r'^\s*UPDATE\b', multiLine: true).hasMatch(sql), false); // คำสั่งจริง (ไม่นับข้อความเตือน)
      expect(RegExp(r'^\s*DELETE\b', multiLine: true).hasMatch(sql), false);
      expect(sql, isNot(contains('INSERT')));
      final lines = diff.summary(old, neu);
      expect(lines.any((l) => l.text.contains('ไม่ถูกแตะ')), true);
      expect(lines.every((l) => !l.destructive), true); // ไม่ใช่การลบข้อมูลโดยสคริปต์
    });

    test('ตารางใหม่ที่มีข้อมูลตั้งต้น: สร้างตารางแล้วใส่ทุกแถว (ตารางแม่ก่อน)', () {
      final old = Project(name: 'app', dialect: Dialect.sqlite);
      final neu = proj(Dialect.sqlite, rows: [
        {'r1': '1', 'r2': 'a'},
        {'r1': '2', 'r2': 'b'}
      ]);
      final sql = generateMigration(old, neu);
      expect(sql.indexOf('CREATE TABLE'), lessThan(sql.indexOf('INSERT OR IGNORE')));
      expect("'a'".allMatches(sql).length, 1);
    });

    test('จับคู่แถวด้วยค่า PK ตามชื่อคอลัมน์ แม้ id คอลัมน์ในไฟล์เก่ากับใหม่ไม่ตรงกัน (ไฟล์ที่ import มา)', () {
      final old = proj(Dialect.mysql, rows: [
        {'r1': '1', 'r2': 'admin'}
      ]);
      // ไฟล์ใหม่: id คอลัมน์/ตารางคนละชุด แต่ชื่อเหมือนกัน
      final neu = Project(name: 'app', dialect: Dialect.mysql, tables: [
        TableModel(id: 'zz', name: 'roles', columns: [
          ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true),
          ColumnModel(id: 'c2', name: 'name', type: DataType.varchar, length: 30, notNull: true),
          ColumnModel(id: 'c3', name: 'label', type: DataType.varchar, length: 30),
        ], seedRows: [
          {'c1': '1', 'c2': 'admin'},
          {'c1': '2', 'c2': 'user'},
        ]),
      ]);
      final sql = generateMigration(old, neu);
      expect(sql, contains("'user'"));
      expect(sql, isNot(contains("'admin'")));
    });

    test('แถวที่ไม่ระบุค่า PK (เช่น PK AUTO INCREMENT ไม่ใส่ค่า) ถูกข้ามพร้อมเตือน ไม่เกิดแถวซ้ำเมื่อรันซ้ำ', () {
      final old = proj(Dialect.mysql);
      final neu = proj(Dialect.mysql, rows: [
        {'r2': 'noid'}
      ]);
      neu.tableById('tr')!.columns.first.autoIncrement = true;
      final sql = generateMigration(old, neu);
      expect(sql, contains('ข้าม 1 แถวของ roles'));
      expect(sql, isNot(contains('INSERT IGNORE')));
    });

    test('ข้อมูลตั้งต้นไม่ถูกต้อง: ข้ามส่วนข้อมูลพร้อมเตือน แต่ส่วนโครงสร้างยังสร้างตามปกติ', () {
      final old = Project(name: 'app', dialect: Dialect.mysql);
      final neu = proj(Dialect.mysql, rows: [
        {'r1': 'abc', 'r2': 'x'}
      ]);
      final sql = generateMigration(old, neu);
      expect(sql, contains('CREATE TABLE'));
      expect(sql, contains('ข้ามข้อมูลตั้งต้น'));
      expect(sql, isNot(contains('INSERT')));
    });

    test('ภาษาอังกฤษ: ข้อความเตือนของข้อมูลตั้งต้นแปลครบ ไม่มีอักษรไทยหลุด', () {
      currentLang = Lang.en;
      addTearDown(() => currentLang = Lang.th);
      final old = proj(Dialect.mysql, rows: [
        {'r1': '1', 'r2': 'admin'},
        {'r1': '2', 'r2': 'user'},
      ]);
      final neu = clonep(old);
      neu.tableById('tr')!.seedRows = [
        {'r1': '1', 'r2': 'changed'},
        {'r1': '3', 'r2': 'new'}
      ];
      final thai = RegExp(r'[฀-๿]');
      final sql = generateMigration(old, neu);
      expect(thai.hasMatch(sql), false, reason: sql);
    });
  });

  group('migration: ห่อด้วยทรานแซกชัน', () {
    Project changed(Dialect d) {
      final old = base(d);
      final neu = clone(old);
      tb(neu, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
      return neu;
    }

    String mig(Dialect d) => generateMigration(base(d), changed(d));

    test('PostgreSQL: BEGIN … COMMIT', () {
      final sql = mig(Dialect.postgres);
      expect(sql.startsWith('BEGIN;'), true);
      expect(sql.trimRight().endsWith('COMMIT;'), true);
    });

    test('SQL Server: XACT_ABORT ON + BEGIN TRANSACTION … COMMIT', () {
      final sql = mig(Dialect.mssql);
      expect(sql.startsWith('SET XACT_ABORT ON;\nBEGIN TRANSACTION;'), true);
      expect(sql.trimRight().endsWith('COMMIT TRANSACTION;'), true);
    });

    test('SQLite: BEGIN TRANSACTION … COMMIT', () {
      final sql = mig(Dialect.sqlite);
      expect(sql.startsWith('BEGIN TRANSACTION;'), true);
      expect(sql.trimRight().endsWith('COMMIT;'), true);
    });

    test('MySQL: ไม่ห่อ (DDL ย้อนกลับไม่ได้) แต่ขึ้นคำเตือนให้สำรองข้อมูล', () {
      final sql = mig(Dialect.mysql);
      expect(sql, isNot(contains('BEGIN')));
      expect(sql, contains('ย้อนกลับไม่ได้'));
    });

    test('ไม่มีอะไรเปลี่ยน: ไม่สร้างสคริปต์ห่อทรานแซกชันเปล่า ๆ', () {
      final sql = generateMigration(base(Dialect.postgres), clone(base(Dialect.postgres)));
      expect(sql, isNot(contains('BEGIN')));
    });

    test('SQLite ที่ต้องสร้างตารางใหม่: ยังใช้รูปแบบเดิม (PRAGMA foreign_keys ปิด-เปิดรอบทรานแซกชัน)', () {
      final old = base(Dialect.sqlite);
      final neu = clone(old);
      cl(neu, 'tu', 'u4').type = DataType.text; // INTEGER -> TEXT เป็นการเปลี่ยนชนิดจริงใน SQLite (VARCHAR -> TEXT ไม่ใช่)
      final sql = generateMigration(old, neu);
      expect(sql.startsWith('PRAGMA foreign_keys = OFF;'), true);
      expect(sql, contains('PRAGMA foreign_key_check;'));
    });
  });

  group('รันบน SQLite จริง: migration + ข้อมูลตั้งต้น', () {
    late Database db;
    setUp(() => db = sqlite3.openInMemory());
    tearDown(() => db.close());

    int count(String t) => db.select('SELECT COUNT(*) AS n FROM "$t"').first['n'] as int;

    test('สร้างฐานจากเวอร์ชันเก่า -> migrate ไปเวอร์ชันใหม่ เพิ่มเฉพาะแถวใหม่ รันสคริปต์ซ้ำได้ ไม่ทับข้อมูลที่ผู้ใช้แก้', () {
      final old = proj(Dialect.sqlite, rows: [
        {'r1': '1', 'r2': 'admin', 'r3': 'Admin'}
      ]);
      db.execute(buildExportSql(old, includeSeed: true));
      db.execute("UPDATE roles SET label = 'ผู้ดูแลระบบ' WHERE id = 1"); // แก้ในฐานข้อมูลจริง
      db.execute("INSERT INTO roles (id, name) VALUES (50, 'custom')"); // ข้อมูลที่ผู้ใช้เพิ่มเอง

      final neu = Project.fromJson(old.toJson());
      neu.tableById('tr')!.seedRows = [
        {'r1': '1', 'r2': 'admin', 'r3': 'Admin (แก้ในโปรแกรม)'}, // แก้ในโปรแกรม แต่ต้องไม่ทับของจริง
        {'r1': '2', 'r2': 'user', 'r3': 'User'}, // ใหม่
      ];
      final script = generateMigration(old, neu);
      db.execute(script);
      db.execute(script); // รันซ้ำ
      db.execute(script);

      expect(count('roles'), 3); // 1, 2, 50
      expect(db.select('SELECT label FROM roles WHERE id = 1').first['label'], 'ผู้ดูแลระบบ'); // ไม่ถูกทับ
      expect(db.select('SELECT name FROM roles WHERE id = 50').first['name'], 'custom'); // ไม่ถูกลบ
      expect(db.select('SELECT name FROM roles WHERE id = 2').first['name'], 'user');
    });

    test('migration ที่ล้มเหลวกลางทาง: ย้อนกลับทั้งหมด (ทรานแซกชัน) ไม่ค้างโครงสร้างครึ่งทาง', () {
      final old = proj(Dialect.sqlite, rows: [
        {'r1': '1', 'r2': 'admin'}
      ]);
      db.execute(buildExportSql(old, includeSeed: true));
      final neu = Project.fromJson(old.toJson());
      neu.tableById('tr')!.columns.add(ColumnModel(id: 'r9', name: 'extra', type: DataType.varchar, length: 5));
      var script = generateMigration(old, neu);
      expect(script, contains('BEGIN TRANSACTION;'));
      // แทรกคำสั่งที่ผิดไว้ท้ายสุดก่อน COMMIT เพื่อจำลองความล้มเหลวกลางทาง
      script = script.replaceFirst(RegExp(r'COMMIT;\s*$'), 'THIS IS NOT SQL;\nCOMMIT;');
      expect(() => db.execute(script), throwsA(isA<SqliteException>()));
      db.execute('ROLLBACK');
      final cols = db.select('PRAGMA table_info(roles)').map((r) => r['name']).toList();
      expect(cols.contains('extra'), false); // ALTER ที่ทำไปแล้วถูกย้อนกลับ
    });
  });

  group('หน้าจอ', () {
    late ProjectController c;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(base(), null);
      c.selectTable('tu');
      await tester.pumpAndSettle();
    }

    Future<void> openSeed(WidgetTester tester) async {
      final btn = find.byKey(const ValueKey('seed-open'));
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pumpAndSettle();
    }

    testWidgets('แผงขวา: ปุ่มข้อมูลตั้งต้น เปิดหน้าต่าง เพิ่มแถว กรอกค่า บันทึก (AUTO INCREMENT ที่ว่าง = ไม่ระบุค่า)', (tester) async {
      await boot(tester);
      expect(find.text('เพิ่มข้อมูลตั้งต้น…'), findsOneWidget);
      await openSeed(tester);
      expect(find.byType(SeedDataDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('seed-add-row')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('seed-0-u2')), 'a@x.com');
      await tester.enterText(find.byKey(const ValueKey('seed-0-u3')), 'Alice');
      await tester.enterText(find.byKey(const ValueKey('seed-0-u4')), '30');
      await tester.pump();
      expect(find.byKey(const ValueKey('seed-problems')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('seed-save')));
      await tester.pumpAndSettle();

      final rows = tb(c.project, 'tu').seedRows;
      expect(rows.length, 1);
      expect(rows.single, {'u2': 'a@x.com', 'u3': 'Alice', 'u4': '30'}); // id (AI) ไม่ถูกใส่
      expect(find.text('1 แถว — แก้ไข…'), findsOneWidget);
      c.undo();
      expect(tb(c.project, 'tu').seedRows, isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('ค่าที่ไม่ถูกต้อง: ช่องแดงและมีข้อความจำนวนปัญหา; ยกเลิกแล้วข้อมูลไม่เปลี่ยน', (tester) async {
      await boot(tester);
      await openSeed(tester);
      await tester.tap(find.byKey(const ValueKey('seed-add-row')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('seed-0-u2')), 'a@x.com');
      await tester.enterText(find.byKey(const ValueKey('seed-0-u4')), 'not a number');
      await tester.pump();
      expect(find.byKey(const ValueKey('seed-problems')), findsOneWidget);
      expect(find.textContaining('พบ 1 ปัญหา'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').seedRows, isEmpty);
    });

    testWidgets('วาง CSV: จับคู่ตามหัวคอลัมน์และเพิ่มแถว', (tester) async {
      await boot(tester);
      await openSeed(tester);
      await tester.tap(find.byKey(const ValueKey('seed-paste-csv')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('csv-text')), 'email,name,age\nb@x.com,Bob,41\nc@x.com,Cy,');
      await tester.tap(find.byKey(const ValueKey('csv-ok')));
      await tester.pumpAndSettle();
      expect(find.textContaining('เพิ่ม 2 แถวจาก CSV'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('seed-save')));
      await tester.pumpAndSettle();
      final rows = tb(c.project, 'tu').seedRows;
      expect(rows.length, 2);
      expect(rows[0], {'u2': 'b@x.com', 'u3': 'Bob', 'u4': '41'});
      expect(rows[1]['u4'], isNull);
    });

    testWidgets('เปิดแก้ข้อมูลที่มีอยู่แล้ว: แสดงค่าเดิม ลบแถวได้', (tester) async {
      await boot(tester);
      c.setSeedRows('tu', [
        {'u2': 'a@x.com', 'u3': 'A', 'u4': '1'},
        {'u2': 'b@x.com', 'u3': 'B', 'u4': '2'},
      ]);
      await tester.pumpAndSettle();
      await openSeed(tester);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('seed-1-u2'))).controller!.text, 'b@x.com');
      await tester.tap(find.byKey(const ValueKey('seed-remove-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('seed-save')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').seedRows.map((r) => r['u2']), ['b@x.com']);
    });

    testWidgets('Export .sql: มีข้อมูลตั้งต้นที่ถูกต้อง = ถามว่าจะรวมหรือไม่ (ยกเลิกได้)', (tester) async {
      await boot(tester);
      c.setSeedRows('tu', [
        {'u2': 'a@x.com', 'u3': 'A', 'u4': '1'}
      ]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      // โปรเจกต์ทดสอบอาจมี error ของ schema ให้ถามก่อน: ข้ามด้วย "Export ต่อ"
      if (find.text('Export ต่อ').evaluate().isNotEmpty) {
        await tester.tap(find.text('Export ต่อ'));
        await tester.pumpAndSettle();
      }
      expect(find.text('รวมข้อมูลตั้งต้นใน SQL หรือไม่'), findsOneWidget);
      expect(find.textContaining('1 แถวใน 1 ตาราง'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.text('รวมข้อมูลตั้งต้นใน SQL หรือไม่'), findsNothing);
    });

    testWidgets('Export .sql: ข้อมูลตั้งต้นผิด = แจ้งปัญหาและให้เลือก Export โดยไม่รวม', (tester) async {
      await boot(tester);
      c.setSeedRows('tu', [
        {'u2': 'a@x.com', 'u3': 'A', 'u4': 'abc'}
      ]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      if (find.text('Export ต่อ').evaluate().isNotEmpty) {
        await tester.tap(find.text('Export ต่อ'));
        await tester.pumpAndSettle();
      }
      expect(find.text('ข้อมูลตั้งต้นมีปัญหา 1 รายการ'), findsOneWidget);
      expect(find.text('Export โดยไม่รวมข้อมูลตั้งต้น'), findsOneWidget);
      expect(find.textContaining('users #1'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
    });
  });

  group('ยืนยันก่อนคัดลอก/บันทึกสคริปต์ที่ข้อมูลอาจหาย', () {
    Future<void> open(WidgetTester tester, MigrationDialog dialog) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(onPressed: () => showDialog<void>(context: ctx, builder: (_) => dialog), child: const Text('open')),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    String? mockClipboard(WidgetTester tester) {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      return copied;
    }

    Project destructive(Project a) {
      final b = clone(a);
      tb(b, 'tu').columns.removeWhere((c) => c.id == 'u4'); // ลบคอลัมน์ age
      return b;
    }

    testWidgets('มีรายการอันตราย: คัดลอกต้องติ๊กยืนยันก่อน; ยกเลิก = ไม่คัดลอก', (tester) async {
      final a = base();
      await open(tester, MigrationDialog(old: a, neu: destructive(a), oldLabel: 'v1.erd'));
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.tap(find.text('คัดลอกสคริปต์'));
      await tester.pumpAndSettle();
      expect(find.text('สคริปต์นี้อาจทำให้ข้อมูลหาย'), findsOneWidget);
      expect(find.textContaining('users: ลบคอลัมน์ age'), findsWidgets);
      // ยังไม่ติ๊ก: ปุ่มดำเนินการต่อกดไม่ได้
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('risky-continue'))).onPressed, isNull);
      expect(copied, isNull);

      await tester.tap(find.text('ยกเลิก').last);
      await tester.pumpAndSettle();
      expect(copied, isNull); // ยกเลิก = ไม่คัดลอก

      await tester.tap(find.text('คัดลอกสคริปต์'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('risky-ack')));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('risky-continue'))).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('risky-continue')));
      await tester.pumpAndSettle();
      expect(copied, contains('DROP COLUMN'));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('ไม่มีรายการอันตราย: คัดลอกได้ทันที ไม่มีหน้ายืนยัน', (tester) async {
      final a = base();
      final b = clone(a);
      tb(b, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
      await open(tester, MigrationDialog(old: a, neu: b, oldLabel: 'v1.erd'));
      mockClipboard(tester);
      await tester.tap(find.text('คัดลอกสคริปต์'));
      await tester.pump();
      expect(find.text('สคริปต์นี้อาจทำให้ข้อมูลหาย'), findsNothing);
      expect(find.text('คัดลอกแล้ว ✓'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
