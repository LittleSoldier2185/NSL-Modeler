import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/export/svg_export.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/core/layout/diagram_geometry.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/export/diagram_png.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// users ซ้าย orders ขวา: เส้น FK ยาวพอวางเครื่องหมาย
Project placed() {
  final p = base();
  tb(p, 'tu')
    ..x = 40
    ..y = 100;
  tb(p, 'to')
    ..x = 700
    ..y = 160;
  return p;
}

void main() {
  group('relationFlowMarker (ทิศจากแม่ไปลูก)', () {
    test('ช่วงแนวนอนที่ยาวสุด: ชี้จากแม่ไปลูก (ย้อนทิศของเส้นที่เรียงจากลูกไปแม่)', () {
      // route: ลูก (0,0) -> ... -> แม่ (200,0) ; ข้อมูลไหลจากแม่ไปลูก = ไปทางซ้าย (-1,0)
      final m = relationFlowMarker([(0.0, 0.0), (200.0, 0.0)])!;
      expect((m.x, m.y), (100, 0));
      expect((m.dx, m.dy), (-1, 0));
    });

    test('เลือกช่วงที่ยาวที่สุด และคำนวณทิศแนวตั้ง', () {
      // ลูก (0,0) -> (30,0) -> (30,300) -> (60,300) ; ช่วงยาวสุดคือแนวตั้ง ลง (ไปหาแม่) ข้อมูลไหลขึ้น (0,-1)
      final m = relationFlowMarker([(0.0, 0.0), (30.0, 0.0), (30.0, 300.0), (60.0, 300.0)])!;
      expect((m.x, m.y), (30, 150));
      expect((m.dx, m.dy), (0, -1));
    });

    test('เส้นสั้นเกินไปไม่วางเครื่องหมาย', () {
      expect(relationFlowMarker([(0.0, 0.0), (40.0, 0.0)]), isNull);
      expect(relationFlowMarker([(0.0, 0.0), (40.0, 0.0)], minLength: 20), isNotNull);
      expect(relationFlowMarker([]), isNull);
    });
  });

  group('ตั้งค่า', () {
    test('ค่าเริ่มต้น: โชว์ทิศทาง เปิด; อนิเมชัน ปิดเมื่อสร้างเอง (เทสต์) แต่เปิดเมื่อโหลดครั้งแรกในแอปจริง', () {
      final s = AppSettings(lang: Lang.th);
      expect((s.showFlow, s.flowAnimation), (true, false));
      final dir = Directory.systemTemp.createTempSync('nsl_settings');
      addTearDown(() => dir.deleteSync(recursive: true));
      final first = AppSettings.load(File('${dir.path}/settings.json'));
      expect((first.showFlow, first.flowAnimation, first.flowAlways), (true, true, true));
    });

    test('เล่นตลอดเวลา/ความเร็ว: ค่าเริ่มต้น ปิด/ปกติ และบันทึก-โหลดกลับ', () {
      final dir = Directory.systemTemp.createTempSync('nsl_settings');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/settings.json');
      final s = AppSettings(lang: Lang.th, file: f);
      expect((s.flowAlways, s.flowSpeed), (false, FlowSpeed.normal));
      s.setFlowAlways(true);
      s.setFlowSpeed(FlowSpeed.slow);
      final back = AppSettings.load(f);
      expect((back.flowAlways, back.flowSpeed), (true, FlowSpeed.slow));
      expect(FlowSpeed.fromName('???'), FlowSpeed.normal);
    });

    test('บันทึกและโหลดกลับ', () {
      final dir = Directory.systemTemp.createTempSync('nsl_settings');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/settings.json');
      final s = AppSettings(lang: Lang.th, file: f);
      s.setShowFlow(false);
      s.setFlowAnimation(true);
      final back = AppSettings.load(f);
      expect((back.showFlow, back.flowAnimation), (false, true));
      s.setFlowAnimation(false);
      expect(AppSettings.load(f).flowAnimation, false);
    });
  });

  group('Export', () {
    test('SVG: มีเครื่องหมายต่อ 1 เส้นเมื่อเปิด; ไม่มีเมื่อปิด (ค่าเริ่มต้น)', () {
      final proj = placed();
      final off = exportSvg(proj)!;
      final on = exportSvg(proj, flowMarkers: true)!;
      expect('r="9.5"'.allMatches(off).length, 0);
      expect('r="9.5"'.allMatches(on).length, 2 * proj.relations.length); // วงกลมพื้น + วงกลมขอบ
      expect(on, contains('stroke-linejoin="round"'));
    });

    testWidgets('PNG: ภาพต่างกันเมื่อเปิดเครื่องหมาย', (tester) async {
      final proj = placed();
      final bytes = await tester.runAsync(() async {
        final a = await exportPng(proj, scale: 1);
        final b = await exportPng(proj, scale: 1, flowMarkers: true);
        return (a!.bytes, b!.bytes);
      });
      expect(bytes!.$1.length == bytes.$2.length && _same(bytes.$1, bytes.$2), false);
    });
  });

  group('บนจอ', () {
    late ProjectController c;
    late AppSettings settings;

    Future<void> boot(WidgetTester tester, {bool animate = false}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      settings = AppSettings(lang: Lang.th, flowAnimation: animate);
      await tester.pumpWidget(NslModelerApp(settings: settings));
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(placed(), null);
      await tester.pump();
    }

    testWidgets('อนิเมชันวิ่งเมื่อเปิดและมีตารางที่เลือก; หยุดเมื่อไม่ได้เลือก/ปิดตัวเลือก', (tester) async {
      await boot(tester, animate: true);
      await tester.pump(const Duration(seconds: 2)); // รอให้อนิเมชันเปิดแอปจบก่อน
      expect(tester.binding.transientCallbackCount, 0); // ยังไม่ได้เลือกอะไร = ไม่วิ่ง
      c.selectTable('tu');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      c.selectTable(null);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      c.selectTable('tu');
      await tester.pump();
      settings.setFlowAnimation(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('เล่นตลอดเวลา: วิ่งแม้ไม่ได้เลือกอะไร; ปิดตัวเลือก/ปิดอนิเมชัน = หยุด', (tester) async {
      await boot(tester, animate: true);
      settings.setFlowAlways(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      settings.setFlowAlways(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      settings.setFlowAlways(true);
      await tester.pump();
      settings.setFlowAnimation(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('ปิดอนิเมชัน (ค่าเริ่มต้นในเทสต์): เลือกตารางแล้ว pumpAndSettle จบ', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('เมนูมุมมองสลับการแสดงทิศทาง/อนิเมชันได้', (tester) async {
      await boot(tester);
      await tester.tap(find.text('มุมมอง'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เส้นความสัมพันธ์ (FK)…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('line-flow')));
      await tester.pumpAndSettle();
      expect(settings.showFlow, false);

      await tester.tap(find.byKey(const ValueKey('line-anim')));
      await tester.pumpAndSettle();
      expect(settings.flowAnimation, true);
      // ตัวเลือกเล่นตลอดเวลา/ความเร็ว ใช้ได้เมื่อเปิดอนิเมชัน
      // โหมดเล่นตลอดเวลาวิ่งไม่หยุด จึงใช้ pump() ไม่ใช่ pumpAndSettle()
      await tester.tap(find.byKey(const ValueKey('line-always')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(settings.flowAlways, true);
      await tester.tap(find.text('เร็ว'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(settings.flowSpeed, FlowSpeed.fast);
      await tester.tap(find.byKey(const ValueKey('line-anim')));
      await tester.pumpAndSettle();
      expect(settings.flowAnimation, false);
      await tester.tap(find.text('ปิด'));
      await tester.pumpAndSettle();
      c.selectTable(null);
      await tester.pump();
    });

    testWidgets('ภาษาอังกฤษ: ชื่อเมนูแปลครบ', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: Lang.en)));
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relationship lines (FK)…'));
      await tester.pumpAndSettle();
      expect(find.text('Show data direction on FK lines'), findsOneWidget);
      expect(find.text('Always play (all lines)'), findsOneWidget);
      expect(find.text('Slow'), findsOneWidget);
      currentLang = Lang.th;
    });
  });
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
