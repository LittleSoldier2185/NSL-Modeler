import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/search/fuzzy.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/ui/palette/command_palette.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  group('fuzzyScore', () {
    test('ลำดับความตรง: ทั้งคำ > ขึ้นต้น > ต้นคำ > ในข้อความ > เรียงตัวอักษร', () {
      int s(String t, String q) => fuzzyScore(t, q)!;
      expect(s('users', 'users'), greaterThan(s('users_log', 'users')));
      expect(s('users_log', 'users'), greaterThan(s('order_users', 'users'))); // ต้นคำหลัง _
      expect(s('order_users', 'users'), greaterThan(s('superusers', 'users'))); // กลางคำ
      expect(s('superusers', 'users'), greaterThan(s('u_s_e_r_s', 'users'))); // เรียงตัวอักษรห่าง ๆ
    });

    test('ไม่สนตัวพิมพ์เล็กใหญ่ และคำค้นว่างตรงทุกอย่าง', () {
      expect(fuzzyScore('Users', 'USERS'), fuzzyScore('users', 'users'));
      expect(fuzzyScore('abc', ''), 0);
      expect(fuzzyScore('abc', '   '), 0);
    });

    test('subsequence: usr ตรง users แต่ xyz ไม่ตรง', () {
      expect(fuzzyScore('users', 'usr'), isNotNull);
      expect(fuzzyScore('users', 'xyz'), isNull);
      expect(fuzzyScore('users', 'sru'), isNull); // ลำดับผิด
    });

    test('หลายคำต้องตรงทุกคำ', () {
      expect(fuzzyScore('export sql ddl', 'export sql'), isNotNull);
      expect(fuzzyScore('export sql ddl', 'sql export'), isNotNull); // ไม่บังคับลำดับคำ
      expect(fuzzyScore('export sql', 'export png'), isNull);
    });

    test('ภาษาไทย', () {
      expect(fuzzyScore('จัดวางตารางอัตโนมัติ', 'จัดวาง'), isNotNull);
      expect(fuzzyScore('จัดวางตารางอัตโนมัติ', 'ตาราง'), isNotNull);
      expect(fuzzyScore('จัดวางตารางอัตโนมัติ', 'ลูกค้า'), isNull);
    });

    test('fuzzyRank: เรียงตามคะแนน คงลำดับเดิมเมื่อเท่ากัน และตัดที่ไม่ตรง', () {
      final items = ['order_items', 'users', 'user_logs', 'products', 'users_archive'];
      // user_logs ก็ตาม (u-s-e-r แล้ว s ใน logs) แต่คะแนนต่ำสุดจึงอยู่ท้าย
      expect(fuzzyRank(items, 'users', (x) => x), ['users', 'users_archive', 'user_logs']);
      expect(fuzzyRank(items, 'usr', (x) => x).first, 'users');
      expect(fuzzyRank(items, '', (x) => x), items);
      expect(fuzzyRank(items, 'zzz', (x) => x), isEmpty);
      // เท่ากัน -> ลำดับเดิม
      expect(fuzzyRank(['b1', 'a1'], '1', (x) => x), ['b1', 'a1']);
    });
  });

  group('CanvasController.centerOn / focusTable', () {
    test('centerOn วางจุดไว้กลางจอ', () {
      final cv = CanvasController()..viewport = const Size(1000, 600);
      cv.centerOn(const Offset(400, 300));
      expect(cv.toWorld(const Offset(500, 300)), const Offset(400, 300));
      cv.dispose();
    });

    test('ซูมออกไกล: ซูมเข้าให้อ่านออก แต่ไม่ลดถ้าซูมเข้าอยู่แล้ว', () {
      final cv = CanvasController()..viewport = const Size(1000, 600);
      cv.zoomAt(Offset.zero, 0.3);
      expect(cv.scale, lessThan(0.6));
      cv.centerOn(const Offset(10, 10), atLeastScale: 0.6);
      expect(cv.scale, 0.6);
      cv.zoomAt(Offset.zero, 2);
      final z = cv.scale;
      cv.centerOn(const Offset(10, 10), atLeastScale: 0.6);
      expect(cv.scale, z);
      cv.dispose();
    });

    test('focusTable วางกึ่งกลางตารางไว้กลางจอ', () {
      final cv = CanvasController()..viewport = const Size(1000, 600);
      final p = base();
      final t = tb(p, 'to')
        ..x = 700
        ..y = 400;
      cv.focusTable(t);
      final center = cv.toWorld(const Offset(500, 300));
      expect(center.dx, closeTo(t.x + t.width / 2, 0.01));
      expect(center.dy, closeTo(t.y + (36 + 28 * t.columns.length) / 2, 0.01));
      cv.dispose();
    });
  });

  group('paletteResults', () {
    PaletteEntry e(PaletteKind k, String title, {String? search}) =>
        PaletteEntry(kind: k, title: title, search: search ?? title, run: () {});
    final all = [
      e(PaletteKind.command, 'Export .sql', search: 'Export .sql export sql ddl'),
      e(PaletteKind.command, 'บันทึก', search: 'บันทึก save'),
      e(PaletteKind.table, 'users'),
      e(PaletteKind.column, 'users.email'),
      e(PaletteKind.column, 'orders.user_id'),
    ];

    test('ค้นว่าง: คำสั่งและตาราง ไม่รวมคอลัมน์', () {
      expect(paletteResults(all, '').map((x) => x.title), ['Export .sql', 'บันทึก', 'users']);
    });

    test('ค้นคำว่า users: ตารางมาก่อนคอลัมน์ที่ชื่อยาวกว่า', () {
      final r = paletteResults(all, 'users').map((x) => x.title).toList();
      expect(r.first, 'users');
      expect(r, contains('users.email'));
    });

    test('ค้นด้วยคำอังกฤษของคำสั่งภาษาไทย', () {
      expect(paletteResults(all, 'save').single.title, 'บันทึก');
    });

    test('limit', () {
      final many = [for (var i = 0; i < 100; i++) e(PaletteKind.table, 't$i')];
      expect(paletteResults(many, '', limit: 10).length, 10);
      expect(paletteResults(many, 't', limit: 10).length, 10);
    });
  });

  group('Command palette (widget)', () {
    Future<(ProjectController, CanvasController)> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      final ctx = tester.element(find.byType(HomePage));
      final c = ctx.read<ProjectController>();
      c.loadProject(base(), null);
      await tester.pump();
      return (c, ctx.read<CanvasController>());
    }

    Future<void> ctrlK(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+K เปิด, Esc ปิดโดยไม่ทำอะไร', (tester) async {
      final (c, _) = await boot(tester);
      await ctrlK(tester);
      expect(find.byType(CommandPalette), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsNothing);
      expect(c.dirty, false);
    });

    testWidgets('ค้นชื่อตาราง + Enter = เลือกตารางและเลื่อน canvas ไปที่ตาราง', (tester) async {
      final (c, cv) = await boot(tester);
      tb(c.project, 'to')
        ..x = 3000
        ..y = 2000;
      await ctrlK(tester);
      await tester.enterText(find.byType(TextField).last, 'orders');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.selectedTableId, 'to');
      final centerWorld = cv.toWorld(cv.viewport.center(Offset.zero));
      expect((centerWorld.dx - (3000 + 110)).abs(), lessThan(5));
    });

    testWidgets('ค้นคอลัมน์ orders.user_id = เลือกคอลัมน์นั้น', (tester) async {
      final (c, _) = await boot(tester);
      await ctrlK(tester);
      await tester.enterText(find.byType(TextField).last, 'orders.user');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.selectedTableId, 'to');
      expect(c.selectedColumnId, 'o2');
    });

    testWidgets('สั่งคำสั่งด้วยชื่อ: ใช้ PostgreSQL', (tester) async {
      final (c, _) = await boot(tester);
      await ctrlK(tester);
      await tester.enterText(find.byType(TextField).last, 'postgres');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.project.dialect, Dialect.postgres);
    });

    testWidgets('ลูกศรลง + Enter เลือกรายการที่สอง', (tester) async {
      final (c, _) = await boot(tester);
      await ctrlK(tester);
      await tester.enterText(find.byType(TextField).last, 'ใช้');
      await tester.pump();
      // รายการที่ตรงคือ "ใช้ <dialect>" 4 รายการ (เรียงตามความสั้นของชื่อ) — อ่านลำดับจริงจากหน้าจอ
      final titles = tester
          .widgetList<Text>(find.textContaining('ใช้ '))
          .map((t) => t.data!)
          .where((s) => s.startsWith('ใช้ '))
          .toList();
      expect(titles.length, 4);
      final second = Dialect.values.firstWhere((d) => 'ใช้ ${d.label}' == titles[1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.project.dialect, second);

      // ลูกศรขึ้นกลับมาที่รายการแรก
      await ctrlK(tester);
      await tester.enterText(find.byType(TextField).last, 'ใช้');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final first = Dialect.values.firstWhere((d) => 'ใช้ ${d.label}' == titles[0]);
      expect(c.project.dialect, first);
    });

    testWidgets('คลิกรายการ = ทำงาน', (tester) async {
      final (c, cv) = await boot(tester);
      await ctrlK(tester);
      await tester.enterText(find.byType(TextField).last, 'เพิ่มตาราง');
      await tester.pump();
      await tester.tap(find.byWidgetPredicate((w) => w is Text && w.data == 'เพิ่มตาราง'));
      await tester.pumpAndSettle();
      expect(cv.tool, CanvasTool.table);
      expect(c.project.tables.length, 2);
    });

    testWidgets('ไม่พบผลลัพธ์: แสดงข้อความ และ Enter ไม่ทำอะไร', (tester) async {
      final (c, _) = await boot(tester);
      await ctrlK(tester);
      await tester.enterText(find.byType(TextField).last, 'zzzzqqq');
      await tester.pump();
      expect(find.textContaining('ไม่พบ "zzzzqqq"'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget); // ยังเปิดอยู่
      expect(c.project.dialect, Dialect.mysql);
    });

    testWidgets('แสดงคีย์ลัดข้างคำสั่ง', (tester) async {
      await boot(tester);
      await ctrlK(tester);
      expect(find.text('Ctrl+N'), findsOneWidget);
      expect(find.text('Ctrl+S'), findsOneWidget);
    });
  });

  group('ค้นหาในแผงซ้าย', () {
    testWidgets('ค้นเจอที่คอลัมน์: แสดงคอลัมน์ใต้ตาราง คลิกแล้วเลือกและเลื่อนไปที่ตาราง', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      final ctx = tester.element(find.byType(HomePage));
      final c = ctx.read<ProjectController>();
      final cv = ctx.read<CanvasController>();
      c.loadProject(base(), null);
      tb(c.project, 'to')
        ..x = 4000
        ..y = 300;
      await tester.pump();

      final search = find.byWidgetPredicate((w) => w is TextField && w.focusNode == cv.searchFocus);
      await tester.enterText(search, 'user_id');
      await tester.pump();
      // คอลัมน์ที่ตรงแสดงใต้ตารางในแผงซ้าย (ในแผงซ้ายมีชื่อซ้ำกับการ์ดบน canvas จึงจำกัดที่แผงซ้าย)
      final hit = find.descendant(
          of: find.byType(ListView).first, matching: find.byWidgetPredicate((w) => w is Text && w.data == 'user_id'));
      expect(hit, findsOneWidget);
      await tester.tap(hit);
      await tester.pump();
      expect(c.selectedTableId, 'to');
      expect(c.selectedColumnId, 'o2');
      expect(cv.toWorld(cv.viewport.center(Offset.zero)).dx, closeTo(4110, 5));
    });

    testWidgets('Ctrl+F ย้ายโฟกัสไปช่องค้นหา', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      final cv = tester.element(find.byType(HomePage)).read<CanvasController>();
      expect(cv.searchFocus.hasFocus, false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(cv.searchFocus.hasFocus, true);
    });
  });
}
