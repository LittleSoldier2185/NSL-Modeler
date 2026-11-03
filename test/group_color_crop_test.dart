import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/export/selection_crop.dart';
import 'package:nsl_modeler/core/export/svg_export.dart';
import 'package:nsl_modeler/core/layout/diagram_geometry.dart';
import 'package:nsl_modeler/core/models/group_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/storage/project_file.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
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
      await tester.pumpWidget(const NslModelerApp());
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
