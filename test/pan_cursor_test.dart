import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/canvas/canvas_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  late ProjectController c;
  late CanvasController cv;

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NslModelerApp());
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

  testWidgets('ลากปุ่มกลางบนพื้นว่าง = เลื่อนมุมมอง, ไม่แก้ข้อมูล, ไม่เข้า undo', (tester) async {
    await boot(tester);
    final before = cv.offset;
    final gesture = await tester.startGesture(const Offset(700, 380), kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await gesture.moveBy(const Offset(80, 50));
    await tester.pump();
    expect(cv.panning, true);
    await gesture.moveBy(const Offset(20, 10));
    await gesture.up();
    await tester.pump();
    expect(cv.panning, false);
    expect((cv.offset - before - const Offset(100, 60)).distance, lessThan(1));
    expect(c.canUndo, false);
  });

  testWidgets('ลากปุ่มกลางบนการ์ดตาราง = เลื่อนมุมมอง ไม่ย้ายตาราง', (tester) async {
    await boot(tester);
    final header = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16);
    final off = cv.offset;
    final g = await tester.startGesture(header, kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await g.moveBy(const Offset(120, 40));
    await g.up();
    await tester.pump();
    expect(tb(c.project, 'tu').x, 40);
    expect(tb(c.project, 'tu').y, 60);
    expect((cv.offset - off).distance, greaterThan(100));
    expect(c.canUndo, false);
  });

  testWidgets('คลิกปุ่มกลางเฉยๆ ไม่เลือก/ไม่ล้างการเลือกตาราง', (tester) async {
    await boot(tester);
    c.selectTable('tu');
    await tester.pump();
    final g = await tester.startGesture(const Offset(700, 380), kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await g.up();
    await tester.pump();
    expect(c.selectedTableIds, {'tu'});
    expect(cv.panning, false);
  });

  testWidgets('ปุ่มซ้ายลากพื้นว่าง = กรอบเลือก ไม่เลื่อนมุมมอง', (tester) async {
    await boot(tester);
    final off = cv.offset;
    final g = await tester.startGesture(const Offset(700, 380), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(60, 20));
    await tester.pump();
    expect(cv.panning, false);
    expect(cv.marquee, isNotNull);
    await g.up();
    await tester.pump();
    expect(cv.marquee, isNull);
    expect(cv.offset, off);
  });

  testWidgets('Space+ลากบนการ์ด = เลื่อนมุมมอง และ panning ถูกล้างเมื่อจบ', (tester) async {
    await boot(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final header = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16);
    final g = await tester.startGesture(header, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(80, 30));
    await tester.pump();
    expect(cv.panning, true);
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(cv.panning, false);
    expect(tb(c.project, 'tu').x, 40);
  });

  testWidgets('เคอร์เซอร์: พื้นว่าง = ลูกศรปกติ (ลาก = กรอบเลือก), ระหว่างเลื่อน = grabbing (มือกำ)', (tester) async {
    await boot(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 380));
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);

    cv.setPanning(true);
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.grabbing);
    cv.setPanning(false);
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
  });

  testWidgets('เคอร์เซอร์ระหว่างเลื่อนเป็นมือกำแม้เมาส์อยู่บนการ์ดตาราง', (tester) async {
    await boot(tester);
    final header = tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: header);
    await tester.pump();
    cv.setPanning(true);
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.grabbing);
  });
}
