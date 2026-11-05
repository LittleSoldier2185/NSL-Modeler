import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/selection_crop.dart';
import 'package:nsl_dev/core/export/svg_export.dart';
import 'package:nsl_dev/core/layout/diagram_geometry.dart';
import 'package:nsl_dev/core/models/group_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

Project laid() {
  final p = base();
  tb(p, 'tu')
    ..x = 100
    ..y = 100;
  tb(p, 'to')
    ..x = 800
    ..y = 100;
  return p;
}

void main() {
  groupAttachTests();
  group('สีกลุ่มกำหนดเอง', () {
    test('บันทึก/เปิดกลับ; ไฟล์ที่ไม่มีสีเองไม่มีฟิลด์ fill; ค่าผิดปกติถูกทิ้ง', () {
      final g = GroupModel(id: 'g', name: 'g', colorIndex: 2);
      expect(g.toJson().containsKey('fill'), false);
      expect(g.colorValue, kGroupColors[2]);
      g.customColor = 0xFF336699;
      expect(g.colorValue, 0xFF336699);
      final p = laid()..groups.add(g);
      expect(ProjectFile.decode(ProjectFile.encode(p)).groups.single.customColor, 0xFF336699);
      expect(GroupModel.fromJson({'id': 'x', 'fill': 'red'}).customColor, isNull);
    });

    test('controller: ตั้ง/ล้าง/undo; เลือกสีสำเร็จรูปแล้วสีเองหาย; ค่าเดิมไม่สร้างประวัติ', () {
      final c = ProjectController(laid());
      final g = c.addGroup(x: 0, y: 0);
      c.setGroupCustomColor(g.id, 0xFF112233);
      c.setGroupCustomColor(g.id, 0xFF112233);
      expect(c.project.groups.single.customColor, 0xFF112233);
      c.undo();
      expect(c.project.groups.single.customColor, isNull);
      c.redo();
      c.setGroupColor(g.id, 4);
      expect(c.project.groups.single.customColor, isNull);
      expect(c.project.groups.single.colorValue, kGroupColors[4]);
      c.setGroupCustomColor(g.id, -5); // ผิดปกติ
      expect(c.project.groups.single.customColor, isNull);
    });

    test('SVG ใช้สีกำหนดเองของกลุ่ม', () {
      final p = laid()..groups.add(GroupModel(id: 'g', name: 'g', x: 50, y: 50, customColor: 0xFFAA33CC));
      expect(exportSvg(p)!, contains('#AA33CC'));
    });
  });

  group('cropToSelection: กลุ่มติดไปด้วย', () {
    Project withGroup() {
      final p = laid();
      p.groups.add(GroupModel(id: 'g', name: 'Customer', x: 60, y: 40, width: 400, height: 400, colorIndex: 3, customColor: 0xFF336699));
      return p;
    }

    test('เลือกตารางที่อยู่ในกลุ่ม = กรอบกลุ่มติดไปด้วย (ชื่อ/สีเดิม) ไม่มีโน้ต', () {
      final p = withGroup();
      final src = cropToSelection(p, {'tu'});
      expect(src.tables.map((t) => t.id), ['tu']);
      final g = src.groups.single;
      expect((g.name, g.colorIndex, g.customColor), ('Customer', 3, 0xFF336699));
      expect(src.notes, isEmpty);
    });

    test('เลือกครบทุกตารางในกลุ่ม = กรอบเท่าเดิม', () {
      final p = withGroup();
      final g = cropToSelection(p, {'tu'}).groups.single; // users เป็นสมาชิกเดียวในกลุ่ม
      expect((g.x, g.y, g.width, g.height), (60, 40, 400, 400));
    });

    test('เลือกแค่บางตัว = กรอบหดให้พอดีกับที่เลือก (ไม่มีที่ว่างของตารางที่ไม่ได้เลือก)', () {
      final p = withGroup();
      tb(p, 'to')
        ..x = 300
        ..y = 100; // orders เข้ามาอยู่ในกลุ่มด้วย
      final src = cropToSelection(p, {'tu'});
      final g = src.groups.single;
      final t = tb(p, 'tu');
      expect(g.x, t.x - kCropGroupPad);
      expect(g.width, lessThan(400));
      expect(g.x + g.width, t.x + t.width + kCropGroupPad);
      // ภาพที่ export ครอบกรอบกลุ่มทั้งอัน
      final b = diagramBounds(src)!;
      expect(b.left, lessThanOrEqualTo(g.x));
    });

    test('ตารางที่เลือกอยู่นอกกลุ่ม = ไม่มีกลุ่มติดไป; กลุ่มที่ถูกเลือกติดไปเสมอแม้ว่าง', () {
      final p = withGroup();
      expect(cropToSelection(p, {'to'}).groups, isEmpty);
      expect(cropToSelection(p, {'to'}, groupId: 'g').groups.single.id, 'g');
    });

    test('SVG ของส่วนที่ crop มีกรอบกลุ่ม', () {
      final svg = exportSvg(cropToSelection(withGroup(), {'tu'}))!;
      expect(svg, contains('Customer'));
      expect(svg, contains('stroke-dasharray'));
    });
  });

  group('บนจอ', () {
    testWidgets('คลิกขวากลุ่ม > กำหนดสีเอง… แล้วกรอก HEX', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      final c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(laid(), null);
      final g = c.addGroup(x: 300, y: 400);
      await tester.pump();
      final gs = await tester.startGesture(
          tester.getTopLeft(find.byKey(ValueKey('group-${g.id}'))) + const Offset(60, 14),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton);
      await gs.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('กำหนดสีเอง…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('color-hex')), '22BB33');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('color-ok')));
      await tester.pumpAndSettle();
      expect(c.project.groups.single.customColor, 0xFF22BB33);
    });
  });
}

