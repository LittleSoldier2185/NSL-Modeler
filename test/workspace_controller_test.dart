import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/clipboard/dfd_clipboard.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/models/diagram.dart';
import 'package:nsl_dev/core/storage/autosave.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/state/autosave_coordinator.dart';
import 'package:nsl_dev/state/dfd_controller.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';

import 'migration_fixtures.dart';
import 'support/project_helpers.dart';

/// controller ถือ [Workspace] จริง: สิ่งที่บันทึกลงไฟล์คือข้อมูลเดียวกับที่ UI แก้
void main() {
  group('undo/redo แล้วบันทึก', () {
    test('ER: undo แล้วบันทึก = ไฟล์มีข้อมูลที่ย้อนแล้ว ; redo แล้วบันทึก = กลับมา', () {
      final c = ProjectController(base());
      final before = jsonEncode(c.project.toContentJson());
      c.addTable(name: 'tmp');
      c.renameTable(c.project.tables.first.id, 'people');
      c.undo();
      c.undo();
      // เอกสาร ER ใน workspace เป็น object เดียวกับ c.project เสมอ (undo สร้าง object ใหม่แล้วใส่กลับ)
      expect(identical(c.workspace.documentById(c.erDocumentId)!.er, c.project), isTrue);
      var saved = erOf(roundTrip(c.workspace));
      expect(jsonEncode(saved.toContentJson()), before);
      expect(saved.tables.any((t) => t.name == 'tmp'), isFalse);

      c.redo();
      c.redo();
      saved = erOf(roundTrip(c.workspace));
      expect(saved.tables.any((t) => t.name == 'tmp'), isTrue);
      expect(saved.tables.first.name, 'people');
    });

    test('ER: ชื่อโปรเจกต์ในไฟล์ตามชื่อ ER ทั้งตอนแก้และตอน undo', () {
      final c = ProjectController(base());
      final old = c.project.name;
      c.setName('Renamed');
      expect(c.workspace.name, 'Renamed');
      expect((jsonDecode(ProjectFile.encode(c.workspace)) as Map)['name'], 'Renamed');
      c.undo();
      expect(c.workspace.name, old);
      expect(erOf(roundTrip(c.workspace)).name, old);
    });

    test('DFD: undo แล้วบันทึก = ไฟล์มีเนื้อหา DFD ที่ย้อนแล้ว ; undo ER ไม่แตะ DFD', () {
      final c = ProjectController(base());
      final tab = c.addDiagram(DocType.dfd, name: 'L0')!;
      final d = dfdCtl(c, tab.id);
      d.addNode(DfdKind.process, 100, 100);
      d.addNode(DfdKind.entity, 400, 100);
      expect(dfdIn(roundTrip(c.workspace), tab.id).nodes, hasLength(2));
      d.undo();
      expect(identical(c.documentById(tab.id)!.dfd, c.dfdOf(tab.id)), isTrue);
      expect(dfdIn(roundTrip(c.workspace), tab.id).nodes.map((n) => n.kind), [DfdKind.process]);
      d.redo();
      expect(dfdIn(roundTrip(c.workspace), tab.id).nodes, hasLength(2));

      c.selectDiagram(c.erDocumentId);
      c.addTable(name: 'x');
      c.undo();
      expect(dfdIn(roundTrip(c.workspace), tab.id).nodes, hasLength(2));
    });
  });

  group('ไฟล์ v3', () {
    test('เปิดไฟล์ v3 แล้วบันทึก: ได้ไบต์เดิม (รวมเอกสารชนิดที่ไม่รู้จัก โฟลเดอร์ และ meta)', () async {
      final dir = await Directory.systemTemp.createTemp('nsl_v3');
      addTearDown(() => dir.delete(recursive: true));
      final src = Workspace(
        name: 'Shop',
        meta: WorkspaceMeta(description: 'x', createdAt: '2026-01-01T00:00:00Z'),
        folders: [DocFolder(id: 'f1', name: 'Database')],
        documents: [
          ProjectDocument(id: 'x1', typeName: 'bpmn', name: 'Map', content: RawDocContent({'a': 1})),
          ProjectDocument.er(id: 'main', name: 'Schema', content: base()..name = 'Shop', folderId: 'f1'),
          ProjectDocument.dfd(id: 'd1', name: 'Flow', content: DfdDiagram()),
        ],
      );
      final path = '${dir.path}/shop.nsld';
      await ProjectFile.save(src, path);
      final text = File(path).readAsStringSync();
      final c = ProjectController()..loadWorkspace(await ProjectFile.load(path), path);
      expect(c.erDocumentId, 'main');
      expect(c.activeDiagramId, 'main');
      expect(c.project.tables, hasLength(2));
      // เอกสารชนิดที่ไม่รู้จักไม่เป็นแท็บ แต่ยังอยู่ในโปรเจกต์
      expect(c.tabDocuments.map((d) => d.id), ['main', 'd1']);
      expect(c.documents.map((d) => d.id), ['x1', 'main', 'd1']);
      c.selectDiagram('x1');
      expect(c.activeDiagramId, 'main');
      await ProjectFile.save(c.workspace, path);
      expect(File(path).readAsStringSync(), text);
    });

    test('ย้ายแท็บข้ามเอกสารที่ไม่มีแท็บ: ลำดับสัมพัทธ์ของเอกสารนั้นคงเดิม', () {
      final w = Workspace(documents: [
        ProjectDocument.er(id: 'er', name: 'ER', content: Project()),
        ProjectDocument(id: 'x', typeName: 'bpmn', name: 'X', content: RawDocContent(null)),
        ProjectDocument.dfd(id: 'a', name: 'A', content: DfdDiagram()),
      ]);
      final c = ProjectController()..loadWorkspace(w, null);
      c.moveDiagram('a', 0);
      expect(c.documents.map((d) => d.id), ['a', 'er', 'x']);
      c.moveDiagram('a', 1);
      expect(c.documents.map((d) => d.id), ['er', 'a', 'x']);
      c.moveDiagram('er', 1);
      expect(c.documents.map((d) => d.id), ['a', 'er', 'x']);
      expect(c.tabDocuments.map((d) => d.id), ['a', 'er']);
    });

    test('เปิดไฟล์ v4 ไม่ได้ (ProjectFormatException)', () {
      final j = encodeProjectMap(Workspace.single(base()))..['version'] = 4;
      expect(() => ProjectFile.decode(jsonEncode(j)), throwsA(isA<ProjectFormatException>()));
    });
  });

  group('DFD ที่เก็บข้อมูลผูกตาราง: tableDocId ติดไปทุกทางที่สร้างวัตถุ', () {
    late ProjectController c;
    late DfdController d;
    late String tab;
    late String store;

    setUp(() {
      c = ProjectController(base());
      tab = c.addDiagram(DocType.dfd, name: 'L0')!.id;
      d = dfdCtl(c, tab);
      final s = d.addNode(DfdKind.store, 100, 300)!;
      store = s.id;
      d.setStoreTable(store, tableRef(c, c.project.tables.first.id));
    });

    test('ผูกตาราง = tableDocId เป็นเอกสาร ER ; เลิกผูก = null', () {
      expect(c.dfdOf(tab).nodeById(store)!.tableDocId, c.erDocumentId);
      d.setStoreTable(store, null);
      expect(c.dfdOf(tab).nodeById(store)!.tableDocId, isNull);
    });

    test('ทำสำเนา (Ctrl+D)', () {
      d.selectNode(store);
      d.duplicateSelection();
      final copy = c.dfdOf(tab).nodes.last;
      expect(copy.id, isNot(store));
      expect((copy.tableId, copy.tableDocId), (c.project.tables.first.id, c.erDocumentId));
    });

    test('สร้างแผนภาพย่อย: ที่เก็บข้อมูลที่คัดลอกไปมี tableDocId', () {
      final p = d.addNode(DfdKind.process, 100, 100)!;
      d.addFlow(p.id, store, label: 'save');
      final child = d.createChildFor(p.id)!;
      final copy = c.dfdOf(child.id).nodes.firstWhere((n) => n.kind == DfdKind.store);
      expect((copy.tableId, copy.tableDocId), (c.project.tables.first.id, c.erDocumentId));
    });

    test('คลิปบอร์ด: คัดลอกมี tableDoc ; วางในโปรเจกต์นี้ได้ tableDocId ของ ER นี้ ; ตารางที่ไม่มีถูกตัด', () {
      d.selectNode(store);
      final text = d.copySelectionText()!;
      expect(((jsonDecode(text) as Map)['nodes'] as List).single['tableDoc'], c.erDocumentId);
      expect(decodeDfdClipboard(text)!.nodes.single.tableDocId, c.erDocumentId);
      d.pasteText(text);
      final pasted = c.dfdOf(tab).nodes.last;
      expect((pasted.tableId, pasted.tableDocId), (c.project.tables.first.id, c.erDocumentId));

      final other = ProjectController();
      final otab = other.addDiagram(DocType.dfd)!.id;
      final od = dfdCtl(other, otab);
      od.pasteText(text);
      final n = other.dfdOf(otab).nodes.single;
      expect((n.tableId, n.tableDocId), (null, null));
    });

    test('บันทึกแล้วเปิดใหม่: tableDoc อยู่ในไฟล์', () {
      final back = roundTrip(c.workspace);
      expect(dfdIn(back, tab).nodeById(store)!.tableDocId, c.erDocumentId);
    });
  });

  test('copyWorkspace แยกขาดจากต้นฉบับ', () {
    final c = ProjectController(base());
    final tab = c.addDiagram(DocType.dfd)!.id;
    final copy = copyWorkspace(c.workspace);
    c.addTable(name: 'later');
    c.dfdOf(tab).nodes.add(DfdNode(id: 'n', kind: DfdKind.entity));
    expect(erOf(copy).tables.any((t) => t.name == 'later'), isFalse);
    expect(dfdIn(copy, tab).nodes, isEmpty);
  });

  group('WorkspaceController: controller ต่อเอกสาร', () {
    late WorkspaceController w;
    late ProjectController er;
    late String a, b;
    late DfdController da, db;

    setUp(() {
      w = WorkspaceController(Workspace.single(base()));
      er = w.mainEr;
      a = w.addDocument(DocType.dfd, name: 'A')!.id;
      b = w.addDocument(DocType.dfd, name: 'B')!.id;
      da = w.dfdController(a)!;
      db = w.dfdController(b)!;
    });
    tearDown(() => w.dispose());

    test('dirty รวมทุกเอกสาร: แก้ DFD ใด ๆ = โปรเจกต์ยังไม่บันทึก ; บันทึกแล้วล้างทุกเอกสาร', () {
      w.markSaved('x.nsld');
      expect(w.dirty, isFalse);
      db.addNode(DfdKind.entity, 0, 0);
      expect((w.dirty, db.docDirty, da.docDirty, er.docDirty, w.structureDirty), (true, true, false, false, false));
      expect(er.dirty, isTrue); // ProjectController.dirty = ทั้งโปรเจกต์ (ของเดิม)
      w.markSaved('x.nsld');
      expect((w.dirty, db.docDirty), (false, false));
      expect(w.renameDocument(a, 'A2'), isTrue);
      expect((w.dirty, w.structureDirty, da.docDirty), (true, true, false));
      w.markSaved('x.nsld');
      er.addTable(name: 'later');
      expect((w.dirty, er.docDirty), (true, true));
    });

    test('ลบเอกสาร = ทิ้ง controller ของมัน และคืนลิงก์จากเอกสารอื่นที่ใช้ไม่ได้แล้ว', () {
      final p = da.addNode(DfdKind.process, 100, 100)!;
      expect(da.setProcessChild(p.id, b), isTrue);
      expect(w.backlinksOf(b), hasLength(1));
      final broken = w.deleteDocument(b)!;
      expect(broken.single.$1, a);
      expect(db.disposed, isTrue);
      expect(w.hasController(b), isFalse);
      expect(w.dfdController(b), isNull);
      expect(w.deleteDocument(er.docId), isNull); // ER หลักลบไม่ได้
      expect(er.disposed, isFalse);
    });

    test('เปิดไฟล์ใหม่ (v2 เก่า / loadProject): ใช้ ProjectController ตัวเดิม ; controller ของ DFD เดิมถูกทิ้ง', () async {
      final c = ProjectController(base());
      final wc = c.workspaceController;
      final old = wc.dfdController(wc.addDocument(DocType.dfd)!.id)!;
      wc.loadWorkspace(await ProjectFile.load('test/fixtures/v2_er_dfd.nsld'), null);
      expect(identical(wc.mainEr, c), isTrue);
      expect(identical(wc.currentEr, c), isTrue);
      expect(old.disposed, isTrue);
      expect(c.project.tables, isNotEmpty);
      expect(identical(wc.documentById(c.erDocumentId)!.er, c.project), isTrue);

      final p2 = Project(name: 'other');
      // ignore: deprecated_member_use_from_same_package
      c.loadProject(p2, null);
      expect(identical(wc.mainEr, c), isTrue);
      expect(identical(c.project, p2), isTrue);
      expect(c.canUndo, isFalse);
      expect(wc.dirty, isFalse);
    });

    test('undo แยกต่อเอกสาร: ย้อนเอกสารหนึ่งไม่แตะเอกสารอื่น ; undo ของ workspace = เอกสารที่ใช้งานอยู่', () {
      da.addNode(DfdKind.entity, 0, 0);
      db.addNode(DfdKind.process, 0, 0);
      db.addNode(DfdKind.process, 300, 0);
      er.addTable(name: 'x');
      expect((da.canUndo, db.canUndo, er.canUndo), (true, true, true));

      db.undo();
      expect((da.diagram.nodes.length, db.diagram.nodes.length), (1, 1));
      expect(er.project.tables.any((t) => t.name == 'x'), isTrue);

      er.undo();
      expect(er.project.tables.any((t) => t.name == 'x'), isFalse);
      expect((da.diagram.nodes.length, db.diagram.nodes.length), (1, 1));

      w.openDocument(a);
      w.undo();
      expect((da.diagram.nodes.length, db.diagram.nodes.length), (0, 1));
      expect(w.canUndo, isFalse);
      w.openDocument(b);
      expect(w.canUndo, isTrue);
      w.redo();
      expect(db.diagram.nodes.length, 2);
    });

    test('auto-save ได้ยินการแก้ของทุกเอกสาร', () async {
      final store = _CountingStore();
      final auto = AutosaveCoordinator(w, store, debounce: const Duration(milliseconds: 5));
      addTearDown(auto.dispose);
      w.markSaved('x.nsld');
      await auto.idle();

      da.addNode(DfdKind.entity, 0, 0);
      await auto.flush();
      expect(store.writes, 1);
      expect(dfdIn(store.last!, a).nodes, hasLength(1));

      db.addNode(DfdKind.process, 0, 0);
      await auto.flush();
      expect(store.writes, 2);
      expect(dfdIn(store.last!, b).nodes, hasLength(1));

      er.addTable(name: 'later');
      await auto.flush();
      expect(store.writes, 3);
      expect(erOf(store.last!).tables.any((t) => t.name == 'later'), isTrue);

      // ลากสด (ยังไม่จบ) ไม่นับว่าแก้ ; จบการลากแล้วนับ
      w.markSaved('x.nsld');
      await auto.idle();
      da.selectAll();
      da.beginMove();
      da.moveBy(40, 0);
      expect(w.dirty, isFalse);
      da.endMove();
      expect(w.dirty, isTrue);
    });

    test('สลับเอกสาร: การเลือกของแต่ละเอกสารคงอยู่ ; provider ได้ controller ของแท็บที่ใช้งาน', () {
      final na = da.addNode(DfdKind.entity, 0, 0)!;
      final nb = db.addNode(DfdKind.process, 0, 0)!;
      w.openDocument(a);
      da.selectNode(na.id);
      w.openDocument(b);
      expect(identical(w.currentDfd, db), isTrue);
      db.selectNode(nb.id);
      w.openDocument(er.docId);
      expect(w.currentDfd.active, isFalse); // แท็บ ER: ตัวแทนว่าง
      expect(w.currentDfd.addNode(DfdKind.entity, 0, 0), isNull);
      er.selectTable('tu');

      w.openDocument(a);
      expect(identical(w.currentDfd, da), isTrue);
      expect(da.selectedNodeIds, {na.id});
      w.openDocument(b);
      expect(db.selectedNodeIds, {nb.id});
      w.openDocument(kErDiagramId);
      expect(identical(w.currentEr, er), isTrue);
      expect(er.selectedTableId, 'tu');
    });
  });
}

/// ที่เก็บ auto-save ในหน่วยความจำ: นับจำนวนครั้งที่เขียน และเก็บสำเนาล่าสุด
class _CountingStore implements AutosaveStore {
  int writes = 0;
  Workspace? last;

  @override
  Future<void> write(Workspace w, {String? originalPath, DateTime? now}) async {
    writes++;
    last = w;
  }

  @override
  Future<AutosaveInfo?> readRecoverable() async => null;

  @override
  Future<void> clear() async {}
}