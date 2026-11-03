import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/parser/sql_decode.dart';
import 'package:nsl_modeler/core/parser/sql_importer.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/import_dialog.dart';

Uint8List utf16(String s, {required bool le, bool bom = true}) {
  final out = <int>[];
  if (bom) out.addAll(le ? [0xFF, 0xFE] : [0xFE, 0xFF]);
  for (final u in s.codeUnits) {
    out.addAll(le ? [u & 0xFF, u >> 8] : [u >> 8, u & 0xFF]);
  }
  return Uint8List.fromList(out);
}

void main() {
  group('decodeSqlBytes', () {
    const text = 'CREATE TABLE `ลูกค้า` (id INT); -- ไทย 😀';

    test('UTF-8 ไม่มี BOM / มี BOM', () {
      expect(decodeSqlBytes(Uint8List.fromList(utf8.encode(text))), text);
      expect(decodeSqlBytes(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)])), text);
    });

    test('UTF-16 LE / BE (SSMS) รวม emoji ที่เป็น surrogate pair', () {
      expect(decodeSqlBytes(utf16(text, le: true)), text);
      expect(decodeSqlBytes(utf16(text, le: false)), text);
    });

    test('ไบต์เสียไม่ทำให้ทั้งไฟล์พัง', () {
      final s = decodeSqlBytes(Uint8List.fromList([...utf8.encode('abc'), 0xFF, 0xC3, ...utf8.encode('xyz')]));
      expect(s.startsWith('abc'), true);
      expect(s.endsWith('xyz'), true);
    });

    test('ไฟล์ว่าง', () {
      expect(decodeSqlBytes(Uint8List(0)), '');
    });

    test('ไฟล์ UTF-16 ของ SSMS import ได้จริงตั้งแต่ไบต์ถึงโมเดล', () {
      final sql = 'CREATE TABLE [dbo].[ผู้ใช้] ([Id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY)\r\nGO\r\n';
      final r = importSql(decodeSqlBytes(utf16(sql, le: true)));
      expect(r.project.tables.single.name, 'ผู้ใช้');
      expect(r.project.tables.single.columns.single.autoIncrement, true);
    });
  });

  group('ProjectController.loadImported', () {
    test('ถือว่ายังไม่บันทึก ไม่มีไฟล์ และล้างประวัติ', () {
      final c = ProjectController();
      c.addTable();
      final r = importSql('CREATE TABLE a (id INT PRIMARY KEY);');
      c.loadImported(r.project);
      expect(c.dirty, true);
      expect(c.filePath, isNull);
      expect(c.canUndo, false);
      expect(c.project.tables.single.name, 'a');
      expect(c.issues.where((i) => i.code == 'no_pk'), isEmpty);
    });
  });

  group('ImportPreviewDialog', () {
    Future<bool?> open(WidgetTester tester, String sql) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => popped = await showDialog<bool>(
                context: ctx,
                builder: (_) => ImportPreviewDialog(result: importSql(sql), fileName: 'x.sql'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    testWidgets('สรุปจำนวน + ปุ่มนำเข้าคืน true', (tester) async {
      bool? result;
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showDialog<bool>(
                context: ctx,
                builder: (_) => ImportPreviewDialog(
                  result: importSql('''
CREATE TABLE a (id INT PRIMARY KEY);
CREATE TABLE b (id INT PRIMARY KEY, a_id INT REFERENCES a(id), g GEOMETRY);
INSERT INTO a VALUES (1);
'''),
                  fileName: 'shop.sql',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('นำเข้า shop.sql'), findsOneWidget);
      expect(find.textContaining('2 ตาราง · 4 คอลัมน์ · 1 ความสัมพันธ์ FK'), findsOneWidget);
      expect(find.textContaining('GEOMETRY'), findsOneWidget); // คำเตือนชนิดที่ไม่รู้จัก
      expect(find.textContaining('INSERT'), findsOneWidget); // ข้อมูลเพิ่มเติม

      await tester.tap(find.widgetWithText(FilledButton, 'นำเข้า'));
      await tester.pumpAndSettle();
      expect(result, true);
    });

    testWidgets('ไม่พบตาราง: ปุ่มนำเข้ากดไม่ได้ ยกเลิกคืน false', (tester) async {
      await open(tester, 'SELECT 1;');
      expect(find.text('ไม่พบ CREATE TABLE ในไฟล์นี้'), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'นำเข้า'));
      expect(btn.onPressed, isNull);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportPreviewDialog), findsNothing);
    });
  });
}
