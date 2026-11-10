import '../l10n/l10n.dart';
import '../models/dfd_model.dart';
import '../models/flowchart_model.dart';
import '../models/screenflow_model.dart';
import '../models/wireframe_model.dart';
import '../validate/screenflow_validator.dart' show sfNodeTitle;
import '../validate/wireframe_validator.dart' show wfDeviceLabel, wfKindLabel, wfRefLabel, wfStyleLabel;
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

/// "อุปกรณ์ ขนาด · รูปแบบ · n ชิ้นส่วน" ของ Wireframe
String wireframeSummary(WireframeDiagram g) {
  final size = '${g.width.round()}×${g.height.round()}';
  final dev = g.device == WfDevice.custom ? size : wfDeviceLabel(g.device);
  return tr('{0} · {1} · {2} ชิ้นส่วน', [dev, wfStyleLabel(g.style), g.components.length]);
}

/// ชื่อหน้าจอ "Screen Flow › หน้าจอ" ที่ผูกกับ Wireframe [docId]
List<String> screensLinkingTo(Workspace w, String docId) => [
      for (final d in w.documentsOf(DocType.screenflow))
        for (final n in d.screenflow!.nodes)
          if (n.wireframeId == docId) '${d.name} › ${sfNodeTitle(n)}',
    ];

/// แถวรายการชิ้นส่วนของ Wireframe ตามลำดับการซ้อน: ลูกในภาชนะตามหลังพ่อ ([depth] = ระดับการซ้อน)
List<({int depth, String kind, String text, String geometry, String state, String binding})> wireframeRows(
    Workspace w, WireframeDiagram g) {
  final parents = wfParentMap(g);
  final kids = <String?, List<WfComponent>>{};
  for (final c in g.components) {
    kids.putIfAbsent(parents[c.id], () => []).add(c);
  }
  final out = <({int depth, String kind, String text, String geometry, String state, String binding})>[];
  void walk(String? parent, int depth) {
    for (final c in kids[parent] ?? const <WfComponent>[]) {
      final text = c.kind == WfKind.table && c.columns.isNotEmpty ? c.columns.join(' | ') : c.text.trim();
      final state = [
        if (c.kind == WfKind.button) c.secondary ? tr('ปุ่มรอง') : tr('ปุ่มหลัก'),
        if (c.disabled) tr('ใช้งานไม่ได้'),
        if (c.checked && kWfCheckableKinds.contains(c.kind)) tr('เลือกอยู่'),
      ].join(', ');
      final ref = c.ref;
      out.add((
        depth: depth,
        kind: wfKindLabel(c.kind),
        text: text,
        geometry: '${c.x.round()}, ${c.y.round()} · ${c.w.round()}×${c.h.round()}',
        state: state,
        binding: ref == null ? '' : wfRefLabel(w, ref, withDoc: w.documentsOf(DocType.er).length > 1),
      ));
      walk(c.id, depth + 1);
    }
  }

  walk(null, 0);
  return out;
}

/// ชื่อโหนด [id] ใน Screen Flow บรรทัดเดียว (ไม่มี = ?)
String sfNodeText(ScreenFlowDiagram g, String id) {
  final n = g.nodeById(id);
  return n == null ? '?' : sfNodeTitle(n);
}

/// ชื่อเอกสาร Wireframe ที่หน้าจอผูกไว้ ("" = ไม่ผูก, "?" = เอกสารไม่มีแล้ว)
String sfWireframeLabel(Workspace w, SfNode n) {
  final id = n.wireframeId;
  if (id == null) return '';
  final d = w.documentById(id);
  return d?.wireframe == null ? '? ($id)' : d!.name;
}

/// ผลรวมของทั้งโปรเจกต์ (wfs/components = Wireframe และชิ้นส่วน ; sfs/screens/navs = Screen Flow, โหนด และเส้นการเปลี่ยนหน้า)
typedef WorkspaceCounts = ({
  int docs,
  int ers,
  int dfds,
  int tables,
  int relations,
  int objects,
  int flows,
  int fcs,
  int symbols,
  int fcEdges,
  int wfs,
  int components,
  int sfs,
  int screens,
  int navs,
});

/// ผลรวมของทั้งโปรเจกต์
WorkspaceCounts workspaceCounts(Workspace w) {
  final k = knownDocs(w);
  final ers = [for (final d in k) if (d.type == DocType.er) d.er!];
  final dfds = [for (final d in k) if (d.type == DocType.dfd) d.dfd!];
  final fcs = [for (final d in k) if (d.type == DocType.flowchart) d.flowchart!];
  final wfs = [for (final d in k) if (d.type == DocType.wireframe) d.wireframe!];
  final sfs = [for (final d in k) if (d.type == DocType.screenflow) d.screenflow!];
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
    wfs: wfs.length,
    components: wfs.fold(0, (a, d) => a + d.components.length),
    sfs: sfs.length,
    screens: sfs.fold(0, (a, d) => a + d.nodes.length),
    navs: sfs.fold(0, (a, d) => a + d.edges.length),
  );
}

/// บรรทัด "n เอกสาร (… ER · … DFD)" — มี Flowchart/Wireframe/Screen Flow จึงต่อท้ายจำนวนของชนิดนั้น
/// (ไม่มี = ข้อความเดิมทุกตัวอักษร)
String docCountLine(WorkspaceCounts c, {bool bullet = false}) {
  if (c.wfs > 0 || c.sfs > 0) {
    final parts = [
      '${c.ers} ER',
      '${c.dfds} DFD',
      if (c.fcs > 0) '${c.fcs} Flowchart',
      if (c.wfs > 0) '${c.wfs} Wireframe',
      if (c.sfs > 0) '${c.sfs} Screen Flow',
    ];
    final s = tr('{0} เอกสาร ({1})', [c.docs, parts.join(' · ')]);
    return bullet ? '- $s' : s;
  }
  if (c.fcs == 0) {
    return bullet ? tr('- {0} เอกสาร ({1} ER · {2} DFD)', [c.docs, c.ers, c.dfds]) : tr('{0} เอกสาร ({1} ER · {2} DFD)', [c.docs, c.ers, c.dfds]);
  }
  final s = tr('{0} เอกสาร ({1} ER · {2} DFD · {3} Flowchart)', [c.docs, c.ers, c.dfds, c.fcs]);
  return bullet ? '- $s' : s;
}
