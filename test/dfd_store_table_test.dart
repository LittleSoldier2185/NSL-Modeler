import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/diagram.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/validate/dfd_validator.dart';
import 'package:nsl_dev/state/dfd_controller.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'support/project_helpers.dart';

import 'migration_fixtures.dart';

void main() {
  late ProjectController pc;
  late DfdController d;
  late String tab;
  late DfdNode store;

  setUp(() {
    pc = ProjectController(base());
    d = DfdController(pc);
    tab = pc.addDiagram(DocType.dfd)!.id;
    store = d.addNode(DfdKind.store, 100, 100)!;
  });

  DfdNode node() => pc.dfdOf(tab).nodeById(store.id)!;

  test('ผูกกับตาราง: เก็บ tableId และตั้งชื่อให้เมื่อยังว่าง, undo ขั้นเดียว', () {
    d.renameNode(store.id, '');
    d.setStoreTable(store.id, 'tu');
    expect(node().tableId, 'tu');
    expect(node().name, 'users');
    pc.undo();
    expect(node().tableId, isNull);
    expect(node().name, '');
  });

  test('มีชื่ออยู่แล้ว = ไม่ทับชื่อ ; เลิกผูกได้ ; ตารางที่ไม่มีอยู่ = ไม่ผูก', () {
    d.renameNode(store.id, 'คลังลูกค้า');
    d.setStoreTable(store.id, 'to');
    expect((node().tableId, node().name), ('to', 'คลังลูกค้า'));
    d.setStoreTable(store.id, null);
    expect(node().tableId, isNull);
    d.setStoreTable(store.id, 'nope');
    expect(node().tableId, isNull);
  });

  test('entity / process ผูกตารางไม่ได้', () {
    final p = d.addNode(DfdKind.process, 300, 100)!;
    d.setStoreTable(p.id, 'tu');
    expect(pc.dfdOf(tab).nodeById(p.id)!.tableId, isNull);
  });

  test('บันทึก-โหลดไฟล์แล้ว tableId ยังอยู่ ; ทำสำเนาวัตถุแล้วผูกตารางเดิมต่อ', () {
    d.setStoreTable(store.id, 'tu');
    final back = roundTrip(pc.workspace);
    expect(dfdIn(back, tab).nodes.firstWhere((n) => n.id == store.id).tableId, 'tu');

    d.selectNode(store.id);
    d.duplicateSelection();
    final copies = pc.dfdOf(tab).nodes.where((n) => n.kind == DfdKind.store && n.id != store.id);
    expect(copies.single.tableId, 'tu');
  });

  test('ตัวตรวจ: ตารางที่ผูกถูกลบ = เตือน ; ไม่ส่ง project = ไม่ตรวจ', () {
    d.setStoreTable(store.id, 'tu');
    expect(validateDfd(pc.dfdOf(tab), workspace: pc.workspace).any((i) => i.code == 'dfd_store_table_missing'), false);
    pc.removeTable('tu');
    final issues = validateDfd(pc.dfdOf(tab), workspace: pc.workspace);
    expect(issues.where((i) => i.code == 'dfd_store_table_missing').single.tableId, store.id);
    expect(validateDfd(pc.dfdOf(tab)).any((i) => i.code == 'dfd_store_table_missing'), false);
  });

  test('gotoLinkedTable สลับไปแท็บ ER และเลือกตาราง', () {
    d.setStoreTable(store.id, 'to');
    expect(pc.activeDiagramId, tab);
    d.gotoLinkedTable(store.id);
    expect(pc.activeDiagramId, kErDiagramId);
    expect(pc.selectedTableId, 'to');
  });
}
