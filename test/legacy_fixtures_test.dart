import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/autosave.dart';
import 'package:nsl_dev/core/storage/history_store.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/state/autosave_coordinator.dart';
import 'package:nsl_dev/state/project_controller.dart';

import 'support/project_helpers.dart';

/// ไฟล์ตัวอย่างรูปแบบเก่า (v1/v2) ที่สร้างจากโค้ดก่อนเปลี่ยนเป็น workspace — ต้องเปิดได้ตลอดไป
/// และเนื้อหา ER ต้องตรงกับไฟล์ `*.er.json` ที่ตรึงไว้
const fixtures = 'test/fixtures';

String fixture(String name) => File('$fixtures/$name').readAsStringSync();

Map<String, dynamic> fixtureMap(String name) => jsonDecode(fixture(name)) as Map<String, dynamic>;

/// เทียบผ่าน JSON (ตัวเลข 2400 กับ 2400.0 ถือว่าเท่ากันหลัง decode)
Object? norm(Object? v) => jsonDecode(jsonEncode(v));

void expectErGolden(Project p, String golden) {
  expect(norm(p.toContentJson()), jsonDecode(fixture(golden)));
  expect(jsonEncode(p.toJson()), jsonEncode(p.toContentJson()));
}

/// เนื้อหา DFD ที่คาดหวังหลังย้ายเป็น v3: เหมือน `dfd[id]` ของไฟล์เก่าทุกประการ
/// ยกเว้นที่เก็บข้อมูลที่ผูกตารางได้ `tableDoc` = เอกสาร ER (`er`)
Map<String, dynamic> expectedDfd(Map<String, dynamic> legacy, String id) {
  final d = norm((legacy['dfd'] as Map)[id]) as Map<String, dynamic>;
  for (final n in d['nodes'] as List) {
    if (n is Map && n['kind'] == 'store' && n['table'] != null) n['tableDoc'] = 'er';
  }
  return d;
}

/// โหลด -> บันทึก -> โหลด แล้วต้องได้ไฟล์เดิมทุกไบต์ (คืนผลการโหลดครั้งที่สอง)
Workspace loadSaveLoad(String text) {
  final a = ProjectFile.decode(text);
  final saved = ProjectFile.encode(a);
  expect((jsonDecode(saved) as Map)['version'], 3);
  final b = ProjectFile.decode(saved);
  expect(ProjectFile.encode(b), saved);
  return b;
}

