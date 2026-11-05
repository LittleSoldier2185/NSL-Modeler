import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/doc_ref.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/core/storage/project_file.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Map<String, dynamic> fixtureMap(String name) => jsonDecode(fixture(name)) as Map<String, dynamic>;

Workspace decodeText(String s) => decodeProjectMap(jsonDecode(s) as Map<String, dynamic>);

String encodeText(Workspace w) => const JsonEncoder.withIndent('  ').convert(encodeProjectMap(w));

Object? norm(Object? v) => jsonDecode(jsonEncode(v));

Map<String, dynamic> v3({List<Object?>? documents, List<Object?>? folders, Object? links}) => {
      'format': 'nsl-erd',
      'version': 3,
      'name': 'Shop',
      'meta': <String, dynamic>{'description': 'd', 'createdAt': '2026-01-01T00:00:00Z'},
      'folders': folders ?? [],
      'documents': documents ?? [],
      'links': links ?? [],
    };

void main() {
  group('ย้ายจาก v1/v2', () {
    test('v1: ER เอกสารเดียว id er ชื่อ ER ชื่อโปรเจกต์ = ชื่อเดิม', () {
      final w = decodeProjectMap(fixtureMap('v1_er_only.nslm'));
      expect(w.name, 'Shop');
      expect(w.documents.map((d) => (d.id, d.type, d.name)), [('er', DocType.er, 'ER')]);
      final er = w.documents.single.er!;
      expect(er.name, 'Shop');
      expect(er.dialect, Dialect.postgres);
      expect(norm(er.toContentJson()), jsonDecode(fixture('v1_er_only.er.json')));
      expect(w.folders, isEmpty);
      expect(w.links, isEmpty);
    });

    test('v2: เรียงตามแท็บเดิม DFD ใช้ id เดิม childId ยังชี้ถูก tableDoc = er', () {
      final w = decodeProjectMap(fixtureMap('v2_er_dfd.nsld'));
      expect(w.name, 'ร้านค้า');
      expect(w.documents.map((d) => (d.id, d.type, d.name)), [
        ('d0', DocType.dfd, 'Level 0'),
        ('er', DocType.er, 'Schema'),
        ('d1', DocType.dfd, 'L1 – Order'),
        ('d2', DocType.dfd, 'Empty'),
      ]);
      final d0 = w.documentById('d0')!.dfd!;
      expect(d0.nodeById('p1')!.childId, 'd1');
      expect(w.documentById(d0.nodeById('p1')!.childId!)!.type, DocType.dfd);
      expect(d0.nodeById('s1')!.tableId, 't2');
      expect(d0.nodeById('s1')!.tableDocId, 'er');
      expect(d0.boundaries.single.id, 'b1');
      expect(w.documentById('d2')!.dfd!.nodes, isEmpty);
      expect(norm(w.documentById('er')!.er!.toContentJson()), jsonDecode(fixture('v2_er_dfd.er.json')));
    });

    test('v2 เสีย: แท็บซ่อมแล้ว เนื้อหาที่ไม่มีแท็บถูกทิ้ง', () {
      final w = decodeProjectMap(fixtureMap('v2_broken.nsld'));
      expect(w.documents.map((d) => (d.id, d.name)), [('d1', 'Flow'), ('er', 'ER'), ('d2', 'flow 2'), ('d3', 'DFD')]);
      expect(w.documentById('orphan'), isNull);
      expect(w.documentById('d1')!.dfd!.nodeById('n2')!.tableDocId, 'er');
      expect(norm(w.documentById('er')!.er!.toContentJson()), jsonDecode(fixture('v2_broken.er.json')));
    });

    test('ย้ายแล้วเขียนเป็น v3 อ่านกลับได้เท่าเดิม', () {
      for (final f in ['v1_er_only.nslm', 'v2_er_dfd.nsld', 'v2_broken.nsld']) {
        final a = encodeText(decodeProjectMap(fixtureMap(f)));
        expect(jsonDecode(a)['version'], 3);
        expect(encodeText(decodeText(a)), a, reason: f);
      }
    });

    test('Workspace.fromLegacy ไม่แก้โปรเจกต์เดิมและใช้ object เดิม', () {
      final p = ProjectFile.decode(fixture('v2_er_dfd.nsld'));
      final before = jsonEncode(p.toJson());
      final w = Workspace.fromLegacy(p);
      expect(identical(w.documentById('er')!.er, p), isTrue);
      expect(identical(w.documentById('d0')!.dfd, p.dfd['d0']), isTrue);
      expect(p.dfd['d0']!.nodeById('s1')!.tableDocId, isNull);
      expect(jsonEncode(p.toJson()), before);
    });
  });

  group('v3', () {
    test('round-trip ได้ไบต์เดิม (golden)', () {
      final a = encodeText(decodeProjectMap(fixtureMap('v2_er_dfd.nsld')));
      final b = encodeText(decodeText(a));
      expect(b, a);
      final j = jsonDecode(a) as Map<String, dynamic>;
      expect(j.keys.toList(), ['format', 'version', 'name', 'meta', 'folders', 'documents', 'links']);
      expect(j['format'], 'nsl-erd');
      final docs = j['documents'] as List;
      expect((docs[1] as Map).keys.toList(), ['id', 'type', 'name', 'typeVersion', 'content']);
      expect((docs[1] as Map)['content'], jsonDecode(fixture('v2_er_dfd.er.json')));
      final s1 = ((docs[0] as Map)['content']['nodes'] as List)[2] as Map;
      expect(s1['table'], 't2');
      expect(s1['tableDoc'], 'er');
    });

    test('meta โฟลเดอร์ ลิงก์ และคีย์ที่ไม่รู้จักเขียนกลับเหมือนเดิม', () {
      final src = v3(
        folders: [
          {'id': 'f1', 'name': 'Database', 'parent': null},
          {'id': 'f2', 'name': 'Sub', 'parent': 'f1'},
        ],
        documents: [
          {
            'id': 'er',
            'type': 'er',
            'name': 'ER',
            'folder': 'f2',
            'typeVersion': 1,
            'color': 'red',
            'content': Project(name: 'shop').toContentJson(),
          },
        ],
        links: [
          {'from': 'a', 'to': 'b'},
        ],
      );
      (src['meta'] as Map)['future'] = [1, 2];
      final w = decodeProjectMap(norm(src) as Map<String, dynamic>);
      expect(w.meta.description, 'd');
      expect(w.meta.createdAt, '2026-01-01T00:00:00Z');
      expect(w.documents.single.folderId, 'f2');
      expect(w.folderById('f2')!.parentId, 'f1');
      expect(norm(encodeProjectMap(w)), norm(src));
    });

    test('เอกสารชนิดที่ไม่รู้จักเก็บไว้และเขียนกลับไม่เปลี่ยน', () {
      final weird = {
        'id': 'x1',
        'type': 'bpmn',
        'name': 'Process map',
        'typeVersion': 7,
        'content': {
          'lanes': [
            {'id': 'l', 'w': 1.5},
          ],
          'deep': {'a': null},
        },
      };
      final scalar = {'id': 'x2', 'type': 'text', 'name': 'Readme', 'typeVersion': 1, 'content': 'hello'};
      final src = v3(documents: [weird, scalar]);
      final w = decodeProjectMap(norm(src) as Map<String, dynamic>);
      expect(w.documents.first.type, isNull);
      expect(w.documents.first.typeName, 'bpmn');
      expect(w.documents.first.content, isA<RawDocContent>());
      expect(norm(encodeProjectMap(w)), norm(src));
    });

    test('ซ่อม: id ซ้ำทิ้งตัวหลัง ชื่อว่าง/ซ้ำต่อเลข โฟลเดอร์เสีย/วน -> ราก', () {
      final src = v3(
        folders: [
          {'id': 'a', 'name': 'A', 'parent': 'b'},
          {'id': 'b', 'name': 'B', 'parent': 'a'},
          {'id': 'c', 'name': 'C', 'parent': 'missing'},
          {'id': 'c', 'name': 'dup'},
          {'id': '', 'name': 'bad'},
          'junk',
        ],
        documents: [
          {'id': 'd1', 'type': 'dfd', 'name': 'Flow', 'content': {}},
          {'id': 'd1', 'type': 'dfd', 'name': 'Second', 'content': {}},
          {'id': 'd2', 'type': 'dfd', 'name': 'FLOW', 'folder': 'nope', 'content': {}},
          {'id': 'd3', 'type': 'dfd', 'name': '  ', 'content': null},
          {'id': 'e1', 'type': 'er', 'name': '', 'content': 5},
          {'id': '', 'type': 'dfd', 'name': 'x'},
          {'id': 'n', 'name': 'no type'},
          42,
        ],
      );
      final w = decodeProjectMap(norm(src) as Map<String, dynamic>);
      expect(w.documents.map((d) => (d.id, d.name)), [('d1', 'Flow'), ('d2', 'FLOW 2'), ('d3', 'DFD'), ('e1', 'ER')]);
      expect(w.documentById('d2')!.folderId, isNull);
      expect(w.documentById('e1')!.er, isNotNull);
      expect(w.folders.map((f) => f.id), ['a', 'b', 'c']);
      expect(w.folderById('c')!.parentId, isNull);
      // วง a <-> b ต้องถูกตัดอย่างน้อยหนึ่งจุด
      final a = w.folderById('a')!, b = w.folderById('b')!;
      expect(a.parentId == null || b.parentId == null, isTrue);
    });

    test('tableDoc: ไม่ระบุและมี ER เดียว -> ER นั้น ; มีหลาย ER -> ไม่เดา', () {
      Map<String, dynamic> dfd() => {
            'id': 'd',
            'type': 'dfd',
            'name': 'D',
            'content': {
              'nodes': [
                {'id': 's', 'kind': 'store', 'name': 'S', 'table': 't1'},
                {'id': 's2', 'kind': 'store', 'name': 'S2', 'table': 't1', 'tableDoc': 'other'},
              ],
              'flows': [],
            },
          };
      Map<String, dynamic> er(String id) => {'id': id, 'type': 'er', 'name': id, 'content': {}};
      final one = decodeProjectMap(norm(v3(documents: [er('main'), dfd()])) as Map<String, dynamic>);
      expect(one.documentById('d')!.dfd!.nodeById('s')!.tableDocId, 'main');
      expect(one.documentById('d')!.dfd!.nodeById('s2')!.tableDocId, 'other');
      final two = decodeProjectMap(norm(v3(documents: [er('a'), er('b'), dfd()])) as Map<String, dynamic>);
      expect(two.documentById('d')!.dfd!.nodeById('s')!.tableDocId, isNull);
    });

    test('ไม่มีเอกสารเลยก็ได้', () {
      final w = decodeProjectMap(v3());
      expect(w.documents, isEmpty);
      expect(norm(encodeProjectMap(w)), norm(v3()));
    });
  });

  test('ปฏิเสธ v4 ขึ้นไป / ไม่ใช่ไฟล์โปรเจกต์ / โครงสร้างเสีย', () {
    expect(() => decodeProjectMap(v3()..['version'] = 4), throwsA(isA<ProjectFormatException>()));
    expect(() => decodeProjectMap(v3()..['version'] = '3'), throwsA(isA<ProjectFormatException>()));
    expect(() => decodeProjectMap(v3()..['format'] = 'other'), throwsA(isA<ProjectFormatException>()));
    expect(
      () => decodeProjectMap({
        'format': 'nsl-erd',
        'version': 1,
        'tables': [
          {'id': 1},
        ],
      }),
      throwsA(isA<ProjectFormatException>()),
    );
  });

  test('Project.toContentJson / fromContentJson ไม่มีแท็บหรือ DFD และอ่านกลับได้เท่าเดิม', () {
    final p = ProjectFile.decode(fixture('v2_er_dfd.nsld'));
    final c = p.toContentJson();
    expect(c.containsKey('diagrams'), isFalse);
    expect(c.containsKey('dfd'), isFalse);
    expect(c.containsKey('format'), isFalse);
    final q = Project.fromContentJson(norm(c) as Map<String, dynamic>);
    expect(jsonEncode(q.toContentJson()), jsonEncode(c));
    expect(q.diagrams, hasLength(1));
    // คีย์ diagrams/dfd ที่หลงมาในเนื้อหา ER ไม่ทำให้เกิดแท็บ DFD
    final r = Project.fromContentJson({
      ...norm(c) as Map<String, dynamic>,
      'diagrams': [
        {'id': 'z', 'name': 'Z', 'kind': 'dfd'},
      ],
    });
    expect(r.diagrams, hasLength(1));
  });

  test('DfdNode.tableDocId: อ่าน/เขียนเป็น tableDoc เฉพาะ store ที่ผูกตาราง', () {
    final n = DfdNode.tryFromJson({'id': 's', 'kind': 'store', 'table': 't', 'tableDoc': 'er'})!;
    expect(n.tableDocId, 'er');
    expect(n.toJson()['tableDoc'], 'er');
    expect(DfdNode.tryFromJson({'id': 's', 'kind': 'store', 'tableDoc': 'er'})!.tableDocId, isNull);
    expect(DfdNode.tryFromJson({'id': 'p', 'kind': 'process', 'table': 't', 'tableDoc': 'er'})!.tableDocId, isNull);
    expect(DfdNode(id: 'e', kind: DfdKind.store, tableId: 't').toJson().containsKey('tableDoc'), isFalse);
  });

  test('WorkspaceIndex นับการอ้างอิงจากเอกสารอื่น', () {
    final w = decodeProjectMap(fixtureMap('v2_er_dfd.nsld'));
    final idx = WorkspaceIndex(w);
    expect(idx.backlinkCount('d1'), 1);
    expect(idx.backlinks('d1').single.$3, const DocRef(docId: 'd1', kind: DocRefKind.dfdChild));
    expect(idx.backlinkCount('er'), 1);
    expect(idx.backlinks('er').single.$3.elementId, 't2');
    expect(idx.backlinkCount('d2'), 0);
  });

  test('Workspace.single และชื่อเอกสารไม่ซ้ำ', () {
    final w = Workspace.single(Project(name: 'x'));
    expect(w.name, 'x');
    expect(w.documents.single.id, 'er');
    expect(w.uniqueDocumentName('er'), 'er 2');
    expect(w.uniqueDocumentName('ER', except: 'er'), 'ER');
  });
}
