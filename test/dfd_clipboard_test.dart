import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/clipboard/dfd_clipboard.dart';
import 'package:nsl_modeler/core/models/dfd_model.dart';
import 'package:nsl_modeler/core/models/diagram.dart';
import 'package:nsl_modeler/state/dfd_controller.dart';
import 'package:nsl_modeler/state/project_controller.dart';

import 'migration_fixtures.dart';

void main() {
  late ProjectController pc;
  late DfdController d;
  late String tabA;

  setUp(() {
    pc = ProjectController(base());
    d = DfdController(pc);
    tabA = pc.addDiagram(DiagramKind.dfd, name: 'A')!.id;
  });

  DfdDiagram dia(String id) => pc.project.dfdOf(id);

  (DfdNode, DfdNode, DfdNode) build() {
    final e = d.addNode(DfdKind.entity, 100, 100)!;
    final p = d.addNode(DfdKind.process, 400, 100)!;
    final s = d.addNode(DfdKind.store, 700, 100)!;
    d.addFlow(e.id, p.id, label: 'in');
    d.addFlow(p.id, s.id, label: 'out');
    return (e, p, s);
  }

  test('คัดลอก-วางข้ามแท็บ: วัตถุ+เส้นระหว่างกันมาครบ id ใหม่ เลขไม่ซ้ำ และเลือกของที่วาง', () {
    final (e, p, s) = build();
    d.setNodeSelection({e.id, p.id, s.id});
    final text = d.copySelectionText()!;

    final tabB = pc.addDiagram(DiagramKind.dfd, name: 'B')!.id;
    expect(d.pasteText(text), 3);
    final b = dia(tabB);
    expect(b.nodes.length, 3);
    expect(b.flows.map((f) => f.label).toSet(), {'in', 'out'});
    expect(b.nodes.map((n) => n.id).toSet().intersection({e.id, p.id, s.id}), isEmpty);
    expect(b.nodes.firstWhere((n) => n.kind == DfdKind.process).number, '1.0'); // แผนภาพใหม่ ไม่ซ้ำจึงได้เลขเดิม
    expect(d.selectedNodeIds.length, 3);
    expect(b.nodeById(d.selectedNodeIds.first), isNotNull);
    pc.undo();
    expect(dia(tabB).nodes, isEmpty);
  });

  test('วางลงแท็บเดิม: เลื่อนตำแหน่ง และ process/store ได้เลขใหม่ไม่ซ้ำ', () {
    final (e, p, s) = build();
    d.setNodeSelection({p.id, s.id});
    final text = d.copySelectionText()!;
    expect(d.pasteText(text, offset: 30), 2);
    final procs = dia(tabA).nodes.where((n) => n.kind == DfdKind.process).toList();
    final stores = dia(tabA).nodes.where((n) => n.kind == DfdKind.store).toList();
    expect(procs.map((n) => n.number).toSet().length, 2);
    expect(stores.map((n) => n.number).toSet().length, 2);
    final copy = procs.firstWhere((n) => n.id != p.id);
    expect((copy.x, copy.y), (p.x + 30, p.y + 30));
    // เส้นระหว่าง p→s คัดลอกไปด้วย ส่วนเส้น e→p (e ไม่ได้เลือก) ไม่ตามไป
    expect(dia(tabA).flows.length, 3);
    expect(e.id, isNotEmpty);
  });

  test('tableId ที่ไม่มีในโปรเจกต์ปลายทางถูกตัดออก แต่ที่มีอยู่คงไว้', () {
    final (_, _, s) = build();
    d.setStoreTable(s.id, 'tu');
    d.setNodeSelection({s.id});
    final text = d.copySelectionText()!;
    expect(d.pasteText(text), 1);
    expect(dia(tabA).nodes.where((n) => n.tableId == 'tu').length, 2);

    final other = ProjectController(); // โปรเจกต์ว่าง ไม่มีตาราง tu
    final d2 = DfdController(other);
    other.addDiagram(DiagramKind.dfd);
    expect(d2.pasteText(text), 1);
    expect(other.project.dfdOf(other.activeDiagramId).nodes.single.tableId, isNull);
  });

  test('คัดลอกขอบเขตที่เลือกอย่างเดียว และวางได้', () {
    build();
    d.clearSelection();
    final k = d.addBoundaryAt(300, 300, name: 'Sys')!;
    d.selectBoundary(k.id);
    final text = d.copySelectionText()!;
    expect(d.pasteText(text), 1);
    expect(dia(tabA).boundaries.length, 2);
    expect(d.selectedBoundary!.name, 'Sys');
    expect(d.selectedBoundaryId, isNot(k.id));
  });

  test('ข้อความที่ไม่ใช่ DFD / ตาราง ER / เสียหาย / ไม่ได้เลือกอะไร = ไม่ทำอะไร', () {
    build();
    d.clearSelection();
    expect(d.copySelectionText(), isNull);
    final before = dia(tabA).nodes.length;
    for (final t in [null, '', 'hello', '{"a":1}', '{"format":"nsl-modeler-tables","tables":[]}', '{bad', '{"format":"nsl-modeler-dfd","nodes":[]}']) {
      expect(d.pasteText(t), 0, reason: '$t');
    }
    expect(dia(tabA).nodes.length, before);
    expect(decodeDfdClipboard('{"format":"nsl-modeler-dfd","nodes":[],"flows":[]}'), isNull);
  });

  test('วางบนแท็บ ER ไม่ทำอะไร', () {
    final (e, _, _) = build();
    d.setNodeSelection({e.id});
    final text = d.copySelectionText()!;
    pc.selectDiagram(kErDiagramId);
    expect(d.pasteText(text), 0);
  });
}
