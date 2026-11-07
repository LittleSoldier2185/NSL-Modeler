import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/diagram.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';
import 'support/project_helpers.dart';

void main() {
  test('accessor เอกสาร: documents / documentById / dfdOf ตรงกับแท็บและเนื้อหา DFD', () {
    final c = ProjectController(base());
    final a = c.addDiagram(DocType.dfd, name: 'A')!;
    expect(c.documents.map((d) => (d.id, d.type, d.name)), [(kErDiagramId, DocType.er, 'ER'), (a.id, DocType.dfd, 'A')]);
    expect(identical(c.documentById(kErDiagramId)!.er, c.project), isTrue);
    expect(identical(c.documentById(a.id)!.dfd, c.dfdOf(a.id)), isTrue);
    expect(c.documentById('nope'), isNull);
    c.renameDiagram(a.id, 'B');
    expect(c.documentById(a.id)!.name, 'B');
  });

  group('โมเดล / ไฟล์', () {
    test('โปรเจกต์ใหม่มีเอกสาร ER อันเดียว; ไฟล์เขียนเป็นเวอร์ชัน 3', () {
      final c = ProjectController(base());
      expect(c.documents.map((d) => (d.id, d.name, d.type)), [(kErDiagramId, 'ER', DocType.er)]);
      final j = jsonDecode(ProjectFile.encode(c.workspace)) as Map<String, dynamic>;
      expect(j['version'], 3);
      expect(j.containsKey('diagrams'), false);
      expect(base().toJson().containsKey('diagrams'), false);
    });

    test('มี DFD = เปิดกลับมาลำดับ/ชื่อ/ชนิดครบ', () {
      final c = ProjectController(base());
      final a = c.addDiagram(DocType.dfd, name: 'Level 0')!;
      final b = c.addDiagram(DocType.dfd, name: 'Level 1')!;
      final back = roundTrip(c.workspace);
      expect(back.documents.map((d) => (d.id, d.name, d.type)), [
        (kErDiagramId, 'ER', DocType.er),
        (a.id, 'Level 0', DocType.dfd),
        (b.id, 'Level 1', DocType.dfd),
      ]);
    });

    test('ไฟล์เก่า (ไม่มี diagrams) เปิดได้ = มี ER อันเดียว', () {
      final j = {'format': 'nsl-erd', 'version': 1, ...base().toJson()};
      expect(decodeProjectMap(j).documents.single.type, DocType.er);
    });

    test('ไฟล์เก่าผิดปกติถูกซ่อม: ไม่มี ER = เติมไว้หน้าสุด, ER ซ้ำ/id ซ้ำ/ชนิดแปลก/ชื่อว่าง/ชื่อซ้ำ', () {
      final j = {
        'format': 'nsl-erd',
        'version': 2,
        ...base().toJson(),
        'diagrams': [
          {'id': 'a', 'name': 'Flow', 'kind': 'dfd'},
          {'id': 'a', 'name': 'dup id', 'kind': 'dfd'},
          {'id': 'b', 'name': 'flow', 'kind': 'dfd'}, // ชื่อซ้ำ (ไม่สนตัวพิมพ์)
          {'id': 'c', 'name': '   ', 'kind': 'dfd'},
          {'id': 'x', 'name': 'odd', 'kind': 'ufo'},
          'not a map',
          {'id': 'er', 'name': 'Main', 'kind': 'er'},
          {'id': 'er2', 'name': 'Another ER', 'kind': 'er'},
          {'id': 'er', 'name': 'bad', 'kind': 'dfd'}, // ใช้ id ของ ER
        ],
      };
      final d = decodeProjectMap(j).documents;
      expect(d.where((x) => x.type == DocType.er).length, 1);
      expect(d.map((x) => x.id).toSet().length, d.length);
      expect(d.map((x) => x.name.toLowerCase()).toSet().length, d.length);
      expect(d.every((x) => x.name.isNotEmpty), true);
      expect(d.map((x) => x.id), ['a', 'b', 'c', 'er']);
      expect(d.firstWhere((x) => x.id == 'er').name, 'Main');
    });

    test('ชื่อยาวเกินถูกตัด', () {
      final j = {
        'format': 'nsl-erd',
        'version': 2,
        ...base().toJson(),
        'diagrams': [
          {'id': 'a', 'name': 'x' * 100, 'kind': 'dfd'},
        ],
      };
      expect(decodeProjectMap(j).documentById('a')!.name.length, kDiagramNameMax);
    });

    test('ไฟล์ v3 ไม่มีเอกสาร ER: เปิดแล้วมีแท็บ ER ว่างให้ (DFD เดิมอยู่ครบ)', () {
      final w = decodeProjectMap({
        'format': 'nsl-erd',
        'version': 3,
        'name': 'Flows',
        'documents': [
          {'id': 'er', 'type': 'dfd', 'name': 'ER', 'content': {}},
        ],
      });
      final c = ProjectController()..loadWorkspace(w, null);
      expect(c.documents.map((d) => (d.id, d.type)), [('er2', DocType.er), ('er', DocType.dfd)]);
      expect(c.documents.first.name, 'ER 2');
      expect(c.project.name, 'Flows');
      expect(c.activeDiagramId, 'er2');
    });
  });

  group('ProjectController: แท็บ', () {
    test('เพิ่ม DFD / ER: เปิดทันที ชื่อไม่ซ้ำ', () {
      final c = ProjectController(base());
      final a = c.addDiagram(DocType.dfd)!;
      final b = c.addDiagram(DocType.dfd)!;
      expect([a.name, b.name], ['DFD', 'DFD 2']);
      expect(c.activeDiagramId, b.id);
      expect(c.dirty, true);
      final e = c.addDiagram(DocType.er)!;
      expect((e.type, e.name, c.activeDiagramId), (DocType.er, 'ER 2', e.id));
    });

    test('เปลี่ยนชื่อ: ว่าง/ซ้ำ = ปฏิเสธ; ชื่อเดิมของตัวเองผ่าน', () {
      final c = ProjectController(base());
      final a = c.addDiagram(DocType.dfd, name: 'Orders')!;
      expect(c.renameDiagram(a.id, '  '), false);
      expect(c.renameDiagram(a.id, 'er'), false); // ซ้ำกับแท็บ ER (ไม่สนตัวพิมพ์)
      expect(c.renameDiagram(a.id, 'ORDERS'), true);
      expect(c.documentById(a.id)!.name, 'ORDERS');
      expect(c.renameDiagram(kErDiagramId, 'Shop ER'), true);
      expect(c.renameDiagram('nope', 'x'), false);
    });

    test('ลบ: ER ลบไม่ได้; ลบแท็บที่เปิดอยู่ = ไปแท็บก่อนหน้า', () {
      final c = ProjectController(base());
      final a = c.addDiagram(DocType.dfd)!;
      final b = c.addDiagram(DocType.dfd)!;
      expect(c.deleteDiagram(kErDiagramId), false);
      expect(c.deleteDiagram(b.id), true);
      expect(c.activeDiagramId, a.id);
      expect(c.deleteDiagram(a.id), true);
      expect(c.activeDiagramId, kErDiagramId);
      expect(c.documents.length, 1);
    });

    test('ย้ายลำดับ', () {
      final c = ProjectController(base());
      final a = c.addDiagram(DocType.dfd, name: 'A')!;
      final b = c.addDiagram(DocType.dfd, name: 'B')!;
      c.moveDiagram(b.id, 0);
      expect(c.documents.map((d) => d.name), ['B', 'ER', 'A']);
      c.moveDiagram(a.id, 99);
      expect(c.documents.map((d) => d.name), ['B', 'ER', 'A']);
      c.moveDiagram(kErDiagramId, 2);
      expect(c.documents.map((d) => d.name), ['B', 'A', 'ER']);
    });

    test('แท็บไม่เข้า undo และ undo ของเนื้อหา ER ไม่ทำให้แท็บหาย', () {
      final c = ProjectController(base());
      c.addTable(name: 'x'); // มีประวัติ 1 ขั้น
      final d = c.addDiagram(DocType.dfd, name: 'Flow')!;
      c.renameDiagram(d.id, 'Flow 2');
      c.selectDiagram(kErDiagramId); // undo ทำงานกับแท็บที่เปิดอยู่
      c.undo(); // ย้อนการเพิ่มตาราง
      expect(c.project.tables.any((t) => t.name == 'x'), false);
      expect(c.documentById(d.id)!.name, 'Flow 2');
      c.redo();
      expect(c.documentById(d.id), isNotNull);
      expect(c.canUndo, true);
    });

    test('เปิด/สร้างโปรเจกต์ใหม่ = กลับมาที่แท็บ ER', () {
      final c = ProjectController(base());
      c.addDiagram(DocType.dfd);
      c.newProject();
      expect(c.activeDiagram.type, DocType.er);
    });
  });

  group('บนจอ', () {
    late ProjectController c;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang)));
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
      await tester.pump();
    }

    Future<void> addDfd(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('tab-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DFD (Data Flow Diagram)'));
      await tester.pumpAndSettle();
    }

    testWidgets('เริ่มต้นมีแท็บ ER; กด + > DFD ได้แท็บใหม่และเปิดพื้นที่ DFD แทน ER; สลับกลับ ER ได้', (tester) async {
      await boot(tester);
      expect(find.text('ER'), findsOneWidget);
      expect(find.byKey(const ValueKey('dfd-canvas')), findsNothing);
      await addDfd(tester);
      expect(find.text('DFD'), findsWidgets);
      expect(find.byKey(const ValueKey('dfd-canvas')), findsOneWidget);
      expect(find.text('เลือกตารางทางซ้ายเพื่อแก้ไข'), findsNothing); // แผง ER ถูกแทนที่

      await tester.tap(find.text('ER'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dfd-canvas')), findsNothing);
      expect(find.text('เลือกตารางทางซ้ายเพื่อแก้ไข'), findsOneWidget);
    });

    testWidgets('คีย์ลัดแก้ ER (เช่น T สร้างตาราง) ไม่ทำงานขณะเปิดแท็บ DFD', (tester) async {
      await boot(tester);
      await addDfd(tester);
      final before = c.project.tables.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, );
      await tester.pump();
      expect(c.project.tables.length, before);
      expect(c.canUndo, false);
    });

    testWidgets('คลิกขวาแท็บ DFD > เปลี่ยนชื่อ; ชื่อซ้ำแจ้งเตือน', (tester) async {
      await boot(tester);
      await addDfd(tester);
      final tab = find.byKey(ValueKey('tab-${c.activeDiagramId}'));
      final g = await tester.startGesture(tester.getCenter(tab), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('เปลี่ยนชื่อ…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Level 0');
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
      expect(c.activeDiagram.name, 'Level 0');

      // ซ้ำกับแท็บ ER
      final g2 = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('tab-${c.activeDiagramId}'))),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g2.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('เปลี่ยนชื่อ…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'er');
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
      expect(c.activeDiagram.name, 'Level 0');
      expect(find.text('ชื่อว่างหรือซ้ำกับแผนภาพอื่น'), findsOneWidget);
    });

    testWidgets('ปุ่ม × ลบแผนภาพ: ถามยืนยันก่อน ยกเลิก = ไม่ลบ; ER ไม่มีปุ่ม ×', (tester) async {
      await boot(tester);
      await addDfd(tester);
      final id = c.activeDiagramId;
      expect(find.byKey(const ValueKey('tab-close-$kErDiagramId')), findsNothing);
      await tester.tap(find.byKey(ValueKey('tab-close-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(c.documentById(id), isNotNull);

      await tester.tap(find.byKey(ValueKey('tab-close-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบ'));
      await tester.pumpAndSettle();
      expect(c.documentById(id), isNull);
      expect(c.activeDiagram.type, DocType.er);
    });

    testWidgets('ลากแท็บเพื่อเรียงลำดับใหม่', (tester) async {
      await boot(tester);
      await addDfd(tester);
      final id = c.activeDiagramId;
      final from = tester.getCenter(find.byKey(ValueKey('tab-$id')));
      final to = tester.getCenter(find.byKey(const ValueKey('tab-$kErDiagramId'))) - const Offset(30, 0);
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 100));
      final steps = 12;
      for (var i = 1; i <= steps; i++) {
        await g.moveTo(Offset.lerp(from, to, i / steps)!);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(c.documents.first.id, id);
    });

    testWidgets('ภาษาอังกฤษ: ข้อความของแท็บแปลครบ', (tester) async {
      await boot(tester, lang: Lang.en);
      await tester.tap(find.byKey(const ValueKey('tab-add')));
      await tester.pumpAndSettle();
      expect(find.text('DFD (Data Flow Diagram)'), findsOneWidget);
      await tester.tap(find.text('DFD (Data Flow Diagram)'));
      await tester.pumpAndSettle();
      expect(find.text('The DFD diagram is empty'), findsOneWidget);
      currentLang = Lang.th;
    });
  });
}
