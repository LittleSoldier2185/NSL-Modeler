import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/ui/project_home.dart';
import 'package:provider/provider.dart';

/// ขั้น 9: หน้า Project Home
void main() {
  late WorkspaceController w;
  final home = find.byKey(const ValueKey('project-home'));

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    await tester.pump();
  }

  /// ER หลักมี 2 ตาราง (3 คอลัมน์) ; DFD 1 อันมีกระบวนการไม่มีชื่อ (ให้เกิดปัญหา)
  ProjectDocument seed() {
    w.mainEr.project.tables
      ..add(TableModel(id: 'a', name: 'users', columns: [ColumnModel(id: 'a1', name: 'id'), ColumnModel(id: 'a2', name: 'name')]))
      ..add(TableModel(id: 'b', name: 'orders', columns: [ColumnModel(id: 'b1', name: 'id')]));
    final d = w.addDocument(DocType.dfd, name: 'Level 0')!;
    d.dfd!.nodes.add(DfdNode(id: 'n1', kind: DfdKind.process, name: '', number: '1.0'));
    return d;
  }

  Future<void> openHome(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('explorer-home')));
    await tester.pump();
  }

  String statValue(WidgetTester tester, String k) =>
      (tester.widget<Container>(find.byKey(ValueKey('home-stat-$k'))).child! as Row).children.whereType<Text>().first.data!;

  testWidgets('เปิดจากปุ่มในตัวสำรวจโปรเจกต์ ; ปกติไม่แสดง', (tester) async {
    await boot(tester);
    expect(home, findsNothing);
    await openHome(tester);
    expect(home, findsOneWidget);
    expect(w.homeView, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('เปิดจากเมนูมุมมอง และจาก command palette', (tester) async {
    await boot(tester);
    await tester.tap(find.text('มุมมอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('หน้า Project Home'));
    await tester.pumpAndSettle();
    expect(home, findsOneWidget);

    w.openDocument(w.mainEr.docId);
    await tester.pump();
    expect(home, findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Project Home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('หน้า Project Home').last);
    await tester.pumpAndSettle();
    expect(home, findsOneWidget);
  });

  testWidgets('แสดงจำนวนของโปรเจกต์หลายเอกสารและการ์ดแต่ละเอกสาร', (tester) async {
    await boot(tester);
    final d = seed();
    final e2 = w.addDocument(DocType.er, name: 'Billing')!;
    await openHome(tester);
    expect(statValue(tester, 'docs'), '3');
    expect(statValue(tester, 'tables'), '2');
    expect(statValue(tester, 'objects'), '1');
    expect(find.descendant(of: find.byKey(ValueKey('home-card-${w.mainEr.docId}')), matching: find.text('2 ตาราง · 3 คอลัมน์ · 0 FK')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('home-card-${d.id}')), matching: find.text('1 วัตถุ · 0 เส้นข้อมูล')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('home-card-${e2.id}')), matching: find.text('Billing')), findsOneWidget);
    expect(find.text('แผนภาพ ER (2)'), findsWidgets); // หัวกลุ่มของ Home และของตัวสำรวจ
    expect(find.text('แผนภาพกระแสข้อมูล (DFD) (1)'), findsWidgets);
  });

  testWidgets('ป้ายปัญหาที่การ์ดรวมกันเท่ากับตัวเลขสรุป', (tester) async {
    await boot(tester);
    final d = seed();
    await openHome(tester);
    expect(find.byKey(ValueKey('home-issues-${d.id}')), findsOneWidget);
    final total = int.parse(statValue(tester, 'errors')) + int.parse(statValue(tester, 'warnings'));
    var sum = 0;
    for (final doc in w.documents) {
      final f = find.descendant(of: find.byKey(ValueKey('home-issues-${doc.id}')), matching: find.byType(Text));
      if (f.evaluate().isNotEmpty) sum += int.parse(tester.widget<Text>(f).data!);
    }
    expect(total, greaterThan(0));
    expect(sum, total);
  });

  testWidgets('คลิกการ์ด = เปิดเอกสารและออกจากหน้า Home ; เอกสารที่ใช้งานอยู่แล้วก็ออก ; คลิกตัวสำรวจก็ออก', (tester) async {
    await boot(tester);
    final d = seed();
    w.openDocument(w.mainEr.docId);
    await openHome(tester);
    await tester.tap(find.byKey(ValueKey('home-card-${d.id}')));
    await tester.pumpAndSettle();
    expect(home, findsNothing);
    expect(w.activeId, d.id);

    await openHome(tester);
    await tester.tap(find.byKey(ValueKey('home-card-${d.id}'))); // ใช้งานอยู่แล้ว
    await tester.pumpAndSettle();
    expect(home, findsNothing);

    await openHome(tester);
    await tester.tap(find.byKey(ValueKey('explorer-row-${w.mainEr.docId}')));
    await tester.pumpAndSettle();
    expect(home, findsNothing);
    expect(w.activeId, w.mainEr.docId);
  });

  testWidgets('ปุ่มลัด: เพิ่ม ER / เพิ่ม DFD / ปัญหาทั้งโปรเจกต์', (tester) async {
    await boot(tester);
    await openHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-add-dfd')));
    await tester.pumpAndSettle();
    expect(w.activeDocument.type, DocType.dfd);
    expect(home, findsNothing);

    await openHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-add-er')));
    await tester.pumpAndSettle();
    expect(w.activeDocument.type, DocType.er);
    expect(w.documents.length, 3);

    await openHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-issues')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-issues')), findsOneWidget);
  });

  testWidgets('แสดงสถานะบันทึก ; การเปิดหน้า Home ไม่ทำให้โปรเจกต์ dirty', (tester) async {
    await boot(tester);
    await openHome(tester);
    expect(w.dirty, isFalse);
    expect(find.byKey(const ValueKey('home-dirty')), findsNothing);
    w.addDocument(DocType.dfd);
    await openHome(tester);
    expect(find.descendant(of: home, matching: find.text('● ยังไม่ได้บันทึก')), findsOneWidget);
    expect(find.text('ยังไม่ได้บันทึกเป็นไฟล์'), findsOneWidget);
  });

  testWidgets('ภาษาอังกฤษ: ไม่มีข้อความไทยหลุดในหน้า Home', (tester) async {
    await boot(tester, lang: Lang.en);
    seed();
    await openHome(tester);
    expect(find.text('Add ER'), findsOneWidget);
    expect(find.text('Add DFD'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('DFD objects'), findsOneWidget);
    expect(find.text('Not saved to a file yet'), findsOneWidget);
    final thai = RegExp(r'[฀-๿]');
    final texts = tester.widgetList<Text>(find.descendant(of: home, matching: find.byType(Text)));
    for (final t in texts) {
      expect(thai.hasMatch(t.data ?? ''), isFalse, reason: t.data);
    }
    currentLang = Lang.th;
  });

  testWidgets('พื้นที่แคบ (360px): หน้า Home ไม่ล้น แม้ชื่อเอกสารยาว', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wc = WorkspaceController();
    addTearDown(wc.dispose);
    wc.mainEr.project.tables.add(TableModel(id: 'a', name: 'users', columns: [ColumnModel(id: 'a1', name: 'id')]));
    wc.addDocument(DocType.er, name: 'ชื่อแผนภาพที่ยาวมากมากมากมากมากมากมากมากมากมากมาก');
    wc.addDocument(DocType.dfd, name: 'Level 0');
    wc.showHome();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: wc,
      child: const MaterialApp(home: Scaffold(body: ProjectHomeView())),
    ));
    expect(home, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
