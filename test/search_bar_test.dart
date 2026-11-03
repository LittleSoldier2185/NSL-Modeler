import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/core/models/dfd_model.dart';
import 'package:nsl_modeler/core/models/diagram.dart';
import 'package:nsl_modeler/core/models/group_model.dart';
import 'package:nsl_modeler/core/models/note_model.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/dfd_controller.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:nsl_modeler/ui/palette/command_palette.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

PaletteEntry e(PaletteKind k, String title, {String? search}) =>
    PaletteEntry(kind: k, title: title, search: search ?? title, run: () {});

void main() {
  group('ตัวนำหน้าของช่องค้นหา', () {
    final all = [
      e(PaletteKind.command, 'Export .sql'),
      e(PaletteKind.table, 'users'),
      e(PaletteKind.column, 'users.email'),
      e(PaletteKind.group, 'Customer'),
      e(PaletteKind.note, 'user notes'),
      e(PaletteKind.dfdNode, 'User'),
      e(PaletteKind.dfdFlow, 'user data'),
      e(PaletteKind.issue, 'users no pk'),
    ];
    List<String> r(String q) => paletteResults(all, q).map((x) => x.title).toList();

    test('แยกตัวนำหน้า', () {
      expect(parsePaletteQuery('@users').kinds, {PaletteKind.table, PaletteKind.group});
      expect(parsePaletteQuery('  #em').query, 'em');
      expect(parsePaletteQuery('users').kinds, isNull);
      expect(parsePaletteQuery('users').query, 'users');
      expect(parsePaletteQuery('').kinds, isNull);
    });

    test('ค้นว่าง: คำสั่ง ตาราง กลุ่ม เท่านั้น', () {
      expect(r(''), ['Export .sql', 'users', 'Customer']);
    });

    test('ไม่มีตัวนำหน้า: ค้นทุกชนิด', () {
      expect(r('user'), containsAll(['users', 'users.email', 'User', 'user data', 'user notes', 'users no pk']));
    });

    test('@ ตาราง/กลุ่ม · # คอลัมน์ · : DFD · ! ปัญหา · > คำสั่ง · ~ โน้ต', () {
      expect(r('@'), ['users', 'Customer']);
      expect(r('@users'), ['users']);
      expect(r('#'), ['users.email']);
      expect(r(':'), ['User', 'user data']);
      expect(r(':user'), ['User', 'user data']);
      expect(r('!'), ['users no pk']);
      expect(r('>'), ['Export .sql']);
      expect(r('~'), ['user notes']);
      expect(r('>user'), isEmpty);
    });
  });

  group('ช่องค้นหาบนแถบบน', () {
    late ProjectController c;
    late DfdController d;

    Future<void> boot(WidgetTester tester, {Size size = const Size(2600, 900), Lang lang = Lang.th}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: lang)));
      final ctx = tester.element(find.byType(HomePage));
      c = ctx.read<ProjectController>();
      d = ctx.read<DfdController>();
      c.loadProject(base(), null);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('หน้าต่างกว้าง: มีช่องค้นหา (พร้อมคีย์ลัด) ไม่ทับกลุ่มปุ่ม; คลิกเปิดหน้าค้นหา', (tester) async {
      await boot(tester);
      final field = find.byKey(const ValueKey('top-search'));
      expect(field, findsOneWidget);
      expect(find.text('Ctrl+K'), findsOneWidget);
      expect(tester.getRect(field).right, lessThanOrEqualTo(tester.getRect(find.byTooltip('ย้อนกลับ (Ctrl+Z)')).left));
      expect(find.byTooltip('ค้นหา / สั่งงาน (Ctrl+K)'), findsNothing); // ไม่ซ้ำกับปุ่มแว่นขยาย
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
    });

    testWidgets('ช่องค้นหาอยู่กึ่งกลางของแถบชื่อหน้าต่างทั้งแถบ (เมื่อที่ว่างพอ)', (tester) async {
      await boot(tester, size: const Size(3200, 900));
      await tester.pump();
      final r = tester.getRect(find.byKey(const ValueKey('top-search')));
      expect(r.center.dx, closeTo(3200 / 2, 1.5));
      // เปลี่ยนขนาดหน้าต่าง = ยังอยู่กลาง
      tester.view.physicalSize = const Size(3600, 900);
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('top-search'))).center.dx, closeTo(3600 / 2, 1.5));
    });

    testWidgets('หน้าต่างแคบ: ช่องถูกซ่อน เหลือปุ่มแว่นขยายในกลุ่มปุ่มที่เปิดหน้าค้นหาเหมือนกัน; ไม่ overflow', (tester) async {
      await boot(tester, size: const Size(1200, 800));
      expect(find.byKey(const ValueKey('top-search')), findsNothing);
      final icon = find.byTooltip('ค้นหา / สั่งงาน (Ctrl+K)');
      expect(icon, findsOneWidget);
      await tester.tap(icon);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ค้น "@" แล้วเห็นเฉพาะตาราง; พิมพ์ชื่อ DFD ข้ามแท็บ = สลับไปแท็บนั้นและเลือกวัตถุ', (tester) async {
      await boot(tester);
      final tab = c.addDiagram(DiagramKind.dfd, name: 'Level 1')!;
      c.project.dfd[tab.id] = DfdDiagram(
        nodes: [DfdNode(id: 'n1', kind: DfdKind.process, name: 'Manage Cart', number: '2.0', x: 3000, y: 2000)],
      );
      c.selectDiagram(kErDiagramId);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('top-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pump();
      expect(find.text('users'), findsWidgets);
      expect(find.text('2.0 Manage Cart'), findsNothing);

      await tester.enterText(find.byType(TextField).last, 'manage cart');
      await tester.pump();
      expect(find.textContaining('Level 1 ·'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.activeDiagramId, tab.id);
      expect(d.selectedNodeIds, {'n1'});
      // เลื่อนไปที่วัตถุ: จุดกึ่งกลางจอ = กึ่งกลางวัตถุ
      final n = d.diagram.nodeById('n1')!;
      final centre = d.toWorld(d.viewport.center(Offset.zero));
      expect((centre - Offset(n.cx, n.cy)).distance, lessThan(2));
    });

    testWidgets('ค้นตารางขณะอยู่แท็บ DFD = กลับแท็บ ER แล้วเลือกตาราง', (tester) async {
      await boot(tester);
      c.addDiagram(DiagramKind.dfd);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('top-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '@orders');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.activeDiagram.kind, DiagramKind.er);
      expect(c.selectedTableId, 'to');
    });

    testWidgets('ค้นกลุ่ม/โน้ต/ปัญหาของ ER ได้', (tester) async {
      await boot(tester);
      c.project.groups.add(GroupModel(id: 'g', name: 'Billing zone', x: 100, y: 100));
      c.project.notes.add(NoteModel(id: 'nt', text: 'remember vacuum job', x: 400, y: 400));
      await tester.tap(find.byKey(const ValueKey('top-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'billing');
      await tester.pump();
      expect(find.text('Billing zone'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '~vacuum');
      await tester.pump();
      expect(find.text('remember vacuum job'), findsOneWidget);
    });

    testWidgets('คำสั่งของ ER ที่เลือกจากช่องค้นหาขณะเปิดแท็บ DFD ไม่แตะ ER', (tester) async {
      await boot(tester);
      c.addDiagram(DiagramKind.dfd);
      await tester.pump();
      final before = c.project.tables.length;
      await tester.tap(find.byKey(const ValueKey('top-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '>เพิ่มตาราง');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.project.tables.length, before);
    });

    testWidgets('ภาษาอังกฤษ: ข้อความของช่อง/ตัวช่วยนำหน้าแปลครบ', (tester) async {
      await boot(tester, lang: Lang.en);
      expect(find.text('Search tables, commands, DFD objects…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('top-search')));
      await tester.pumpAndSettle();
      expect(find.textContaining('@ tables'), findsOneWidget);
      currentLang = Lang.th;
    });
  });

  group('ปุ่ม + ของแท็บแผนภาพ (แบบแท็บเบราว์เซอร์)', () {
    testWidgets('ต่อท้ายแท็บสุดท้ายทันที และขยับไปทางขวาเมื่อมีแท็บเพิ่ม', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslModelerApp());
      final c = tester.element(find.byType(HomePage)).read<ProjectController>();
      await tester.pump();
      final add = find.byKey(const ValueKey('tab-add'));
      double gap() => tester.getRect(add).left - tester.getRect(find.byKey(ValueKey('tab-${c.project.diagrams.last.id}'))).right;
      expect(gap(), lessThan(8));
      final x0 = tester.getRect(add).left;
      c.addDiagram(DiagramKind.dfd);
      await tester.pumpAndSettle();
      expect(tester.getRect(add).left, greaterThan(x0 + 60));
      expect(gap(), lessThan(8));
      c.addDiagram(DiagramKind.dfd);
      await tester.pumpAndSettle();
      expect(gap(), lessThan(8));
    });

    testWidgets('แท็บเยอะเกินแถบ: ปุ่ม + ยังอยู่ในจอ ไม่ overflow', (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslModelerApp());
      final c = tester.element(find.byType(HomePage)).read<ProjectController>();
      for (var i = 0; i < 14; i++) {
        c.addDiagram(DiagramKind.dfd, name: 'Diagram number $i');
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(const ValueKey('tab-add'))).right, lessThanOrEqualTo(1000));
    });
  });

  group('โลโก้แอป', () {
    testWidgets('แถบบนใช้ไอคอนของแอป (ไฟล์เดียวกับไอคอนโปรแกรม)', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslModelerApp());
      await tester.pump();
      expect(find.byKey(const ValueKey('app-logo')), findsOneWidget);
      expect(find.byIcon(Icons.storage_rounded), findsNothing);
    });
  });
}
