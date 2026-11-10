import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../core/validate/issue.dart';
import '../core/validate/workspace_validator.dart';
import '../state/workspace_controller.dart';
import 'app_actions.dart';
import 'document_actions.dart' show docTypeIcon;
import 'wireframe/wf_panels.dart' show WireframeThumbnail;
import '../core/export/workspace_summary.dart' show wireframeSummary;
import 'shortcuts.dart';
import 'theme.dart';
import 'workspace_issues_dialog.dart';

typedef _DocIssues = ({int errors, int warnings});

/// หน้า Project Home: ภาพรวมทั้งโปรเจกต์ (ไม่ใช่เอกสารในไฟล์) — แสดงแทนแคนวาสขณะ [WorkspaceController.homeView]
/// ชื่อ/ไฟล์/สถานะบันทึก, ปุ่มลัด (เพิ่ม ER/DFD · ปัญหา · บันทึก), แถบสรุปทั้งโปรเจกต์,
/// การ์ดเอกสารแยกตามชนิด (คลิก = เปิดเอกสารและออกจากหน้านี้)
class ProjectHomeView extends StatelessWidget {
  const ProjectHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final perDoc = <String, _DocIssues>{};
    var errors = 0, warnings = 0;
    for (final i in validateWorkspace(w.workspace)) {
      final cur = perDoc[i.docId] ?? (errors: 0, warnings: 0);
      if (i.issue.severity == Severity.error) {
        perDoc[i.docId] = (errors: cur.errors + 1, warnings: cur.warnings);
        errors++;
      } else if (i.issue.severity == Severity.warning) {
        perDoc[i.docId] = (errors: cur.errors, warnings: cur.warnings + 1);
        warnings++;
      }
    }
    final ers = [for (final d in w.documents) if (d.type == DocType.er) d];
    final dfds = [for (final d in w.documents) if (d.type == DocType.dfd) d];
    final tables = ers.fold<int>(0, (a, d) => a + d.er!.tables.length);
    final objects = dfds.fold<int>(0, (a, d) => a + d.dfd!.nodes.length);
    final fcs = [for (final d in w.documents) if (d.type == DocType.flowchart) d];
    final symbols = fcs.fold<int>(0, (a, d) => a + d.flowchart!.nodes.length);
    final wfs = [for (final d in w.documents) if (d.type == DocType.wireframe) d];
    final sfs = [for (final d in w.documents) if (d.type == DocType.screenflow) d];
    final components = wfs.fold<int>(0, (a, d) => a + d.wireframe!.components.length);
    final screens = sfs.fold<int>(0, (a, d) => a + d.screenflow!.nodes.length);
    final path = w.filePath;
    final name = w.workspace.name.trim().isEmpty ? tr('(ไม่มีชื่อ)') : w.workspace.name;