void main() {
  test('v1 (.nslm) ER ล้วน: เปิดได้ เนื้อหา ER ตรงกับที่ตรึงไว้ ; โหลด-บันทึก-โหลด ได้เท่าเดิม', () {
    final w = ProjectFile.decode(fixture('v1_er_only.nslm'));
    final p = erOf(w);
    expect(w.name, 'Shop');
    expect(p.name, 'Shop');
    expect(p.dialect, Dialect.postgres);
    expect(p.boardWidth, 3000);
    expect(p.lineColor, 0xFF336699);
    expect(p.tables.map((t) => t.name), ['users', 'orders']);
    expect(p.tables.first.seedRows, hasLength(2));
    expect(p.groups.single.name, 'Core');
    expect(w.documents.map((d) => (d.id, d.name, d.type)), [('er', 'ER', DocType.er)]);
    expectErGolden(p, 'v1_er_only.er.json');

    final back = loadSaveLoad(fixture('v1_er_only.nslm'));
    expect(back.documents.map((d) => (d.id, d.name, d.type)), [('er', 'ER', DocType.er)]);
    expectErGolden(erOf(back), 'v1_er_only.er.json');
  });

  test('v2 (.nsld) ER + DFD: แท็บ ชื่อแท็บ ER ที่ไม่ใช่ค่าเริ่มต้น childId tableId boundary', () {
    final w = ProjectFile.decode(fixture('v2_er_dfd.nsld'));
    expect(w.documents.map((d) => (d.id, d.name, d.type)), [
      ('d0', 'Level 0', DocType.dfd),
      ('er', 'Schema', DocType.er),
      ('d1', 'L1 – Order', DocType.dfd),
      ('d2', 'Empty', DocType.dfd),
    ]);
    final d0 = dfdIn(w, 'd0');
    expect(d0.nodes.map((n) => n.id), ['e1', 'p1', 's1']);
    expect(d0.nodeById('p1')!.childId, 'd1');
    expect(d0.nodeById('s1')!.tableId, 't2');
    expect(d0.nodeById('s1')!.tableDocId, 'er');
    expect(d0.flows.map((f) => f.id), ['f1', 'f2']);
    expect(d0.flows[1].bidirectional, isTrue);
    expect(d0.boundaries.single.name, 'System');
    expect(dfdIn(w, 'd1').nodes, hasLength(2));
    expect(dfdIn(w, 'd2').nodes, isEmpty);
    expectErGolden(erOf(w), 'v2_er_dfd.er.json');
  });

  test('golden v2: โหลด -> บันทึก (v3) -> โหลด ได้เนื้อหา ER และ DFD ตรงตามที่คาด (ที่เก็บข้อมูลได้ tableDoc)', () {
    final legacy = fixtureMap('v2_er_dfd.nsld');
    final back = loadSaveLoad(fixture('v2_er_dfd.nsld'));
    expect(back.name, 'ร้านค้า');
    expect(back.documents.map((d) => d.id), ['d0', 'er', 'd1', 'd2']);
    expectErGolden(erOf(back), 'v2_er_dfd.er.json');
    for (final id in ['d0', 'd1', 'd2']) {
      expect(norm(dfdIn(back, id).toJson()), expectedDfd(legacy, id), reason: id);
    }
    // ไฟล์ที่บันทึกมี tableDoc จริง
    final saved = jsonDecode(ProjectFile.encode(ProjectFile.decode(fixture('v2_er_dfd.nsld')))) as Map<String, dynamic>;
    final s1 = ((saved['documents'] as List).first['content']['nodes'] as List).firstWhere((n) => n['id'] == 's1') as Map;
    expect(s1['tableDoc'], 'er');
  });

  test('v2 ที่ข้อมูลเสีย: ซ่อมได้โดยไม่ throw ; โหลด-บันทึก-โหลด ได้เท่าเดิม', () {
    for (final w in [ProjectFile.decode(fixture('v2_broken.nsld')), loadSaveLoad(fixture('v2_broken.nsld'))]) {
      expect(w.documents.map((d) => (d.id, d.name, d.type)), [
        ('d1', 'Flow', DocType.dfd),
        ('er', 'ER', DocType.er),
        ('d2', 'flow 2', DocType.dfd),
        ('d3', 'DFD', DocType.dfd),
      ]);
      // เนื้อหา DFD ของแท็บที่ไม่มีอยู่ถูกทิ้ง แท็บที่ไม่มีเนื้อหาได้แผนภาพว่าง
      expect(w.documentById('orphan'), isNull);
      final d1 = dfdIn(w, 'd1');
      expect(d1.nodes.map((n) => (n.id, n.kind)), [('n1', DfdKind.process), ('n2', DfdKind.store)]);
      expect(d1.nodeById('n1')!.tableId, isNull, reason: 'process ผูกตารางไม่ได้');
      expect(d1.nodeById('n1')!.childId, 'nowhere');
      expect(d1.nodeById('n2')!.childId, isNull, reason: 'store มีแผนภาพย่อยไม่ได้');
      expect(d1.nodeById('n2')!.tableId, 'tZ');
      expect(d1.nodeById('n2')!.tableDocId, 'er');
      expect(d1.flows.map((f) => f.id), ['f1']);
      expect(d1.boundaries, hasLength(1));
      expect(dfdIn(w, 'd2').nodes, isEmpty);
      expect(dfdIn(w, 'd3').nodes, isEmpty);
      expectErGolden(erOf(w), 'v2_broken.er.json');
    }
  });

  test('autosave (v2 ข้างใน) กู้คืนได้', () async {
    final dir = await Directory.systemTemp.createTemp('nsl_fx_auto');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/autosave.json').writeAsStringSync(fixture('autosave_v2.json'));
    final info = await FileAutosaveStore(dir).readRecoverable();
    expect(info, isNotNull);
    expect(info!.originalPath, isNull);
    expect(info.savedAt, DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal());
    expect(info.workspace.documents.map((d) => d.id), ['d0', 'er', 'd1', 'd2']);
    expect(dfdIn(info.workspace, 'd0').nodeById('p1')!.childId, 'd1');
    expectErGolden(erOf(info.workspace), 'v2_er_dfd.er.json');
  });

  test('กู้คืน autosave v2 เข้า controller แล้วบันทึก: ได้ไฟล์ v3 ที่มีทุกแท็บ และ auto-save รอบใหม่เป็น v3', () async {
    final dir = await Directory.systemTemp.createTemp('nsl_fx_restore');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/autosave.json').writeAsStringSync(fixture('autosave_v2.json'));
    final store = FileAutosaveStore(dir);
    final info = (await store.readRecoverable())!;
    final c = ProjectController()..restoreWorkspace(info.workspace, info.originalPath);
    expect(c.dirty, isTrue);
    expect(c.tabDocuments.map((d) => d.name), ['Level 0', 'Schema', 'L1 – Order', 'Empty']);
    expect(c.activeDiagramId, 'er');

    final back = roundTrip(c.workspace);
    expect(back.documents.map((d) => d.id), ['d0', 'er', 'd1', 'd2']);
    expect(dfdIn(back, 'd0').nodeById('s1')!.tableDocId, 'er');
    expectErGolden(erOf(back), 'v2_er_dfd.er.json');

    // แก้ต่อแล้ว auto-save ใหม่: เขียนเป็น v3 และอ่านกลับได้ทั้ง ER และ DFD
    final a = AutosaveCoordinator(c, store, debounce: const Duration(milliseconds: 5));
    addTearDown(a.dispose);
    c.addTable(name: 'later');
    await a.flush();
    final raw = jsonDecode(store.file.readAsStringSync()) as Map<String, dynamic>;
    expect((raw['project'] as Map)['version'], 3);
    final again = (await store.readRecoverable())!;
    expect(erOf(again.workspace).tables.any((t) => t.name == 'later'), isTrue);
    expect(dfdIn(again.workspace, 'd0').nodes.map((n) => n.id), ['e1', 'p1', 's1']);
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
    expect(list.single.documents, isNull); // สำเนารุ่นเก่าไม่ได้จดไว้
    final w = await store.load(key, list.single.id);
    expect(w, isNotNull);
    expect(w!.documents.single.id, 'er');
    expectErGolden(erOf(w), 'v1_er_only.er.json');
    // ลายนิ้วมือคิดจากรูปแบบ v3 แล้ว จึงไม่ตรงกับของรุ่นเก่า (สำเนาถัดไปถูกเก็บใหม่หนึ่งครั้ง)
    expect(HistoryStore.digestOf(w), isNot(list.single.digest));
    expect(HistoryStore.digestOf(w), HistoryStore.digestOf(decodeProjectMap(encodeProjectMap(w))));
  });
}
