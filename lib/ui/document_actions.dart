import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/doc_ref.dart';
import '../core/models/workspace.dart';
import '../state/workspace_controller.dart';
import 'prompt_dialog.dart';
import 'theme.dart';

/// ไอคอนประจำชนิดเอกสาร (แท็บ / ตัวสำรวจ / Project Home / หน้าต่างปัญหา)
IconData docTypeIcon(DocType? t) => switch (t) {
      DocType.er => Icons.table_chart_outlined,
      DocType.flowchart => Icons.schema_outlined,
      _ => Icons.account_tree_outlined,
    };

/// กล่องเปลี่ยนชื่อเอกสาร (ใช้ร่วมกันระหว่างแท็บแผนภาพและ Project Explorer): ชื่อว่าง/ซ้ำ = แจ้งเตือนและไม่เปลี่ยน
Future<void> renameDocumentDialog(BuildContext context, String docId) async {
  final c = context.read<WorkspaceController>();
  final doc = c.documentById(docId);
  if (doc == null) return;
  final r = await showDialog<PromptResult>(
    context: context,
    builder: (_) => TextPromptDialog(
      title: tr('เปลี่ยนชื่อแผนภาพ'),
      initial: doc.name,
      label: tr('ชื่อ'),
    ),
  );
  if (r == null || !context.mounted) return;
  if (!c.renameDocument(docId, r.text)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('ชื่อว่างหรือซ้ำกับแผนภาพอื่น'))),
    );
  }
}

/// กล่องยืนยันลบเอกสาร (แสดงลิงก์ข้ามเอกสารที่จะขาด) แล้วลบถ้ายืนยัน ; ลบไม่ได้ (ER อันสุดท้าย) = ไม่ทำอะไร
Future<void> deleteDocumentDialog(BuildContext context, String docId) async {
  final c = context.read<WorkspaceController>();
  final doc = c.documentById(docId);
  if (doc == null || !c.canDeleteDocument(docId)) return;
  final broken = brokenLinkLines(c, docId);
  const maxLines = 8;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('ลบแผนภาพ "{0}"', [doc.name])),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('เนื้อหาในแผนภาพนี้จะหายไปและย้อนกลับด้วย Ctrl+Z ไม่ได้')),
            if (broken.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                tr('ลิงก์จากแผนภาพอื่น {0} รายการจะใช้ไม่ได้:', [broken.length]),
                key: const ValueKey('delete-broken-links'),
                style: TextStyle(color: C.danger, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              for (final line in broken.take(maxLines))
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text('• $line', style: const TextStyle(fontSize: 12.5)),
                ),
              if (broken.length > maxLines)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    tr('และอีก {0} รายการ', [broken.length - maxLines]),
                    style: TextStyle(fontSize: 12.5, color: C.muted),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('ยกเลิก')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('ลบ')),
        ),
      ],
    ),
  );
  if (ok == true) c.deleteDocument(docId);
}

/// รายการลิงก์จากเอกสารอื่นที่จะใช้ไม่ได้ถ้าลบเอกสาร [docId] (ข้อความหนึ่งบรรทัดต่อหนึ่งลิงก์ ใช้ในกล่องยืนยันการลบ)
List<String> brokenLinkLines(WorkspaceController c, String docId) {
  final target = c.documentById(docId);
  final out = <String>[];
  for (final (fromDoc, fromElement, ref) in c.backlinksOf(docId)) {
    final src = c.documentById(fromDoc);
    final node = src?.dfd?.nodeById(fromElement);
    final from = '${src?.name ?? fromDoc} · ${node == null || node.title.isEmpty ? tr('(ไม่มีชื่อ)') : node.title}';
    out.add(switch (ref.kind) {
      DocRefKind.storeTable => tr('{0} → ตาราง {1}', [
          from,
          target?.er?.tableById(ref.elementId ?? '')?.name ?? ref.elementId ?? '?',
        ]),
      DocRefKind.dfdChild => tr('{0} → แผนภาพย่อย', [from]),
    });
  }
  return out;
}