    return Container(
      key: const ValueKey('project-home'),
      color: C.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.home_rounded, color: C.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                      key: const ValueKey('home-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(path ?? tr('ยังไม่ได้บันทึกเป็นไฟล์'),
                    key: const ValueKey('home-path'), style: TextStyle(fontSize: 12.5, color: C.muted)),
                if (w.dirty || path != null)
                  Text(
                    w.dirty ? tr('● ยังไม่ได้บันทึก') : tr('✓ บันทึกแล้ว'),
                    key: const ValueKey('home-dirty'),
                    style: TextStyle(fontSize: 12.5, color: w.dirty ? C.warnText : C.muted),
                  ),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _Action(const ValueKey('home-add-er'), Icons.table_chart_outlined, tr('เพิ่ม ER'), () => w.addDocument(DocType.er)),
                _Action(const ValueKey('home-add-dfd'), Icons.account_tree_outlined, tr('เพิ่ม DFD'), () => w.addDocument(DocType.dfd)),
                _Action(const ValueKey('home-add-flowchart'), Icons.schema_outlined, tr('เพิ่ม Flowchart'),
                    () => w.addDocument(DocType.flowchart)),
                _Action(const ValueKey('home-add-wireframe'), Icons.web_outlined, tr('เพิ่ม Wireframe'),
                    () => w.addDocument(DocType.wireframe)),
                _Action(const ValueKey('home-add-screenflow'), Icons.alt_route_rounded, tr('เพิ่ม Screen Flow'),
                    () => w.addDocument(DocType.screenflow)),
                _Action(const ValueKey('home-issues'), Icons.rule_rounded, tr('ปัญหาทั้งโปรเจกต์…'), () => showWorkspaceIssues(context)),
                _Action(const ValueKey('home-export'), Icons.ios_share_rounded, tr('Export เอกสารทั้งโปรเจกต์…'),
                    () => AppActions(context).run(Cmd.exportText)),
                _Action(const ValueKey('home-save'), Icons.save_outlined, tr('บันทึก'), () => AppActions(context).run(Cmd.save)),
              ]),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _Stat(const ValueKey('home-stat-docs'), tr('เอกสาร'), '${w.documents.length}'),
                _Stat(const ValueKey('home-stat-tables'), tr('ตาราง'), '$tables'),
                _Stat(const ValueKey('home-stat-objects'), tr('วัตถุ DFD'), '$objects'),
                if (fcs.isNotEmpty) _Stat(const ValueKey('home-stat-symbols'), tr('สัญลักษณ์ Flowchart'), '$symbols'),
                if (wfs.isNotEmpty) _Stat(const ValueKey('home-stat-components'), tr('ชิ้นส่วน Wireframe'), '$components'),
                if (sfs.isNotEmpty) _Stat(const ValueKey('home-stat-screens'), tr('หน้าจอใน Screen Flow'), '$screens'),
                _Stat(const ValueKey('home-stat-errors'), tr('ข้อผิดพลาด'), '$errors', color: errors > 0 ? C.danger : null),
                _Stat(const ValueKey('home-stat-warnings'), tr('คำเตือน'), '$warnings', color: warnings > 0 ? C.warnText : null),
              ]),
              _section(tr('แผนภาพ ER'), ers, perDoc, w),
              _section(tr('แผนภาพกระแสข้อมูล (DFD)'), dfds, perDoc, w),
              _section(tr('ผังงาน (Flowchart)'), fcs, perDoc, w),
              _section(tr('หน้าจอ (Wireframe)'), wfs, perDoc, w),
              _section(tr('ลำดับหน้าจอ (Screen Flow)'), sfs, perDoc, w),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _section(String label, List<ProjectDocument> docs, Map<String, _DocIssues> perDoc, WorkspaceController w) {
    if (docs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label (${docs.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final d in docs)
            _DocCard(doc: d, issues: perDoc[d.id] ?? (errors: 0, warnings: 0), onOpen: () => w.openDocument(d.id)),
        ]),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.k, this.icon, this.label, this.onTap);
  final Key k;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: k,
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.k, this.label, this.value, {this.color});
  final Key k;
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        key: k,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: C.surface,
          border: Border.all(color: C.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color ?? C.text)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12.5, color: C.muted)),
        ]),
      );
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, required this.issues, required this.onOpen});
  final ProjectDocument doc;
  final _DocIssues issues;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final er = doc.er;
    final dfd = doc.dfd;
    final fc = doc.flowchart;
    final String detail;
    if (er != null) {
      final cols = er.tables.fold<int>(0, (a, t) => a + t.columns.length);
      detail = tr('{0} ตาราง · {1} คอลัมน์ · {2} FK', [er.tables.length, cols, er.relations.length]);
    } else if (fc != null) {
      detail = tr('{0} สัญลักษณ์ · {1} เส้นเชื่อม', [fc.nodes.length, fc.edges.length]);
    } else if (doc.wireframe != null) {
      detail = wireframeSummary(doc.wireframe!);
    } else if (doc.screenflow != null) {
      detail = tr('{0} หน้าจอ · {1} การเปลี่ยนหน้า', [doc.screenflow!.nodes.length, doc.screenflow!.edges.length]);
    } else {
      detail = tr('{0} วัตถุ · {1} เส้นข้อมูล', [dfd!.nodes.length, dfd.flows.length]);
    }
    final total = issues.errors + issues.warnings;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Material(
        color: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: C.border)),
        child: InkWell(
          key: ValueKey('home-card-${doc.id}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(docTypeIcon(doc.type), size: 16, color: C.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 140),
                    child: Text(doc.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                if (total > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    key: ValueKey('home-issues-${doc.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: issues.errors > 0 ? C.danger.withValues(alpha: 0.15) : C.palette.warnBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$total',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: issues.errors > 0 ? C.danger : C.palette.warnText)),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: C.muted)),
              if (er != null) Text(er.dialect.label, style: TextStyle(fontSize: 12, color: C.muted)),
              if (doc.wireframe != null) ...[
                const SizedBox(height: 6),
                SizedBox(width: 220, child: WireframeThumbnail(diagram: doc.wireframe!, height: 80)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
