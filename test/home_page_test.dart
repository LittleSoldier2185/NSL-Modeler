import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/main.dart';

void main() {
  testWidgets('เพิ่มตาราง -> เห็นในรายการ + แผงขวา แล้วเพิ่ม/ลบคอลัมน์', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const NslModelerApp());
    expect(find.text('เลือกตารางทางซ้ายเพื่อแก้ไข'), findsOneWidget);

    await tester.tap(find.byTooltip('เพิ่มตาราง'));
    await tester.pump();
    expect(find.text('table_1'), findsWidgets);
    expect(find.text('คุณสมบัติของตาราง'), findsOneWidget);
    expect(find.text('● ยังไม่ได้บันทึก'), findsOneWidget);

    await tester.tap(find.text('+ เพิ่มคอลัมน์'));
    await tester.pump();
    expect(find.text('column_1'), findsWidgets);
    expect(find.text('ลบคอลัมน์นี้'), findsOneWidget);

    // แผงขวาเลื่อนได้และสูงขึ้นแล้ว (ช่องหมายเหตุหลายบรรทัด + สีตาราง) จึงเลื่อนให้เห็นปุ่มก่อนกด
    await tester.ensureVisible(find.text('ลบคอลัมน์นี้'));
    await tester.pump();
    await tester.tap(find.text('ลบคอลัมน์นี้'));
    await tester.pump();
    expect(find.text('column_1'), findsNothing);
  });

  testWidgets('เทมเพลต users สร้างตารางพร้อม 3 คอลัมน์ และ undo ได้', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const NslModelerApp());
    await tester.tap(find.text('+ users (id, email, password)'));
    await tester.pump();
    expect(find.text('email'), findsWidgets);
    expect(find.text('password'), findsWidgets);

    await tester.tap(find.byTooltip('ย้อนกลับ (Ctrl+Z)'));
    await tester.pump();
    expect(find.text('email'), findsNothing);
  });
}
