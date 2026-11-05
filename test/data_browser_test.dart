import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/db/data_access.dart';
import 'package:nsl_dev/core/db/sqlite_data.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/ui/data_browser_dialog.dart';
import 'package:sqlite3/sqlite3.dart';

/// หน้าเปิดดู/แก้ข้อมูล ทดสอบกับไฟล์ SQLite จริง
void main() {
  late Directory dir;
  late String path;
  final opened = <DataSession>[];

  setUp(() {
    currentLang = Lang.th;
    dir = Directory.systemTemp.createTempSync('nsl_browser');
    path = '${dir.path}/shop.db';
    final db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE, name TEXT);
      CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);
      INSERT INTO users (email, name) VALUES ('a@x.com', 'Ann'), ('b@x.com', 'Bob'), ('c@x.com', NULL);
      INSERT INTO notes (body) VALUES ('n1');
    ''');
    // ตารางใหญ่สำหรับแบ่งหน้า
    db.execute('CREATE TABLE big (id INTEGER PRIMARY KEY, v TEXT)');
    db.execute('BEGIN');
    for (var i = 1; i <= 250; i++) {
      db.execute('INSERT INTO big (v) VALUES (?)', ['row$i']);
    }
    db.execute('COMMIT');
    db.close();
  });

  tearDown(() async {
    for (final s in opened) {
      await s.close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showDataBrowser(ctx, title: 'shop.db', opener: (w) async {
              final s = SqliteDataSession.open(path, writable: w);
              opened.add(s);
              return s;
            }),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// คลิกสองครั้งติดกัน = double tap
  Future<void> doubleTap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> enableEdit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('edit-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-mode-ok')));
    await tester.pumpAndSettle();
  }

  String dbValue(String sql) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    final v = db.select(sql).first.values.first.toString();
    db.close();
    return v;
  }

  testWidgets('เปิดแล้วเห็นรายการตารางและข้อมูลของตารางแรก ; NULL แสดงเป็น NULL', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('data-table-users')), findsOneWidget);
    expect(find.byKey(const ValueKey('data-table-big')), findsOneWidget);
    // ตารางแรกตามตัวอักษรคือ big
    expect(find.text('1–100 / 250'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('data-table-users')));
    await tester.pumpAndSettle();
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('a@x.com'), findsOneWidget);
    expect(find.text('NULL'), findsOneWidget);
    expect(find.text('1–3 / 3'), findsOneWidget);
  });

  testWidgets('โหมดดูอย่างเดียว : ไม่มีปุ่มเพิ่ม/ลบ/บันทึก และดับเบิลคลิกเซลล์ไม่เปิดตัวแก้', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('data-table-users')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('data-add')), findsNothing);
    expect(find.byKey(const ValueKey('data-save')), findsNothing);
    await doubleTap(tester, find.byKey(const ValueKey('cell-1-name')));
    expect(find.byKey(const ValueKey('cell-value')), findsNothing);
    expect(opened.last.writable, false);
  });

  testWidgets('แบ่งหน้า / เรียง / ค้นหา', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('data-next')));
    await tester.pumpAndSettle();
    expect(find.text('101–200 / 250'), findsOneWidget);
    expect(find.text('row101'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('data-next')));
    await tester.pumpAndSettle();
    expect(find.text('201–250 / 250'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('data-next'))).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('data-search')), 'row25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('1–2 / 2'), findsOneWidget); // row25, row250
    expect(find.text('row250'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('data-search')), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('data-head-v')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('data-head-v'))); // เรียงมากไปน้อย
    await tester.pumpAndSettle();
    expect(find.text('row99'), findsOneWidget); // row99 > row98... ตามตัวอักษร
  });

  testWidgets('แก้เซลล์ : เตรียมไว้ก่อน (ยังไม่แตะฐานข้อมูล) > บันทึก > ยืนยันเห็นคำสั่ง > เขียนจริง + ไฟล์สำรอง', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('data-table-users')));
    await tester.pumpAndSettle();
    await enableEdit(tester);
    expect(opened.last.writable, true);

    await doubleTap(tester, find.byKey(const ValueKey('cell-1-name')));
    await tester.enterText(find.byKey(const ValueKey('cell-value')), 'Annie');
    await tester.tap(find.byKey(const ValueKey('cell-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Annie'), findsOneWidget);
    expect(dbValue('SELECT name FROM users WHERE id = 1'), 'Ann'); // ยังไม่ถูกเขียน

    await tester.tap(find.byKey(const ValueKey('data-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-confirm')), findsOneWidget);
    expect(find.textContaining('UPDATE "users" SET "name" = \'Annie\' WHERE "id" = \'1\''), findsOneWidget);
    expect(dbValue('SELECT name FROM users WHERE id = 1'), 'Ann'); // ดูคำสั่งอยู่ ยังไม่เขียน

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('save-ok')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    expect(dbValue('SELECT name FROM users WHERE id = 1'), 'Annie');
    expect(find.byKey(const ValueKey('data-save')), findsNothing); // ไม่มีค้างแล้ว
    expect(find.textContaining('.bak-'), findsOneWidget);
    expect(dir.listSync().whereType<File>().where((f) => f.path.contains('.bak-')).length, 1);
  });

  testWidgets('ตั้งเป็น NULL ได้ แต่คอลัมน์ NOT NULL ไม่มีตัวเลือก NULL ; แก้กลับเป็นค่าเดิม = ไม่นับ', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('data-table-users')));
    await tester.pumpAndSettle();
    await enableEdit(tester);

    await doubleTap(tester, find.byKey(const ValueKey('cell-1-email')));
    expect(find.byKey(const ValueKey('cell-null')), findsNothing); // email NOT NULL
    await tester.tap(find.text('ยกเลิก').last);
    await tester.pumpAndSettle();

    await doubleTap(tester, find.byKey(const ValueKey('cell-1-name')));
    await tester.tap(find.byKey(const ValueKey('cell-null')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cell-ok')));
    await tester.pumpAndSettle();
    expect(find.text('บันทึก (1)'), findsOneWidget);

    await doubleTap(tester, find.byKey(const ValueKey('cell-1-name')));
    await tester.tap(find.byKey(const ValueKey('cell-null'))); // เอา NULL ออก
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('cell-value')), 'Ann'); // เท่าค่าเดิม
    await tester.tap(find.byKey(const ValueKey('cell-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('data-save')), findsNothing);
  });

  testWidgets('ลบแถว (ขีดฆ่าก่อน กดซ้ำเพื่อยกเลิกได้) และเพิ่มแถวใหม่ ในชุดเดียวกัน', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('data-table-notes')));
    await tester.pumpAndSettle();
    await enableEdit(tester);

    await tester.tap(find.byKey(const ValueKey('data-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ins-body')), 'new note');
    await tester.tap(find.byKey(const ValueKey('ins-ok')));
    await tester.pumpAndSettle();
    expect(find.text('new note'), findsOneWidget);
    expect(find.text('(ค่าเริ่มต้น)'), findsOneWidget); // id ปล่อยให้ฐานข้อมูลใส่เอง

    final del = find.byKey(ValueKey('data-del-${'[["id","1"]]'}'));
    await tester.tap(del);
    await tester.pump();
    await tester.tap(del); // ยกเลิกการลบ
    await tester.pump();
    await tester.tap(del);
    await tester.pump();
    expect(find.text('บันทึก (2)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('data-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('INSERT INTO "notes" ("body") VALUES (\'new note\')'), findsOneWidget);
    expect(find.textContaining('DELETE FROM "notes" WHERE "id" = \'1\''), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('save-ok')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    expect(dbValue('SELECT count(*) FROM notes'), '1');
    expect(dbValue('SELECT body FROM notes'), 'new note');
  });

  testWidgets('บันทึกไม่ผ่าน (UNIQUE ซ้ำ) = แสดงข้อผิดพลาด ฐานข้อมูลไม่เปลี่ยน และยังเก็บที่เตรียมไว้ให้แก้ต่อ', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('data-table-users')));
    await tester.pumpAndSettle();
    await enableEdit(tester);
    await doubleTap(tester, find.byKey(const ValueKey('cell-2-email')));
    await tester.enterText(find.byKey(const ValueKey('cell-value')), 'a@x.com'); // ซ้ำกับแถว 1
    await tester.tap(find.byKey(const ValueKey('cell-ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('data-save')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('save-ok')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('data-error')), findsOneWidget);
    expect(find.textContaining('ยกเลิกทั้งหมดแล้ว'), findsOneWidget);
    expect(dbValue("SELECT email FROM users WHERE id = 2"), 'b@x.com');
    expect(find.text('บันทึก (1)'), findsOneWidget);
  });

  testWidgets('มีที่เตรียมไว้แล้วเปลี่ยนตาราง/ปิด = ถามก่อนทิ้ง ; ทิ้งแล้วไม่เหลือค้าง ; ปิดโหมดแก้ไขกลับเป็นอ่านอย่างเดียวจริง', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('data-table-users')));
    await tester.pumpAndSettle();
    await enableEdit(tester);
    await doubleTap(tester, find.byKey(const ValueKey('cell-1-name')));
    await tester.enterText(find.byKey(const ValueKey('cell-value')), 'X');
    await tester.tap(find.byKey(const ValueKey('cell-ok')));
    await tester.pumpAndSettle();

    // เปลี่ยนตาราง -> ถาม -> กลับไปแก้ต่อ
    await tester.tap(find.byKey(const ValueKey('data-table-notes')));
    await tester.pumpAndSettle();
    expect(find.text('ทิ้งการแก้ไขที่ยังไม่บันทึก?'), findsOneWidget);
    await tester.tap(find.text('กลับไปแก้ต่อ'));
    await tester.pumpAndSettle();
    expect(find.text('X'), findsOneWidget);

    // ปิดโหมดแก้ไข -> ถาม -> ทิ้ง -> เซสชันใหม่เขียนไม่ได้
    await tester.tap(find.byKey(const ValueKey('edit-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discard-ok')));
    await tester.pumpAndSettle();
    expect(opened.last.writable, false);
    expect(find.byKey(const ValueKey('data-save')), findsNothing);
    expect(find.text('Ann'), findsOneWidget);
    expect(dbValue('SELECT name FROM users WHERE id = 1'), 'Ann');
  });
}
