import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/diagram.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/storage/autosave.dart';
import 'package:nsl_dev/core/storage/history_store.dart';
import 'package:nsl_dev/core/storage/project_file.dart';

/// ไฟล์ตัวอย่างรูปแบบเก่า (v1/v2) ที่สร้างจากโค้ดก่อนเปลี่ยนเป็น workspace — ต้องเปิดได้ตลอดไป
/// และเนื้อหา ER ต้องตรงกับไฟล์ `*.er.json` ที่ตรึงไว้
const fixtures = 'test/fixtures';

String fixture(String name) => File('$fixtures/$name').readAsStringSync();

/// ส่วนที่เป็นเนื้อหา ER ของโปรเจกต์ (คีย์เดียวกับใน toJson ไม่รวมแท็บ/DFD/หัวไฟล์)
Map<String, dynamic> erContentOf(Project p) {
  final j = p.toJson();
  const keys = ['name', 'dialect', 'board', 'lineColor', 'tables', 'relations', 'notes', 'groups'];
  return {for (final k in keys) if (j.containsKey(k)) k: j[k]};
}

/// เทียบผ่าน JSON (ตัวเลข 2400 กับ 2400.0 ถือว่าเท่ากันหลัง decode)
Object? norm(Object? v) => jsonDecode(jsonEncode(v));

void expectErGolden(Project p, String golden) {
  expect(norm(erContentOf(p)), jsonDecode(fixture(golden)));
  // เนื้อหาเอกสาร ER ของไฟล์ v3 ต้องเหมือนส่วน ER ของไฟล์เก่าทุกคีย์ (เรียงคีย์เดียวกัน)
  expect(jsonEncode(p.toContentJson()), jsonEncode(erContentOf(p)));
}

void main() {
  test('v1 (.nslm) ER ล้วน: เปิดได้ เนื้อหา ER ตรงกับที่ตรึงไว้', () {
    final p = ProjectFile.decode(fixture('v1_er_only.nslm'));
    expect(p.name, 'Shop');
    expect(p.dialect, Dialect.postgres);
    expect(p.boardWidth, 3000);
    expect(p.lineColor, 0xFF336699);
    expect(p.tables.map((t) => t.name), ['users', 'orders']);
    expect(p.tables.first.seedRows, hasLength(2));
    expect(p.groups.single.name, 'Core');
    expect(p.diagrams.map((d) => (d.id, d.name, d.kind)), [('er', 'ER', DiagramKind.er)]);
    expect(p.dfd, isEmpty);
    expectErGolden(p, 'v1_er_only.er.json');
  });

  test('v2 (.nsld) ER + DFD: แท็บ ชื่อแท็บ ER ที่ไม่ใช่ค่าเริ่มต้น childId tableId boundary', () {
    final p = ProjectFile.decode(fixture('v2_er_dfd.nsld'));
    expect(p.diagrams.map((d) => (d.id, d.name, d.kind)), [
      ('d0', 'Level 0', DiagramKind.dfd),
      ('er', 'Schema', DiagramKind.er),
      ('d1', 'L1 – Order', DiagramKind.dfd),
      ('d2', 'Empty', DiagramKind.dfd),
    ]);
    final d0 = p.dfd['d0']!;
    expect(d0.nodes.map((n) => n.id), ['e1', 'p1', 's1']);
    expect(d0.nodeById('p1')!.childId, 'd1');
    expect(d0.nodeById('s1')!.tableId, 't2');
    expect(d0.flows.map((f) => f.id), ['f1', 'f2']);
    expect(d0.flows[1].bidirectional, isTrue);
    expect(d0.boundaries.single.name, 'System');
    expect(p.dfd['d1']!.nodes, hasLength(2));
    expect(p.dfd['d2']!.nodes, isEmpty);
    expectErGolden(p, 'v2_er_dfd.er.json');
  });

  test('v2 ที่ข้อมูลเสีย: ซ่อมได้โดยไม่ throw', () {
    final p = ProjectFile.decode(fixture('v2_broken.nsld'));
    expect(p.diagrams.map((d) => (d.id, d.name, d.kind)), [
      ('d1', 'Flow', DiagramKind.dfd),
      ('er', 'ER', DiagramKind.er),
      ('d2', 'flow 2', DiagramKind.dfd),
      ('d3', 'DFD', DiagramKind.dfd),
    ]);
    // เนื้อหา DFD ของแท็บที่ไม่มีอยู่ถูกทิ้ง แท็บที่ไม่มีเนื้อหาได้แผนภาพว่าง
    expect(p.dfd.keys.toSet(), {'d1', 'd2', 'd3'});
    final d1 = p.dfd['d1']!;
    expect(d1.nodes.map((n) => (n.id, n.kind)), [('n1', DfdKind.process), ('n2', DfdKind.store)]);
    expect(d1.nodeById('n1')!.tableId, isNull, reason: 'process ผูกตารางไม่ได้');
    expect(d1.nodeById('n1')!.childId, 'nowhere');
    expect(d1.nodeById('n2')!.childId, isNull, reason: 'store มีแผนภาพย่อยไม่ได้');
    expect(d1.nodeById('n2')!.tableId, 'tZ');
    expect(d1.flows.map((f) => f.id), ['f1']);
    expect(d1.boundaries, hasLength(1));
    expect(p.dfd['d2']!.nodes, isEmpty);
    expect(p.dfd['d3']!.nodes, isEmpty);
    expectErGolden(p, 'v2_broken.er.json');
  });

  test('autosave (v2 ข้างใน) กู้คืนได้', () async {
    final dir = await Directory.systemTemp.createTemp('nsl_fx_auto');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/autosave.json').writeAsStringSync(fixture('autosave_v2.json'));
    final info = await FileAutosaveStore(dir).readRecoverable();
    expect(info, isNotNull);
    expect(info!.originalPath, isNull);
    expect(info.savedAt, DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal());
    expect(info.project.diagrams.map((d) => d.id), ['d0', 'er', 'd1', 'd2']);
    expect(info.project.dfd['d0']!.nodeById('p1')!.childId, 'd1');
    expectErGolden(info.project, 'v2_er_dfd.er.json');
  });

  test('สำเนาประวัติ (v1 ข้างใน) อ่านกลับได้', () async {
    final dir = await Directory.systemTemp.createTemp('nsl_fx_hist');
    addTearDown(() => dir.delete(recursive: true));
    const key = 'pfixture';
    Directory('${dir.path}/$key').createSync();
    File('${dir.path}/$key/20260102-030405-000.json').writeAsStringSync(fixture('snapshot_v1.json'));
    final store = HistoryStore(dir);
    final list = await store.list(key);
    expect(list.single.label, 'fixture');
    expect(list.single.tables, 2);
    final p = await store.load(key, list.single.id);
    expect(p, isNotNull);
    expect(list.single.digest, HistoryStore.digestOf(p!));
    expectErGolden(p, 'v1_er_only.er.json');
  });
}
