import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

void main() {
  Future<(ProjectController, CanvasController)> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NslDevApp());
    final ctx = tester.element(find.byType(HomePage));
    return (ctx.read<ProjectController>(), ctx.read<CanvasController>());
  }

  testWidgets('แท็บ ปัญหา: schema สะอาดแสดงว่าพร้อม Export', (tester) async {
    final (c, cv) = await pump(tester);
    c.addTable(name: 'users');
    await tester.pump();
    cv.showDock(DockTab.issues);
    await tester.pump();
    expect(find.textContaining('ไม่พบปัญหา'), findsWidgets);
  });

  testWidgets('แท็บ ปัญหา: แสดงรายการ, ป้ายนับ และคลิกแล้วเลือกตารางนั้น', (tester) async {
    final (c, cv) = await pump(tester);
    final a = c.addTable(name: 'a', withId: false);
    c.addColumn(a.id, name: 'x'); // ไม่มี PK -> warning
    c.addTable(name: 'b');
    c.selectTable(null);
    cv.showDock(DockTab.issues);
    await tester.pump();

    expect(find.text('ไม่มี Primary Key'), findsOneWidget);
    expect(find.text('1 คำเตือน'), findsOneWidget);
    expect(find.text('1'), findsWidgets); // ป้ายนับบนแท็บ

    await tester.tap(find.text('ไม่มี Primary Key'));
    await tester.pump();
    expect(c.selectedTableId, a.id);
  });

  testWidgets('ปัญหาเปลี่ยนตาม dialect (user เป็น reserved ใน PostgreSQL)', (tester) async {
    final (c, cv) = await pump(tester);
    c.addTable(name: 'user');
    cv.showDock(DockTab.issues);
    await tester.pump();
    expect(find.text('ชื่อชนกับ reserved word'), findsNothing); // MySQL ไม่สงวน
    c.setDialect(Dialect.postgres);
    await tester.pump();
    expect(find.text('ชื่อชนกับ reserved word'), findsWidgets);
  });

  testWidgets('แผงขวาแสดงปัญหาเฉพาะตารางที่เลือก', (tester) async {
    final (c, _) = await pump(tester);
    final a = c.addTable(name: 'a', withId: false);
    c.addColumn(a.id, name: 'x');
    c.addTable(name: 'b'); // ตารางนี้ไม่มีปัญหา และถูกเลือกอยู่
    await tester.pump();
    expect(find.text('✓ ตารางนี้ไม่พบปัญหา'), findsOneWidget);

    c.selectTable(a.id);
    await tester.pump();
    expect(find.text('✓ ตารางนี้ไม่พบปัญหา'), findsNothing);
    expect(find.text('ไม่มี Primary Key'), findsOneWidget);
  });

  testWidgets('ผลตรวจถูกแคช และคำนวณใหม่เมื่อแก้ข้อมูล', (tester) async {
    final (c, _) = await pump(tester);
    final a = c.addTable(name: 'a');
    expect(identical(c.issues, c.issues), true);
    final before = c.issues;
    c.updateColumn(a.id, a.columns.first.id, (x) => x.isPrimaryKey = false);
    expect(identical(c.issues, before), false);
    expect(c.issues.map((i) => i.code), contains('no_pk'));
    c.undo();
    expect(c.issues.map((i) => i.code), isNot(contains('no_pk')));
  });
}
