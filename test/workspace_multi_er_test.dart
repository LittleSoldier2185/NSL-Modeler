import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/diagram.dart';
import 'package:nsl_dev/core/models/doc_ref.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/core/validate/workspace_validator.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/dfd_controller.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/diagram_tabs.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';
import 'support/project_helpers.dart';

/// ขั้น 7: โปรเจกต์มีเอกสาร ER ได้หลายอัน — เพิ่ม/ทำสำเนา/เปลี่ยนชื่อ/ย้าย/ลบ, undo แยกต่อ ER, ลิงก์ DFD ข้าม ER
void main() {
  group('WorkspaceController: ER หลายอัน', () {
    late WorkspaceController w;
    late ProjectController er1;

    setUp(() {
      w = WorkspaceController(Workspace.single(base(Dialect.postgres)));
      er1 = w.mainEr;
      er1.setBoardSize(3000, 2000);
    });
    tearDown(() => w.dispose());

    test('เพิ่ม ER: ชื่อไม่ซ้ำ เปิดทันที controller แยก ; dialect/ขนาดกระดานตั้งต้นตาม ER ที่ใช้งานอยู่', () {
      w.markSaved('x.nsld');
      final doc = w.addDocument(DocType.er)!;
      expect((doc.type, doc.name), (DocType.er, 'ER 2'));
      expect(w.activeId, doc.id);
      expect(w.structureDirty, isTrue);
      final er2 = w.currentEr;
      expect(identical(er2, er1), isFalse);
      expect(identical(w.mainEr, er1), isTrue);
      expect(er2.docId, doc.id);
      expect(er2.project.tables, isEmpty);
      expect((er2.project.dialect, er2.project.boardWidth, er2.project.boardHeight), (Dialect.postgres, 3000, 2000));
      expect(w.addDocument(DocType.er, name: 'Billing')!.name, 'Billing');
      expect(w.addDocument(DocType.er, name: 'billing')!.name, 'billing 2');
    });

    test('dialect / ขนาดกระดาน / undo แยกต่อ ER ; undo ของ workspace = ER ที่เปิดอยู่', () {
      final er2 = w.erController(w.addDocument(DocType.er)!.id)!;
      er2.setDialect(Dialect.sqlite);
      er2.addTable(name: 'invoices');
      er1.addTable(name: 'later');
      expect((er1.project.dialect, er2.project.dialect), (Dialect.postgres, Dialect.sqlite));

      w.openDocument(er2.docId);
      w.undo(); // ย้อนการเพิ่มตารางของ ER 2
      expect(er2.project.tables, isEmpty);
      expect(er1.project.tables.any((t) => t.name == 'later'), isTrue);
      w.undo();
      expect(er2.project.dialect, Dialect.postgres);
      expect(w.canUndo, isFalse);

      w.openDocument(er1.docId);
      expect(w.canUndo, isTrue);
      w.undo();
      expect(er1.project.tables.any((t) => t.name == 'later'), isFalse);
      expect(er2.project.dialect, Dialect.postgres);
    });

    test('ทำสำเนา ER: เนื้อหาเหมือนกันแต่แยกขาด ชื่อใหม่ ประวัติเริ่มใหม่ วางต่อจากต้นฉบับ', () {
      w.addDocument(DocType.dfd, name: 'Flow');
      er1.addTable(name: 'extra');
      final copy = w.duplicateDocument(er1.docId)!;
      expect((copy.type, copy.name), (DocType.er, 'ER 2'));
      expect(w.documents.map((d) => d.id), [er1.docId, copy.id, w.documents.last.id]);
      expect(w.activeId, copy.id);
      final c2 = w.currentEr;
      expect(jsonEncode(c2.project.toContentJson()), jsonEncode(er1.project.toContentJson()));
      expect(c2.canUndo, isFalse);
      c2.renameTable('tu', 'members');
      expect(er1.project.tableById('tu')!.name, 'users');
      expect(w.duplicateDocument('nope'), isNull);
    });

    test('เปลี่ยนชื่อ ER: ห้ามซ้ำทั้งโปรเจกต์ (ไม่สนตัวพิมพ์)', () {
      final e2 = w.addDocument(DocType.er, name: 'Sales')!;
      final d = w.addDocument(DocType.dfd, name: 'Flow')!;
      expect(w.renameDocument(e2.id, 'flow'), isFalse);
      expect(w.renameDocument(e2.id, 'er'), isFalse);
      expect(w.renameDocument(d.id, 'SALES'), isFalse);
      expect(w.renameDocument(e2.id, 'Sales DB'), isTrue);
      expect(w.documentById(e2.id)!.name, 'Sales DB');
    });

    test('ย้ายแท็บ ER ได้ ; ER หลักยังเป็นตัวเดิม', () {
      final e2 = w.addDocument(DocType.er, name: 'B')!;
      w.reorderTab(e2.id, 0);
      expect(w.documents.map((d) => d.id), [e2.id, er1.docId]);
      expect(identical(w.mainEr, er1), isTrue);
    });

    test('ลบ ER: อันสุดท้ายลบไม่ได้ ; ลบได้เมื่อมี ER อื่น — controller ถูกทิ้ง ไปแท็บข้างเคียง', () {
      expect(w.canDeleteDocument(er1.docId), isFalse);
      expect(w.deleteDocument(er1.docId), isNull);
      final dfd = w.addDocument(DocType.dfd)!;
      expect(w.canDeleteDocument(er1.docId), isFalse); // DFD ไม่นับ: ต้องเหลือ ER อย่างน้อยหนึ่งอัน
      final e2 = w.addDocument(DocType.er)!;
      final er2 = w.erController(e2.id)!;
      expect((w.canDeleteDocument(er1.docId), w.canDeleteDocument(e2.id)), (true, true));
      expect(w.deleteDocument(e2.id), isEmpty);
      expect(er2.disposed, isTrue);
      expect(w.hasController(e2.id), isFalse);
      expect(w.activeId, dfd.id);
      expect(w.structureDirty, isTrue);
      expect(identical(w.currentEr, er1), isTrue);
    });

    test('ลบ ER หลัก: ER อันถัดไปเป็นตัวหลักแทน (controller ตัวเดิมของมัน ประวัติยังอยู่) ; บันทึก-เปิดใหม่ได้', () {
      final e2 = w.addDocument(DocType.er, name: 'Next')!;
      final er2 = w.erController(e2.id)!;
      er2.addTable(name: 'kept');
      w.openDocument(er1.docId);
      expect(w.deleteDocument(er1.docId), isEmpty);
      expect(er1.disposed, isTrue);
      expect(identical(w.mainEr, er2), isTrue);
      expect(identical(w.currentEr, er2), isTrue);
      expect(w.activeId, e2.id);
      expect(er2.canUndo, isTrue);
      final back = roundTrip(w.workspace);
      expect(back.documents.map((d) => (d.id, d.type)), [(e2.id, DocType.er)]);
      expect(back.firstEr!.er!.tables.single.name, 'kept');

      // เปิดไฟล์ใหม่หลังจากนั้น: ใช้ ER หลักตัวใหม่ต่อ
      w.loadProject(base(), null);
      expect(identical(w.mainEr, er2), isTrue);
      expect(er2.docId, kErDiagramId);
    });

    test('บันทึก-เปิดใหม่: ER หลายอันกลับมาครบ (ชื่อ ลำดับ dialect ของแต่ละอัน) เป็นไฟล์ v3', () {
      final e2 = w.addDocument(DocType.er, name: 'Archive')!;
      w.erController(e2.id)!
        ..setDialect(Dialect.mssql)
        ..addTable(name: 'logs');
      final text = ProjectFile.encode(w.workspace);
      expect((jsonDecode(text) as Map)['version'], 3);
      final back = ProjectFile.decode(text);
      expect(back.documents.map((d) => (d.id, d.name, d.type)), [
        (kErDiagramId, 'ER', DocType.er),
        (e2.id, 'Archive', DocType.er),
      ]);
      expect(back.documents[0].er!.dialect, Dialect.postgres);
      expect(back.documents[1].er!.dialect, Dialect.mssql);
      expect(back.documents[1].er!.tables.single.name, 'logs');

      final c = WorkspaceController()..loadWorkspace(back, null);
      addTearDown(c.dispose);
      expect(c.mainEr.docId, kErDiagramId);
      expect(c.erController(e2.id)!.project.dialect, Dialect.mssql);
    });

    test('ตัวตรวจทั้งโปรเจกต์: ปัญหาของ ER แต่ละอันแยกตามเอกสาร', () {
      final e2 = w.addDocument(DocType.er, name: 'Two')!;
      w.erController(e2.id)!.addTable(name: 'no_pk', withId: false);
      final issues = validateWorkspace(w.workspace);
      expect(issues.where((i) => i.docId == e2.id && i.issue.tableId != null), isNotEmpty);
      expect(issues.every((i) => i.docId == er1.docId || i.docId == e2.id), isTrue);
    });
  });

  group('DFD ผูกตารางข้าม ER', () {
    late WorkspaceController w;
    late ProjectController er1, er2;
    late DfdController d;
    late String dfd, store;

    setUp(() {
      w = WorkspaceController(Workspace.single(base()));
      er1 = w.mainEr;
      er2 = w.erController(w.addDocument(DocType.er, name: 'Billing')!.id)!;
      er2.addBuiltTable(TableModel(id: 'inv', name: 'invoices'));
      dfd = w.addDocument(DocType.dfd, name: 'L0')!.id;
      d = w.dfdController(dfd)!;
      store = d.addNode(DfdKind.store, 100, 100)!.id;
      d.renameNode(store, '');
      d.setStoreTable(store, DocRef(docId: er2.docId, elementId: 'inv', kind: DocRefKind.storeTable));
    });
    tearDown(() => w.dispose());

    DfdNode node() => w.dfdOf(dfd).nodeById(store)!;

    test('ผูกกับตารางใน ER อันที่สอง: tableDocId = ER นั้น ; ชื่อตามตาราง', () {
      expect((node().tableId, node().tableDocId, node().name), ('inv', er2.docId, 'invoices'));
      expect(w.erDocumentWithTable(er2.docId, 'inv')!.id, er2.docId);
      expect(w.erDocumentWithTable(er1.docId, 'inv'), isNull);
    });

    test('"ไปที่ตาราง" เปิดแท็บ ER ที่ผูกอยู่และเลือกตาราง ; ER ที่ใช้งานล่าสุดคงอยู่ระหว่างอยู่แท็บ DFD', () {
      w.openDocument(er1.docId);
      w.openDocument(dfd);
      expect(identical(w.currentEr, er1), isTrue);
      d.gotoLinkedTable(store);
      expect(w.activeId, er2.docId);
      expect(identical(w.currentEr, er2), isTrue);
      expect(er2.selectedTableId, 'inv');
      w.openDocument(dfd);
      expect(identical(w.currentEr, er2), isTrue);
    });

    test('ข้อมูลเก่าที่ไม่รู้เอกสาร (tableDocId = null): หาตาราง id เดียวกันใน ER ที่ใช้งานก่อน แล้วไล่ทุก ER', () {
      w.openDocument(er1.docId);
      expect(w.erDocumentWithTable(null, 'inv')!.id, er2.docId);
      expect(w.erDocumentWithTable(null, 'tu')!.id, er1.docId);
      expect(w.erDocumentWithTable(null, 'nope'), isNull);
    });

    test('คัดลอก/วางที่เก็บข้อมูล: tableDocId ของ ER ต้นทางติดไป (ไม่เปลี่ยนเป็น ER ที่ใช้งานอยู่)', () {
      w.openDocument(er1.docId);
      w.openDocument(dfd);
      d.selectNode(store);
      d.pasteText(d.copySelectionText());
      final pasted = w.dfdOf(dfd).nodes.last;
      expect(pasted.id, isNot(store));
      expect((pasted.tableId, pasted.tableDocId), ('inv', er2.docId));
    });

    test('ลบ ER ที่มีที่เก็บข้อมูลผูกอยู่: คืนลิงก์ที่ขาด ; ตัวตรวจแจ้ง ; "ไปที่ตาราง" ไม่ทำอะไร', () {
      expect(brokenLinkLines(w, er2.docId), ['L0 · D1 invoices → ตาราง invoices']);
      final broken = w.deleteDocument(er2.docId)!;
      expect(broken.single.$1, dfd);
      expect(broken.single.$3, DocRef(docId: er2.docId, elementId: 'inv', kind: DocRefKind.storeTable));
      // ลิงก์ไม่ถูกลบทิ้ง ผู้ใช้เห็นเป็นปัญหาแล้วแก้เอง
      expect(node().tableDocId, er2.docId);
      expect(
        validateWorkspace(w.workspace).where((i) => i.issue.code == 'dfd_store_table_missing').single.docId,
        dfd,
      );
      w.openDocument(dfd);
      d.gotoLinkedTable(store);
      expect(w.activeId, dfd);
    });
  });

  group('บนจอ', () {
    late WorkspaceController w;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.loadProject(base(), null);
      await tester.pump();
    }

    ProjectController er(WidgetTester tester) => tester.element(find.byType(HomePage)).read<ProjectController>();

    Future<void> addEr(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const ValueKey('tab-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> rightClickTab(WidgetTester tester, String id) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('tab-$id'))),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('กด + > ER Diagram: ได้แท็บ ER ใหม่ แคนวาส ER ว่าง ; สลับแท็บ = provider ได้ ER ของแท็บนั้น', (tester) async {
      await boot(tester);
      final first = er(tester);
      await addEr(tester, 'ER Diagram (ตารางฐานข้อมูล)');
      final id = w.activeId;
      expect(w.documentById(id)!.type, DocType.er);
      expect(find.text('ER 2'), findsOneWidget);
      expect(er(tester).docId, id);
      expect(er(tester).project.tables, isEmpty);
      expect(find.byKey(ValueKey('er-canvas-$id')), findsOneWidget);
      // ER มีสองอัน = มีปุ่ม × ทั้งคู่
      expect(find.byKey(ValueKey('tab-close-$id')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab-close-$kErDiagramId')), findsOneWidget);

      await tester.tap(find.text('ER').first);
      await tester.pumpAndSettle();
      expect(identical(er(tester), first), isTrue);
      expect(find.byKey(const ValueKey('er-canvas-$kErDiagramId')), findsOneWidget);
    });

    testWidgets('คลิกขวา > ทำสำเนาแผนภาพ: ได้ ER สำเนาที่มีตารางเดิม', (tester) async {
      await boot(tester);
      await rightClickTab(tester, kErDiagramId);
      await tester.tap(find.text('ทำสำเนาแผนภาพ'));
      await tester.pumpAndSettle();
      expect(w.documents.map((d) => d.name), ['ER', 'ER 2']);
      expect(er(tester).docId, w.documents[1].id);
      expect(er(tester).project.tables.map((t) => t.name), ['users', 'orders']);
    });

    testWidgets('ลบแท็บ ER ที่ DFD ผูกตารางอยู่: กล่องยืนยันแสดงลิงก์ที่จะขาด ; ยกเลิกไม่ลบ ; ยืนยันลบ', (tester) async {
      await boot(tester);
      final e2 = w.addDocument(DocType.er, name: 'Billing')!;
      w.erController(e2.id)!.addBuiltTable(TableModel(id: 'inv', name: 'invoices'));
      final dfd = w.addDocument(DocType.dfd, name: 'L0')!.id;
      final d = w.dfdController(dfd)!;
      final s = d.addNode(DfdKind.store, 100, 100)!;
      d.renameNode(s.id, 'Bills');
      d.setStoreTable(s.id, DocRef(docId: e2.id, elementId: 'inv', kind: DocRefKind.storeTable));
      w.openDocument(e2.id);
      await tester.pumpAndSettle();

      await rightClickTab(tester, e2.id);
      await tester.tap(find.text('ลบแผนภาพ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('delete-broken-links')), findsOneWidget);
      expect(find.text('ลิงก์จากแผนภาพอื่น 1 รายการจะใช้ไม่ได้:'), findsOneWidget);
      expect(find.text('• L0 · D1 Bills → ตาราง invoices'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(w.documentById(e2.id), isNotNull);

      await tester.tap(find.byKey(ValueKey('tab-close-${e2.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบ'));
      await tester.pumpAndSettle();
      expect(w.documentById(e2.id), isNull);
      expect(find.byKey(ValueKey('tab-${e2.id}')), findsNothing);
      // เหลือ ER อันเดียว = ลบไม่ได้ (ไม่มีปุ่ม ×)
      expect(find.byKey(const ValueKey('tab-close-$kErDiagramId')), findsNothing);
    });

    testWidgets('ภาษาอังกฤษ: เมนูเพิ่ม ER / ทำสำเนา / กล่องลบที่มีลิงก์ แปลครบ', (tester) async {
      await boot(tester, lang: Lang.en);
      addTearDown(() => currentLang = Lang.th);
      await addEr(tester, 'ER Diagram (database tables)');
      final e2 = w.activeId;
      w.erController(e2)!.addBuiltTable(TableModel(id: 'inv', name: 'invoices'));
      final d = w.dfdController(w.addDocument(DocType.dfd, name: 'L0')!.id)!;
      final s = d.addNode(DfdKind.store, 100, 100)!;
      d.setStoreTable(s.id, DocRef(docId: e2, elementId: 'inv', kind: DocRefKind.storeTable));
      w.openDocument(e2);
      await tester.pumpAndSettle();
      await rightClickTab(tester, e2);
      expect(find.text('Duplicate diagram'), findsOneWidget);
      await tester.tap(find.text('Delete diagram'));
      await tester.pumpAndSettle();
      expect(find.text('1 link(s) from other diagrams will stop working:'), findsOneWidget);
      expect(find.textContaining('→ table invoices'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('palette ค้นตารางของ ER อีกอัน: เปิดแท็บ ER นั้นและเลือกตาราง', (tester) async {
      await boot(tester);
      final e2 = w.addDocument(DocType.er, name: 'Billing')!;
      w.erController(e2.id)!.addBuiltTable(TableModel(id: 'inv', name: 'invoices'));
      w.openDocument(kErDiagramId);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'invoices');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(w.activeId, e2.id);
      expect(er(tester).docId, e2.id);
      expect(er(tester).selectedTableId, 'inv');
    });
  });

  test('ER ใหม่ไม่ระบุเนื้อหา = โปรเจกต์ว่างชื่อเดียวกับโปรเจกต์ ; ระบุเนื้อหาได้', () {
    final w = WorkspaceController(Workspace.single(base()));
    addTearDown(w.dispose);
    expect(w.erController(w.addDocument(DocType.er)!.id)!.project.name, 'shop');
    final p = Project(name: 'imported', tables: [TableModel(id: 'x', name: 'x')]);
    final doc = w.addDocument(DocType.er, er: p)!;
    expect(identical(doc.er, p), isTrue);
  });
}
