import 'package:flutter/gestures.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/core/models/group_model.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/canvas/canvas_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:nsl_modeler/ui/left_panel.dart';
import 'package:nsl_modeler/ui/right_panel.dart';
import 'package:nsl_modeler/ui/sql_dock.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  group('PanelLayout', () {
    test('ค่าเริ่มต้นเท่าเดิม และค่าที่ตั้งถูกบีบให้อยู่ในช่วง', () {
      final l = PanelLayout();
      expect((l.left, l.right, l.dock), (248.0, 320.0, 248.0));
      l.setLeft(10);
      l.setRight(9999);
      l.setDock(1);
      expect((l.left, l.right, l.dock), (PanelLayout.kLeftMin, PanelLayout.kRightMax, PanelLayout.kDockMin));
      l.resetLeft();
      l.resetRight();
      l.resetDock();
      expect((l.left, l.right, l.dock), (248.0, 320.0, 248.0));
    });

    test('แจ้งเตือนเฉพาะเมื่อค่าเปลี่ยนจริง', () {
      final l = PanelLayout();
      var n = 0;
      l.addListener(() => n++);
      l.setLeft(248);
      expect(n, 0);
      l.setLeft(300);
      expect(n, 1);
    });

    test('หน้าต่างกว้างพอ = ใช้ค่าเดิม; หน้าต่างแคบ = บีบสองแผงตามสัดส่วนแต่ไม่ต่ำกว่าขั้นต่ำ และไม่แก้ค่าที่จำไว้', () {
      final l = PanelLayout()
        ..setLeft(400)
        ..setRight(500);
      expect(l.effectiveWidths(1600), (400.0, 500.0));
      final (a, b) = l.effectiveWidths(1000); // เหลือ canvas ต่ำสุด 320 -> สองแผงรวมไม่เกิน 680
      expect(a + b, lessThanOrEqualTo(1000 - PanelLayout.kCanvasMinWidth + 1));
      expect(a, greaterThanOrEqualTo(PanelLayout.kLeftMin));
      expect(b, greaterThanOrEqualTo(PanelLayout.kRightMin));
      expect((l.left, l.right), (400.0, 500.0)); // ค่าจริงยังอยู่
      // แคบจนเหลือไม่พอแม้ที่ขั้นต่ำ: ไม่คำนวณจนติดลบ
      final (c, d) = l.effectiveWidths(500);
      expect(c, 400.0);
      expect(d, 500.0);
    });

    test('ความสูงแผง SQL ถูกจำกัดให้ canvas เหลือพื้นที่', () {
      final l = PanelLayout()..setDock(600);
      expect(l.effectiveDock(1000), 600);
      expect(l.effectiveDock(500), 500 - PanelLayout.kCanvasMinHeight);
      expect(l.effectiveDock(100), PanelLayout.kDockMin);
    });

    test('บันทึก/อ่านผ่านไฟล์การตั้งค่า และค่าเสียถูกแทนด้วยค่าเริ่มต้น', () {
      final dir = Directory.systemTemp.createTempSync('nsl_layout');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/settings.json');
      final s = AppSettings.load(f)..setLang(Lang.th);
      s.layout
        ..setLeft(300)
        ..setRight(400)
        ..setDock(200);
      s.commitLayout();
      final back = AppSettings.load(f);
      expect((back.layout.left, back.layout.right, back.layout.dock), (300.0, 400.0, 200.0));

      f.writeAsStringSync('{"lang":"th","layout":{"left":"x","right":-5,"dock":1e9}}');
      final bad = AppSettings.load(f);
      expect(bad.layout.left, 248.0); // ไม่ใช่ตัวเลข -> ค่าเริ่มต้น
      expect(bad.layout.right, PanelLayout.kRightMin); // ติดลบ -> บีบเข้าช่วง
      expect(bad.layout.dock, PanelLayout.kDockMax);
    });
  });

  group('ลากขอบแผง', () {
    late ProjectController c;
    late CanvasController cv;
    late AppSettings settings;

    Future<void> boot(WidgetTester tester, {Size size = const Size(1440, 900), File? file}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      settings = file == null ? AppSettings(lang: Lang.th) : AppSettings.load(file);
      if (file != null) settings.setLang(Lang.th);
      await tester.pumpWidget(NslModelerApp(settings: settings));
      final ctx = tester.element(find.byType(HomePage));
      c = ctx.read<ProjectController>();
      cv = ctx.read<CanvasController>();
      c.loadProject(base(), null);
      await tester.pump();
    }

    /// ลากแถบแล้วรอให้ timer ท้ายท่าทาง (double-tap) หมดก่อนจบเทสต์
    Future<void> dragSplitter(WidgetTester tester, String key, Offset by) async {
      await tester.drag(find.byKey(ValueKey(key)), by);
      await tester.pump(const Duration(milliseconds: 500));
    }

    double leftW(WidgetTester t) => t.getSize(find.byType(LeftPanel)).width;
    double rightW(WidgetTester t) => t.getSize(find.byType(RightPanel)).width;
    double dockH(WidgetTester t) => t.getSize(find.byType(SqlDock)).height;

    testWidgets('ลากขอบแผงซ้ายไปขวา = แผงกว้างขึ้น; ลากเกินสุด = หยุดที่ขีดจำกัด', (tester) async {
      await boot(tester);
      expect(leftW(tester), 248);
      await dragSplitter(tester, 'splitter-left', const Offset(100, 0));
      expect(leftW(tester), closeTo(348, 20)); // หักระยะ slop ของท่าทาง
      await dragSplitter(tester, 'splitter-left', const Offset(900, 0));
      expect(leftW(tester), PanelLayout.kLeftMax);
      await dragSplitter(tester, 'splitter-left', const Offset(-900, 0));
      expect(leftW(tester), PanelLayout.kLeftMin);
    });

    testWidgets('ลากขอบแผงขวาไปซ้าย = แผงกว้างขึ้น', (tester) async {
      await boot(tester);
      expect(rightW(tester), 320);
      await dragSplitter(tester, 'splitter-right', const Offset(-120, 0));
      expect(rightW(tester), closeTo(440, 20));
    });

    testWidgets('ลากขอบบนของแผง SQL ขึ้น = สูงขึ้น; ลงจนสุด = ต่ำสุด', (tester) async {
      await boot(tester);
      expect(dockH(tester), 248);
      await dragSplitter(tester, 'splitter-dock', const Offset(0, -100));
      expect(dockH(tester), closeTo(348, 20));
      await dragSplitter(tester, 'splitter-dock', const Offset(0, 900));
      expect(dockH(tester), PanelLayout.kDockMin);
    });

    testWidgets('แผง SQL ย่ออยู่ = ไม่มีแถบลาก; ขยายแล้วกลับมา', (tester) async {
      await boot(tester);
      cv.toggleDockCollapsed();
      await tester.pump();
      expect(find.byKey(const ValueKey('splitter-dock')), findsNothing);
      expect(dockH(tester), 44);
      cv.toggleDockCollapsed();
      await tester.pump();
      expect(find.byKey(const ValueKey('splitter-dock')), findsOneWidget);
    });

    testWidgets('ดับเบิลคลิกแถบ = คืนขนาดเริ่มต้น', (tester) async {
      await boot(tester);
      settings.layout
        ..setLeft(400)
        ..setRight(450)
        ..setDock(400);
      await tester.pump();
      for (final k in ['splitter-left', 'splitter-right', 'splitter-dock']) {
        final f = find.byKey(ValueKey(k));
        await tester.tap(f);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(f);
        await tester.pumpAndSettle();
      }
      expect((leftW(tester), rightW(tester), dockH(tester)), (248.0, 320.0, 248.0));
    });

    testWidgets('ลากเสร็จแล้วบันทึกลงไฟล์ และเปิดครั้งหน้าได้ขนาดเดิม', (tester) async {
      final dir = Directory.systemTemp.createTempSync('nsl_layout_ui');
      addTearDown(() => dir.deleteSync(recursive: true));
      // ปิดแอนิเมชันเส้น (ค่าเริ่มต้นของแอปจริงคือเล่นตลอดเวลา ซึ่งทำให้ pumpAndSettle ไม่จบ)
      final f = File('${dir.path}/settings.json')..writeAsStringSync('{"flowAnim": false}');
      await boot(tester, file: f);
      await tester.drag(find.byKey(const ValueKey('splitter-left')), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(f.readAsStringSync(), contains('"layout"'));
      final saved = settings.layout.left;
      expect(saved, greaterThan(248));

      await tester.pumpWidget(const SizedBox()); // ปิดแอป
      await boot(tester, file: f);
      expect(leftW(tester), closeTo(saved, 0.5));
    });

    testWidgets('ลากขอบแล้วงานบน canvas ไม่หาย และ canvas ยังใช้งานได้ (ลากตารางได้)', (tester) async {
      await boot(tester);
      final before = c.project.tables.length;
      await dragSplitter(tester, 'splitter-left', const Offset(60, 0));
      expect(c.project.tables.length, before);
      expect(c.canUndo, false); // ขนาดแผงไม่เข้า undo
      expect(tester.takeException(), isNull);
    });

    testWidgets('หน้าต่างแคบมาก: canvas ยังเหลือพื้นที่และไม่มี overflow', (tester) async {
      await boot(tester, size: const Size(800, 600));
      settings.layout
        ..setLeft(480)
        ..setRight(560);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(LeftPanel)).width + tester.getSize(find.byType(RightPanel)).width,
          lessThanOrEqualTo(800 - PanelLayout.kCanvasMinWidth + 1));
    });
  });

  group('แถบหัว SQL ไม่ล้น (Row overflow)', () {
    for (final size in const [Size(1440, 900), Size(1100, 700), Size(900, 600), Size(780, 560), Size(760, 520)]) {
      testWidgets('ขนาดหน้าต่าง ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: Lang.th)));
        tester.element(find.byType(HomePage)).read<ProjectController>().loadProject(base(), null);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // ขยายปัญหาด้วย: แท็บ "ปัญหา" มีตัวเลข badge และปุ่มคัดลอกแสดงอยู่
        expect(find.text('SQL Preview'), findsOneWidget);
      });
    }

    testWidgets('ภาษาอังกฤษ (ข้อความยาวกว่า) ที่หน้าต่างแคบ ก็ไม่ล้น', (tester) async {
      tester.view.physicalSize = const Size(800, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: Lang.en)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      currentLang = Lang.th;
    });
  });

  group('แผงขวา: ช่องชื่อตาราง / หมายเหตุ', () {
    testWidgets('ชื่อตารางสูงขึ้น และหมายเหตุเป็นหลายบรรทัดที่ใหญ่กว่าเดิมมาก; Enter ในหมายเหตุขึ้นบรรทัดใหม่ แล้วบันทึกเมื่อออกจากช่อง', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: Lang.th)));
      final c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(base(), null);
      c.selectTable('tu');
      await tester.pumpAndSettle();

      final fields = find.descendant(of: find.byType(RightPanel), matching: find.byType(TextField));
      final nameBox = tester.getSize(fields.at(0));
      final commentBox = tester.getSize(fields.at(1));
      expect(nameBox.height, greaterThanOrEqualTo(42)); // เดิม 34
      expect(commentBox.height, greaterThanOrEqualTo(90)); // เดิม 34 (บรรทัดเดียว)
      expect(tester.widget<TextField>(fields.at(1)).minLines, 4);
      expect(tester.widget<TextField>(fields.at(1)).maxLines, 10);

      await tester.enterText(fields.at(1), 'บรรทัดแรก\nบรรทัดสอง');
      await tester.pump();
      expect(c.project.tables.first.comment, isNot('บรรทัดแรก\nบรรทัดสอง')); // ยังไม่บันทึกจนกว่าจะออกจากช่อง
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(c.project.tables.first.comment, 'บรรทัดแรก\nบรรทัดสอง');
    });
  });

  group('เลือกกลุ่มและลบด้วย Delete', () {
    late ProjectController c;
    late CanvasController cv;

    Future<GroupModel> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: Lang.th, snapToGrid: false)));
      final ctx = tester.element(find.byType(HomePage));
      c = ctx.read<ProjectController>();
      cv = ctx.read<CanvasController>();
      c.loadProject(base(), null);
      tb(c.project, 'tu')
        ..x = 100
        ..y = 160;
      tb(c.project, 'to')
        ..x = 500
        ..y = 160;
      final g = c.addGroup(x: 60, y: 60, width: 340, height: 360, name: 'G');
      await tester.pump();
      return g;
    }

    Finder header(GroupModel g) => find.byKey(ValueKey('group-header-${g.id}'));

    testWidgets('คลิกแถบชื่อ = เลือกกลุ่ม (และล้างตารางที่เลือก)', (tester) async {
      final g = await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      await tester.tapAt(tester.getTopLeft(header(g)) + const Offset(150, 16));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selectedGroupId, g.id);
      expect(c.selectedTableIds, isEmpty);
    });

    testWidgets('กด Delete ตอนเลือกกลุ่ม = ลบกลุ่ม ตารางไม่ถูกลบ และ undo กู้คืนกลุ่มได้', (tester) async {
      final g = await boot(tester);
      c.selectGroup(g.id);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.project.groups, isEmpty);
      expect(c.project.tables.length, 2);
      expect(c.selectedGroupId, isNull);
      c.undo();
      expect(c.project.groups.length, 1);
      expect(c.project.groups.single.name, 'G');
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('เลือกตารางแล้ว Delete = ลบตาราง ไม่ใช่กลุ่ม', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.project.tables.map((t) => t.id), ['to']);
      expect(c.project.groups.length, 1);
    });

    testWidgets('เลือกตาราง / คลิกพื้นว่าง / Esc = ล้างการเลือกกลุ่ม', (tester) async {
      final g = await boot(tester);
      c.selectGroup(g.id);
      c.selectTable('to');
      expect(c.selectedGroupId, isNull);

      c.selectGroup(g.id);
      await tester.pump();
      await tester.tapAt(const Offset(1050, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selectedGroupId, isNull);

      c.selectGroup(g.id);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.selectedGroupId, isNull);
    });

    testWidgets('ลากแถบชื่อ = เลือกกลุ่มไปด้วย', (tester) async {
      final g = await boot(tester);
      await tester.dragFrom(tester.getTopLeft(header(g)) + const Offset(150, 16), const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selectedGroupId, g.id);
    });

    testWidgets('F2 ตอนเลือกกลุ่ม = พิมพ์ชื่อบนแถบชื่อ', (tester) async {
      final g = await boot(tester);
      c.selectGroup(g.id);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('group-name-field-${g.id}')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets('Delete ขณะพิมพ์ชื่อกลุ่ม = ลบตัวอักษร ไม่ลบกลุ่ม', (tester) async {
      final g = await boot(tester);
      c.selectGroup(g.id);
      cv.requestGroupEdit(g.id);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('group-name-field-${g.id}')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.project.groups.length, 1);
    });

    testWidgets('คลิกขวาที่กลุ่มเลือกกลุ่มนั้นก่อนเปิดเมนู', (tester) async {
      final g = await boot(tester);
      final gs = await tester.startGesture(tester.getTopLeft(header(g)) + const Offset(150, 16),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gs.up();
      await tester.pumpAndSettle();
      expect(c.selectedGroupId, g.id);
      expect(find.text('ลบกลุ่ม (ไม่ลบตาราง)'), findsOneWidget);
    });
  });
}
