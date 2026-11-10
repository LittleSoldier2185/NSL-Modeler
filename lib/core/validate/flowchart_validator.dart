import '../l10n/l10n.dart';
import '../models/flowchart_model.dart';
import 'issue.dart';

/// ตรวจ Flowchart ตามกฎพื้นฐาน (ใช้ [Issue] ตัวเดียวกับ ER/DFD: [Issue.tableId] = id สัญลักษณ์, [Issue.relationId] = id เส้น)
///
/// - error: ไม่มีจุดเริ่มต้น, ไม่มีจุดสิ้นสุด, เส้นที่ปลายชี้ไปสัญลักษณ์ที่ไม่มี
/// - warning: จุดเริ่มต้นมากกว่าหนึ่ง, สัญลักษณ์ที่ไปไม่ถึงจากจุดเริ่มต้น, การตัดสินใจที่มีทางออกน้อยกว่า 2 ทาง
///   หรือทางออกไม่มีป้าย, สัญลักษณ์ทางตัน (ไม่ใช่จุดสิ้นสุดแต่ไม่มีทางออก), จุดสิ้นสุดที่มีทางออก, เส้นวนเข้าตัวเอง, สัญลักษณ์ไม่มีข้อความ
/// - โน้ตเป็นคำอธิบาย ไม่นับในกฎการไหล ; แผนภาพที่ไม่มีสัญลักษณ์ขั้นตอนเลย = ไม่มีปัญหา
List<Issue> validateFlowchart(FlowchartDiagram d) {
  final out = <Issue>[];
  final flowNodes = [for (final n in d.nodes) if (!fcIsAnnotation(n.shape)) n];
  if (flowNodes.isEmpty) return out;
  final byId = {for (final n in d.nodes) n.id: n};
  String name(FcNode n) => n.text.trim().isEmpty ? fcShapeLabel(n.shape) : n.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  final outs = <String, List<FcEdge>>{}, ins = <String, int>{};
  for (final e in d.edges) {
    final a = byId[e.fromId], b = byId[e.toId];
    if (a == null || b == null) {
      out.add(Issue(
        severity: Severity.error,
        code: 'fc_edge_dangling',
        title: tr('เส้นเชื่อมไม่ได้ต่อกับสัญลักษณ์'),
        message: tr('ปลายเส้นข้างหนึ่งชี้ไปสัญลักษณ์ที่ไม่มีแล้ว — ลบหรือต่อใหม่'),
        relationId: e.id,
      ));
      continue;
    }
    if (a.id == b.id) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'fc_self_loop',
        title: tr('เส้นวนเข้าตัวเอง'),
        message: tr('{0} มีเส้นที่ออกแล้ววนกลับเข้าตัวเอง', [name(a)]),
        relationId: e.id,
      ));
    }
    if (fcIsAnnotation(a.shape) || fcIsAnnotation(b.shape)) continue;
    outs.putIfAbsent(a.id, () => []).add(e);
    ins[b.id] = (ins[b.id] ?? 0) + 1;
  }

  final starts = [for (final n in flowNodes) if (n.shape == FcShape.start) n];
  final ends = [for (final n in flowNodes) if (n.shape == FcShape.end) n];
  if (starts.isEmpty) {
    out.add(Issue(
      severity: Severity.error,
      code: 'fc_no_start',
      title: tr('ไม่มีจุดเริ่มต้น'),
      message: tr('เพิ่มสัญลักษณ์ "เริ่มต้น" หนึ่งอันเป็นจุดเริ่มของผังงาน'),
    ));
  } else if (starts.length > 1) {
    for (final s in starts.skip(1)) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'fc_many_starts',
        title: tr('มีจุดเริ่มต้นมากกว่าหนึ่ง'),
        message: tr('{0}: ผังงานควรมีจุดเริ่มต้นเดียว', [name(s)]),
        tableId: s.id,
      ));
    }
  }
  if (ends.isEmpty) {
    out.add(Issue(
      severity: Severity.error,
      code: 'fc_no_end',
      title: tr('ไม่มีจุดสิ้นสุด'),
      message: tr('เพิ่มสัญลักษณ์ "สิ้นสุด" อย่างน้อยหนึ่งอัน'),
    ));
  }

  // ไปถึงได้จากจุดเริ่มต้น (เดินตามทิศเส้น)
  if (starts.isNotEmpty) {
    final seen = <String>{};
    final stack = [for (final s in starts) s.id];
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      if (!seen.add(u)) continue;
      for (final e in outs[u] ?? const <FcEdge>[]) {
        stack.add(e.toId);
      }
    }
    for (final n in flowNodes) {
      if (!seen.contains(n.id)) {
        out.add(Issue(
          severity: Severity.warning,
          code: 'fc_unreachable',
          title: tr('ไปไม่ถึงจากจุดเริ่มต้น'),
          message: tr('{0} ไม่มีทางเดินจากจุดเริ่มต้นมาถึง', [name(n)]),
          tableId: n.id,
        ));
      }
    }
  }

  for (final n in flowNodes) {
    final o = outs[n.id] ?? const <FcEdge>[];
    if (n.text.trim().isEmpty && n.shape != FcShape.connector) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'fc_empty_text',
        title: tr('สัญลักษณ์ไม่มีข้อความ'),
        message: tr('ใส่ข้อความให้ {0}', [fcShapeLabel(n.shape)]),
        tableId: n.id,
      ));
    }
    switch (n.shape) {
      case FcShape.end:
        if (o.isNotEmpty) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'fc_end_has_exit',
            title: tr('จุดสิ้นสุดมีทางออก'),
            message: tr('{0} เป็นจุดสิ้นสุดแต่มีเส้นออกไปต่อ', [name(n)]),
            tableId: n.id,
          ));
        }
      case FcShape.decision:
        final real = o.where((e) => e.toId != n.id).toList();
        if (real.length < 2) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'fc_decision_branches',
            title: tr('การตัดสินใจมีทางออกไม่ครบ'),
            message: tr('{0} ควรมีทางออกอย่างน้อย 2 ทาง (เช่น ใช่ / ไม่ใช่)', [name(n)]),
            tableId: n.id,
          ));
        }
        for (final e in real) {
          if (e.label.trim().isEmpty) {
            out.add(Issue(
              severity: Severity.warning,
              code: 'fc_decision_unlabeled',
              title: tr('ทางออกของการตัดสินใจไม่มีป้าย'),
              message: tr('{0} → {1}: ใส่ป้าย เช่น ใช่ / ไม่ใช่', [name(n), byId[e.toId] == null ? '?' : name(byId[e.toId]!)]),
              relationId: e.id,
            ));
          }
        }
      case FcShape.connector:
        break; // จุดต่อ (ไปหน้าอื่น) เป็นทางตันได้
      default:
        if (o.isEmpty) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'fc_dead_end',
            title: tr('ทางตัน'),
            message: tr('{0} ไม่ใช่จุดสิ้นสุดแต่ไม่มีเส้นออก', [name(n)]),
            tableId: n.id,
          ));
        }
    }
  }
  out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return out;
}

/// ชื่อชนิดสัญลักษณ์ (แสดงในแผง/รายงาน)
String fcShapeLabel(FcShape s) => switch (s) {
      FcShape.start => tr('เริ่มต้น@@flow'),
      FcShape.end => tr('สิ้นสุด'),
      FcShape.process => tr('กระบวนการ'),
      FcShape.decision => tr('การตัดสินใจ'),
      FcShape.io => tr('รับ/แสดงข้อมูล'),
      FcShape.subroutine => tr('โปรแกรมย่อย'),
      FcShape.connector => tr('จุดต่อ'),
      FcShape.note => tr('โน้ต'),
      FcShape.rounded => tr('สี่เหลี่ยมมุมมน'),
      FcShape.ellipse => tr('วงรี'),
      FcShape.text => tr('ข้อความ'),
      FcShape.hexagon => tr('หกเหลี่ยม'),
      FcShape.cylinder => tr('ทรงกระบอก (ฐานข้อมูล)'),
      FcShape.document => tr('เอกสาร@@fcshape'),
    };
