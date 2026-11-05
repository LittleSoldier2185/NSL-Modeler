import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/svg_export.dart';
import 'package:nsl_dev/core/fonts/system_fonts.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/layout/diagram_geometry.dart';
import 'package:nsl_dev/core/models/color_utils.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_view.dart';
import 'package:nsl_dev/ui/export/diagram_png.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';
import 'support/project_helpers.dart';

import 'migration_fixtures.dart';

void main() {
  group('color_utils', () {
    test('parseHexColor / hexRgb', () {
      expect(parseHexColor('#0f766e'), 0xFF0F766E);
      expect(parseHexColor('abc'), 0xFFAABBCC);
      expect(parseHexColor('#12'), isNull);
      expect(parseHexColor('zzzzzz'), isNull);
      expect(hexRgb(0xFF0F766E), '#0F766E');
    });

    test('HSV ไป-กลับให้สีเดิม', () {
      for (final c in [0xFF0F766E, 0xFFFF0000, 0xFF123456, 0xFFFFFFFF, 0xFF000000]) {
        final (h, s, v) = argbToHsv(c);
        expect(hsvToArgb(h, s, v), c);
      }
    });

    test('onColor: พื้นอ่อน = ตัวอักษรเข้ม, พื้นเข้ม = ตัวอักษรขาว', () {
      expect(onColor(0xFFFFFFFF), isNot(0xFFFFFFFF));
      expect(onColor(0xFF1F2A37), 0xFFFFFFFF);
    });

    test('parseArgb ปฏิเสธค่าผิดปกติ', () {
      for (final bad in [-1, 'red', 1.5, null, 0x1FFFFFFFF]) {
        expect(parseArgb(bad), isNull, reason: '$bad');
      }
      expect(parseArgb(0xFF112233), 0xFF112233);
    });
  });

  group('โมเดล / ไฟล์', () {
    test('สีกำหนดเอง ฟอนต์ สีเส้น บันทึกแล้วเปิดกลับมาครบ', () {
      final p = base();
      tb(p, 'tu')
        ..customColor = 0xFF336699
        ..fontFamily = 'Tahoma';
      p.lineColor = 0xFFAA0000;
      p.relations.first.color = 0xFF00AA00;
      final back = roundTripEr(p);
      expect(tb(back, 'tu').customColor, 0xFF336699);
      expect(tb(back, 'tu').fontFamily, 'Tahoma');
      expect(tb(back, 'tu').colorValue, 0xFF336699);
      expect(back.lineColor, 0xFFAA0000);
      expect(back.relations.first.color, 0xFF00AA00);
      expect(tb(back, 'to').customColor, isNull);
    });

    test('ค่าผิดปกติในไฟล์ = ไม่ตั้งค่า', () {
      final j = tb(base(), 'tu').toJson()
        ..['fill'] = 'red'
        ..['font'] = '   ';
      final t = TableModel.fromJson(j);
      expect(t.customColor, isNull);
      expect(t.fontFamily, isNull);
      final r = RelationModel.fromJson(base().relations.first.toJson()..['color'] = -5);
      expect(r.color, isNull);
    });

    test('สีกำหนดเองมาก่อนสีสำเร็จรูป', () {
      final t = tb(base(), 'tu')
        ..colorIndex = 1
        ..customColor = 0xFF010203;
      expect(t.colorValue, 0xFF010203);
    });
  });

  group('ProjectController', () {
    test('setTablesCustomColor: undo ขั้นเดียว และล้างสีสำเร็จรูป', () {
      final c = ProjectController(base());
      c.setTablesColor(['tu'], 2);
      c.setTablesCustomColor(['tu', 'to'], 0xFF445566);
      expect(tb(c.project, 'tu').customColor, 0xFF445566);
      expect(tb(c.project, 'tu').colorIndex, isNull);
      expect(tb(c.project, 'to').customColor, 0xFF445566);
      c.undo();
      expect(tb(c.project, 'tu').colorIndex, 2);
      expect(tb(c.project, 'tu').customColor, isNull);
    });

    test('เลือกสีสำเร็จรูปแล้วสีกำหนดเองถูกล้าง', () {
      final c = ProjectController(base());
      c.setTablesCustomColor(['tu'], 0xFF445566);
      c.setTablesColor(['tu'], 3);
      expect(tb(c.project, 'tu').customColor, isNull);
      expect(tb(c.project, 'tu').colorValue, kTableColors[3]);
      c.setTablesColor(['tu'], null);
      expect(tb(c.project, 'tu').colorValue, isNull);
    });

    test('setTablesFont: ตั้ง ล้าง undo และค่าเดิมไม่สร้างประวัติ', () {
      final c = ProjectController(base());
      c.setTablesFont(['tu'], 'Tahoma');
      c.setTablesFont(['tu'], 'Tahoma');
      expect(tb(c.project, 'tu').fontFamily, 'Tahoma');
      c.undo();
      expect(tb(c.project, 'tu').fontFamily, isNull);
      expect(c.canUndo, false);
      c.redo();
      c.setTablesFont(['tu'], null);
      expect(tb(c.project, 'tu').fontFamily, isNull);
    });

    test('สีเส้น: รายความสัมพันธ์ และทั้งโปรเจกต์', () {
      final c = ProjectController(base());
      final id = c.project.relations.first.id;
      c.setRelationColor(id, 0xFF112233);
      expect(c.project.relations.first.color, 0xFF112233);
      c.setLineColor(0xFF445566);
      expect(c.project.lineColor, 0xFF445566);
      c.setLineColor(-1); // ผิดปกติ
      c.setRelationColor('nope', 1);
      expect(c.project.lineColor, 0xFF445566);
      c.undo();
      expect(c.project.lineColor, isNull);
      c.undo();
      expect(c.project.relations.first.color, isNull);
    });
  });

  group('export', () {
    Project placed() {
      final p = base();
      tb(p, 'tu')
        ..x = 0
        ..y = 0;
      tb(p, 'to')
        ..x = 400
        ..y = 0;
      return p;
    }

    test('SVG ธีมมืดใช้พื้น/การ์ดสีมืด ไม่มีสีของธีมสว่าง', () {
      final svg = exportSvg(placed(), dark: true)!;
      expect(svg, contains('#121820'));
      expect(svg, contains('#19212B'));
      expect(svg, isNot(contains('#F6F8FB')));
      expect(svg, isNot(contains('fill="#FFFFFF" stroke')));
      expect(exportSvg(placed())!, contains('#F6F8FB'));
    });

    test('SVG: สีกำหนดเอง + ตัวอักษรหัวตารางอ่านออกบนสีอ่อน', () {
      final p = placed();
      tb(p, 'tu').customColor = 0xFFFFFF99; // เหลืองอ่อน
      final svg = exportSvg(p)!;
      expect(svg, contains('fill="#FFFF99"'));
      expect(svg, contains(hexRgb(onColor(0xFFFFFF99))));
    });

    test('SVG: ฟอนต์ของตารางลงใน font-family พร้อมฟอนต์สำรอง', () {
      final p = placed();
      tb(p, 'tu').fontFamily = 'Tahoma';
      final svg = exportSvg(p)!;
      expect(svg, contains("font-family=\"'Tahoma',"));
      expect(svg, contains('Noto Sans Thai'));
    });

    test('SVG: สีเส้นเริ่มต้นและสีเส้นเฉพาะความสัมพันธ์', () {
      final p = placed();
      p.lineColor = 0xFFAA1122;
      expect(exportSvg(p)!, contains('stroke="#AA1122"'));
      p.relations.first.color = 0xFF22BB33;
      expect(exportSvg(p)!, contains('stroke="#22BB33"'));
    });

    testWidgets('PNG ธีมมืด: พิกเซลมุมภาพเป็นสีมืด / ธีมสว่างเป็นสีอ่อน', (tester) async {
      final p = placed();
      Future<int> corner(bool dark) async {
        final r = await tester.runAsync(() async {
          final out = await exportPng(p, scale: 1, dark: dark);
          final codec = await ui.instantiateImageCodec(out!.bytes);
          final img = (await codec.getNextFrame()).image;
          final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          return data.getUint8(0) + data.getUint8(1) + data.getUint8(2);
        });
        return r!;
      }

      expect(await corner(true), lessThan(200));
      expect(await corner(false), greaterThan(600));
    });
  });

  group('SystemFonts', () {
    test('parseWindowsRegistry: ตัดชนิดไฟล์/สไตล์ ซ้ำกัน และแยกไฟล์รวม', () {
      final r = SystemFonts.parseWindowsRegistry([
        'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts',
        '    Arial (TrueType)    REG_SZ    arial.ttf',
        '    Arial Bold (TrueType)    REG_SZ    arialbd.ttf',
        '    Arial Bold Italic (TrueType)    REG_SZ    arialbi.ttf',
        '    Cambria & Cambria Math (TrueType)    REG_SZ    cambria.ttc',
        '    Leelawadee UI (TrueType)    REG_SZ    LeelawUI.ttf',
      ]);
      expect(r, ['Arial', 'Cambria', 'Cambria Math', 'Leelawadee UI']);
    });

    test('parseFcList: หลายชื่อต่อบรรทัด', () {
      expect(SystemFonts.parseFcList(['DejaVu Sans,DejaVu Sans Bold', 'Noto Sans Thai', '']), ['DejaVu Sans', 'Noto Sans Thai']);
    });

    test('list: แคชผล และโหลดพังได้ลิสต์ว่าง', () async {
      var n = 0;
      SystemFonts.loader = () async {
        n++;
        return ['A'];
      };
      SystemFonts.resetCache();
      await SystemFonts.list();
      expect(await SystemFonts.list(), ['A']);
      expect(n, 1);
      SystemFonts.loader = () async => throw Exception('x');
      SystemFonts.resetCache();
      expect(await SystemFonts.list(), isEmpty);
      SystemFonts.resetCache();
    });
  });

  group('บนจอ', () {
    late ProjectController c;
    late AppSettings settings;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SystemFonts.loader = () async => ['Arial', 'Tahoma', 'Zeta Sans'];
      SystemFonts.resetCache();
      addTearDown(SystemFonts.resetCache);
      settings = AppSettings(lang: Lang.th);
      await tester.pumpWidget(NslDevApp(settings: settings));
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

    testWidgets('แผงขวา: กำหนดสีเอง ด้วยฮีกซ์ แล้วกดตกลง', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pumpAndSettle();
      final sw = find.byKey(const ValueKey('table-color-custom'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('color-hex')), '#336699');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('color-ok')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').customColor, 0xFF336699);
      expect(tb(c.project, 'to').customColor, isNull);
    });

    testWidgets('กล่องเลือกสี: ลากในพื้นที่สี/แถบเฉดสี แล้วฮีกซ์เปลี่ยนตาม', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pumpAndSettle();
      final sw = find.byKey(const ValueKey('table-color-custom'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      String hex() => tester.widget<TextField>(find.byKey(const ValueKey('color-hex'))).controller!.text;
      // มุมขวาบนของพื้นที่ = สีเฉดเต็มสว่างสุด; มุมซ้ายล่าง = ดำ
      final sv = find.byKey(const ValueKey('color-sv'));
      await tester.tapAt(tester.getTopRight(sv) + const Offset(-0.01, 0.01));
      await tester.pump();
      final top = hex();
      expect(top, isNot('#000000'));
      await tester.tapAt(tester.getBottomLeft(sv) + const Offset(0, -0.01));
      await tester.pump();
      expect(hex(), '#000000');
      // ลากแถบเฉดสีไปสุดซ้าย = แดง (ที่ความสว่างเดิมยังเป็น 0 จึงต้องยกความสว่างก่อน)
      await tester.tapAt(tester.getTopRight(sv) + const Offset(-0.01, 0.01));
      await tester.pump();
      await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('color-h'))) + const Offset(0, 9));
      await tester.pump();
      expect(hex(), '#FF0000');
      await tester.tap(find.byKey(const ValueKey('color-ok')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').customColor, 0xFFFF0000);
    });

    testWidgets('กล่องเลือกสี: ใช้ค่าเริ่มต้น = ล้างสี; ยกเลิก = ไม่เปลี่ยน', (tester) async {
      await boot(tester);
      c.setTablesCustomColor(['tu'], 0xFF336699);
      c.selectTable('tu');
      await tester.pumpAndSettle();
      final sw = find.byKey(const ValueKey('table-color-custom'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').customColor, 0xFF336699);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('color-reset')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').colorValue, isNull);
    });

    testWidgets('แผงขวา: เลือกฟอนต์จากรายการ ค้นหาได้ และกลับค่าเริ่มต้นได้', (tester) async {
      await boot(tester);
      c.selectTable('tu');
      await tester.pumpAndSettle();
      final btn = find.byKey(const ValueKey('table-font'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('font-Tahoma')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('font-search')), 'zet');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('font-Tahoma')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('font-Zeta Sans')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').fontFamily, 'Zeta Sans');

      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('font-default')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').fontFamily, isNull);
    });

    testWidgets('คลิกขวาที่ตาราง > ฟอนต์ตาราง…', (tester) async {
      await boot(tester);
      final gs = await tester.startGesture(
          tester.getTopLeft(find.byKey(const ValueKey('table-tu'))) + const Offset(60, 16),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton);
      await gs.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('ฟอนต์ตาราง…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('font-Arial')));
      await tester.pumpAndSettle();
      expect(tb(c.project, 'tu').fontFamily, 'Arial');
    });

    Offset onLine(WidgetTester tester) {
      final id = c.project.relations.first.id;
      final pts = relationRoutes(c.project)[id]!;
      final (ax, ay) = pts[pts.length ~/ 2 - 1];
      final (bx, by) = pts[pts.length ~/ 2];
      final w = Offset((ax + bx) / 2, (ay + by) / 2);
      // พิกัดโปรเจกต์ -> พิกัดหน้าจอ ผ่านตัวควบคุม canvas
      final cv = tester.element(find.byType(HomePage)).read<CanvasController>();
      final canvas = tester.getTopLeft(find.byType(CanvasView));
      return canvas + w * cv.scale + cv.offset;
    }

    testWidgets('คลิกซ้ายที่เส้น FK = เลือกคอลัมน์ FK; คลิกขวา = เมนูเปลี่ยนสีเส้น', (tester) async {
      await boot(tester);
      final at = onLine(tester);
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      final r = c.project.relations.first;
      expect(c.selectedTableId, r.fromTableId);
      expect(c.selectedColumnId, r.fromColumnId);

      final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('เปลี่ยนสีเส้นนี้…'), findsOneWidget);
      await tester.tap(find.text('เปลี่ยนสีเส้นนี้…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('color-hex')), '22BB33');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('color-ok')));
      await tester.pumpAndSettle();
      expect(c.project.relations.first.color, 0xFF22BB33);
    });

    testWidgets('คลิกขวาที่เส้น > ลบ FK นี้', (tester) async {
      await boot(tester);
      final n = c.project.relations.length;
      final g = await tester.startGesture(onLine(tester), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบ FK นี้'));
      await tester.pumpAndSettle();
      expect(c.project.relations.length, n - 1);
    });

    testWidgets('เมนูมุมมอง: สีเส้นความสัมพันธ์…', (tester) async {
      await boot(tester);
      await tester.tap(find.text('มุมมอง'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เส้นความสัมพันธ์ (FK)…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('line-color')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('color-hex')), 'AA1122');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('color-ok')));
      await tester.pumpAndSettle();
      expect(c.project.lineColor, 0xFFAA1122);
    });

    testWidgets('ภาษาอังกฤษ: ปุ่มฟอนต์/สีแปลครบ', (tester) async {
      await boot(tester);
      settings.setLang(Lang.en);
      await tester.pumpAndSettle();
      c.selectTable('tu');
      await tester.pumpAndSettle();
      expect(find.text('Table font'), findsOneWidget);
      expect(find.text('Default (Noto Sans Thai)'), findsOneWidget);
      currentLang = Lang.th;
    });
  });
}
