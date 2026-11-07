import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../core/validate/issue.dart';
import '../core/validate/workspace_validator.dart';
import '../state/workspace_controller.dart';
import 'canvas/context_menu.dart';
import 'document_actions.dart';
import 'theme.dart';

/// Project Explorer: รายการเอกสารทั้งโปรเจกต์จัดกลุ่มตามชนิด (ER / DFD) ตามลำดับในไฟล์ — วางเหนือแผงซ้าย
/// คลิก = เปิด ; ดับเบิลคลิก/F2 = เปลี่ยนชื่อ ; คลิกขวา = เปลี่ยนชื่อ·ทำสำเนา·ลบ ; ปุ่ม + = สร้างแผนภาพใหม่
class ProjectExplorer extends StatefulWidget {
  const ProjectExplorer({super.key, this.maxHeight = 260});

  /// ความสูงสูงสุดของแผง (เกินนี้เลื่อนดูได้)
  final double maxHeight;

  @override
  State<ProjectExplorer> createState() => _ProjectExplorerState();
}

class _ProjectExplorerState extends State<ProjectExplorer> {
  final _collapsed = <DocType>{};

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final issues = <String, (int, int)>{}; // docId -> (errors, warnings)
    for (final i in validateWorkspace(w.workspace)) {
      final cur = issues[i.docId] ?? (0, 0);
      if (i.issue.severity == Severity.error) {
        issues[i.docId] = (cur.$1 + 1, cur.$2);
      } else if (i.issue.severity == Severity.warning) {
        issues[i.docId] = (cur.$1, cur.$2 + 1);
      }
    }
    final groups = <(DocType, String)>[
      (DocType.er, tr('แผนภาพ ER')),
      (DocType.dfd, tr('แผนภาพกระแสข้อมูล (DFD)')),
    ];
    return Container(
      key: const ValueKey('project-explorer'),
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(right: BorderSide(color: C.border), bottom: BorderSide(color: C.border)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
          child: Row(children: [
            Expanded(
              child: Text(
                tr('ตัวสำรวจโปรเจกต์'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            IconButton(
              key: const ValueKey('explorer-home'),
              tooltip: tr('หน้า Project Home'),
              style: IconButton.styleFrom(
                minimumSize: const Size(28, 28),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.home_outlined, size: 18, color: w.homeView ? C.primary : C.muted),
              onPressed: () => w.showHome(),
            ),
            PopupMenuButton<DocType>(
              key: const ValueKey('explorer-add'),
              tooltip: tr('สร้างแผนภาพใหม่'),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                minimumSize: const Size(28, 28),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.add_rounded, size: 18, color: C.muted),
              onSelected: (k) => w.addDocument(k),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: DocType.er,
                  height: 36,
                  child: Text(tr('ER Diagram (ตารางฐานข้อมูล)'), style: const TextStyle(fontSize: 13)),
                ),
                PopupMenuItem(
                  value: DocType.dfd,
                  height: 36,
                  child: Text(tr('DFD (Data Flow Diagram)'), style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ]),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 6),
            children: [
              for (final (type, label) in groups) ..._group(w, type, label, issues),
            ],
          ),
        ),
      ]),
    );
  }

  List<Widget> _group(WorkspaceController w, DocType type, String label, Map<String, (int, int)> issues) {
    final docs = [for (final d in w.documents) if (d.type == type) d];
    if (docs.isEmpty) return const [];
    final open = !_collapsed.contains(type);
    return [
      InkWell(
        key: ValueKey('explorer-group-${type.name}'),
        onTap: () => setState(() => open ? _collapsed.add(type) : _collapsed.remove(type)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(children: [
            Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 16, color: C.muted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$label (${docs.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ),
      if (open)
        for (final d in docs)
          _ExplorerRow(
            key: ValueKey('explorer-row-${d.id}'),
            doc: d,
            active: d.id == w.activeId,
            issueCount: issues[d.id] ?? (0, 0),
          ),
    ];
  }
}

class _ExplorerRow extends StatefulWidget {
  const _ExplorerRow({super.key, required this.doc, required this.active, required this.issueCount});
  final ProjectDocument doc;
  final bool active;
  final (int, int) issueCount;

  @override
  State<_ExplorerRow> createState() => _ExplorerRowState();
}

class _ExplorerRowState extends State<_ExplorerRow> {
  final _focus = FocusNode(debugLabel: 'explorer-row');
  bool _hover = false;
  DateTime? _lastTap;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _open() {
    _focus.requestFocus();
    context.read<WorkspaceController>().openDocument(widget.doc.id);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final d = widget.doc;
    final (errors, warnings) = widget.issueCount;
    final total = errors + warnings;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.f2) {
          renameDocumentDialog(context, d.id);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // ดับเบิลคลิกจับเวลาเอง (ใช้ onDoubleTap จะหน่วงการเปิดเอกสารตอนคลิกเดียว)
          onTap: () {
            _open();
            final now = clock.now();
            final last = _lastTap;
            _lastTap = now;
            if (last != null && now.difference(last) < const Duration(milliseconds: 400)) {
              _lastTap = null;
              renameDocumentDialog(context, d.id);
            }
          },
          onSecondaryTapDown: (e) {
            _open();
            showContextMenu(context, e.globalPosition, [
              MenuSpec(tr('เปลี่ยนชื่อ…'), Icons.drive_file_rename_outline, () => renameDocumentDialog(context, d.id),
                  shortcut: 'F2'),
              MenuSpec(tr('ทำสำเนาแผนภาพ'), Icons.copy_rounded, () => w.duplicateDocument(d.id)),
              if (w.canDeleteDocument(d.id))
                MenuSpec(tr('ลบแผนภาพ'), Icons.delete_outline, () => deleteDocumentDialog(context, d.id), danger: true),
            ]);
          },
          child: Container(
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.only(left: 22, right: 6),
            decoration: BoxDecoration(
              color: widget.active
                  ? C.primary.withValues(alpha: 0.14)
                  : (_hover ? C.text.withValues(alpha: 0.05) : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Icon(
                d.type == DocType.er ? Icons.table_chart_outlined : Icons.account_tree_outlined,
                size: 14,
                color: widget.active ? C.primary : C.muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                    color: widget.active ? C.text : C.muted,
                  ),
                ),
              ),
              if (total > 0)
                Tooltip(
                  message: tr('ปัญหา {0} รายการ', [total]),
                  child: Container(
                    key: ValueKey('explorer-issues-${d.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: errors > 0 ? C.danger.withValues(alpha: 0.15) : C.palette.warnBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$total',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: errors > 0 ? C.danger : C.palette.warnText,
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
