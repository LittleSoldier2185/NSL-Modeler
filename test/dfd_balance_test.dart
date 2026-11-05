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
  late String l0;
  late DfdNode cust, proc, store;

  List<String> codes(String tab) =>
      validateDfd(pc.dfdOf(tab), workspace: pc.workspace, diagramId: tab).map((i) => i.code).toList();

  setUp(() {
    pc = ProjectController(base());
    d = DfdController(pc);
    l0 = pc.addDiagram(DocType.dfd, name: 'L0')!.id;
    cust = d.addNode(DfdKind.entity, 100, 100)!;
    d.renameNode(cust.id, 'Customer');
    proc = d.addNode(DfdKind.process, 400, 100)!;
    d.renameNode(proc.id, 'Order');
    store = d.addNode(DfdKind.store, 700, 100)!;
    d.renameNode(store.id, 'Orders');
    d.addFlow(cust.id, proc.id, label: 'order');
    d.addFlow(proc.id, cust.id, label: 'receipt');
    d.addFlow(proc.id, store.id, label: 'save');
  });

  test('สร้างแผนภาพย่อย: ลิงก์ เปิดแท็บใหม่ มีเพื่อนบ้านและเส้นเดียวกับแม่ และเริ่มต้นสมดุล', () {
    final tab = d.createChildFor(proc.id)!;
    expect(pc.activeDiagramId, tab.id);
    final child = pc.dfdOf(tab.id);
    expect(child.nodes.where((n) => n.kind == DfdKind.process).single.number, '1.1');
    expect(child.nodes.map((n) => n.name).toSet(), {'Customer', 'Order', 'Orders'});
    expect(child.flows.map((f) => f.label).toSet(), {'order', 'receipt', 'save'});
    expect(pc.dfdOf(l0).nodeById(proc.id)!.childId, tab.id);
    expect(codes(l0).where((c) => c == 'dfd_unbalanced' || c == 'dfd_child_missing'), isEmpty);
    expect(d.parentsOf(tab.id).single.$2.id, proc.id);
  });

  test('แผนภาพย่อยขาดเส้น = เตือนไม่สมดุล (ขาด) ; เติมกลับแล้วหาย', () {
    final tab = d.createChildFor(proc.id)!;
    final child = pc.dfdOf(tab.id);
    final receipt = child.flows.firstWhere((f) => f.label == 'receipt');
    d.selectFlow(receipt.id);
    d.deleteSelection();
    final issues = validateDfd(pc.dfdOf(l0), workspace: pc.workspace, diagramId: l0);
    final u = issues.singleWhere((i) => i.code == 'dfd_unbalanced');
    expect(u.tableId, proc.id);
    expect(u.message, contains('receipt'));
    expect(u.message, contains('ขาด'));
    final sub = child.nodes.firstWhere((n) => n.kind == DfdKind.process);
    final c = child.nodes.firstWhere((n) => n.kind == DfdKind.entity);
    d.addFlow(sub.id, c.id, label: 'receipt');
    expect(codes(l0), isNot(contains('dfd_unbalanced')));
  });

  test('แผนภาพย่อยมีเส้นเกินที่แม่ไม่มี = เตือน ; ที่เก็บข้อมูลภายในแผนภาพย่อยเท่านั้นไม่นับ', () {
    final tab = d.createChildFor(proc.id)!;
    final child = pc.dfdOf(tab.id);
    final sub = child.nodes.firstWhere((n) => n.kind == DfdKind.process);
    final cust2 = child.nodes.firstWhere((n) => n.kind == DfdKind.entity);
    final internal = d.addNode(DfdKind.store, 900, 400)!;
    d.renameNode(internal.id, 'Cache');
    d.addFlow(sub.id, internal.id, label: 'tmp'); // ภายใน ไม่นับ
    expect(codes(l0), isNot(contains('dfd_unbalanced')));
    d.addFlow(cust2.id, sub.id, label: 'extra');
    final u = validateDfd(pc.dfdOf(l0), workspace: pc.workspace, diagramId: l0)
        .singleWhere((i) => i.code == 'dfd_unbalanced');
    expect(u.message, contains('extra'));
    expect(u.message, contains('เกิน'));
  });

  test('ลิงก์ไปแท็บที่มีอยู่: ห้ามลิงก์ตัวเอง/วนเป็นวง และเฉพาะ process → DFD', () {
    pc.selectDiagram(l0);
    final other = pc.addDiagram(DocType.dfd, name: 'X')!;
    pc.selectDiagram(l0);
    expect(d.childCandidates(l0).map((t) => t.id), [other.id]);
    expect(d.setProcessChild(proc.id, l0), false); // ตัวเอง
    expect(d.setProcessChild(proc.id, kErDiagramId), false); // ไม่ใช่ DFD
    expect(d.setProcessChild(cust.id, other.id), false); // ไม่ใช่ process
    expect(d.setProcessChild(proc.id, other.id), true);

    // other -> l0 จะวนเป็นวง
    pc.selectDiagram(other.id);
    final p2 = d.addNode(DfdKind.process, 100, 100)!;
    expect(d.childCandidates(other.id), isEmpty);
    expect(d.setProcessChild(p2.id, l0), false);
  });

  test('แท็บย่อยถูกลบ = เตือน child_missing ; เลิกลิงก์ได้ ; undo ลิงก์', () {
    final tab = d.createChildFor(proc.id)!;
    pc.selectDiagram(l0);
    pc.deleteDiagram(tab.id);
    expect(codes(l0), contains('dfd_child_missing'));
    expect(d.setProcessChild(proc.id, null), true);
    expect(codes(l0), isNot(contains('dfd_child_missing')));
    pc.undo();
    expect(pc.dfdOf(l0).nodeById(proc.id)!.childId, tab.id);
  });

  test('บันทึก-โหลดไฟล์คง childId ; คัดลอก-วาง/ทำสำเนาไม่พาลิงก์ตามไป ; childId เฉพาะ process', () {
    final tab = d.createChildFor(proc.id)!;
    pc.selectDiagram(l0);
    final back = roundTrip(pc.workspace);
    expect(dfdIn(back, l0).nodeById(proc.id)!.childId, tab.id);

    d.setNodeSelection({proc.id});
    d.duplicateSelection();
    expect(pc.dfdOf(l0).nodes.where((n) => n.childId != null).length, 1);
    d.setNodeSelection({proc.id});
    d.pasteText(d.copySelectionText());
    expect(pc.dfdOf(l0).nodes.where((n) => n.childId != null).length, 1);

    final bad = DfdNode.tryFromJson({'id': 'e', 'kind': 'entity', 'child': 'x'})!;
    expect(bad.childId, isNull);
  });

  test('ไม่มีเพื่อนบ้านภายนอก = แผนภาพย่อยมีแค่กระบวนการย่อย และสมดุล', () {
    pc.selectDiagram(l0);
    final lone = d.addNode(DfdKind.process, 400, 500)!;
    final tab = d.createChildFor(lone.id)!;
    expect(pc.dfdOf(tab.id).nodes.length, 1);
    expect(codes(l0), isNot(contains('dfd_unbalanced')));
  });
}
