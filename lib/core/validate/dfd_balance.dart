import '../l10n/l10n.dart';
import '../models/dfd_model.dart';
import '../models/workspace.dart';
import 'issue.dart';

/// เส้นข้อมูลที่ขอบของกระบวนการ : ข้อมูล [label] ไหล "เข้า" ([incoming]) หรือ "ออก" จากกระบวนการ ไปหา/มาจากวัตถุภายนอก [neighbor]
class _Edge {
  _Edge(this.incoming, this.kind, this.neighbor, this.label);
  final bool incoming;
  final DfdKind kind;
  final String neighbor;
  final String label;

  String get key => '${incoming ? 'in' : 'out'}|${kind.name}|${_norm(neighbor)}|${_norm(label)}';

  /// ข้อความอ่านง่าย เช่น `Order ← Customer` / `Receipt → Customer`
  String get text {
    final l = label.trim().isEmpty ? tr('(ไม่มีชื่อ)') : label.trim();
    return incoming ? '$l ← ${neighbor.trim()}' : '$l → ${neighbor.trim()}';
  }
}

String _norm(String s) => s.trim().toLowerCase();

bool _external(DfdKind k) => k == DfdKind.entity || k == DfdKind.store;

/// เส้นข้อมูลที่ต่อกับ [process] ใน [d] เฉพาะปลายที่เป็นผู้ใช้ภายนอก/ที่เก็บข้อมูล
List<_Edge> _parentEdges(DfdDiagram d, DfdNode process) {
  final out = <_Edge>[];
  for (final f in d.flows) {
    final a = d.nodeById(f.fromId), b = d.nodeById(f.toId);
    if (a == null || b == null) continue;
    if (b.id == process.id && _external(a.kind)) out.add(_Edge(true, a.kind, a.name, f.label));
    if (a.id == process.id && _external(b.kind)) out.add(_Edge(false, b.kind, b.name, f.label));
    if (f.bidirectional) {
      if (a.id == process.id && _external(b.kind)) out.add(_Edge(true, b.kind, b.name, f.label));
      if (b.id == process.id && _external(a.kind)) out.add(_Edge(false, a.kind, a.name, f.label));
    }
  }
  return out;
}

/// เส้นข้อมูลของแผนภาพย่อย [child] ที่ต่อกับวัตถุภายนอกซึ่งมีชื่อ/ชนิดตรงกับเพื่อนบ้านของกระบวนการแม่ ([known]) —
/// วัตถุภายในที่มีเฉพาะในแผนภาพย่อย (เช่นที่เก็บข้อมูลย่อย) ไม่นับ
List<_Edge> _childEdges(DfdDiagram child, Set<String> known) {
  final out = <_Edge>[];
  bool isKnown(DfdNode n) => _external(n.kind) && known.contains('${n.kind.name}|${_norm(n.name)}');
  for (final f in child.flows) {
    final a = child.nodeById(f.fromId), b = child.nodeById(f.toId);
    if (a == null || b == null) continue;
    if (isKnown(a) && !isKnown(b)) out.add(_Edge(true, a.kind, a.name, f.label));
    if (isKnown(b) && !isKnown(a)) out.add(_Edge(false, b.kind, b.name, f.label));
    if (f.bidirectional) {
      if (isKnown(b) && !isKnown(a)) out.add(_Edge(true, b.kind, b.name, f.label));
      if (isKnown(a) && !isKnown(b)) out.add(_Edge(false, a.kind, a.name, f.label));
    }
  }
  return out;
}

/// ผลการตรวจความสมดุลของกระบวนการหนึ่ง : เส้นที่แผนภาพย่อยขาด และเส้นเกินที่แม่ไม่มี
({List<String> missing, List<String> extra}) dfdBalanceOf(DfdDiagram parent, DfdNode process, DfdDiagram child) {
  final pe = _parentEdges(parent, process);
  final known = {for (final e in pe) '${e.kind.name}|${_norm(e.neighbor)}'};
  final ce = _childEdges(child, known);
  final pk = {for (final e in pe) e.key}, ck = {for (final e in ce) e.key};
  final seenM = <String>{}, seenE = <String>{};
  return (
    missing: [for (final e in pe) if (!ck.contains(e.key) && seenM.add(e.key)) e.text],
    extra: [for (final e in ce) if (!pk.contains(e.key) && seenE.add(e.key)) e.text],
  );
}

/// ตรวจการแตกรายละเอียด (Level 0 → Level 1) ของกระบวนการทุกตัวใน [diagramId] :
/// - warning `dfd_child_missing` : แผนภาพย่อยที่ชี้ไว้ถูกลบ/ไม่ใช่ DFD
/// - warning `dfd_unbalanced` : เส้นข้อมูลเข้า/ออกของกระบวนการไม่ตรงกับแผนภาพย่อย (ขาดหรือเกิน)
List<Issue> dfdBalanceIssues(Workspace w, String diagramId) {
  final parent = w.documentById(diagramId)?.dfd;
  if (parent == null) return const [];
  final out = <Issue>[];
  for (final n in parent.nodes) {
    final cid = n.childId;
    if (n.kind != DfdKind.process || cid == null) continue;
    final tab = w.documentById(cid);
    final child = tab?.dfd;
    final label = n.title.isEmpty ? tr('(ไม่มีชื่อ)') : n.title;
    if (tab == null || child == null) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'dfd_child_missing',
        title: tr('แผนภาพย่อยที่ชี้ไว้ไม่มีแล้ว'),
        message: tr('{0} ชี้ไปแผนภาพย่อยที่ถูกลบ — เลือกแผนภาพใหม่หรือเลิกลิงก์', [label]),
        tableId: n.id,
      ));
      continue;
    }
    final r = dfdBalanceOf(parent, n, child);
    if (r.missing.isEmpty && r.extra.isEmpty) continue;
    final parts = <String>[
      if (r.missing.isNotEmpty) tr('ขาดในแผนภาพย่อย: {0}', [r.missing.join(', ')]),
      if (r.extra.isNotEmpty) tr('เกินจากแม่: {0}', [r.extra.join(', ')]),
    ];
    out.add(Issue(
      severity: Severity.warning,
      code: 'dfd_unbalanced',
      title: tr('ข้อมูลเข้า/ออกไม่สมดุลกับแผนภาพย่อย'),
      message: '$label → "${tab.name}" · ${parts.join(' · ')}',
      tableId: n.id,
    ));
  }
  return out;
}
