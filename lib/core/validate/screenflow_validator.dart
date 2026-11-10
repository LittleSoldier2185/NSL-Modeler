import '../l10n/l10n.dart';
import '../models/screenflow_model.dart';
import '../models/workspace.dart';
import 'issue.dart';

/// ตรวจ Screen Flow ([Issue.tableId] = id โหนด, [Issue.relationId] = id เส้น)
///
/// - error: ไม่มีจุดเริ่ม, หน้าจอผูกกับ Wireframe ที่ไม่มีแล้ว (ต้องส่ง [workspace]), เส้นชี้ไปโหนดที่ไม่มี
/// - warning: หน้าจอที่ไปไม่ถึงจากจุดเริ่ม, หน้าจอทางตัน (ไม่ใช่จุดจบแต่ไม่มีทางไปต่อ)
/// - info: หน้าจอที่ยังไม่ได้ผูกกับ Wireframe
/// แผนผังว่าง = ไม่มีปัญหา
List<Issue> validateScreenFlow(ScreenFlowDiagram d, {Workspace? workspace}) {
  final out = <Issue>[];
  if (d.nodes.isEmpty) return out;
  final byId = {for (final n in d.nodes) n.id: n};
  final outs = <String, List<SfEdge>>{};
  for (final e in d.edges) {
    final a = byId[e.fromId], b = byId[e.toId];
    if (a == null || b == null) {
      out.add(Issue(
        severity: Severity.error,
        code: 'sf_edge_dangling',
        title: tr('เส้นการเปลี่ยนหน้าไม่ได้ต่อกับหน้าจอ'),
        message: tr('ปลายเส้นข้างหนึ่งชี้ไปหน้าจอที่ไม่มีแล้ว — ลบหรือต่อใหม่'),
        relationId: e.id,
      ));
      continue;
    }
    outs.putIfAbsent(a.id, () => []).add(e);
  }

  final starts = [for (final n in d.nodes) if (n.kind == SfKind.start) n];
  if (starts.isEmpty) {
    out.add(Issue(
      severity: Severity.error,
      code: 'sf_no_start',
      title: tr('ไม่มีจุดเริ่ม'),
      message: tr('เพิ่มโหนด "เริ่ม" เพื่อบอกว่าผู้ใช้เข้ามาที่หน้าจอไหนก่อน'),
    ));
  } else {
    final seen = <String>{};
    final stack = [for (final s in starts) s.id];
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      if (!seen.add(u)) continue;
      for (final e in outs[u] ?? const <SfEdge>[]) {
        stack.add(e.toId);
      }
    }
    for (final n in d.nodes) {
      if (n.kind != SfKind.start && !seen.contains(n.id)) {
        out.add(Issue(
          severity: Severity.warning,
          code: 'sf_unreachable',
          title: tr('ไปไม่ถึงจากจุดเริ่ม'),
          message: tr('{0} ไม่มีทางมาถึงจากจุดเริ่ม', [sfNodeTitle(n)]),
          tableId: n.id,
        ));
      }
    }
  }

  for (final n in d.nodes) {
    final o = outs[n.id] ?? const <SfEdge>[];
    if ((n.kind == SfKind.screen || n.kind == SfKind.start) && o.isEmpty) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'sf_dead_end',
        title: tr('หน้าจอทางตัน'),
        message: tr('{0} ไม่ใช่จุดจบแต่ไม่มีทางไปหน้าอื่น', [sfNodeTitle(n)]),
        tableId: n.id,
      ));
    }
    if (n.kind != SfKind.screen) continue;
    final wf = n.wireframeId;
    if (wf == null) {
      out.add(Issue(
        severity: Severity.info,
        code: 'sf_no_wireframe',
        title: tr('หน้าจอยังไม่มี Wireframe'),
        message: tr('{0} ยังไม่ได้ผูกกับเอกสาร Wireframe', [sfNodeTitle(n)]),
        tableId: n.id,
      ));
    } else if (workspace != null && workspace.documentById(wf)?.wireframe == null) {
      out.add(Issue(
        severity: Severity.error,
        code: 'sf_wireframe_missing',
        title: tr('ผูกกับ Wireframe ที่ไม่มีแล้ว'),
        message: tr('{0} ผูกกับเอกสาร Wireframe ที่ถูกลบไป — เลือกใหม่หรือเลิกผูก', [sfNodeTitle(n)]),
        tableId: n.id,
      ));
    }
  }
  out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return out;
}

/// ชื่อแสดงของโหนด (บรรทัดเดียว) — ว่าง = ชื่อชนิด
String sfNodeTitle(SfNode n) {
  final t = n.title.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.isEmpty ? sfKindLabel(n.kind) : t;
}

/// ชื่อชนิดโหนด
String sfKindLabel(SfKind k) => switch (k) {
      SfKind.start => tr('เริ่ม@@sf'),
      SfKind.screen => tr('หน้าจอ'),
      SfKind.external => tr('ภายนอก / ป๊อปอัป'),
      SfKind.end => tr('จบ@@sf'),
    };
