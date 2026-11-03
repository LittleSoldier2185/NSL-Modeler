import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/export/svg_export.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/core/layout/diagram_geometry.dart';
import 'package:nsl_modeler/core/models/group_model.dart';
import 'package:nsl_modeler/core/models/note_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/storage/project_file.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/canvas/canvas_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:provider/provider.dart';
import 'package:xml/xml.dart';

import 'migration_fixtures.dart';

Project laid() {
  final p = base();
  tb(p, 'tu')
    ..x = 100
    ..y = 100;
  tb(p, 'to')
    ..x = 500
    ..y = 100;
  return p;
}

void main() {
  group('โมเดล / ไฟล์', () {
    test('บันทึกแล้วเปิดกลับมาได้ครบ และไฟล์ที่ไม่มีกลุ่มไม่มีฟิลด์ groups', () {
      expect(laid().toJson().containsKey('groups'), false);
      final p = laid()..groups.add(GroupModel(id: 'g1', name: 'Customer', x: 10, y: 20, width: 600, height: 400, colorIndex: 3));
      final back = ProjectFile.decode(ProjectFile.encode(p));
      final g = back.groups.single;
      expect((g.id, g.name, g.x, g.y, g.width, g.height, g.colorIndex), ('g1', 'Customer', 10.0, 20.0, 600.0, 400.0, 3));
    });

    test('ค่าผิดปกติในไฟล์ (ขนาดเล็กเกิน/สีนอกช่วง) ถูกแทนด้วยค่าที่ปลอดภัย', () {
      final g = GroupModel.fromJson({'id': 'g', 'name': 'x', 'width': 5, 'height': -1, 'color': 99});
      expect((g.width, g.height, g.colorIndex), (kGroupDefaultWidth, kGroupDefaultHeight, 0));
    });

    test('กลุ่มรวมอยู่ในขอบเขตแผนภาพ/กรอบกระดาน (export และกรอบขยายตาม)', () {
      final p = laid()..groups.add(GroupModel(id: 'g', name: 'big', x: 3000, y: -200, width: 500, height: 300));
      expect(diagramBounds(p)!.right, greaterThan(3500));
      expect(boardBounds(p).right, 3500);
      expect(boardBounds(p).top, -200);
    });
  });

  group('groupMembers', () {
    test('สมาชิก = ของที่จุดกึ่งกลางอยู่ในกรอบ (ไม่ใช่แค่ทับกัน)', () {
      final p = laid();
      final g = GroupModel(id: 'g', name: 'g', x: 60, y: 60, width: 340, height: 300); // ครอบ users ทั้งใบ
      p.groups.add(g);
      p.notes.add(NoteModel(id: 'n1', text: 'in', x: 80, y: 250));
      p.notes.add(NoteModel(id: 'n2', text: 'out', x: 900, y: 250));
      final m = groupMembers(p, g);
      expect(m.tables, ['tu']);
      expect(m.notes, ['n1']);
    });

    test('กลุ่มซ้อนกลุ่ม: นับเฉพาะกลุ่มที่เล็กกว่าและอยู่ข้างใน', () {
      final p = laid();
      final outer = GroupModel(id: 'o', name: 'outer', x: 0, y: 0, width: 1000, height: 600);
      final inner = GroupModel(id: 'i', name: 'inner', x: 50, y: 50, width: 300, height: 200);
      p.groups.addAll([outer, inner]);
      expect(groupMembers(p, outer).groups, ['i']);
      expect(groupMembers(p, inner).groups, isEmpty);
    });
  });

  group('ProjectController: กลุ่ม', () {
    ProjectController make() => ProjectController(laid());

    test('จัดกลุ่มจากตารางที่เลือก: กรอบครอบตารางพร้อมระยะเผื่อและแถบชื่อ undo ขั้นเดียว', () {
      final c = make();
      c.selectAllTables();
      final g = c.groupSelectedTables()!;
      for (final t in c.project.tables) {
        expect(t.x, greaterThan(g.x));
        expect(t.x + t.width, lessThan(g.x + g.width));
        expect(t.y - g.y, greaterThanOrEqualTo(kGroupHeader)); // เหลือที่ให้แถบชื่อ
        expect(t.y + tableHeight(t), lessThan(g.y + g.height));
      }
      expect(groupMembers(c.project, g).tables.toSet(), {'tu', 'to'});
      expect(g.name, 'Group 1');
      c.undo();
      expect(c.project.groups, isEmpty);
    });

    test('ไม่มีตารางที่เลือก = ไม่สร้างกลุ่ม', () {
      final c = make();
      expect(c.groupSelectedTables(), isNull);
      expect(c.project.groups, isEmpty);
    });

    test('ชื่อกลุ่มอัตโนมัติไม่ซ้ำ และสีหมุนเวียน', () {
      final c = make();
      final a = c.addGroup();
      final b = c.addGroup();
      expect({a.name, b.name}.length, 2);
      expect(a.colorIndex, isNot(b.colorIndex));
    });

    test('ลากกลุ่ม: ตาราง/โน้ตข้างในเลื่อนตามเท่ากัน ของข้างนอกอยู่กับที่ และเป็น undo ขั้นเดียว', () {
      final c = make();
      c.project.notes.add(NoteModel(id: 'n1', text: 'in', x: 120, y: 330));
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 360);
      final before = (tb(c.project, 'tu').x, tb(c.project, 'tu').y, tb(c.project, 'to').x);
      c.beginGroupDrag(g.id);
      c.moveGroupBy(g.id, 30, 10);
      c.moveGroupBy(g.id, 20, 10);
      c.endGesture();
      expect((g.x, g.y), (110.0, 80.0));
      expect(tb(c.project, 'tu').x, before.$1 + 50);
      expect(tb(c.project, 'tu').y, before.$2 + 20);
      expect(c.project.notes.single.x, 170);
      expect(tb(c.project, 'to').x, before.$3); // อยู่นอกกลุ่ม ไม่ขยับ
      c.undo(); // undo สร้างโปรเจกต์ใหม่จาก snapshot จึงต้องอ่านจากตัวควบคุมอีกครั้ง
      expect((c.project.groups.single.x, tb(c.project, 'tu').x, c.project.notes.single.x), (60.0, before.$1, 120.0));
    });

    test('ลากกลุ่มด้วย snap: ตำแหน่งกลุ่มลงช่อง สมาชิกเลื่อนด้วยระยะเท่ากัน (รักษาระยะห่างสัมพัทธ์)', () {
      final c = make();
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 360);
      final dx0 = tb(c.project, 'tu').x - g.x;
      c.beginGroupDrag(g.id);
      c.moveGroupBy(g.id, 7, 0, grid: 20);
      c.moveGroupBy(g.id, 7, 0, grid: 20);
      c.moveGroupBy(g.id, 7, 0, grid: 20); // รวม 21 -> +20
      c.endGesture();
      expect(g.x, 80);
      expect(tb(c.project, 'tu').x - g.x, dx0);
    });

    test('ปรับขนาด: คิดจากขนาดตอนเริ่ม + ระยะสะสม, ไม่เล็กกว่าขั้นต่ำ, snap ที่มุมขวาล่าง', () {
      final c = make();
      final g = c.addGroup(x: 0, y: 0, width: 400, height: 300);
      c.beginGroupResize(g.id);
      c.resizeGroupBy(g.id, 7, 3, grid: 20);
      c.resizeGroupBy(g.id, 7, 3, grid: 20);
      c.resizeGroupBy(g.id, 7, 3, grid: 20); // w 421 -> 420, h 309 -> 300
      expect((g.width, g.height), (420.0, 300.0));
      c.resizeGroupBy(g.id, -1000, -1000);
      expect((g.width, g.height), (kGroupMinWidth, kGroupMinHeight));
      c.endGesture();
      c.undo();
      expect((c.project.groups.single.width, c.project.groups.single.height), (400.0, 300.0));
    });

    test('ลบกลุ่มไม่ลบตาราง; เปลี่ยนชื่อ/สีเป็น undo ได้', () {
      final c = make();
      final id = c.addGroup().id;
      c.renameGroup(id, 'Customer');
      c.setGroupColor(id, 4);
      expect((c.project.groupById(id)!.name, c.project.groupById(id)!.colorIndex), ('Customer', 4));
      c.undo();
      c.undo();
      expect(c.project.groupById(id)!.name, isNot('Customer'));
      c.redo();
      c.redo();
      expect(c.project.groupById(id)!.name, 'Customer');
      c.removeGroup(id);
      expect(c.project.groups, isEmpty);
      expect(c.project.tables.length, 2);
    });

    test('selectGroupMembers เลือกตารางในกลุ่ม', () {
      final c = make();
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 360);
      c.selectGroupMembers(g.id);
      expect(c.selectedTableIds, {'tu'});
    });
  });

  group('export', () {
    test('SVG: มีกรอบเส้นประและชื่อกลุ่ม และยัง well-formed', () {
      final p = laid()..groups.add(GroupModel(id: 'g', name: 'Customer & Co', x: 60, y: 40, width: 340, height: 300, colorIndex: 1));
      final svg = exportSvg(p)!;
      XmlDocument.parse(svg);
      expect(svg, contains('stroke-dasharray="8 6"'));
      expect(svg, contains('Customer &amp; Co'));
      expect(svg, contains('#9333EA')); // สีม่วง (colorIndex 1)
    });
  });

  group('บน canvas', () {
    late ProjectController c;
    late CanvasController cv;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: Lang.th, snapToGrid: false)));
      final ctx = tester.element(find.byType(HomePage));
      c = ctx.read<ProjectController>();
      cv = ctx.read<CanvasController>();
      c.loadProject(laid(), null);
      // วางตารางต่ำลง เพื่อไม่ให้แถบเครื่องมือลอยมุมซ้ายบนบังแถบชื่อกลุ่มที่ทดสอบ
      tb(c.project, 'tu').y = 160;
      tb(c.project, 'to').y = 160;
      await tester.pump();
    }

    testWidgets('Ctrl+G กับตารางที่เลือก = สร้างกลุ่มและเข้าโหมดพิมพ์ชื่อทันที', (tester) async {
      await boot(tester);
      c.selectAllTables();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(c.project.groups.length, 1);
      final id = c.project.groups.single.id;
      final field = find.byKey(ValueKey('group-name-field-$id'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Customer');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.project.groups.single.name, 'Customer');
      expect(find.text('Customer'), findsOneWidget);
    });

    testWidgets('Ctrl+G โดยไม่มีตารางที่เลือก = แจ้งเตือน ไม่สร้างกลุ่ม', (tester) async {
      await boot(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(c.project.groups, isEmpty);
      expect(find.textContaining('เลือกตารางก่อน'), findsOneWidget);
    });

    testWidgets('ลากแถบชื่อกลุ่ม = ย้ายกลุ่มและตารางข้างใน', (tester) async {
      await boot(tester);
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 300, name: 'G');
      await tester.pump();
      final x0 = tb(c.project, 'tu').x;
      await tester.dragFrom(tester.getTopLeft(find.byKey(ValueKey('group-header-${g.id}'))) + const Offset(120, 16),
          const Offset(80, 0));
      await tester.pump();
      expect(g.x, greaterThan(60 + 40));
      expect(tb(c.project, 'tu').x - x0, closeTo(g.x - 60, 0.001));
      expect(tb(c.project, 'to').x, 500); // นอกกลุ่ม
      expect(c.canUndo, true);
      c.undo();
      expect((c.project.groups.single.x, tb(c.project, 'tu').x), (60.0, x0)); // undo สร้างโปรเจกต์ใหม่ อ่านจากตัวควบคุม
      await tester.pump(const Duration(milliseconds: 500)); // ให้ timer ค้างของท่าทางจบก่อนปิดเทสต์
    });

    testWidgets('ลากมุมขวาล่าง = ปรับขนาดกลุ่ม', (tester) async {
      await boot(tester);
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 300, name: 'G');
      await tester.pump();
      await tester.dragFrom(
          tester.getCenter(find.byKey(ValueKey('group-resize-${g.id}'))), const Offset(100, 60));
      await tester.pump();
      expect(g.width, greaterThan(340 + 50));
      expect(g.height, greaterThan(300 + 20));
    });

    testWidgets('ดับเบิลคลิกแถบชื่อ = พิมพ์ชื่อบนแถบ; Esc ยกเลิก', (tester) async {
      await boot(tester);
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 300, name: 'เดิม');
      await tester.pump();
      final header = find.byKey(ValueKey('group-header-${g.id}'));
      final at = tester.getTopLeft(header) + const Offset(150, 16);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      final field = find.byKey(ValueKey('group-name-field-${g.id}'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'ทิ้ง');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(g.name, 'เดิม');
      expect(field, findsNothing);
    });

    testWidgets('พื้นที่ข้างในกลุ่มไม่บังเมาส์: ลากกรอบเลือกจากพื้นว่างในกลุ่มได้ และตารางข้างในยังลากได้', (tester) async {
      await boot(tester);
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 420, name: 'G');
      await tester.pump();
      // เริ่มลากกรอบจากพื้นว่างในกลุ่ม (ใต้ตาราง users)
      final origin = tester.getTopLeft(find.byKey(const ValueKey('table-tu')));
      final from = origin + const Offset(100, 200); // ใต้การ์ด (สูง 148) แต่ยังอยู่ในกลุ่ม
      final gs = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await gs.moveTo(origin + const Offset(60, 60));
      await tester.pump();
      expect(cv.marquee, isNotNull);
      expect(c.selectedTableIds, {'tu'});
      await gs.up();
      await tester.pump();
      expect(g.x, 60); // กลุ่มไม่ขยับ
    });

    testWidgets('คลิกขวาที่แถบชื่อ: เมนูกลุ่ม เปลี่ยนสี / เลือกตารางในกลุ่ม / ลบกลุ่ม', (tester) async {
      await boot(tester);
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 300, name: 'G');
      await tester.pump();
      final at = tester.getTopLeft(find.byKey(ValueKey('group-header-${g.id}'))) + const Offset(150, 16);
      Future<void> rc() async {
        final gs = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        await gs.up();
        await tester.pumpAndSettle();
      }

      await rc();
      await tester.tap(find.text('ม่วง'));
      await tester.pumpAndSettle();
      expect(g.colorIndex, 1);

      await rc();
      await tester.tap(find.text('เลือกตารางทั้งหมดในกลุ่ม'));
      await tester.pumpAndSettle();
      expect(c.selectedTableIds, {'tu'});

      await rc();
      await tester.tap(find.text('ลบกลุ่ม (ไม่ลบตาราง)'));
      await tester.pumpAndSettle();
      expect(c.project.groups, isEmpty);
      expect(c.project.tables.length, 2);
    });

    testWidgets('คลิกขวาพื้นว่าง > เพิ่มกลุ่มที่นี่ = สร้างกลุ่มและเข้าโหมดพิมพ์ชื่อ', (tester) async {
      await boot(tester);
      final gs = await tester.startGesture(const Offset(700, 600), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gs.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('เพิ่มกลุ่มที่นี่'));
      await tester.pumpAndSettle();
      expect(c.project.groups.length, 1);
      expect(find.byKey(ValueKey('group-name-field-${c.project.groups.single.id}')), findsOneWidget);
    });

    testWidgets('เมนูตาราง > จัดกลุ่มตารางที่เลือก', (tester) async {
      await boot(tester);
      final gs = await tester.startGesture(
          tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton);
      await gs.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('จัดกลุ่มตารางที่เลือก'));
      await tester.pumpAndSettle();
      expect(c.project.groups.length, 1);
      expect(groupMembers(c.project, c.project.groups.single).tables, ['tu']);
    });
  });
}
