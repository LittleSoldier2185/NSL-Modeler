import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/diff/migration.dart';
import '../core/diff/schema_diff.dart';
import '../core/models/project.dart';
import 'file_actions.dart';
import 'sql_view.dart';
import 'theme.dart';
import '../core/l10n/l10n.dart';

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

  /// ถ้าสคริปต์มีรายการที่ข้อมูลอาจหาย ต้องให้ผู้ใช้ยืนยัน (ติ๊กว่าสำรองแล้ว) ก่อนคัดลอก/บันทึก
  Future<bool> _confirmRisky() async {
    final risky = lines.where((l) => l.destructive).toList();
    if (risky.isEmpty) return true;
    final ok = await showDialog<bool>(context: context, builder: (_) => _RiskyConfirmDialog(risky: risky));
    return ok == true && mounted;
  }

  Future<void> _save() async {
    if (!await _confirmRisky()) return;
    if (mounted) await FileActions.saveMigration(context, script, widget.neu);
  }

  Future<void> _copy() async {
    if (!await _confirmRisky()) return;
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
            Text(tr('Migration: {0} → โปรเจกต์ปัจจุบัน', [widget.oldLabel]),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              diff.isEmpty
                  ? tr('โครงสร้างเหมือนกัน ไม่ต้อง migrate')
                  : tr('{0} การเปลี่ยนแปลง · สร้างสคริปต์สำหรับ {1}{2}', [lines.length, d.label, widget.old.dialect != d ? tr(' (ไฟล์เก่าใช้ {0})', [widget.old.dialect.label]) : '']),
              style: TextStyle(fontSize: 12.5, color: C.muted),
            ),
            if (risky > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(7)),
                child: Text(tr('⚠ {0} รายการอาจทำให้ข้อมูลหาย — สำรองฐานข้อมูลก่อนรันสคริปต์', [risky]),
                    style: TextStyle(fontSize: 12.5, color: C.warnText)),
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
                  child: Text(_copied ? tr('คัดลอกแล้ว ✓') : tr('คัดลอกสคริปต์')),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _save,
                  child: Text(tr('บันทึกเป็น .sql')),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('ปิด'))),
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
              ChangeKind.drop => (Icons.remove_circle_outline, C.danger),
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
                          color: l.destructive ? C.danger : C.text,
                          fontWeight: l.destructive ? FontWeight.w600 : FontWeight.w400)),
                ),
              ]),
            );
          },
        ),
      );
}

/// ยืนยันก่อนนำสคริปต์ที่อาจทำให้ข้อมูลหายไปใช้: ต้องติ๊กว่าสำรองข้อมูลแล้ว จึงกดดำเนินการต่อได้
class _RiskyConfirmDialog extends StatefulWidget {
  const _RiskyConfirmDialog({required this.risky});
  final List<ChangeLine> risky;

  @override
  State<_RiskyConfirmDialog> createState() => _RiskyConfirmDialogState();
}

class _RiskyConfirmDialogState extends State<_RiskyConfirmDialog> {
  bool _ack = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('สคริปต์นี้อาจทำให้ข้อมูลหาย')),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('รายการต่อไปนี้ลบหรือเปลี่ยนข้อมูลที่มีอยู่ในฐานข้อมูล:'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final l in widget.risky)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('• ${l.text}', style: TextStyle(fontSize: 12.5, color: C.danger)),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('risky-ack'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _ack,
              onChanged: (v) => setState(() => _ack = v ?? false),
              title: Text(tr('ฉันสำรองฐานข้อมูลแล้ว และเข้าใจว่าข้อมูลอาจหาย'), style: const TextStyle(fontSize: 13)),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('ยกเลิก'))),
          FilledButton(
            key: const ValueKey('risky-continue'),
            onPressed: _ack ? () => Navigator.pop(context, true) : null,
            child: Text(tr('ดำเนินการต่อ')),
          ),
        ],
      );
}