void groupAttachTests() {
  group('กรอบเลือกครอบกลุ่ม = กลุ่มติดไปกับตาราง', () {
    ProjectController make() {
      final c = ProjectController(laid());
      return c;
    }

    test('ลากตารางที่เลือก: กรอบกลุ่มที่ติดไปและโน้ตข้างในเลื่อนด้วย; undo ขั้นเดียวคืนทั้งหมด', () {
      final c = make();
      final g = c.addGroup(x: 60, y: 60); // ครอบ users (100,100)
      c.project.groups.single
        ..width = 400
        ..height = 300;
      final n = c.addNote(x: 300, y: 300); // โน้ตอยู่ในกลุ่ม
      c.undo(); // ไม่ได้ต้องการประวัติ — ล้างแล้วสร้างใหม่ให้แน่ใจ
      c.redo();
      c.setTableSelection({'tu'}, groups: {g.id});
      expect(c.attachedGroupIds, {g.id});
      final tx = tb(c.project, 'tu').x, gx = c.project.groups.single.x, nx = c.project.notes.single.x;
      c.beginGesture();
      c.moveSelectedBy(30, 40);
      c.endGesture();
      expect(tb(c.project, 'tu').x, tx + 30);
      expect(c.project.groups.single.x, gx + 30);
      expect(c.project.groups.single.y, 60 + 40);
      expect(c.project.notes.single.x, nx + 30);
      c.undo();
      expect(c.project.groups.single.x, gx);
      expect(tb(c.project, 'tu').x, tx);
      expect(n.id, c.project.notes.single.id);
    });

    test('ลากแบบ snap: กลุ่มเลื่อนด้วยระยะเท่ากับตาราง (รักษาระยะห่าง)', () {
      final c = make();
      final g = c.addGroup(x: 60, y: 60);
      c.setTableSelection({'tu'}, groups: {g.id});
      final dxBefore = tb(c.project, 'tu').x - c.project.groups.single.x;
      c.beginGesture();
      c.moveSelectedBy(33, 27, grid: 20);
      c.moveSelectedBy(5, 5, grid: 20);
      c.endGesture();
      expect(tb(c.project, 'tu').x - c.project.groups.single.x, dxBefore);
      expect(tb(c.project, 'tu').y - c.project.groups.single.y, 40);
    });

    test('ปุ่มลูกศร (nudge) ขยับกลุ่มที่ติดไปด้วย', () {
      final c = make();
      final g = c.addGroup(x: 60, y: 60);
      c.setTableSelection({'tu'}, groups: {g.id});
      c.nudgeSelected(10, 0);
      expect(c.project.groups.single.x, 70);
    });

    test('ไม่ได้ติดไป (เลือกตารางเฉย ๆ) = กลุ่มอยู่ที่เดิม; เลือกใหม่/คลิก/ล้าง = เลิกติด', () {
      final c = make();
      final g = c.addGroup(x: 60, y: 60);
      c.setTableSelection({'tu'});
      c.beginGesture();
      c.moveSelectedBy(30, 0);
      c.endGesture();
      expect(c.project.groups.single.x, 60);

      c.setTableSelection({'tu'}, groups: {g.id});
      c.selectTable('to');
      expect(c.attachedGroupIds, isEmpty);
      c.setTableSelection({'tu'}, groups: {g.id});
      c.clearSelection();
      expect(c.attachedGroupIds, isEmpty);
      c.setTableSelection({'tu'}, groups: {g.id});
      c.selectGroup(g.id);
      expect(c.attachedGroupIds, isEmpty);
    });

    test('Ctrl+A เลือกกลุ่มทุกกลุ่มติดไปด้วย; export เฉพาะที่เลือกพากลุ่มที่ติดไป', () {
      final c = make();
      final g = c.addGroup(x: 60, y: 60);
      c.selectAllTables();
      expect(c.attachedGroupIds, {g.id});
      c.setTableSelection({'to'}, groups: {g.id}); // กลุ่มว่างที่ติดไป
      final src = cropToSelection(c.project, c.selectedTableIds, groupIds: c.attachedGroupIds);
      expect(src.groups.map((x) => x.id), [g.id]);
    });
  });

  group('กรอบเลือกบนจอ', () {
    testWidgets('ลากกรอบครอบกลุ่มทั้งกลุ่ม = กลุ่มติดไป; ครอบไม่หมด = ไม่ติด; ลากตารางแล้วกลุ่มตามไป', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      final c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(laid(), null);
      tb(c.project, 'tu')
        ..x = 140
        ..y = 140;
      final g = c.addGroup(x: 100, y: 100);
      c.project.groups.single
        ..width = 330
        ..height = 300;
      await tester.pump();
      final origin = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) - const Offset(140, 140);
      Offset at(double x, double y) => origin + Offset(x, y);

      // ครอบไม่หมด: ลากจากด้านล่างขวาเข้ามาแค่บางส่วนของกลุ่ม
      var gs = await tester.startGesture(at(520, 330), kind: PointerDeviceKind.mouse);
      await gs.moveTo(at(120, 120));
      await gs.up();
      await tester.pump();
      expect(c.attachedGroupIds, isEmpty);

      // ครอบทั้งกลุ่ม
      gs = await tester.startGesture(at(560, 480), kind: PointerDeviceKind.mouse);
      await gs.moveTo(at(60, 60));
      await tester.pump();
      expect(c.selectedTableIds, contains('tu'));
      expect(c.attachedGroupIds, {g.id});
      await gs.up();
      await tester.pump();
      expect(c.attachedGroupIds, {g.id}); // ปล่อยเมาส์แล้วยังติดอยู่

      // ลากตาราง users: กลุ่มตามไปด้วย
      final before = c.project.groups.single.x;
      final tg = await tester.startGesture(
          tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16),
          kind: PointerDeviceKind.mouse);
      await tg.moveBy(const Offset(40, 0));
      await tg.moveBy(const Offset(40, 0));
      await tg.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.project.groups.single.x, greaterThan(before + 30));
    });
  });
}
