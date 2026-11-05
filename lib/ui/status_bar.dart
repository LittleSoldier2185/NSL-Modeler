import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/l10n/l10n.dart';
import '../core/storage/project_file.dart';
import '../core/models/diagram.dart';
import '../core/validate/dfd_validator.dart';
import '../core/validate/issue.dart';
import '../state/app_settings.dart';
import '../state/dfd_controller.dart';
import '../state/project_controller.dart';
import 'canvas/canvas_controller.dart';
import 'theme.dart';
import 'whats_new_dialog.dart';

/// แถบสถานะล่างสุดของหน้าต่าง (สูง [height] px): รุ่นของโปรแกรม + ปุ่ม patch note ทางซ้าย,
/// สรุปแผนภาพที่เปิดอยู่ ปัญหาที่ตรวจพบ ซูม และสถานะการบันทึกทางขวา
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  static const height = 24.0;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final settings = context.watch<AppSettings>();
    final isEr = c.activeDiagram.kind == DiagramKind.er;
    final dfd = context.watch<DfdController>();
    final cv = context.watch<CanvasController>();

    final p = c.project;
    // ชื่อไฟล์ที่เปิดอยู่ (ยังไม่บันทึก = ชื่อโปรเจกต์ + .nsld)
    final fileName = c.filePath == null ? '${p.name}.$kProjectExt' : c.filePath!.split(RegExp(r'[\\/]')).last;
    final String summary;
    final List<Issue> issues;
    final double zoom;
    if (isEr) {
      summary = tr('{0} ตาราง · {1} ความสัมพันธ์', [p.tables.length, p.relations.length]);
      issues = c.issues;
      zoom = cv.scale;
    } else {
      final d = c.dfdOf(c.activeDiagramId);
      summary = tr('{0} วัตถุ · {1} เส้นข้อมูล', [d.nodes.length, d.flows.length]);
      issues = validateDfd(d, workspace: c.workspace, diagramId: c.activeDiagramId);
      zoom = dfd.scale;
    }
    final errors = issues.where((i) => i.severity == Severity.error).length;
    final warnings = issues.where((i) => i.severity == Severity.warning).length;

    Widget sep() => Container(width: 1, height: 12, margin: const EdgeInsets.symmetric(horizontal: 10), color: C.border);
    final small = TextStyle(fontSize: 11.5, color: C.muted);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: C.surface, border: Border(top: BorderSide(color: C.border))),
      child: Row(children: [
        // ---- ซ้าย: รุ่น + มีอะไรใหม่ ----
        Icon(Icons.auto_awesome_rounded, size: 12, color: C.primary),
        const SizedBox(width: 5),
        Text(appVersionLabel, key: const ValueKey('status-version'), style: small.copyWith(fontWeight: FontWeight.w600, color: C.text)),
        sep(),
        InkWell(
          key: const ValueKey('status-whats-new'),
          borderRadius: BorderRadius.circular(4),
          onTap: () => showWhatsNew(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('มีอะไรใหม่'), style: small.copyWith(color: C.primaryDark)),
              if (settings.hasUnseenNotes(kAppVersion)) ...[
                const SizedBox(width: 5),
                Container(
                  key: const ValueKey('status-unseen-dot'),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: C.warnText, shape: BoxShape.circle),
                ),
              ],
            ]),
          ),
        ),
        const Spacer(),
        // ---- ขวา ----
        Flexible(
          child: Text(
            '$fileName · ${c.activeDiagram.name} · $summary',
            key: const ValueKey('status-summary'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small,
          ),
        ),
        sep(),
        _IssueBadge(errors: errors, warnings: warnings, onTap: isEr ? () => cv.showDock(DockTab.issues) : null),
        sep(),
        Text('${(zoom * 100).round()}%', key: const ValueKey('status-zoom'), style: small),
        if (c.dirty) ...[
          sep(),
          Text(tr('● ยังไม่ได้บันทึก'), key: const ValueKey('status-dirty'), style: small),
        ] else if (c.filePath != null) ...[
          sep(),
          Text(tr('✓ บันทึกแล้ว'), key: const ValueKey('status-saved'), style: small),
        ],
      ]),
    );
  }
}

class _IssueBadge extends StatelessWidget {
  const _IssueBadge({required this.errors, required this.warnings, this.onTap});
  final int errors, warnings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ok = errors == 0 && warnings == 0;
    final color = errors > 0 ? C.danger : (warnings > 0 ? C.warnText : C.primaryDark);
    final text = ok ? tr('ไม่พบปัญหา') : tr('{0} ข้อผิดพลาด · {1} คำเตือน', [errors, warnings]);
    return InkWell(
      key: const ValueKey('status-issues'),
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ok ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11.5, color: color)),
        ]),
      ),
    );
  }
}
