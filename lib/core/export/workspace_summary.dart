import '../l10n/l10n.dart';
import '../models/dfd_model.dart';
import '../models/flowchart_model.dart';
import '../validate/flowchart_validator.dart' show fcShapeLabel;
import '../models/workspace.dart';
import '../validate/issue.dart';
import '../validate/workspace_validator.dart';

/// ตัวช่วยร่วมของการ Export เอกสารรวมทั้งโปรเจกต์ (Markdown / HTML) — ฟังก์ชันล้วน ไม่แตะ UI

/// เอกสารที่รู้จักตามลำดับในไฟล์ (ข้ามชนิดที่ไม่รู้จัก)
List<ProjectDocument> knownDocs(Workspace w) => [for (final d in w.documents) if (d.type != null) d];

/// โปรเจกต์ที่มีเอกสารที่รู้จักชิ้นเดียวและเป็น ER = ใช้รูปแบบเอกสารเดิม (ไม่มีภาพรวมโปรเจกต์)
bool isSingleErWorkspace(Workspace w) {
  final k = knownDocs(w);
  return k.length == 1 && k.first.type == DocType.er;
}

/// ปัญหาระดับ error/warning ของทุกเอกสาร (ไม่รวมคำแนะนำ)
List<WorkspaceIssue> exportIssues(Workspace w) =>
    [for (final i in validateWorkspace(w)) if (i.issue.severity != Severity.info) i];

String dfdKindLabel(DfdKind k) => switch (k) {
      DfdKind.entity => tr('ผู้ใช้ภายนอก'),
      DfdKind.process => tr('กระบวนการ'),
      DfdKind.store => tr('ที่เก็บข้อมูล'),
    };

String severityLabel(Severity s) => switch (s) {
      Severity.error => tr('ข้อผิดพลาด'),
      Severity.warning => tr('คำเตือน'),
      Severity.info => tr('คำแนะนำ'),
    };

/// ข้อความของสัญลักษณ์ [id] ใน Flowchart บรรทัดเดียว (ว่าง = ชื่อชนิด ; ไม่มี = ?)
String fcNodeText(FlowchartDiagram g, String id) {
  final n = g.nodeById(id);
  if (n == null) return '?';
  final t = n.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.isEmpty ? fcShapeLabel(n.shape) : t;
}

/// "ชื่อ ER › ตาราง" ของที่เก็บข้อมูลที่ผูกกับตาราง (null = ไม่ได้ผูก/หาไม่พบ)
String? dfdStoreTableLabel(Workspace w, DfdNode n) {
  final tid = n.tableId;
  if (tid == null) return null;
  final ers = w.documentsOf(DocType.er);
  final docId = n.tableDocId;
  final first = docId == null ? null : w.documentById(docId);
  for (final d in [?first, ...ers]) {
    final t = d.er?.tableById(tid);
    if (t != null) return ers.length > 1 ? '${d.name} › ${t.name}' : t.name;
  }
  return null;
}

/// ผลรวมของทั้งโปรเจกต์
({int docs, int ers, int dfds, int tables, int relations, int objects, int flows, int fcs, int symbols, int fcEdges})
    workspaceCounts(Workspace w) {
  final k = knownDocs(w);
  final ers = [for (final d in k) if (d.type == DocType.er) d.er!];
  final dfds = [for (final d in k) if (d.type == DocType.dfd) d.dfd!];
  final fcs = [for (final d in k) if (d.type == DocType.flowchart) d.flowchart!];
  return (
    docs: k.length,
    ers: ers.length,
    dfds: dfds.length,
    tables: ers.fold(0, (a, p) => a + p.tables.length),
    relations: ers.fold(0, (a, p) => a + p.relations.length),
    objects: dfds.fold(0, (a, d) => a + d.nodes.length),
    flows: dfds.fold(0, (a, d) => a + d.flows.length),
    fcs: fcs.length,
    symbols: fcs.fold(0, (a, d) => a + d.nodes.length),
    fcEdges: fcs.fold(0, (a, d) => a + d.edges.length),
  );
}

/// บรรทัด "n เอกสาร (… ER · … DFD)" — มี Flowchart จึงต่อท้ายจำนวน Flowchart (ไม่มี = ข้อความเดิมทุกตัวอักษร)
String docCountLine(({int docs, int ers, int dfds, int tables, int relations, int objects, int flows, int fcs, int symbols, int fcEdges}) c,
    {bool bullet = false}) {
  if (c.fcs == 0) {
    return bullet ? tr('- {0} เอกสาร ({1} ER · {2} DFD)', [c.docs, c.ers, c.dfds]) : tr('{0} เอกสาร ({1} ER · {2} DFD)', [c.docs, c.ers, c.dfds]);
  }
  final s = tr('{0} เอกสาร ({1} ER · {2} DFD · {3} Flowchart)', [c.docs, c.ers, c.dfds, c.fcs]);
  return bullet ? '- $s' : s;
}
