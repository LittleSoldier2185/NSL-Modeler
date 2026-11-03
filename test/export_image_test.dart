import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/export/svg_export.dart';
import 'package:nsl_modeler/core/layout/diagram_geometry.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/note_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/ui/export/diagram_png.dart';
import 'package:nsl_modeler/ui/file_actions.dart';
import 'package:nsl_modeler/ui/export/export_image_dialog.dart';
import 'package:xml/xml.dart';

import 'migration_fixtures.dart';

Project laid() {
  final p = base();
  tb(p, 'tu')
    ..x = 40
    ..y = 60;
  tb(p, 'to')
    ..x = 400
    ..y = 80;
  return p;
}

void main() {
  group('diagram_geometry', () {
    test('เส้น FK: การ์ดซ้าย -> ขวา ออกขวาเข้าซ้าย; กลับด้านเมื่ออยู่ฝั่งตรงข้าม', () {
      final p = laid();
      final r = p.relations.single; // orders (ขวา) -> users (ซ้าย)
      final g = relationGeometry(p, r)!;
      expect([g.d0, g.d1], [-1, 1]); // ลูกอยู่ขวา ออกซ้ายเข้าขวาของแม่
      expect(g.fx, tb(p, 'to').x);
      expect(g.tx, tb(p, 'tu').x + tb(p, 'tu').width);
      expect(g.fy, rowCenterY(tb(p, 'to').y, 1)); // user_id = แถวที่ 2
      expect(g.ty, rowCenterY(tb(p, 'tu').y, 0)); // id = แถวแรก
      expect(g.oneToOne, false);
    });

    test('การ์ดซ้อนแนวนอน: ออกขวาทั้งคู่', () {
      final p = laid();
      tb(p, 'to').x = 100;
      final g = relationGeometry(p, p.relations.single)!;
      expect([g.d0, g.d1], [1, 1]);
    });

    test('ความสัมพันธ์ที่ชี้ไม่ถูกต้องคืน null', () {
      final p = laid();
      p.relations.single.toColumnId = 'nope';
      expect(relationGeometry(p, p.relations.single), isNull);
    });

    test('1:1 เมื่อคอลัมน์ FK เป็น UNIQUE', () {
      final p = laid();
      cl(p, 'to', 'o2').unique = true;
      expect(relationGeometry(p, p.relations.single)!.oneToOne, true);
    });

    test('ตารางเชื่อม (PK หลายคอลัมน์): FK ไม่ใช่ 1:1; PK เดี่ยวที่เป็น FK คือ 1:1', () {
      final p = Project(tables: [
        TableModel(id: 'a', name: 'a', x: 0, columns: [col('a1', 'id', pk: true)]),
        TableModel(id: 'b', name: 'b', x: 400, columns: [col('b1', 'id', pk: true)]),
        TableModel(id: 'j', name: 'j', x: 800, columns: [
          col('j1', 'a_id', pk: true),
          col('j2', 'b_id', pk: true),
        ]),
        TableModel(id: 'o', name: 'one', x: 1200, columns: [col('o1', 'a_id', pk: true)]),
      ], relations: [
        RelationModel(id: 'r1', fromTableId: 'j', fromColumnId: 'j1', toTableId: 'a', toColumnId: 'a1'),
        RelationModel(id: 'r2', fromTableId: 'j', fromColumnId: 'j2', toTableId: 'b', toColumnId: 'b1'),
        RelationModel(id: 'r3', fromTableId: 'o', fromColumnId: 'o1', toTableId: 'a', toColumnId: 'a1'),
      ]);
      bool oneToOne(String id) => relationGeometry(p, p.relations.firstWhere((r) => r.id == id))!.oneToOne;
      expect(oneToOne('r1'), false);
      expect(oneToOne('r2'), false);
      expect(oneToOne('r3'), true);
    });

    test('diagramBounds ครอบตาราง+โน้ต และ null เมื่อว่าง', () {
      expect(diagramBounds(Project()), isNull);
      final p = laid();
      final b = diagramBounds(p)!;
      for (final t in p.tables) {
        expect(b.left, lessThan(t.x));
        expect(b.right, greaterThan(t.x + t.width));
        expect(b.bottom, greaterThan(t.y + tableHeight(t)));
      }
      p.notes.add(NoteModel(id: 'n', text: 'x', x: 900, y: 700));
      expect(diagramBounds(p)!.right, greaterThan(900));
      expect(diagramBounds(p, includeNotes: false)!.right, lessThan(900));
    });

    test('wrapNoteText: ตัดคำ ไม่ทิ้งบรรทัดเกินความกว้าง และเคารพ \\n', () {
      final lines = wrapNoteText('hello world this is a long note that must wrap\nsecond', 190);
      expect(lines.length, greaterThan(2));
      expect(lines.last, 'second');
      expect(lines.every((l) => l.length <= 24), true);
      expect(wrapNoteText('', 190), ['']);
      expect(wrapNoteText('a' * 100, 190).every((l) => l.length <= 24), true); // ไม่มีช่องว่างก็ตัดแข็ง
    });
  });

  group('exportSvg', () {
    test('ไม่มีอะไรให้วาด = null', () {
      expect(exportSvg(Project()), isNull);
    });

    test('เป็น XML ที่ถูกต้อง มี viewBox ตามกรอบ และตารางครบ', () {
      final p = laid();
      final svg = exportSvg(p)!;
      final doc = XmlDocument.parse(svg); // ไม่ throw = well-formed
      final root = doc.rootElement;
      expect(root.name.local, 'svg');
      final b = diagramBounds(p)!;
      final vb = root.getAttribute('viewBox')!.split(' ').map(double.parse).toList();
      expect(vb[2], closeTo(b.width, 0.01));
      expect(vb[3], closeTo(b.height, 0.01));
      final groups = root.findElements('g').where((g) => g.getAttribute('transform') != null).toList();
      expect(groups.length, 2);
      expect(svg, contains('>users<'));
      expect(svg, contains('>orders<'));
      expect(svg, contains('VARCHAR(255)'));
      expect(svg, contains('DECIMAL(10,2)'));
    });

    test('ป้าย PK / FK / UQ', () {
      final svg = exportSvg(laid())!;
      expect(RegExp('>PK<').allMatches(svg).length, 2); // users.id, orders.id
      expect(RegExp('>FK<').allMatches(svg).length, 1); // orders.user_id
      expect(RegExp('>UQ<').allMatches(svg).length, 1); // users.email
    });

    test('เส้น FK ใช้พิกัดเดียวกับ relationGeometry', () {
      final p = laid();
      final g = relationGeometry(p, p.relations.single)!;
      final svg = exportSvg(p)!;
      String n(num v) {
        final s = v.toStringAsFixed(2);
        return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
      }

      expect(svg, contains('M${n(g.fx)} ${n(g.fy)} C'));
      expect(svg, contains('${n(g.tx)} ${n(g.ty)}"/>'));
    });

    test('escape อักขระพิเศษ และคงภาษาไทย', () {
      final p = Project(name: 'A&B <x>', tables: [
        TableModel(id: 't', name: 'a<b>&"c\'', columns: [
          ColumnModel(id: 'c', name: 'ชื่อ & สกุล', type: DataType.varchar, length: 50),
        ]),
      ], notes: [
        NoteModel(id: 'n', text: 'x < y && "z"', x: 300, y: 0),
      ]);
      final svg = exportSvg(p)!;
      XmlDocument.parse(svg); // ต้อง parse ผ่าน
      expect(svg, contains('a&lt;b&gt;&amp;&quot;c&apos;'));
      expect(svg, contains('ชื่อ &amp; สกุล'));
      expect(svg, contains('x &lt; y &amp;&amp; &quot;z&quot;'));
      expect(svg, contains('<title>A&amp;B &lt;x&gt;</title>'));
    });

    test('ตัดอักขระควบคุมที่ XML ไม่รับ', () {
      final p = Project(tables: [
        TableModel(id: 't', name: 'bad\u0001name\u000B', columns: [ColumnModel(id: 'c', name: 'a\u0000b')]),
      ]);
      final svg = exportSvg(p)!;
      XmlDocument.parse(svg);
      expect(svg, contains('>badname<'));
      expect(svg, contains('>ab<'));
    });

    test('ชื่อยาวถูกย่อด้วย …', () {
      final p = Project(tables: [
        TableModel(id: 't', name: 'x' * 80, columns: [ColumnModel(id: 'c', name: 'y' * 80)]),
      ]);
      final svg = exportSvg(p)!;
      expect(svg, contains('…'));
      expect(svg, isNot(contains('x' * 80)));
    });

    test('โน้ต: รวม/ไม่รวมตามตัวเลือก และกรอบเปลี่ยนตาม', () {
      final p = laid();
      p.notes.add(NoteModel(id: 'n', text: 'อย่าลืมเปลี่ยน price', x: 800, y: 50));
      expect(exportSvg(p)!, contains('อย่าลืมเปลี่ยน price'));
      expect(exportSvg(p, includeNotes: false)!, isNot(contains('อย่าลืมเปลี่ยน price')));
      double w(String s) => double.parse(XmlDocument.parse(s).rootElement.getAttribute('width')!);
      expect(w(exportSvg(p)!), greaterThan(w(exportSvg(p, includeNotes: false)!)));
    });

    test('โปรเจกต์มีแต่โน้ตก็ export ได้', () {
      final p = Project(notes: [NoteModel(id: 'n', text: 'hi', x: 10, y: 10)]);
      expect(XmlDocument.parse(exportSvg(p)!).rootElement.name.local, 'svg');
    });

    test('ผลลัพธ์คงที่', () {
      expect(exportSvg(laid()), exportSvg(laid()));
    });

    test('FK ที่ชี้ผิดถูกข้าม ไม่ทำให้พัง', () {
      final p = laid();
      p.relations.single.toTableId = 'ghost';
      XmlDocument.parse(exportSvg(p)!);
    });
  });

  group('exportPng', () {
    Future<ui.Image> decode(Uint8List bytes) async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    }

    testWidgets('ว่าง = null', (tester) async {
      final r = await tester.runAsync(() => exportPng(Project()));
      expect(r, isNull);
    });

    testWidgets('PNG ถูกต้อง ขนาดตามกรอบ×สเกล', (tester) async {
      final p = laid();
      final b = diagramBounds(p)!;
      for (final scale in [1.0, 2.0]) {
        final r = (await tester.runAsync(() => exportPng(p, scale: scale)))!;
        expect(r.bytes.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        expect(r.width, (b.width * scale).ceil());
        expect(r.height, (b.height * scale).ceil());
        final img = (await tester.runAsync(() => decode(r.bytes)))!;
        expect([img.width, img.height], [r.width, r.height]);
        img.dispose();
      }
    });

    testWidgets('ภาพไม่ว่าง: หัวตารางเป็นสีเข้ม พื้นหลังเป็นสีพื้น', (tester) async {
      final p = laid();
      final b = diagramBounds(p)!;
      final r = (await tester.runAsync(() => exportPng(p, scale: 1)))!;
      final img = (await tester.runAsync(() => decode(r.bytes)))!;
      final data = (await tester.runAsync(() => img.toByteData(format: ui.ImageByteFormat.rawRgba)))!;

      int px(double wx, double wy) {
        final x = (wx - b.left).round(), y = (wy - b.top).round();
        final i = (y * img.width + x) * 4;
        return (data.getUint8(i) << 16) | (data.getUint8(i + 1) << 8) | data.getUint8(i + 2);
      }

      final t = tb(p, 'tu');
      expect(px(t.x + 60, t.y + 5), 0x1F2A37, reason: 'หัวตาราง'); // พื้นหัวตาราง (ไม่ชนข้อความชื่อ)
      expect(px(b.left + 2, b.top + 2), 0xF6F8FB, reason: 'พื้นหลัง');
      img.dispose();
    });

    testWidgets('แผนภาพใหญ่มากถูกลดสเกลไม่ให้เกิน 16000px', (tester) async {
      final p = laid();
      tb(p, 'to').x = 30000;
      final r = (await tester.runAsync(() => exportPng(p, scale: 3)))!;
      expect(r.scale, lessThan(3));
      expect(r.width <= kMaxPngSide && r.height <= kMaxPngSide, true);
    });

    testWidgets('รวม/ไม่รวมโน้ตมีผลต่อขนาดภาพ', (tester) async {
      final p = laid();
      p.notes.add(NoteModel(id: 'n', text: 'note', x: 1200, y: 40));
      final withN = (await tester.runAsync(() => exportPng(p, scale: 1)))!;
      final without = (await tester.runAsync(() => exportPng(p, scale: 1, includeNotes: false)))!;
      expect(withN.width, greaterThan(without.width));
    });
  });

  group('ชื่อไฟล์ภาพ / ตัวเลือก', () {
    test('imageFileName', () {
      expect(FileActions.imageFileName('shop', ImageFormat.png), 'shop_diagram.png');
      expect(FileActions.imageFileName('a/b:c', ImageFormat.svg), 'a_b_c_diagram.svg');
      expect(FileActions.imageFileName(' ', ImageFormat.png), 'schema_diagram.png');
    });
  });

  group('ExportImageDialog', () {
    Future<ImageExportOptions?> run(WidgetTester tester, {bool hasNotes = true, List<String> taps = const []}) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ImageExportOptions? result;
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              result = await showDialog<ImageExportOptions>(
                  context: ctx, builder: (_) => ExportImageDialog(hasNotes: hasNotes));
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final t in taps) {
        await tester.tap(find.text(t));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(done, true);
      return result;
    }

    testWidgets('ค่าเริ่มต้น PNG 2x รวมโน้ต', (tester) async {
      final r = (await run(tester))!;
      expect([r.format, r.scale, r.includeNotes], [ImageFormat.png, 2.0, true]);
    });

    testWidgets('เลือก 3x และไม่รวมโน้ต', (tester) async {
      final r = (await run(tester, taps: ['3x', 'รวมโน้ตในภาพ']))!;
      expect([r.format, r.scale, r.includeNotes], [ImageFormat.png, 3.0, false]);
    });

    testWidgets('เลือก SVG ซ่อนตัวเลือกความละเอียด', (tester) async {
      final r = (await run(tester, taps: ['SVG']))!;
      expect(r.format, ImageFormat.svg);
    });

    testWidgets('ไม่มีโน้ต: ไม่แสดงตัวเลือกโน้ต', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ExportImageDialog(hasNotes: false)));
      expect(find.text('รวมโน้ตในภาพ'), findsNothing);
    });
  });

  test('RelationModel ถูกใช้ในเรขาคณิตเฉพาะที่ตรงกัน (sanity)', () {
    final p = laid();
    p.relations.add(RelationModel(
        id: 'r2', fromTableId: 'to', fromColumnId: 'o1', toTableId: 'tu', toColumnId: 'u2'));
    expect(p.relations.map((r) => relationGeometry(p, r)).whereType<RelationGeometry>().length, 2);
  });
}
