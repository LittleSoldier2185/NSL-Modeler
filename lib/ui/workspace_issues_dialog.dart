import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../core/validate/issue.dart';
import '../core/validate/workspace_validator.dart';
import '../state/workspace_controller.dart';
import 'canvas/canvas_controller.dart';
import 'issue_widgets.dart';
import 'palette/command_palette.dart' show gotoDfd;
import 'theme.dart';

/// ปัญหาที่ตรวจพบทั้งโปรเจกต์ — รวมทุกเอกสาร (ER และ DFD ทุกแท็บ) แยกเป็นกลุ่มตามเอกสาร คลิกรายการเพื่อไปที่วัตถุนั้น
Future<void> showWorkspaceIssues(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const WorkspaceIssuesDialog());

class WorkspaceIssuesDialog extends StatefulWidget {
  const WorkspaceIssuesDialog({super.key});

  @override
  State<WorkspaceIssuesDialog> createState() => _WorkspaceIssuesDialogState();
}

class _WorkspaceIssuesDialogState extends State<WorkspaceIssuesDialog> {
  bool _showInfo = true;

  void _goto(WorkspaceIssue wi) {
    final nav = Navigator.of(context);
    final w = context.read<WorkspaceController>();
    final cv = context.read<CanvasController>();
    final i = wi.issue;
    if (wi.docType == DocType.dfd) {
      nav.pop();
      gotoDfd(context, wi.docId, node: i.tableId, flow: i.relationId);
      return;
    }
    final er = w.erController(wi.docId);
    if (er == null || !w.openDocument(wi.docId)) return;
    nav.pop();
    final t = i.tableId == null ? null : er.project.tableById(i.tableId!);
    if (t == null) {
      cv.showDock(DockTab.issues);
      return;
    }
    er.selectTable(t.id, columnId: i.columnId);
    cv.focusTable(t);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final all = validateWorkspace(w.workspace);
    final shown = _showInfo ? all : all.where((x) => x.issue.severity != Severity.info).toList();
    final n = countIssues(all.map((x) => x.issue));

    // จัดกลุ่มตามเอกสารตามลำดับที่เจอ
    final groups = <String, List<WorkspaceIssue>>{};
    for (final x in shown) {
      groups.putIfAbsent(x.docId, () => []).add(x);
    }

    return AlertDialog(
      key: const ValueKey('workspace-issues'),
      title: Text(tr('ปัญหาที่ตรวจพบทั้งโปรเจกต์')),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                all.isEmpty
                    ? tr('✓ ไม่พบปัญหาในทุกเอกสาร')
                    : tr('{0} ข้อผิดพลาด · {1} คำเตือน · {2} คำแนะนำ — ใน {3} เอกสาร', [n.errors, n.warnings, n.infos, groups.length]),
                key: const ValueKey('workspace-issues-summary'),
                style: TextStyle(fontSize: 12.5, color: C.muted),
              ),
            ),
            if (n.infos > 0)
              TextButton(
                key: const ValueKey('workspace-issues-toggle-info'),
                onPressed: () => setState(() => _showInfo = !_showInfo),
                child: Text(_showInfo ? tr('ซ่อนคำแนะนำ') : tr('แสดงคำแนะนำ')),
              ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final e in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Row(children: [
                    Icon(w.documentById(e.key)?.type == DocType.dfd ? Icons.account_tree_outlined : Icons.table_chart_outlined,
                        size: 15, color: C.muted),
                    const SizedBox(width: 6),
                    Text(e.value.first.docName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('  (${e.value.length})', style: TextStyle(fontSize: 12.5, color: C.muted)),
                  ]),
                ),
                for (final x in e.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: IssueCard(issue: x.issue, onTap: () => _goto(x)),
                  ),
              ],
            ]),
          ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('ปิด')))],
    );
  }
}
