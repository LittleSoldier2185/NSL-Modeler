import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/clipboard/dfd_clipboard.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/state/dfd_controller.dart';
import 'package:nsl_dev/state/project_controller.dart';

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
      final d = DfdController(c);
      addTearDown(d.dispose);
      final tab = c.addDiagram(DocType.dfd, name: 'L0')!;
      d.addNode(DfdKind.process, 100, 100);
      d.addNode(DfdKind.entity, 400, 100);
      expect(dfdIn(roundTrip(c.workspace), tab.id).nodes, hasLength(2));
      c.undo();
      expect(identical(c.documentById(tab.id)!.dfd, c.dfdOf(tab.id)), isTrue);
      expect(dfdIn(roundTrip(c.workspace), tab.id).nodes.map((n) => n.kind), [DfdKind.process]);
      c.redo();
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
      d = DfdController(c);
      tab = c.addDiagram(DocType.dfd, name: 'L0')!.id;
      final s = d.addNode(DfdKind.store, 100, 300)!;
      store = s.id;
      d.setStoreTable(store, c.project.tables.first.id);
    });
    tearDown(() => d.dispose());

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
      final od = DfdController(other);
      addTearDown(od.dispose);
      final otab = other.addDiagram(DocType.dfd)!.id;
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
}
