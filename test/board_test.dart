import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/layout/diagram_geometry.dart';
import 'package:nsl_dev/core/models/note_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  group('boardBounds: ขยายเฉพาะเมื่อชนและล้ำขอบ', () {
    test('โปรเจกต์ว่าง = ขนาดตั้งต้นที่มุม 0,0', () {
      final s = boardBounds(Project(name: 'x'));
      expect((s.left, s.top, s.right, s.bottom), (0.0, 0.0, kBoardMinWidth, kBoardMinHeight));
    });

    test('ตารางอยู่ในกรอบ (รวมที่ชิดขอบพอดี) = ไม่ขยาย', () {
      final p = base();
      var s = boardBounds(p);
      expect((s.left, s.top, s.width, s.height), (0.0, 0.0, kBoardMinWidth, kBoardMinHeight));
      final t = tb(p, 'tu');
      t.x = kBoardMinWidth - t.width; // ขอบขวาชนขอบกรอบพอดี
      s = boardBounds(p);
      expect(s.right, kBoardMinWidth);
      expect(extendedEdges(p), isEmpty);
    });

    test('ล้ำขอบขวา/ล่างเพียงนิด = ขยายพอดีให้ครอบ ไม่เผื่อล่วงหน้า และหดกลับเมื่อลากกลับ', () {
      final p = base();
      final t = tb(p, 'tu');
      t.x = kBoardMinWidth - t.width + 10;
      t.y = kBoardMinHeight - tableHeight(t) + 4;
      var s = boardBounds(p);
      expect(s.right, kBoardMinWidth + 10);
      expect(s.bottom, kBoardMinHeight + 4);
      expect(extendedEdges(p), {BoardEdge.right, BoardEdge.bottom});

      t.x = 40;
      t.y = 60;
      s = boardBounds(p);
      expect((s.right, s.bottom), (kBoardMinWidth, kBoardMinHeight));
      expect(extendedEdges(p), isEmpty);
    });

    test('ล้ำขอบซ้าย/บน (พิกัดติดลบ) = กรอบขยายไปทางซ้าย/บนพอดีขอบตาราง', () {
      final p = base();
      final t = tb(p, 'tu');
      t.x = -700;
      t.y = -450;
      final s = boardBounds(p);
      expect((s.left, s.top), (-700.0, -450.0));
      expect((s.right, s.bottom), (kBoardMinWidth, kBoardMinHeight));
      expect(extendedEdges(p), {BoardEdge.left, BoardEdge.top});
    });

    test('โน้ตที่ล้ำขอบก็ขยายกรอบ', () {
      final p = base();
      final n = NoteModel(id: 'n1', x: 4000, y: -900, text: 'hello');
      p.notes.add(n);
      final s = boardBounds(p);
      expect(s.right, 4000 + n.width);
      expect(s.top, -900);
    });

    test('ขนาดตั้งต้นมาจากโปรเจกต์ ไม่ใช่ค่าตายตัว', () {
      final p = Project(name: 'x', boardWidth: 1600, boardHeight: 1000);
      expect(boardBounds(p).right, 1600);
      expect(baseBoard(p).bottom, 1000);
    });
  });

  group('edgesNearTables (hint)', () {
    test('ตารางกลางกระดาน = ไม่ใกล้ขอบไหน', () {
      final p = base();
      final t = tb(p, 'tu');
      t.x = 1000;
      t.y = 600;
      expect(edgesNearTables(p, ['tu']), isEmpty);
    });

    test('เข้าใกล้ภายใน 120 px หรือชนขอบ = ติดขอบนั้น', () {
      final p = base();
      final t = tb(p, 'tu');
      t.x = 50; // ใกล้ซ้าย
      t.y = 600;
      expect(edgesNearTables(p, ['tu']), {BoardEdge.left});
      t.x = 1000;
      t.y = kBoardMinHeight - tableHeight(t) - 20; // ใกล้ล่าง
      expect(edgesNearTables(p, ['tu']), {BoardEdge.bottom});
      t.x = kBoardMinWidth - t.width - 5; // ใกล้ขวา
      t.y = 5; // ใกล้บน
      expect(edgesNearTables(p, ['tu']), {BoardEdge.right, BoardEdge.top});
    });

    test('ตารางที่ไม่ได้อยู่ในรายการ (ไม่ได้ลาก) ไม่นับ', () {
      final p = base();
      tb(p, 'tu').x = 0;
      expect(edgesNearTables(p, ['to']).contains(BoardEdge.left), true); // 'to' ก็อยู่ที่ 0
      expect(edgesNearTables(p, <String>[]), isEmpty);
    });
  });

  group('กรอบบนจอ', () {
    Future<ProjectController> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      final c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(base(), null);
      tb(c.project, 'tu')
        ..x = 40
        ..y = 60;
      tb(c.project, 'to')
        ..x = 400
        ..y = 60;
      await tester.pump();
      return c;
    }

    testWidgets('วาดกรอบได้โดยไม่มี exception ทั้งตอนซูมออก/เข้าและเมื่อตารางไกลมาก', (tester) async {
      final c = await boot(tester);
      expect(tester.takeException(), isNull);

      // ลากตารางไปไกลด้วยตัวควบคุมจริง แล้วให้ canvas วาดใหม่
      c.selectTable('tu');
      c.moveSelectedBy(6000, 4000);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(boardBounds(c.project).width, greaterThan(kBoardMinWidth));
    });

    testWidgets('ลากตารางไปซ้าย/บนจนติดลบได้ ยังคลิกเลือกได้ และกรอบขยายตาม', (tester) async {
      final c = await boot(tester);
      c.selectTable('tu');
      c.moveSelectedBy(-400, -300); // x = -360, y = -240
      await tester.pump();
      expect(tb(c.project, 'tu').x, -360);
      expect(tb(c.project, 'tu').y, -240);
      expect(boardBounds(c.project).left, -360);
      expect(boardBounds(c.project).top, -240);

      // ยังอยู่ใต้เมาส์และคลิกเลือกได้ (ชั้นวาดต้องครอบคลุมพิกัดติดลบ)
      c.selectTable(null);
      await tester.pump();
      final cv = tester.element(find.byType(HomePage)).read<CanvasController>();
      cv.centerOn(const Offset(-250, -200));
      await tester.pump();
      await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16));
      await tester.pump();
      expect(c.selectedTableIds, {'tu'});
      expect(tester.takeException(), isNull);
    });

    testWidgets('hint: ลากตารางเข้าใกล้ขอบ -> "ลากชนขอบเพื่อขยาย", ล้ำขอบ -> "กำลังขยาย", ปล่อยแล้ว hint หาย', (tester) async {
      final c = await boot(tester);
      expect(find.byKey(const ValueKey('edge-hint-will-extend')), findsNothing);

      // ตารางอยู่ที่ x=40 ใกล้ขอบซ้ายอยู่แล้ว: เริ่มลาก (beginGesture) hint "จะขยาย" ต้องขึ้น
      final header = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16);
      final g = await tester.startGesture(header, kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('edge-hint-will-extend')), findsOneWidget);
      expect(find.byKey(const ValueKey('edge-hint-extending')), findsNothing);

      // ลากไปทางซ้ายจนล้ำขอบ
      await g.moveBy(const Offset(-200, 0));
      await tester.pump();
      expect(tb(c.project, 'tu').x, lessThan(0));
      expect(find.byKey(const ValueKey('edge-hint-extending')), findsOneWidget);

      await g.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('edge-hint-extending')), findsNothing);
      expect(find.byKey(const ValueKey('edge-hint-will-extend')), findsNothing);
    });

    testWidgets('hint ไม่ขึ้นถ้าตารางที่ลากอยู่กลางกระดาน', (tester) async {
      final c = await boot(tester);
      tb(c.project, 'tu')
        ..x = 1000
        ..y = 600;
      tb(c.project, 'to')
        ..x = 1400
        ..y = 600;
      final cv = tester.element(find.byType(HomePage)).read<CanvasController>();
      cv.centerOn(const Offset(1100, 700));
      await tester.pump();
      final header = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16);
      final g = await tester.startGesture(header, kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(30, 20));
      await tester.pump();
      expect(find.byKey(const ValueKey('edge-hint-will-extend')), findsNothing);
      expect(find.byKey(const ValueKey('edge-hint-extending')), findsNothing);
      await g.up();
      await tester.pump();
    });

    testWidgets('หยิบตาราง: ยกขึ้นเล็กน้อย (ขยายนิด) ระหว่างลาก แล้ววางลงเมื่อปล่อย', (tester) async {
      await boot(tester);
      Transform scaleOf() => tester.widget<Transform>(find
          .descendant(of: find.byKey(const ValueKey('table-tu')), matching: find.byType(Transform))
          .first);
      expect(scaleOf().transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));

      final header = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16);
      final g = await tester.startGesture(header, kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(30, 30));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(scaleOf().transform.getMaxScaleOnAxis(), closeTo(1.025, 0.002));

      // ตารางอื่นที่ไม่ได้ถูกหยิบไม่ขยาย
      final other = tester.widget<Transform>(find
          .descendant(of: find.byKey(const ValueKey('table-to')), matching: find.byType(Transform))
          .first);
      expect(other.transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));

      await g.up();
      await tester.pumpAndSettle();
      expect(scaleOf().transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));
    });

    testWidgets('ย้ายตารางด้วยเมาส์ไปชิดขอบ: ตำแหน่งยังเปลี่ยนตามปกติและกรอบขยายตามผลลัพธ์', (tester) async {
      final c = await boot(tester);
      final card = find.byKey(const ValueKey('table-tu'));
      final from = tester.getTopLeft(card) + const Offset(60, 16);
      await tester.dragFrom(from, const Offset(300, 200));
      await tester.pump();
      expect(tb(c.project, 'tu').x, greaterThan(200));
      expect(tester.takeException(), isNull);
    });
  });
}
