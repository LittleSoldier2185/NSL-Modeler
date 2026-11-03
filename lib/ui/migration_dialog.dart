import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/diff/migration.dart';
import '../core/diff/schema_diff.dart';
import '../core/models/project.dart';
import 'file_actions.dart';
import 'sql_view.dart';
import 'theme.dart';

/// เทียบโครงสร้าง [old] (ไฟล์เก่า) กับ [neu] (โปรเจกต์ปัจจุบัน) แล้วแสดงรายการเปลี่ยนแปลง + สคริปต์ migration
class MigrationDialog extends StatefulWidget {
  const MigrationDialog({super.key, required this.old, required this.neu, required this.oldLabel});
  final Project old;
  final Project neu;
  final String oldLabel;

  @override
  State<MigrationDialog> createState() => _MigrationDialogState();
}

class _MigrationDialogState extends State<MigrationDialog> {
  late final SchemaDiff diff = diffProjects(widget.old, widget.neu);
  late final List<ChangeLine> lines = diff.summary(widget.old, widget.neu);
  late final String script = generateMigration(widget.old, widget.neu, diff: diff);
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: script));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final risky = lines.where((l) => l.destructive).length;
    final d = widget.neu.dialect;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Migration: ${widget.oldLabel} → โปรเจกต์ปัจจุบัน',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              diff.isEmpty
                  ? 'โครงสร้างเหมือนกัน ไม่ต้อง migrate'
                  : '${lines.length} การเปลี่ยนแปลง · สร้างสคริปต์สำหรับ ${d.label}'
                      '${widget.old.dialect != d ? ' (ไฟล์เก่าใช้ ${widget.old.dialect.label})' : ''}',
              style: const TextStyle(fontSize: 12.5, color: C.muted),
            ),
            if (risky > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(7)),
                child: Text('⚠ $risky รายการอาจทำให้ข้อมูลหาย — สำรองฐานข้อมูลก่อนรันสคริปต์',
                    style: const TextStyle(fontSize: 12.5, color: C.warnText)),
              ),
            ],
            const SizedBox(height: 12),
            if (!diff.isEmpty)
              Flexible(
                child: SizedBox(
                  height: 440,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(width: 330, child: _changeList()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ColoredBox(
                          color: const Color(0xFF0F172A),
                          child: SqlCodeView(lines: SqlCodeView.splitLines(script)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (!diff.isEmpty) ...[
                OutlinedButton(
                  onPressed: _copy,
                  child: Text(_copied ? 'คัดลอกแล้ว ✓' : 'คัดลอกสคริปต์'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => FileActions.saveMigration(context, script, widget.neu),
                  child: const Text('บันทึกเป็น .sql'),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด')),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _changeList() => Container(
        decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(8)),
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: lines.length,
          itemBuilder: (_, i) {
            final l = lines[i];
            final (icon, color) = switch (l.kind) {
              ChangeKind.add => (Icons.add_circle_outline, C.primaryDark),
              ChangeKind.drop => (Icons.remove_circle_outline, const Color(0xFFB42318)),
              ChangeKind.change => (Icons.edit_outlined, C.infoText),
            };
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(l.text,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: l.destructive ? const Color(0xFFB42318) : C.text,
                          fontWeight: l.destructive ? FontWeight.w600 : FontWeight.w400)),
                ),
              ]),
            );
          },
        ),
      );
}
