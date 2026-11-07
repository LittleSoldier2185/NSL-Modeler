import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/validate/flowchart_validator.dart';
import 'package:nsl_dev/core/validate/issue.dart';
import 'package:nsl_dev/core/validate/workspace_validator.dart';

FcNode n(String id, FcShape s, [String text = 'x']) => FcNode(id: id, shape: s, text: text);
FcEdge e(String id, String a, String b, [String label = '']) => FcEdge(id: id, fromId: a, toId: b, label: label);

/// ผังงานที่ถูกต้องครบ: start -> p -> d -(Yes)-> end, d -(No)-> p
FlowchartDiagram good() => FlowchartDiagram(
      nodes: [n('s', FcShape.start), n('p', FcShape.process), n('d', FcShape.decision), n('t', FcShape.end)],
      edges: [e('1', 's', 'p'), e('2', 'p', 'd'), e('3', 'd', 't', 'Yes'), e('4', 'd', 'p', 'No')],
    );

Set<String> codes(FlowchartDiagram d) => {for (final i in validateFlowchart(d)) i.code};

void main() {
  setUp(() => currentLang = Lang.th);

  test('ผังงานถูกต้อง = ไม่มีปัญหา ; แผนภาพว่าง/มีแต่โน้ต = ไม่มีปัญหา', () {
    expect(validateFlowchart(good()), isEmpty);
    expect(validateFlowchart(FlowchartDiagram()), isEmpty);
    expect(validateFlowchart(FlowchartDiagram(nodes: [n('a', FcShape.note, '')])), isEmpty);
  });

  test('ไม่มีจุดเริ่มต้น = error ; ไม่มีจุดสิ้นสุด = error', () {
    final d = good()..nodes.removeWhere((x) => x.id == 's');
    d.edges.removeWhere((x) => x.fromId == 's');
    final i = validateFlowchart(d).firstWhere((x) => x.code == 'fc_no_start');
    expect(i.severity, Severity.error);
    final d2 = good()..nodes.removeWhere((x) => x.id == 't');
    d2.edges.removeWhere((x) => x.toId == 't');
    expect(validateFlowchart(d2).firstWhere((x) => x.code == 'fc_no_end').severity, Severity.error);
    // error มาก่อน warning
    expect(validateFlowchart(d2).first.severity, Severity.error);
  });

  test('จุดเริ่มต้นมากกว่าหนึ่ง = warning ที่อันที่เกิน', () {
    final d = good()
      ..nodes.add(n('s2', FcShape.start))
      ..edges.add(e('9', 's2', 'p'));
    final i = validateFlowchart(d).where((x) => x.code == 'fc_many_starts').toList();
    expect(i.length, 1);
    expect(i.single.tableId, 's2');
    expect(i.single.severity, Severity.warning);
  });

  test('ไปไม่ถึงจากจุดเริ่มต้น (เดินตามทิศเส้น) และทางตัน', () {
    final d = good()
      ..nodes.add(n('x', FcShape.process))
      ..edges.add(e('9', 'x', 'p'));
    final i = validateFlowchart(d);
    expect(i.where((x) => x.code == 'fc_unreachable').map((x) => x.tableId), ['x']);
    final d2 = good()
      ..nodes.add(n('y', FcShape.io))
      ..edges.add(e('9', 'p', 'y'));
    expect(validateFlowchart(d2).where((x) => x.code == 'fc_dead_end').map((x) => x.tableId), ['y']);
    // จุดต่อ (connector) เป็นทางตันได้
    final d3 = good()
      ..nodes.add(n('c', FcShape.connector, 'A'))
      ..edges.add(e('9', 'p', 'c'));
    expect(codes(d3), isNot(contains('fc_dead_end')));
  });

  test('การตัดสินใจ: ทางออกน้อยกว่า 2 และทางออกไม่มีป้าย', () {
    final d = good()..edges.removeWhere((x) => x.id == '4');
    expect(validateFlowchart(d).where((x) => x.code == 'fc_decision_branches').map((x) => x.tableId), ['d']);
    final d2 = good();
    d2.edgeById('3')!.label = ' ';
    expect(validateFlowchart(d2).where((x) => x.code == 'fc_decision_unlabeled').map((x) => x.relationId), ['3']);
  });

  test('เส้นวนเข้าตัวเอง, จุดสิ้นสุดมีทางออก, สัญลักษณ์ไม่มีข้อความ, เส้นชี้ไปที่ไม่มี', () {
    final d = good()
      ..edges.add(e('9', 'p', 'p'))
      ..edges.add(e('10', 't', 'p'))
      ..edges.add(e('11', 'p', 'ghost'));
    d.nodeById('p')!.text = '  ';
    final i = validateFlowchart(d);
    expect(i.where((x) => x.code == 'fc_self_loop').map((x) => x.relationId), ['9']);
    expect(i.where((x) => x.code == 'fc_end_has_exit').map((x) => x.tableId), ['t']);
    expect(i.where((x) => x.code == 'fc_empty_text').map((x) => x.tableId), ['p']);
    final dang = i.firstWhere((x) => x.code == 'fc_edge_dangling');
    expect((dang.relationId, dang.severity), ('11', Severity.error));
  });

  test('ชื่อซ้ำไม่ใช่ปัญหา ; โน้ตที่ต่อเส้นไม่ทำให้เกิดทางตัน/ไปไม่ถึง', () {
    final d = good()
      ..nodes.add(n('p2', FcShape.process, 'x'))
      ..nodes.add(n('note', FcShape.note, ''))
      ..edges.add(e('9', 'p', 'p2'))
      ..edges.add(e('10', 'p2', 't'))
      ..edges.add(e('11', 'note', 'p'));
    expect(validateFlowchart(d), isEmpty);
  });

  test('ตัวตรวจทั้งโปรเจกต์รวม Flowchart (ชนิดเอกสาร = flowchart)', () {
    final w = Workspace(documents: [
      ProjectDocument.er(id: 'er', name: 'ER', content: Project()),
      ProjectDocument.flowchart(id: 'f', name: 'Flow', content: FlowchartDiagram(nodes: [n('p', FcShape.process)])),
    ]);
    final all = validateWorkspace(w).where((x) => x.docId == 'f').toList();
    expect(all, isNotEmpty);
    expect(all.every((x) => x.docType == DocType.flowchart && x.docName == 'Flow'), isTrue);
    expect(all.map((x) => x.issue.code), containsAll(['fc_no_start', 'fc_no_end']));
  });

  test('ภาษาอังกฤษ: ชื่อและข้อความแปลครบ', () {
    currentLang = Lang.en;
    final d = good()..edges.add(e('9', 'p', 'p'));
    d.nodeById('s')!.text = '';
    final thai = RegExp(r'[฀-๿]');
    for (final i in validateFlowchart(d)) {
      expect(thai.hasMatch(i.title), isFalse, reason: i.title);
      expect(thai.hasMatch(i.message), isFalse, reason: i.message);
    }
    expect(fcShapeLabel(FcShape.start), 'Start');
    for (final s in FcShape.values) {
      expect(thai.hasMatch(fcShapeLabel(s)), isFalse, reason: s.name);
    }
    currentLang = Lang.th;
  });
}
