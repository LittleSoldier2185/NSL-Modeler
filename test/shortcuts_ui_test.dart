import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/app_actions.dart';
import 'package:nsl_modeler/ui/canvas/canvas_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:nsl_modeler/ui/palette/command_palette.dart';
import 'package:nsl_modeler/ui/shortcuts.dart';
import 'package:nsl_modeler/ui/shortcuts_help.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

late ProjectController c;
late CanvasController cv;
String? clipboardText;

Future<void> boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  clipboardText = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboardText = (call.arguments as Map)['text'] as String?;
      return null;
    }
    if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clipboardText};
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

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

Future<void> press(WidgetTester tester, LogicalKeyboardKey key,
    {bool ctrl = false, bool shift = false, bool alt = false, String? character}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key, character: character);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Finder card(String id) => find.byKey(ValueKey('table-$id'));
Offset header(WidgetTester tester, String id) => tester.getTopLeft(card(id)) + const Offset(60, 16);

void main() {
  group('ข้อมูลคีย์ลัด', () {
    test('ไม่มีคีย์ลัดซ้ำกันสองคำสั่ง', () {
      final seen = <String, Cmd?>{};
      for (final s in kShortcuts) {
        final a = s.activator;
        if (a == null) continue;
        final key = '${a.trigger.keyId}|${a.control}|${a.shift}|${a.alt}|${a.meta}';
        expect(seen.containsKey(key), false, reason: '${s.keys} (${s.cmd}) ซ้ำกับ ${seen[key]}');
        seen[key] = s.cmd;
      }
    });

    test('คำสั่งทุกตัวมีคีย์ลัด และคีย์ลัดทุกตัวชี้คำสั่งจริง (ยกเว้นรายการอธิบายอย่างเดียว)', () {
      final mapped = kShortcuts.map((s) => s.cmd).whereType<Cmd>().toSet();
      expect(mapped, Cmd.values.toSet());
      for (final s in kShortcuts.where((s) => s.cmd == null)) {
        expect(s.activator, isNull);
        expect(s.keys, isNotEmpty);
      }
    });

    test('ทุกรายการที่แสดงใน F1 มีข้อความและคีย์', () {
      for (final s in visibleShortcuts) {
        expect(s.label, isNotEmpty);
        expect(s.keys, isNotEmpty, reason: s.label);
      }
    });

    test('คีย์ลัดครบตามแผน §6', () {
      String keys(Cmd k) => shortcutText(k);
      expect(keys(Cmd.newProject), 'Ctrl+N');
      expect(keys(Cmd.open), 'Ctrl+O');
      expect(keys(Cmd.save), 'Ctrl+S');
      expect(keys(Cmd.saveAs), 'Ctrl+Shift+S');
      expect(keys(Cmd.exportSql), 'Ctrl+E');
      expect(keys(Cmd.exportImage), 'Ctrl+Shift+E');
      expect(keys(Cmd.undo), 'Ctrl+Z');
      expect(keys(Cmd.redo), 'Ctrl+Y');
      expect(keys(Cmd.copy), 'Ctrl+C');
      expect(keys(Cmd.paste), 'Ctrl+V');
      expect(keys(Cmd.duplicate), 'Ctrl+D');
      expect(keys(Cmd.delete), 'Delete');
      expect(keys(Cmd.selectAll), 'Ctrl+A');
      expect(keys(Cmd.rename), 'F2');
      expect(keys(Cmd.toolTable), 'T');
      expect(keys(Cmd.toolFk), 'F');
      expect(keys(Cmd.toolNote), 'N');
      expect(keys(Cmd.escape), 'Esc');
      expect(keys(Cmd.fit), 'Ctrl+0');
      expect(keys(Cmd.zoom100), 'Ctrl+1');
      expect(keys(Cmd.find), 'Ctrl+F');
      expect(keys(Cmd.palette), 'Ctrl+K');
      expect(keys(Cmd.help), 'F1 หรือ ?');
    });
  });

  testWidgets('AppActions มีการทำงานให้ทุกคำสั่ง', (tester) async {
    await boot(tester);
    final map = AppActions(tester.element(find.byType(HomePage))).map;
    expect(map.keys.toSet(), Cmd.values.toSet());
  });

  group('เลือกหลายตาราง', () {
    testWidgets('คลิกธรรมดาเลือกตัวเดียว; Ctrl+คลิกเพิ่ม; Ctrl+คลิกซ้ำเอาออก', (tester) async {
      await boot(tester);
      await tester.tapAt(header(tester, 'tu'));
      await tester.pump();
      expect(c.selectedTableIds, {'tu'});

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(header(tester, 'to'));
      await tester.pump();
      expect(c.selectedTableIds, {'tu', 'to'});
      await tester.tapAt(header(tester, 'to'));
      await tester.pump();
      expect(c.selectedTableIds, {'tu'});
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      // Shift+คลิกก็เพิ่มเช่นกัน
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(header(tester, 'to'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.selectedTableIds, {'tu', 'to'});
    });

    testWidgets('ลากตารางที่อยู่ในกลุ่ม = ย้ายทั้งกลุ่ม เป็น undo ขั้นเดียว', (tester) async {
      await boot(tester);
      c.selectAllTables();
      await tester.pump();
      final before = (tb(c.project, 'tu').x, tb(c.project, 'to').x);
      await tester.dragFrom(header(tester, 'tu'), const Offset(100, 50));
      await tester.pump();
      expect(tb(c.project, 'tu').x, greaterThan(before.$1 + 50));
      expect(tb(c.project, 'to').x, greaterThan(before.$2 + 50));
      expect(tb(c.project, 'to').x - tb(c.project, 'tu').x, closeTo(before.$2 - before.$1, 0.001));
      c.undo();
      expect((tb(c.project, 'tu').x, tb(c.project, 'to').x), before);
    });

    testWidgets('ลากตารางที่ไม่อยู่ในกลุ่ม = เลือกมันตัวเดียวแล้วย้ายตัวเดียว', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      final toX = tb(c.project, 'to').x;
      await tester.dragFrom(header(tester, 'to'), const Offset(80, 0));
      await tester.pump();
      expect(c.selectedTableIds, {'to'});
      expect(tb(c.project, 'to').x, greaterThan(toX + 40));
      expect(tb(c.project, 'tu').x, 40);
    });

    testWidgets('Space + ลาก = เลื่อนมุมมอง ไม่ย้ายตาราง', (tester) async {
      await boot(tester);
      final before = (tb(c.project, 'tu').x, tb(c.project, 'tu').y);
      final off = cv.offset;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.dragFrom(header(tester, 'tu'), const Offset(60, 40));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect((tb(c.project, 'tu').x, tb(c.project, 'tu').y), before);
      expect((cv.offset - off).distance, greaterThan(30));
      expect(c.canUndo, false); // ไม่ใช่การแก้ข้อมูล
    });

    testWidgets('แผงซ้าย: Ctrl+คลิกชื่อตารางเลือกเพิ่ม; แผงขวาแสดงจำนวนและปุ่มกลุ่ม', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.descendant(of: find.byType(ListView).first, matching: find.text('orders')));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.selectedTableIds, {'tu', 'to'});
      expect(find.textContaining('เลือกอยู่ 2 ตาราง'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'ลบ'));
      await tester.pump();
      expect(c.project.tables, isEmpty);
    });
  });

  group('คีย์ลัดแก้ไข', () {
    testWidgets('Ctrl+A เลือกทุกตาราง', (tester) async {
      await boot(tester);
      await press(tester, LogicalKeyboardKey.keyA, ctrl: true);
      expect(c.selectedTableIds, {'tu', 'to'});
    });

    testWidgets('Delete ลบตารางที่เลือก (หลายตัวพร้อมกัน) และ undo ได้ขั้นเดียว', (tester) async {
      await boot(tester);
      await press(tester, LogicalKeyboardKey.keyA, ctrl: true);
      await press(tester, LogicalKeyboardKey.delete);
      expect(c.project.tables, isEmpty);
      await press(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(c.project.tables.length, 2);
    });

    testWidgets('Delete เมื่อเลือกคอลัมน์ (ตารางเดียว) ลบแค่คอลัมน์', (tester) async {
      await boot(tester);
      c.selectTable('tu', columnId: 'u4');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.delete);
      expect(tb(c.project, 'tu').columnById('u4'), isNull);
      expect(c.project.tables.length, 2);
    });

    testWidgets('Ctrl+C แล้ว Ctrl+V วางสำเนา (ชื่อต่อท้าย _1) และเลือกสำเนา', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyC, ctrl: true);
      expect(clipboardText, contains('nsl-modeler-tables'));
      await press(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await tester.pump();
      expect(c.project.tables.length, 3);
      expect(c.selectedTable!.name, 'users_1');
      // วางซ้ำเลื่อนตำแหน่งต่อไป ไม่ทับกัน
      final first = c.selectedTable!;
      await press(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await tester.pump();
      expect(c.project.tables.length, 4);
      expect(c.selectedTable!.x, greaterThan(first.x));
      expect(c.selectedTable!.name, 'users_2');
    });

    testWidgets('Ctrl+V เมื่อคลิปบอร์ดเป็นข้อความทั่วไป: ไม่ทำอะไร แจ้งผู้ใช้', (tester) async {
      await boot(tester);
      clipboardText = 'สวัสดี';
      await press(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await tester.pump();
      expect(c.project.tables.length, 2);
      expect(find.textContaining('ไม่มีตารางของ NSL Modeler ในคลิปบอร์ด'), findsOneWidget);
    });

    testWidgets('Ctrl+D ทำสำเนากลุ่มพร้อม FK ระหว่างกัน', (tester) async {
      await boot(tester);
      await press(tester, LogicalKeyboardKey.keyA, ctrl: true);
      await press(tester, LogicalKeyboardKey.keyD, ctrl: true);
      expect(c.project.tables.length, 4);
      expect(c.project.relations.length, 2);
    });

    testWidgets('ลูกศรขยับ 10 px, Shift+ลูกศร 50 px, ขยับไม่ได้เมื่อชนขอบ', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(tb(c.project, 'tu').x, 50);
      await press(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(tb(c.project, 'tu').y, 110);
      await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      expect(tb(c.project, 'tu').x, 0); // ไม่ติดลบ
      c.undo();
      expect(tb(c.project, 'tu').x, greaterThan(0)); // undo ทีละการกด
    });

    testWidgets('F2 เปลี่ยนชื่อตารางที่เลือก', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('เปลี่ยนชื่อตาราง'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'members');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').name, 'members');
    });

    testWidgets('F2 เมื่อเลือกคอลัมน์ = เปลี่ยนชื่อคอลัมน์; ยกเลิก/ชื่อเดิม ไม่สร้างประวัติ', (tester) async {
      await boot(tester);
      c.selectTable('tu', columnId: 'u3');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('เปลี่ยนชื่อคอลัมน์'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(c.canUndo, false);

      await press(tester, LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'full_name');
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
      expect(cl(c.project, 'tu', 'u3').name, 'full_name');
    });

    testWidgets('Esc: ยกเลิกเครื่องมือก่อน แล้วค่อยล้างการเลือก', (tester) async {
      await boot(tester);
      c.selectAllTables();
      cv.setTool(CanvasTool.fk);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.escape);
      expect(cv.tool, CanvasTool.select);
      expect(c.selectionCount, 2); // ยังเลือกอยู่
      await press(tester, LogicalKeyboardKey.escape);
      expect(c.selectionCount, 0);
    });
  });

  group('ไม่รบกวนการพิมพ์ในช่องข้อความ', () {
    testWidgets('พิมพ์ T/F/N ในช่องค้นหาไม่เปลี่ยนเครื่องมือ', (tester) async {
      await boot(tester);
      await press(tester, LogicalKeyboardKey.keyF, ctrl: true); // โฟกัสช่องค้นหา
      expect(cv.searchFocus.hasFocus, true);
      await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.focusNode == cv.searchFocus), '');
      await press(tester, LogicalKeyboardKey.keyT);
      await press(tester, LogicalKeyboardKey.keyN);
      await press(tester, LogicalKeyboardKey.keyF);
      expect(cv.tool, CanvasTool.select);
    });

    testWidgets('Delete / ลูกศร / Ctrl+A / Ctrl+C ในช่องข้อความไม่กระทบตาราง', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      cv.searchFocus.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.delete);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.keyA, ctrl: true);
      await press(tester, LogicalKeyboardKey.keyD, ctrl: true);
      expect(c.project.tables.length, 2);
      expect(tb(c.project, 'tu').x, 40);
      expect(c.selectedTableIds, {'tu'}); // Ctrl+A ไม่ได้เลือกทุกตาราง
    });

    testWidgets('คีย์ระดับแอปยังทำงานขณะพิมพ์: Ctrl+K เปิด palette, F1 เปิดหน้าคีย์ลัด', (tester) async {
      await boot(tester);
      cv.searchFocus.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyK, ctrl: true);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      cv.searchFocus.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsHelpDialog), findsOneWidget);
    });

    testWidgets('Ctrl+Z ในช่องข้อความไม่ undo โปรเจกต์ (ปล่อยให้ช่องข้อความจัดการ)', (tester) async {
      await boot(tester);
      c.addTable(name: 'x');
      cv.searchFocus.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(c.project.tables.length, 3);
    });
  });

  group('หน้าคีย์ลัด (F1 / ?)', () {
    testWidgets('F1 เปิด และแสดงรายการทุกกลุ่มพร้อมคีย์', (tester) async {
      await boot(tester);
      await press(tester, LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsHelpDialog), findsOneWidget);
      for (final g in ShortcutsHelpDialog.groupOrder) {
        expect(find.descendant(of: find.byType(ShortcutsHelpDialog), matching: find.text(g)), findsOneWidget);
      }
      expect(find.text('Ctrl+Shift+S'), findsOneWidget);
      expect(find.text('Space + ลาก'), findsOneWidget);
      expect(find.text('ทำสำเนาตาราง'), findsOneWidget);
      await tester.tap(find.text('ปิด'));
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsHelpDialog), findsNothing);
    });

    testWidgets('กด ? เปิดหน้าคีย์ลัด', (tester) async {
      await boot(tester);
      // ผู้ใช้กด Shift+/ ได้ตัวอักษร ? (ตัวจำลองไม่มีปุ่มฟิสิคัลของ question)
      await press(tester, LogicalKeyboardKey.slash, shift: true, character: '?');
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsHelpDialog), findsOneWidget);
    });

    testWidgets('ทุกแถวใน F1 มาจาก kShortcuts (ไม่มีรายการลอย)', (tester) async {
      await boot(tester);
      await press(tester, LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      for (final s in visibleShortcuts) {
        expect(find.text(s.label), findsWidgets, reason: s.label);
      }
    });
  });

  group('เมนู', () {
    testWidgets('เมนูแก้ไขแสดงคีย์ลัด และปุ่มที่ใช้ไม่ได้ถูกปิด', (tester) async {
      await boot(tester);
      await tester.tap(find.text('แก้ไข'));
      await tester.pumpAndSettle();
      expect(find.text('Ctrl+C'), findsOneWidget);
      expect(find.text('Ctrl+D'), findsOneWidget);
      expect(find.text('F2'), findsOneWidget);
      final copy = tester.widget<PopupMenuItem<VoidCallback>>(find.widgetWithText(PopupMenuItem<VoidCallback>, 'คัดลอกตาราง'));
      expect(copy.enabled, false); // ยังไม่ได้เลือกอะไร
      final selectAll = tester.widget<PopupMenuItem<VoidCallback>>(find.widgetWithText(PopupMenuItem<VoidCallback>, 'เลือกทุกตาราง'));
      expect(selectAll.enabled, true);
    });

    testWidgets('เมนูมุมมอง/ช่วยเหลือมีอยู่ และ "เลือกทุกตาราง" ทำงาน', (tester) async {
      await boot(tester);
      await tester.tap(find.text('แก้ไข'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เลือกทุกตาราง'));
      await tester.pumpAndSettle();
      expect(c.selectionCount, 2);

      await tester.tap(find.text('ช่วยเหลือ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ดูคีย์ลัดทั้งหมด'));
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsHelpDialog), findsOneWidget);
    });
  });

  testWidgets('สลับ dialect ด้วย Alt+1..4 ยังทำงานผ่านตัวดักปุ่มใหม่', (tester) async {
    await boot(tester);
    await press(tester, LogicalKeyboardKey.digit3, alt: true);
    expect(c.project.dialect, Dialect.sqlite);
    await press(tester, LogicalKeyboardKey.digit4, alt: true);
    expect(c.project.dialect, Dialect.mssql);
    await press(tester, LogicalKeyboardKey.digit1, alt: true);
    expect(c.project.dialect, Dialect.mysql);
  });

  testWidgets('T / F / N เปลี่ยนเครื่องมือ; Ctrl+T ไม่ใช่ T', (tester) async {
    await boot(tester);
    await press(tester, LogicalKeyboardKey.keyT);
    expect(cv.tool, CanvasTool.table);
    await press(tester, LogicalKeyboardKey.keyF);
    expect(cv.tool, CanvasTool.fk);
    await press(tester, LogicalKeyboardKey.keyN);
    expect(cv.tool, CanvasTool.note);
    cv.setTool(CanvasTool.select);
    await press(tester, LogicalKeyboardKey.keyT, ctrl: true);
    expect(cv.tool, CanvasTool.select);
  });
}
