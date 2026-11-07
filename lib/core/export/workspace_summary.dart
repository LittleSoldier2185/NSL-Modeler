import '../l10n/l10n.dart';
import '../models/dfd_model.dart';
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
({int docs, int ers, int dfds, int tables, int relations, int objects, int flows}) workspaceCounts(Workspace w) {
  final k = knownDocs(w);
  final ers = [for (final d in k) if (d.type == DocType.er) d.er!];
  final dfds = [for (final d in k) if (d.type == DocType.dfd) d.dfd!];
  return (
    docs: k.length,
    ers: ers.length,
    dfds: dfds.length,
    tables: ers.fold(0, (a, p) => a + p.tables.length),
    relations: ers.fold(0, (a, p) => a + p.relations.length),
    objects: dfds.fold(0, (a, d) => a + d.nodes.length),
    flows: dfds.fold(0, (a, d) => a + d.flows.length),
  );
}
