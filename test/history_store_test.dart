import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/history_store.dart';

import 'support/project_helpers.dart';

Workspace proj(int tables) => Workspace.single(Project(name: 'p', tables: [
      for (var i = 0; i < tables; i++)
        TableModel(id: 't$i', name: 'tb$i', columns: [ColumnModel(id: 'c$i', name: 'id', isPrimaryKey: true)]),
    ]));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nslhist'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('keyFor: ไม่สนตัวพิมพ์/ทิศของ slash และต่างไฟล์ต่างคีย์', () {
    expect(HistoryStore.keyFor(r'C:\A\b.nsld'), HistoryStore.keyFor('c:/a/B.NSLD'));
    expect(HistoryStore.keyFor(r'C:\A\b.nsld'), isNot(HistoryStore.keyFor(r'C:\A\c.nsld')));
    expect(HistoryStore.keyFor(null), 'unsaved');
  });

  test('add/list/load: ใหม่สุดก่อน และอ่านกลับได้เท่าเดิม', () async {
    final h = HistoryStore(dir);
    final k = HistoryStore.keyFor('x.nsld');
    final t0 = DateTime(2026, 1, 1, 10);
    await h.add(k, proj(1), now: t0);
    await h.add(k, proj(2), now: t0.add(const Duration(minutes: 5)), kind: SnapshotKind.manual, label: 'ก่อนรีแฟกเตอร์');
    final l = await h.list(k);
    expect(l.length, 2);
    expect(l.first.tables, 2);
    expect(l.first.kind, SnapshotKind.manual);
    expect(l.first.label, 'ก่อนรีแฟกเตอร์');
    expect(l.last.tables, 1);
    final back = await h.load(k, l.first.id);
    expect(erOf(back!).tables.length, 2);
    expect(erOf(back).tables.first.name, 'tb0');
    expect(l.first.documents, 1);
  });

  test('เก็บทั้ง workspace: ข้อมูลประกอบนับรวมทุกเอกสาร ER + จำนวนเอกสาร ; DFD อ่านกลับครบ ; digest เปลี่ยนเมื่อ DFD เปลี่ยน', () async {
    final h = HistoryStore(dir);
    final w = proj(2)
      ..documents.add(ProjectDocument.dfd(
        id: 'd1',
        name: 'Level 0',
        content: DfdDiagram(nodes: [DfdNode(id: 'p', kind: DfdKind.process, name: 'Pay')]),
      ));
    final d0 = HistoryStore.digestOf(w);
    final s = (await h.add('k', w))!;
    expect((s.tables, s.relations, s.documents), (2, 0, 2));
    final raw = jsonDecode(File('${dir.path}/k/${s.id}.json').readAsStringSync()) as Map<String, dynamic>;
    expect((raw['tables'], raw['relations'], raw['documents']), (2, 0, 2));
    expect((raw['project'] as Map)['version'], 3);
    final l = await h.list('k');
    expect(l.single.documents, 2);
    final back = (await h.load('k', s.id))!;
    expect(dfdIn(back, 'd1').nodes.single.name, 'Pay');
    expect(HistoryStore.digestOf(back), d0);
    dfdIn(back, 'd1').nodes.single.name = 'Refund';
    expect(HistoryStore.digestOf(back), isNot(d0));
    expect(await h.add('k', back), isNotNull);
  });

  test('สำเนาที่เป็นไฟล์เวอร์ชันใหม่กว่าที่รองรับ: load = null', () async {
    final h = HistoryStore(dir);
    final s = (await h.add('k', proj(1)))!;
    final f = File('${dir.path}/k/${s.id}.json');
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    (raw['project'] as Map)['version'] = 4;
    f.writeAsStringSync(jsonEncode(raw));
    expect(await h.load('k', s.id), isNull);
  });

  test('เนื้อหาเหมือนล่าสุด = ไม่เก็บซ้ำ (force เก็บได้)', () async {
    final h = HistoryStore(dir);
    expect(await h.add('k', proj(1)), isNotNull);
    expect(await h.add('k', proj(1)), isNull);
    expect(await h.add('k', proj(1), force: true), isNotNull);
    expect((await h.list('k')).length, 2);
  });

  test('เวลาเดียวกันเป๊ะ (ms) ไม่ทับกัน', () async {
    final h = HistoryStore(dir);
    final t = DateTime(2026, 1, 1);
    await h.add('k', proj(1), now: t);
    await h.add('k', proj(2), now: t);
    await h.add('k', proj(3), now: t);
    expect((await h.list('k')).length, 3);
  });

  test('เกินจำนวนสูงสุด ลบอันเก่าสุด แต่เก็บ manual ไว้ก่อน', () async {
    final h = HistoryStore(dir, maxPerProject: 3);
    final t = DateTime(2026, 1, 1);
    await h.add('k', proj(1), now: t, kind: SnapshotKind.manual);
    for (var i = 2; i <= 5; i++) {
      await h.add('k', proj(i), now: t.add(Duration(minutes: i)));
    }
    final l = await h.list('k');
    expect(l.length, 3);
    expect(l.any((s) => s.kind == SnapshotKind.manual), isTrue);
    expect(l.map((s) => s.tables), containsAll([5, 4]));
  });

  test('ไฟล์เสียถูกข้าม ไม่ทำให้รายการพัง', () async {
    final h = HistoryStore(dir);
    await h.add('k', proj(1));
    File('${dir.path}/k/bad.json').writeAsStringSync('{{{');
    expect((await h.list('k')).length, 1);
    expect(await h.load('k', 'bad'), isNull);
    expect(await h.load('k', 'missing'), isNull);
  });

  test('delete และ adopt (ย้ายประวัติของงานที่ยังไม่บันทึกไปไฟล์ใหม่)', () async {
    final h = HistoryStore(dir);
    final s = await h.add('unsaved', proj(1));
    await h.adopt('unsaved', 'pnew');
    expect(await h.list('unsaved'), isEmpty);
    expect((await h.list('pnew')).length, 1);
    await h.delete('pnew', s!.id);
    expect(await h.list('pnew'), isEmpty);
  });
}
