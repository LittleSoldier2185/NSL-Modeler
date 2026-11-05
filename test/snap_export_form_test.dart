import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/svg_export.dart';
import 'package:nsl_dev/core/layout/diagram_geometry.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_controller.dart';
import 'package:nsl_dev/ui/create_table_dialog.dart';
import 'package:nsl_dev/ui/export/export_image_dialog.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  late ProjectController c;
  late CanvasController cv;
  late AppSettings settings;

  Future<void> boot(WidgetTester tester, {bool snap = true}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = AppSettings(lang: Lang.th, snapToGrid: snap);
    await tester.pumpWidget(NslDevApp(settings: settings));
    final ctx = tester.element(find.byType(HomePage));
    c = ctx.read<ProjectController>();
    cv = ctx.read<CanvasController>();
    c.loadProject(base(), null);
    tb(c.project, 'tu')
      ..x = 40
      ..y = 60;
    tb(c.project, 'to')
      ..x = 400
      ..y = 60;
    await tester.pump();
  }

  Offset header(WidgetTester tester, String id) =>
      tester.getTopLeft(find.byKey(ValueKey('table-$id'))) + const Offset(60, 16);

  group('คีย์ลัด S = โหมดเลือก', () {
    testWidgets('กด S จากเครื่องมืออื่นกลับเป็นโหมดเลือก', (tester) async {
      await boot(tester);
      cv.setTool(CanvasTool.table);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(cv.tool, CanvasTool.select);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      expect(cv.tool, CanvasTool.fk);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      expect(cv.tool, CanvasTool.select);
    });
  });

  group('Alt+Z = ทำซ้ำ (Redo)', () {
    testWidgets('ย้อนกลับด้วย Ctrl+Z แล้ว Alt+Z ทำซ้ำได้ เหมือน Ctrl+Y', (tester) async {
      await boot(tester);
      final before = c.project.tables.length;
      c.addTable(name: 'extra');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.project.tables.length, before);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(c.project.tables.length, before + 1);
      expect(c.canRedo, false);
    });

    testWidgets('Ctrl+Shift+Z ทำซ้ำได้ (แบบ Adobe)', (tester) async {
      await boot(tester);
      final before = c.project.tables.length;
      c.addTable(name: 'extra');
      c.undo();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.project.tables.length, before + 1);
    });

    testWidgets('Ctrl+Y ยังทำซ้ำได้เหมือนเดิม', (tester) async {
      await boot(tester);
      final before = c.project.tables.length;
      c.addTable(name: 'extra');
      c.undo();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.project.tables.length, before + 1);
    });

    testWidgets('Alt+Z ไม่ทำงานขณะพิมพ์ในช่องข้อความ (ปล่อยให้ช่องข้อความจัดการเอง) แต่รายการแสดงใน F1', (tester) async {
      await boot(tester);
      c.addTable(name: 'extra');
      c.undo();
      cv.searchFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(c.canRedo, true); // ไม่ถูก redo ระหว่างพิมพ์
    });
  });

  group('snap to grid', () {
    test('moveSelectedBy(grid) ปัดเข้าช่องโดยคิดจากตำแหน่งเริ่ม + ระยะสะสม (ไม่คลาดเคลื่อนสะสม)', () {
      final c = ProjectController(base());
      tb(c.project, 'tu')
        ..x = 40
        ..y = 60;
      tb(c.project, 'to')
        ..x = 400
        ..y = 60;
      c.selectTable('tu');
      c.beginGesture();
      for (var i = 0; i < 3; i++) {
        c.moveSelectedBy(7, 0, grid: 20); // รวม 21 -> ปัดเป็น +20
      }
      expect(tb(c.project, 'tu').x, 60);
      expect(tb(c.project, 'tu').y, 60);
      c.moveSelectedBy(0, 11, grid: 20); // y +11 -> 71 -> 80
      expect(tb(c.project, 'tu').y, 80);
      c.endGesture();
      c.undo();
      expect(tb(c.project, 'tu').x, 40); // ทั้งการลากเป็น undo ขั้นเดียว
    });

    test('ลากทั้งกลุ่ม: ทุกตัวเลื่อนเท่ากัน รักษาระยะห่างสัมพัทธ์เดิม', () {
      final c = ProjectController(base());
      tb(c.project, 'tu')
        ..x = 43 // ไม่ตรงช่องอยู่แล้ว
        ..y = 61;
      tb(c.project, 'to')
        ..x = 400
        ..y = 100;
      c.selectAllTables();
      final gapX = tb(c.project, 'to').x - tb(c.project, 'tu').x;
      final gapY = tb(c.project, 'to').y - tb(c.project, 'tu').y;
      c.beginGesture();
      c.moveSelectedBy(33, 27, grid: 20);
      c.endGesture();
      expect(tb(c.project, 'to').x - tb(c.project, 'tu').x, gapX);
      expect(tb(c.project, 'to').y - tb(c.project, 'tu').y, gapY);
      expect(tb(c.project, 'tu').x % 20, 0); // ตัวอ้างอิงลงช่อง
      expect(tb(c.project, 'tu').y % 20, 0);
    });

    test('ไม่ส่ง grid = ทำงานเหมือนเดิม (ย้ายตามจริง)', () {
      final c = ProjectController(base());
      tb(c.project, 'tu')
        ..x = 40
        ..y = 60;
      c.selectTable('tu');
      c.moveSelectedBy(7, 3);
      expect((tb(c.project, 'tu').x, tb(c.project, 'tu').y), (47.0, 63.0));
    });

    test('snapToGrid ปัดเข้าช่องที่ใกล้ที่สุด รวมค่าติดลบ', () {
      expect(snapToGrid(29), 20);
      expect(snapToGrid(31), 40);
      expect(snapToGrid(-9), -0.0);
      expect(snapToGrid(-11), -20);
    });

    testWidgets('ลากตารางด้วยเมาส์: ตำแหน่งลงช่อง 20px', (tester) async {
      await boot(tester);
      await tester.dragFrom(header(tester, 'tu'), const Offset(37, 23));
      await tester.pump();
      expect(tb(c.project, 'tu').x % 20, 0);
      expect(tb(c.project, 'tu').y % 20, 0);
      // ลากได้จริง ~37 px หักระยะ slop ของท่าทาง แล้วปัดลงช่อง
      expect(tb(c.project, 'tu').x, isIn([60.0, 80.0]));
    });

    testWidgets('กด Alt ค้างตอนลาก = ข้าม snap ชั่วคราว', (tester) async {
      await boot(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.dragFrom(header(tester, 'tu'), const Offset(37, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(tb(c.project, 'tu').x, greaterThan(40)); // ขยับจริง
      expect(tb(c.project, 'tu').x % 20, isNot(0)); // แต่ไม่ถูกปัดเข้าช่อง
    });

    testWidgets('ปิด snap ในการตั้งค่า = ลากอิสระ', (tester) async {
      await boot(tester, snap: false);
      await tester.dragFrom(header(tester, 'tu'), const Offset(37, 0));
      await tester.pump();
      expect(tb(c.project, 'tu').x % 20, isNot(0));
    });

    testWidgets('คลิกวางตารางใหม่ด้วยเครื่องมือตาราง: ลงช่อง', (tester) async {
      await boot(tester);
      cv.setTool(CanvasTool.table);
      await tester.pump();
      await tester.tapAt(const Offset(731, 413));
      await tester.pump();
      final t = c.project.tables.last;
      expect(t.x % 20, 0);
      expect(t.y % 20, 0);
    });

    testWidgets('ปุ่มบนแถบซูมสลับ snap และเก็บลงการตั้งค่า', (tester) async {
      await boot(tester);
      expect(settings.snapToGrid, true);
      await tester.tap(find.byKey(const ValueKey('snap-toggle')));
      await tester.pump();
      expect(settings.snapToGrid, false);
      await tester.tap(find.byKey(const ValueKey('snap-toggle')));
      await tester.pump();
      expect(settings.snapToGrid, true);
    });
  });

  group('ตัวเลือกพื้นที่ export ภาพ', () {
    test('exportSvg: ปกติตัดเฉพาะส่วนที่มีตาราง; ส่ง bounds = ทั้งกระดาน', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 400
        ..y = 60;
      double width(String svg) => double.parse(RegExp(r'<svg[^>]*\swidth="([\d.]+)"').firstMatch(svg)!.group(1)!);
      final content = exportSvg(p)!;
      final board = exportSvg(p, bounds: boardBounds(p))!;
      expect(width(content), lessThan(width(board)));
      expect(width(board), boardBounds(p).width);
    });

    testWidgets('dialog: ค่าเริ่มต้น = เฉพาะส่วนที่มีตาราง; เลือกทั้งกระดานได้', (tester) async {
      ImageExportOptions? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await showDialog<ImageExportOptions>(
                context: ctx, builder: (_) => const ExportImageDialog(hasNotes: false, hasSelection: true)),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('เฉพาะส่วนที่มีตาราง'), findsOneWidget);
      expect(find.text('ทั้งกระดาน'), findsOneWidget);
      expect(find.text('เฉพาะที่เลือก'), findsOneWidget); // เพราะมีตารางที่เลือกอยู่

      await tester.tap(find.text('ทั้งกระดาน'));
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(result!.area, ImageArea.board);
    });

    testWidgets('dialog: ไม่มีตารางที่เลือก = ไม่มีตัวเลือก "เฉพาะที่เลือก" และค่าเริ่มต้นคือ content', (tester) async {
      ImageExportOptions? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result =
                await showDialog<ImageExportOptions>(context: ctx, builder: (_) => const ExportImageDialog(hasNotes: false)),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('เฉพาะที่เลือก'), findsNothing);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(result!.area, ImageArea.content);
    });
  });

  group('สร้างตารางแบบฟอร์ม (phpMyAdmin)', () {
    test('validateLengthText', () {
      expect(validateLengthText(DataType.varchar, ''), isNull);
      expect(validateLengthText(DataType.varchar, '100'), isNull);
      expect(validateLengthText(DataType.varchar, '0'), isNotNull);
      expect(validateLengthText(DataType.varchar, 'abc'), isNotNull);
      expect(validateLengthText(DataType.decimal, '10,2'), isNull);
      expect(validateLengthText(DataType.decimal, '10'), isNull);
      expect(validateLengthText(DataType.decimal, '2,10'), isNotNull); // scale > precision
      expect(validateLengthText(DataType.decimal, '1,2,3'), isNotNull);
      expect(validateLengthText(DataType.integer, 'whatever'), isNull); // ไม่ใช้ความยาว
    });

    test('buildTableFromDrafts: PK ผสม / UNIQUE / INDEX / default / decimal / null', () {
      var n = 0;
      String id(String p) => '$p${n++}';
      final drafts = [
        ColumnDraft(name: 'order_id', allowNull: true, index: ColumnIndex.primary),
        ColumnDraft(name: 'line_no', index: ColumnIndex.primary),
        ColumnDraft(name: 'sku', type: DataType.varchar, length: '40', index: ColumnIndex.unique, allowNull: false),
        ColumnDraft(name: 'price', type: DataType.decimal, length: '10,2', defaultValue: '0', index: ColumnIndex.plain),
        ColumnDraft(name: 'note', type: DataType.text, comment: 'ข้อความ'),
      ];
      final t = buildTableFromDrafts(newId: id, name: '  order_lines ', comment: ' รายการ ', drafts: drafts);
      expect(t.name, 'order_lines');
      expect(t.comment, 'รายการ');
      expect(t.columns.where((x) => x.isPrimaryKey).map((x) => x.name), ['order_id', 'line_no']);
      expect(t.columns[0].notNull, true); // PRIMARY บังคับ NOT NULL
      final sku = t.columns[2];
      expect((sku.length, sku.unique, sku.notNull), (40, true, true));
      final price = t.columns[3];
      expect((price.length, price.scale, price.defaultValue), (10, 2, '0'));
      expect(t.columns[4].defaultValue, isNull);
      expect(t.columns[4].comment, 'ข้อความ');
      expect(t.indexes.length, 1);
      expect(t.indexes.single.columnIds, [price.id]);
      expect(t.indexes.single.unique, false);
    });

    Future<void> openForm(WidgetTester tester) async {
      await boot(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+Shift+T เปิดฟอร์ม: แถวแรกเป็น id INT PRIMARY A_I และมี 4 แถวตามค่าเริ่มต้น', (tester) async {
      await openForm(tester);
      expect(find.byType(CreateTableDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('ct-name-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('ct-name-4')), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('ct-name-0'))).controller!.text, 'id');
      // ยังไม่ได้ตั้งชื่อตาราง -> สร้างไม่ได้
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ct-save'))).onPressed, isNull);
    });

    testWidgets('กรอกฟอร์มแล้วสร้าง = ตารางใหม่ครบทุกคอลัมน์ undo ขั้นเดียว และถูกเลือก', (tester) async {
      await openForm(tester);
      final before = c.project.tables.length;
      await tester.enterText(find.byKey(const ValueKey('ct-table-name')), 'customers');
      await tester.enterText(find.byKey(const ValueKey('ct-name-1')), 'email');
      await tester.enterText(find.byKey(const ValueKey('ct-name-2')), 'age');
      await tester.enterText(find.byKey(const ValueKey('ct-name-3')), 'bio');
      // email: VARCHAR(120) UNIQUE NOT NULL
      await tester.tap(find.byKey(const ValueKey('ct-type-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VARCHAR').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ct-len-1')), '120');
      await tester.tap(find.byKey(const ValueKey('ct-index-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UNIQUE').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ct-null-1'))); // เอา Null ออก = NOT NULL
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('ct-save')));
      await tester.pumpAndSettle();

      expect(find.byType(CreateTableDialog), findsNothing);
      expect(c.project.tables.length, before + 1);
      final t = c.project.tables.last;
      expect(t.name, 'customers');
      expect(t.columns.map((x) => x.name), ['id', 'email', 'age', 'bio']);
      expect(t.columns[0].isPrimaryKey && t.columns[0].autoIncrement && t.columns[0].notNull, true);
      final email = t.columns[1];
      expect((email.type, email.length, email.unique, email.notNull), (DataType.varchar, 120, true, true));
      expect(c.selectedTableId, t.id);
      c.undo();
      expect(c.project.tables.length, before);
    });

    testWidgets('ชื่อคอลัมน์ซ้ำ / ความยาวผิด = แจ้งและกดสร้างไม่ได้', (tester) async {
      await openForm(tester);
      await tester.enterText(find.byKey(const ValueKey('ct-table-name')), 'x');
      await tester.enterText(find.byKey(const ValueKey('ct-name-1')), 'a');
      await tester.enterText(find.byKey(const ValueKey('ct-name-2')), 'A'); // ซ้ำแบบไม่สนตัวพิมพ์
      await tester.enterText(find.byKey(const ValueKey('ct-name-3')), 'c');
      await tester.pump();
      expect(find.text('ชื่อซ้ำ'), findsNWidgets(2));
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ct-save'))).onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('ct-name-2')), 'b');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ct-save'))).onPressed, isNotNull);

      // varchar ความยาวผิด
      await tester.tap(find.byKey(const ValueKey('ct-type-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VARCHAR').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ct-len-2')), '0');
      await tester.pump();
      expect(find.textContaining('ความยาวต้องเป็นจำนวนเต็ม'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ct-save'))).onPressed, isNull);
    });

    testWidgets('จำนวนคอลัมน์: เพิ่ม/ลดแถวได้ ข้อมูลแถวที่เหลือไม่หาย; ปุ่มลบแถวและเพิ่มคอลัมน์ทำงาน', (tester) async {
      await openForm(tester);
      await tester.enterText(find.byKey(const ValueKey('ct-name-1')), 'keep_me');
      await tester.enterText(find.byKey(const ValueKey('ct-count')), '7');
      await tester.tap(find.byKey(const ValueKey('ct-apply-count')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ct-name-6')), findsOneWidget);
      expect(find.byKey(const ValueKey('ct-name-7')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('ct-count')), '2');
      await tester.tap(find.byKey(const ValueKey('ct-apply-count')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ct-name-2')), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('ct-name-1'))).controller!.text, 'keep_me');

      await tester.tap(find.byKey(const ValueKey('ct-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ct-name-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ct-remove-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ct-name-2')), findsNothing);
    });

    testWidgets('ชื่อตารางซ้ำกับของเดิม: สร้างได้โดยต่อท้ายเลขให้ ไม่ทับของเดิม', (tester) async {
      await openForm(tester);
      await tester.enterText(find.byKey(const ValueKey('ct-table-name')), 'users');
      await tester.enterText(find.byKey(const ValueKey('ct-count')), '1');
      await tester.tap(find.byKey(const ValueKey('ct-apply-count')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ct-save')));
      await tester.pumpAndSettle();
      final names = c.project.tables.map((t) => t.name).toList();
      expect(names.where((n) => n == 'users').length, 1);
      expect(names.last, isNot('users'));
      expect(names.last, startsWith('users'));
    });

    testWidgets('ยกเลิก = ไม่เพิ่มตาราง', (tester) async {
      await openForm(tester);
      final before = c.project.tables.length;
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(c.project.tables.length, before);
    });
  });
}
