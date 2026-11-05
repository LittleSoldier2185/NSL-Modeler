import '../l10n/l10n.dart';
import '../models/dfd_model.dart';
import '../models/workspace.dart';
import 'dfd_balance.dart';
import 'issue.dart';

/// ตรวจแผนภาพ DFD ตามกฎพื้นฐาน (ใช้ [Issue] ตัวเดียวกับ ER: [Issue.tableId] เก็บ id ของวัตถุ, [Issue.relationId] เก็บ id ของ flow)
///
/// - error: flow ระหว่างสองวัตถุที่ไม่ใช่ process (entity↔entity, entity↔store, store↔store) — ข้อมูลต้องผ่าน process เสมอ
/// - warning: process ไม่มีข้อมูลเข้า/ออก, flow ไม่มีชื่อ, เลขลำดับ/รหัสซ้ำหรือว่าง, วัตถุไม่มีชื่อ
/// - info: entity/store ที่ไม่ได้เชื่อมกับอะไรเลย
/// [workspace] = ใช้ตรวจตาราง ER ที่ที่เก็บข้อมูลผูกไว้ และความสมดุลกับแผนภาพย่อย (ต้องมี [diagramId] ด้วย)
List<Issue> validateDfd(DfdDiagram d, {Workspace? workspace, String? diagramId}) {
  final out = <Issue>[];
  if (workspace != null && diagramId != null) out.addAll(dfdBalanceIssues(workspace, diagramId));
  String name(DfdNode n) => n.title.isEmpty ? tr('(ไม่มีชื่อ)') : n.title;

  final incoming = <String, int>{}, outgoing = <String, int>{};
  for (final f in d.flows) {
    final a = d.nodeById(f.fromId), b = d.nodeById(f.toId);
    if (a == null || b == null) continue;
    outgoing[a.id] = (outgoing[a.id] ?? 0) + 1;
    incoming[b.id] = (incoming[b.id] ?? 0) + 1;
    if (f.bidirectional) {
      outgoing[b.id] = (outgoing[b.id] ?? 0) + 1;
      incoming[a.id] = (incoming[a.id] ?? 0) + 1;
    }
    if (a.kind != DfdKind.process && b.kind != DfdKind.process) {
      out.add(Issue(
        severity: Severity.error,
        code: 'dfd_no_process',
        title: tr('เส้นข้อมูลต้องผ่านกระบวนการ'),
        message: tr('{0} → {1}: ข้อมูลระหว่าง entity / ที่เก็บข้อมูลต้องไหลผ่าน process', [name(a), name(b)]),
        relationId: f.id,
      ));
    }
    if (f.label.trim().isEmpty) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'dfd_flow_unlabeled',
        title: tr('เส้นข้อมูลไม่มีชื่อ'),
        message: tr('{0} → {1}: ตั้งชื่อว่าข้อมูลอะไรไหล', [name(a), name(b)]),
        relationId: f.id,
      ));
    }
  }

  final procNumbers = <String, int>{}, storeNumbers = <String, int>{};
  for (final n in d.nodes) {
    if (n.kind == DfdKind.process) procNumbers[n.number.trim()] = (procNumbers[n.number.trim()] ?? 0) + 1;
    if (n.kind == DfdKind.store) storeNumbers[n.number.trim()] = (storeNumbers[n.number.trim()] ?? 0) + 1;
  }

  for (final n in d.nodes) {
    if (n.name.trim().isEmpty) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'dfd_no_name',
        title: tr('วัตถุไม่มีชื่อ'),
        message: tr('ตั้งชื่อให้ {0}', [n.number.isEmpty ? n.kind.name : n.number]),
        tableId: n.id,
      ));
    }
    switch (n.kind) {
      case DfdKind.process:
        final i = incoming[n.id] ?? 0, o = outgoing[n.id] ?? 0;
        if (i == 0 && o == 0) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'dfd_process_isolated',
            title: tr('กระบวนการไม่ได้เชื่อมกับอะไร'),
            message: tr('{0} ไม่มีข้อมูลเข้าและไม่มีข้อมูลออก', [name(n)]),
            tableId: n.id,
          ));
        } else if (i == 0) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'dfd_process_no_input',
            title: tr('กระบวนการไม่มีข้อมูลเข้า'),
            message: tr('{0} มีแต่ข้อมูลออก — ข้อมูลที่ออกมาจากไหน', [name(n)]),
            tableId: n.id,
          ));
        } else if (o == 0) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'dfd_process_no_output',
            title: tr('กระบวนการไม่มีข้อมูลออก'),
            message: tr('{0} รับข้อมูลเข้าแต่ไม่มีข้อมูลออก', [name(n)]),
            tableId: n.id,
          ));
        }
        final num = n.number.trim();
        if (num.isEmpty) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'dfd_no_number',
            title: tr('กระบวนการไม่มีเลขลำดับ'),
            message: tr('ตั้งเลขลำดับให้ {0} เช่น 1.0', [name(n)]),
            tableId: n.id,
          ));
        } else if ((procNumbers[num] ?? 0) > 1) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'dfd_dup_number',
            title: tr('เลขลำดับซ้ำ'),
            message: tr('เลข {0} ถูกใช้กับกระบวนการมากกว่าหนึ่งอัน', [num]),
            tableId: n.id,
          ));
        }
      case DfdKind.store:
        final tid = n.tableId;
        if (workspace != null && tid != null && !_tableExists(workspace, n.tableDocId, tid)) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'dfd_store_table_missing',
            title: tr('ที่เก็บข้อมูลผูกกับตารางที่ไม่มีแล้ว'),
            message: tr('{0} ผูกกับตาราง ER ที่ถูกลบไป — เลือกตารางใหม่หรือเลิกผูก', [name(n)]),
            tableId: n.id,
          ));
        }
        final num = n.number.trim();
        if (num.isNotEmpty && (storeNumbers[num] ?? 0) > 1) {
          out.add(Issue(
            severity: Severity.warning,
            code: 'dfd_dup_number',
            title: tr('รหัสที่เก็บข้อมูลซ้ำ'),
            message: tr('รหัส {0} ถูกใช้กับที่เก็บข้อมูลมากกว่าหนึ่งอัน', [num]),
            tableId: n.id,
          ));
        }
        if ((incoming[n.id] ?? 0) + (outgoing[n.id] ?? 0) == 0) {
          out.add(Issue(
            severity: Severity.info,
            code: 'dfd_isolated',
            title: tr('ที่เก็บข้อมูลไม่ได้เชื่อมกับอะไร'),
            message: tr('{0} ยังไม่มีเส้นข้อมูล', [name(n)]),
            tableId: n.id,
          ));
        }
      case DfdKind.entity:
        if ((incoming[n.id] ?? 0) + (outgoing[n.id] ?? 0) == 0) {
          out.add(Issue(
            severity: Severity.info,
            code: 'dfd_isolated',
            title: tr('ผู้ใช้/ระบบภายนอกไม่ได้เชื่อมกับอะไร'),
            message: tr('{0} ยังไม่มีเส้นข้อมูล', [name(n)]),
            tableId: n.id,
          ));
        }
    }
  }
  out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return out;
}

/// ตาราง [tableId] มีอยู่ในเอกสาร ER [docId] หรือไม่ (ไม่ระบุเอกสาร = หาในเอกสาร ER ทุกชิ้น)
bool _tableExists(Workspace w, String? docId, String tableId) {
  if (docId != null) return w.documentById(docId)?.er?.tableById(tableId) != null;
  return w.documentsOf(DocType.er).any((e) => e.er?.tableById(tableId) != null);
}
