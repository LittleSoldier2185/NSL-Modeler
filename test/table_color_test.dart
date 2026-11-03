import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/export/svg_export.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/core/storage/project_file.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  group('โมเดล / ไฟล์', () {
    test('ค่าเริ่มต้นไม่มีสี และไฟล์ไม่มีฟิลด์ color', () {
      final p = base();
      expect(tb(p, 'tu').colorIndex, isNull);
      expect(tb(p, 'tu').toJson().containsKey('color'), false);
    });

    test('บันทึกแล้วเปิดกลับมาได้สีเดิม', () {
      final p = base();
      tb(p, 'tu').colorIndex = 3;
      final back = ProjectFile.decode(ProjectFile.encode(p));
      expect(tb(back, 'tu').colorIndex, 3);
      expect(tb(back, 'to').colorIndex, isNull);
    });

    test('ค่าในไฟล์ที่ผิดปกติ (นอกช่วง / ไม่ใช่เลข) = ไม่มีสี', () {
      for (final bad in [-1, 99, 'red', 1.5]) {
        final j = tb(base(), 'tu').toJson()..['color'] = bad;
        expect(TableModel.fromJson(j).colorIndex, isNull, reason: '$bad');
      }
    });

    test('ทำสำเนาโปรเจกต์/ตารางแล้วสียังอยู่', () {
      final p = base();
      tb(p, 'tu').colorIndex = 2;
      expect(tb(clone(p), 'tu').colorIndex, 2);
    });
  });

  group('ProjectController.setTablesColor', () {
    test('ตั้งสีให้หลายตารางพร้อมกัน เป็น undo ขั้นเดียว', () {
      final c = ProjectController(base());
      c.setTablesColor(['tu', 'to'], 4);
      expect([tb(c.project, 'tu').colorIndex, tb(c.project, 'to').colorIndex], [4, 4]);
      c.undo();
      expect([tb(c.project, 'tu').colorIndex, tb(c.project, 'to').colorIndex], [null, null]);
      expect(c.canUndo, false);
    });

    test('null = ล้างสี; ค่าเดิม/ค่านอกช่วง/ตารางที่ไม่มี ไม่สร้างประวัติ', () {
      final c = ProjectController(base());
      c.setTablesColor(['tu'], 1);
      c.setTablesColor(['tu'], 1); // ค่าเดิม
      c.setTablesColor(['tu'], 99); // นอกช่วง
      c.setTablesColor(['nope'], 2); // ไม่มีตาราง
      expect(tb(c.project, 'tu').colorIndex, 1);
      c.undo();
      expect(c.canUndo, false); // มีประวัติแค่ครั้งแรกครั้งเดียว
      c.redo();
      c.setTablesColor(['tu'], null);
      expect(tb(c.project, 'tu').colorIndex, isNull);
    });
  });

  group('export', () {
    test('SVG: หัวตารางใช้สีที่เลือก และมีแต้มพื้นจาง; ตารางไม่มีสียังเป็นสีเดิม', () {
      final p = base();
      tb(p, 'tu')
        ..x = 0
        ..y = 0
        ..colorIndex = 1; // ม่วง 7E22CE
      tb(p, 'to')
        ..x = 400
        ..y = 0;
      final svg = exportSvg(p)!;
      expect(svg, contains('fill="#7E22CE"'));
      expect(svg, contains('fill-opacity="0.06"'));
      expect(svg, contains('fill="#1F2A37"')); // orders ยังเป็นสีเดิม
    });
  });

  group('บนจอ', () {
    late ProjectController c;
    late AppSettings settings;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      settings = AppSettings(lang: Lang.th);
      await tester.pumpWidget(NslModelerApp(settings: settings));
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(base(), null);
      tb(c.project, 'tu')
        ..x = 100
        ..y = 160;
      tb(c.project, 'to')
        ..x = 500
        ..y = 160;
      await tester.pump();
    }

    testWidgets('แผงขวา: เลือกสีตารางที่เลือกอยู่ และกด "ไม่มีสี" เพื่อล้าง', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('table-color-2')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').colorIndex, 2);
      expect(tb(c.project, 'to').colorIndex, isNull);

      await tester.tap(find.byKey(const ValueKey('table-color-none')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').colorIndex, isNull);
    });

    testWidgets('เลือกหลายตาราง: สีถูกตั้งให้ทุกตารางที่เลือก', (tester) async {
      await boot(tester);
      c.selectAllTables();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('table-color-5')));
      await tester.pumpAndSettle();
      expect([tb(c.project, 'tu').colorIndex, tb(c.project, 'to').colorIndex], [5, 5]);
    });

    testWidgets('หัวการ์ดบน canvas เปลี่ยนเป็นสีที่เลือก', (tester) async {
      await boot(tester);
      tb(c.project, 'tu').colorIndex = 3; // ส้ม C2410C
      c.selectTable('to');
      await tester.pumpAndSettle();
      final headers = tester.widgetList<Container>(find.descendant(
        of: find.byKey(const ValueKey('table-tu')),
        matching: find.byType(Container),
      ));
      bool hasOrange = false;
      for (final h in headers) {
        final d = h.decoration;
        if (d is BoxDecoration && d.gradient is LinearGradient) {
          final colors = (d.gradient as LinearGradient).colors;
          if (colors.last == const Color(0xFFC2410C)) hasOrange = true;
        }
      }
      expect(hasOrange, true);
    });

    testWidgets('คลิกขวาที่ตาราง > สีตาราง… > เลือกสี', (tester) async {
      await boot(tester);
      final gs = await tester.startGesture(
          tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton);
      await gs.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('สีตาราง…'));
      await tester.pumpAndSettle();
      expect(find.text('ไม่มีสี (ค่าเริ่มต้น)'), findsOneWidget);
      await tester.tap(find.text('ม่วง'));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').colorIndex, 1);
    });

    testWidgets('ภาษาอังกฤษ: ชื่อสีและรายการเมนูแปลครบ', (tester) async {
      await boot(tester);
      settings.setLang(Lang.en);
      await tester.pumpAndSettle();
      c.selectTable('tu');
      await tester.pumpAndSettle();
      expect(find.text('Table color'), findsOneWidget);
      currentLang = Lang.th;
    });
  });
}
