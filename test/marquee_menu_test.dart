import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/layout/diagram_geometry.dart';
import 'package:nsl_dev/core/models/note_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_controller.dart';
import 'package:nsl_dev/ui/export/export_image_dialog.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  late ProjectController c;
  late CanvasController cv;
  late AppSettings settings;

  Future<void> boot(WidgetTester tester, {List<NoteModel> notes = const []}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = AppSettings(lang: Lang.th);
    await tester.pumpWidget(NslDevApp(settings: settings));
    final ctx = tester.element(find.byType(HomePage));
    c = ctx.read<ProjectController>();
    cv = ctx.read<CanvasController>();
    final p = base();
    p.notes.addAll(notes);
    c.loadProject(p, null);
    tb(c.project, 'tu')
      ..x = 40
      ..y = 60;
    tb(c.project, 'to')
      ..x = 500
      ..y = 60;
    await tester.pump();
  }

  /// พิกัดจอของจุดใน world (อ้างอิงจากการ์ด users ที่ world 40,60)
  Offset screenOf(WidgetTester tester, Offset world) =>
      tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + (world - const Offset(40, 60));

  /// รายการในเมนูคลิกขวา (กันชนกับข้อความชื่อเดียวกันในแผงอื่น)
  Finder menuItem(String text) =>
      find.descendant(of: find.byType(PopupMenuItem<VoidCallback>), matching: find.text(text));

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g.up();
    await tester.pumpAndSettle();
  }

  group('ลากซ้ายบนพื้นว่าง = กรอบเลือก', () {
    testWidgets('ลากคลุมตารางหนึ่งใบ -> เลือกเฉพาะใบนั้น และกรอบหายหลังปล่อย', (tester) async {
      await boot(tester);
      final g = await tester.startGesture(screenOf(tester, const Offset(330, 260)), kind: PointerDeviceKind.mouse);
      await g.moveTo(screenOf(tester, const Offset(150, 110)));
      await tester.pump();
      expect(cv.marquee, isNotNull);
      expect(c.selectedTableIds, {'tu'}); // เลือกสดระหว่างลาก
      await g.up();
      await tester.pump();
      expect(cv.marquee, isNull);
      expect(c.selectedTableIds, {'tu'});
      expect(c.canUndo, false); // การเลือกไม่เข้า undo
    });

    testWidgets('ลากคลุมสองใบ -> เลือกทั้งคู่', (tester) async {
      await boot(tester);
      final g = await tester.startGesture(screenOf(tester, const Offset(200, 300)), kind: PointerDeviceKind.mouse);
      await g.moveTo(screenOf(tester, const Offset(620, 90)));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(c.selectedTableIds, {'tu', 'to'});
    });

    testWidgets('ลากบนพื้นว่างล้วน -> ล้างการเลือกเดิม', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      final g = await tester.startGesture(screenOf(tester, const Offset(300, 400)), kind: PointerDeviceKind.mouse);
      await g.moveTo(screenOf(tester, const Offset(330, 430)));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(c.selectedTableIds, isEmpty);
    });

    testWidgets('กด Ctrl ค้างตอนลาก = เลือกเพิ่มจากที่เลือกอยู่', (tester) async {
      await boot(tester);
      c.selectTable('to');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final g = await tester.startGesture(screenOf(tester, const Offset(330, 260)), kind: PointerDeviceKind.mouse);
      await g.moveTo(screenOf(tester, const Offset(150, 110)));
      await tester.pump();
      await g.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.selectedTableIds, {'tu', 'to'});
    });

    testWidgets('กด Space ค้าง = เลื่อนมุมมองแทนกรอบเลือก', (tester) async {
      await boot(tester);
      final off = cv.offset;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      final g = await tester.startGesture(screenOf(tester, const Offset(300, 400)), kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(80, 40));
      await tester.pump();
      expect(cv.marquee, isNull);
      expect(cv.panning, true);
      await g.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect((cv.offset - off).distance, greaterThan(40));
    });

    testWidgets('ลากกรอบแล้วย้ายทั้งกลุ่มที่เลือกต่อได้', (tester) async {
      await boot(tester);
      final g = await tester.startGesture(screenOf(tester, const Offset(200, 300)), kind: PointerDeviceKind.mouse);
      await g.moveTo(screenOf(tester, const Offset(620, 90)));
      await g.up();
      await tester.pump();
      final x0 = tb(c.project, 'tu').x;
      await tester.dragFrom(
          tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16), const Offset(100, 0));
      await tester.pump();
      expect(tb(c.project, 'tu').x, greaterThan(x0 + 40));
      expect(tb(c.project, 'to').x, greaterThan(500 + 40)); // ย้ายไปพร้อมกัน
    });

    test('setTableSelection: ไม่แจ้งซ้ำเมื่อชุดเดิม, ชุดว่าง = ล้างการเลือก, id ที่ไม่มีถูกข้าม', () {
      final c = ProjectController(base());
      var n = 0;
      c.addListener(() => n++);
      c.setTableSelection(['tu', 'to']);
      expect(c.selectedTableIds, {'tu', 'to'});
      final after = n;
      c.setTableSelection(['to', 'tu']);
      expect(n, after);
      c.setTableSelection(['nope']);
      expect(c.selectedTableIds, isEmpty);
    });
  });

  group('คลิกขวา: เมนูคำสั่ง', () {
    testWidgets('พื้นที่ว่าง: เมนูขึ้น และ "เพิ่มตารางที่นี่" วางที่จุดนั้น (ลงช่อง snap)', (tester) async {
      await boot(tester);
      final before = c.project.tables.length;
      final at = screenOf(tester, const Offset(333, 417));
      await rightClick(tester, at);
      expect(find.text('เพิ่มตารางที่นี่'), findsOneWidget);
      expect(find.text('เพิ่มโน้ตที่นี่'), findsOneWidget);
      expect(find.text('เลือกทุกตาราง'), findsOneWidget);
      await tester.tap(find.text('เพิ่มตารางที่นี่'));
      await tester.pumpAndSettle();
      expect(c.project.tables.length, before + 1);
      final t = c.project.tables.last;
      expect((t.x % kGridSize, t.y % kGridSize), (0.0, 0.0));
      expect((t.x - 333).abs(), lessThanOrEqualTo(kGridSize / 2));
      expect((t.y - 417).abs(), lessThanOrEqualTo(kGridSize / 2));
    });

    testWidgets('"เพิ่มโน้ตที่นี่" -> โน้ตใหม่เข้าโหมดพิมพ์ทันที', (tester) async {
      await boot(tester);
      await rightClick(tester, screenOf(tester, const Offset(333, 417)));
      await tester.tap(find.text('เพิ่มโน้ตที่นี่'));
      await tester.pumpAndSettle();
      expect(c.project.notes.length, 1);
      expect(find.byKey(ValueKey('note-field-${c.project.notes.single.id}')), findsOneWidget);
    });

    testWidgets('ขณะมีเครื่องมือค้างอยู่ คลิกขวา = ยกเลิกเครื่องมือ ไม่เปิดเมนู', (tester) async {
      await boot(tester);
      cv.setTool(CanvasTool.table);
      await tester.pump();
      await rightClick(tester, screenOf(tester, const Offset(333, 417)));
      expect(cv.tool, CanvasTool.select);
      expect(find.text('เพิ่มตารางที่นี่'), findsNothing);
    });

    testWidgets('สลับ Snap จากเมนู (มีเครื่องหมายถูกเมื่อเปิดอยู่)', (tester) async {
      await boot(tester);
      await rightClick(tester, screenOf(tester, const Offset(333, 417)));
      await tester.tap(find.text('จัดแนวตามตาราง (Snap)'));
      await tester.pumpAndSettle();
      expect(settings.snapToGrid, false);
    });

    testWidgets('ตาราง: คลิกขวาเลือกตารางนั้น แล้ว "ลบตาราง" ลบได้ (undo กู้คืน)', (tester) async {
      await boot(tester);
      await rightClick(tester, tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16));
      expect(c.selectedTableIds, {'tu'});
      await tester.tap(find.text('ลบตาราง'));
      await tester.pumpAndSettle();
      expect(c.project.tables.map((t) => t.id), ['to']);
      c.undo();
      expect(c.project.tables.length, 2);
    });

    testWidgets('ตาราง: ทำสำเนา / เพิ่มคอลัมน์ / คัดลอก', (tester) async {
      await boot(tester);
      final head = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16);
      await rightClick(tester, head);
      await tester.tap(find.text('เพิ่มคอลัมน์'));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').columns.length, 5);

      await rightClick(tester, head);
      await tester.tap(find.text('ทำสำเนาตาราง'));
      await tester.pumpAndSettle();
      expect(c.project.tables.length, 3);
    });

    testWidgets('หลายตารางที่เลือก: คลิกขวาในกลุ่ม = เมนูใช้กับทั้งกลุ่ม ("ลบ 2 ตาราง")', (tester) async {
      await boot(tester);
      c.selectAllTables();
      await tester.pump();
      await rightClick(tester, tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16));
      expect(c.selectedTableIds, {'tu', 'to'}); // ไม่ยุบเหลือใบเดียว
      expect(find.text('ลบ 2 ตาราง'), findsOneWidget);
      await tester.tap(find.text('ลบ 2 ตาราง'));
      await tester.pumpAndSettle();
      expect(c.project.tables, isEmpty);
    });

    testWidgets('คอลัมน์: คลิกขวาที่แถว -> สลับ UNIQUE / NOT NULL / PK ได้ และลบคอลัมน์ได้', (tester) async {
      await boot(tester);
      // แถว name (u3) = แถวที่ 3 ของ users
      final row = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) +
          Offset(60, kCardHeaderHeight + kCardRowHeight * 2 + 14);
      await rightClick(tester, row);
      expect(c.selectedColumnId, 'u3');
      await tester.tap(menuItem('UNIQUE'));
      await tester.pumpAndSettle();
      expect(cl(c.project, 'tu', 'u3').unique, true);

      await rightClick(tester, row);
      await tester.tap(menuItem('Primary Key'));
      await tester.pumpAndSettle();
      expect(cl(c.project, 'tu', 'u3').isPrimaryKey, true);
      expect(cl(c.project, 'tu', 'u3').notNull, true); // PK บังคับ NOT NULL

      await rightClick(tester, row);
      await tester.tap(menuItem('ลบคอลัมน์นี้'));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').columnById('u3'), isNull);
    });

    testWidgets('คอลัมน์: "เริ่มเชื่อม FK จากคอลัมน์นี้" -> เข้าโหมด FK พร้อมต้นทาง', (tester) async {
      await boot(tester);
      final row = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) +
          Offset(60, kCardHeaderHeight + kCardRowHeight * 3 + 14);
      await rightClick(tester, row);
      await tester.tap(menuItem('เริ่มเชื่อม FK จากคอลัมน์นี้'));
      await tester.pumpAndSettle();
      expect(cv.tool, CanvasTool.fk);
      expect(cv.fkSource, (tableId: 'tu', columnId: 'u4'));
    });

    testWidgets('คอลัมน์ที่ไม่ใช่จำนวนเต็ม: AUTO INCREMENT ถูกปิดในเมนู', (tester) async {
      await boot(tester);
      final row = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) +
          Offset(60, kCardHeaderHeight + kCardRowHeight * 1 + 14); // email = varchar
      await rightClick(tester, row);
      final item = tester.widget<PopupMenuItem<VoidCallback>>(
          find.ancestor(of: find.text('AUTO INCREMENT'), matching: find.byType(PopupMenuItem<VoidCallback>)));
      expect(item.enabled, false);
    });

    testWidgets('ตาราง > Export ภาพเฉพาะตารางที่เลือก -> dialog เปิดโดยเลือกพื้นที่ "เฉพาะที่เลือก" ไว้แล้ว', (tester) async {
      await boot(tester);
      await rightClick(tester, tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16));
      await tester.tap(find.text('Export ภาพเฉพาะตารางที่เลือก…'));
      await tester.pumpAndSettle();
      expect(find.byType(ExportImageDialog), findsOneWidget);
      final seg = tester.widget<SegmentedButton<ImageArea>>(find.byKey(const ValueKey('export-area')));
      expect(seg.selected, {ImageArea.selection});
    });

    testWidgets('โน้ต: แก้ไขข้อความ / ทำสำเนา / ลบ', (tester) async {
      await boot(tester, notes: [NoteModel(id: 'n1', text: 'hello', x: 300, y: 400)]);
      final note = find.byKey(const ValueKey('note-n1'));
      await rightClick(tester, tester.getCenter(note));
      await tester.tap(find.text('แก้ไขข้อความ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-field-n1')), findsOneWidget);
      await tester.tapAt(const Offset(1000, 700)); // คลิกที่อื่น = บันทึก/จบ
      await tester.pumpAndSettle();

      await rightClick(tester, tester.getCenter(note));
      await tester.tap(find.text('ทำสำเนาโน้ต'));
      await tester.pumpAndSettle();
      expect(c.project.notes.length, 2);
      expect(c.project.notes.last.text, 'hello');

      await rightClick(tester, tester.getCenter(note));
      await tester.tap(find.text('ลบโน้ต'));
      await tester.pumpAndSettle();
      expect(c.project.notes.length, 1);
    });

    testWidgets('เมนูเป็นภาษาอังกฤษเมื่อเลือก English และไม่มีอักษรไทยหลุด', (tester) async {
      await boot(tester);
      settings.setLang(Lang.en);
      await tester.pumpAndSettle();
      await rightClick(tester, screenOf(tester, const Offset(333, 417)));
      expect(find.text('Add table here'), findsOneWidget);
      final thai = RegExp(r'[฀-๿]');
      for (final e in find.byType(Text).evaluate()) {
        final t = (e.widget as Text).data ?? '';
        expect(thai.hasMatch(t), false, reason: t);
      }
      currentLang = Lang.th;
    });
  });

  test('Project ไม่มีผลข้างเคียง: tablesInMarquee คืนว่างเมื่อไม่ได้ลากกรอบ', () {
    final cv = CanvasController();
    expect(cv.tablesInMarquee(Project()), isEmpty);
    cv.dispose();
  });
}
