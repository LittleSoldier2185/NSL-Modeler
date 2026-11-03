import 'package:nsl_modeler/core/layout/diagram_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/canvas/canvas_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:provider/provider.dart';

void main() {
  group('CanvasController', () {
    test('zoomAt เก็บจุดโฟกัสไว้ที่เดิม', () {
      final cv = CanvasController()..viewport = const Size(1000, 600);
      const focal = Offset(300, 200);
      final before = cv.toWorld(focal);
      cv.zoomAt(focal, 1.5);
      expect(cv.scale, 1.5);
      expect((cv.toWorld(focal) - before).distance, lessThan(1e-9));
    });

    test('ซูมถูกจำกัด 25%-200%', () {
      final cv = CanvasController()..viewport = const Size(1000, 600);
      for (var i = 0; i < 40; i++) {
        cv.zoomAt(Offset.zero, 1.5);
      }
      expect(cv.scale, CanvasController.maxScale);
      for (var i = 0; i < 80; i++) {
        cv.zoomAt(Offset.zero, 1 / 1.5);
      }
      expect(cv.scale, CanvasController.minScale);
    });

    test('fit จัดเนื้อหาไว้กลางจอ', () {
      final cv = CanvasController()..viewport = const Size(1000, 600);
      final p = Project(tables: [
        TableModel(id: 't', name: 't', x: 100, y: 100, width: 200, columns: [
          ColumnModel(id: 'a', name: 'a'),
          ColumnModel(id: 'b', name: 'b'),
        ]),
      ]);
      cv.fit(p);
      final worldCenter = const Offset(200, 100 + 92 / 2);
      final screen = worldCenter * cv.scale + cv.offset;
      expect((screen - const Offset(500, 300)).distance, lessThan(1e-9));
    });

    test('fit โปรเจกต์ว่างรีเซ็ตมุมมอง', () {
      final cv = CanvasController()..viewport = const Size(1000, 600);
      cv.zoomAt(Offset.zero, 1.5);
      cv.panBy(const Offset(50, 50));
      cv.fit(Project());
      expect(cv.scale, 1);
      expect(cv.offset, Offset.zero);
    });

    test('เปลี่ยนเครื่องมือล้าง fkSource', () {
      final cv = CanvasController()..setTool(CanvasTool.fk);
      cv.setFkSource('t', 'c');
      cv.setTool(CanvasTool.select);
      expect(cv.fkSource, isNull);
    });
  });

  group('Canvas widget', () {
    Future<(ProjectController, CanvasController)> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslModelerApp());
      final ctx = tester.element(find.byType(HomePage));
      return (ctx.read<ProjectController>(), ctx.read<CanvasController>());
    }

    testWidgets('ลากการ์ดตารางย้ายตำแหน่ง และ undo ขั้นเดียวกลับที่เดิม', (tester) async {
      final (c, _) = await pump(tester);
      final t = c.addTable(x: 100, y: 100);
      await tester.pump();

      final head = find.descendant(
          of: find.byKey(ValueKey('table-${t.id}')), matching: find.text('table_1'));
      await tester.drag(head, const Offset(120, 60));
      await tester.pump();
      expect(t.x, closeTo(220, 25));
      expect(t.y, closeTo(160, 25));

      c.undo(); // ลาก = 1 ขั้น
      await tester.pump();
      expect(c.project.tableById(t.id)!.x, 100);
      expect(c.project.tableById(t.id)!.y, 100);
    });

    testWidgets('โหมด FK: คลิกคอลัมน์ลูกแล้วคอลัมน์แม่ สร้างความสัมพันธ์', (tester) async {
      final (c, cv) = await pump(tester);
      final a = c.addTable(x: 40, y: 80);
      final b = c.addTable(x: 400, y: 80);
      await tester.pump();

      cv.setTool(CanvasTool.fk);
      await tester.pump();
      Finder idOf(String tid) => find.descendant(
          of: find.byKey(ValueKey('table-$tid')), matching: find.text('id'));

      await tester.tap(idOf(a.id));
      await tester.pump();
      expect(cv.fkSource, isNotNull);
      expect(c.project.relations, isEmpty);

      await tester.tap(idOf(b.id));
      await tester.pump();
      expect(c.project.relations.length, 1);
      final r = c.project.relations.single;
      expect(r.fromTableId, a.id);
      expect(r.toTableId, b.id);
      expect(cv.tool, CanvasTool.select);
    });

    testWidgets('โหมด + ตาราง: คลิกพื้นที่ว่างวางตารางตรงจุดนั้น (ปัดเข้าช่องตาราง 20px เมื่อเปิด snap)', (tester) async {
      final (c, cv) = await pump(tester);
      cv.setTool(CanvasTool.table);
      await tester.pump();
      // กลางพื้นที่ canvas ประมาณ (248 + 436, 52 + 36 + 400) — 36 = แถบแท็บแผนภาพ
      await tester.tapAt(const Offset(700, 400));
      await tester.pump();
      expect(c.project.tables.length, 1);
      final t = c.project.tables.single;
      final w = cv.toWorld(const Offset(700 - 248, 400 - 52 - 36));
      expect(t.x, snapToGrid(w.dx));
      expect(t.y, snapToGrid(w.dy));
      expect((t.x - w.dx).abs(), lessThanOrEqualTo(kGridSize / 2));
      expect((t.y - w.dy).abs(), lessThanOrEqualTo(kGridSize / 2));
      expect(cv.tool, CanvasTool.select);
    });
  });
}
