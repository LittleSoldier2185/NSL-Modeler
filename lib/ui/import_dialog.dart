import 'package:flutter/material.dart';

import '../core/parser/sql_importer.dart';
import 'theme.dart';
import '../core/l10n/l10n.dart';

/// พรีวิวผลการ import: จำนวนที่อ่านได้ + รายการที่ข้าม/ไม่แน่ใจ ก่อนยืนยันแทนที่โปรเจกต์
/// คืน true เมื่อผู้ใช้กด "นำเข้า"
class ImportPreviewDialog extends StatelessWidget {
  const ImportPreviewDialog({super.key, required this.result, required this.fileName});
  final ImportResult result;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final p = result.project;
    final cols = p.tables.fold<int>(0, (s, t) => s + t.columns.length);
    final warnings = result.notes.where((n) => n.warning).toList();
    final infos = result.notes.where((n) => !n.warning).toList();
    final empty = p.tables.isEmpty;

    return AlertDialog(
      title: Text(tr('นำเข้า {0}', [fileName])),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            empty
                ? tr('ไม่พบ CREATE TABLE ในไฟล์นี้')
                : tr('พบ {0} ตาราง · {1} คอลัมน์ · {2} ความสัมพันธ์ FK\nตรวจพบ dialect: {3}',
                    [p.tables.length, cols, p.relations.length, result.detected.label]),
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
          if (!empty) ...[
            const SizedBox(height: 6),
            Text(tr('การนำเข้าจะแทนที่โปรเจกต์ที่เปิดอยู่'),
                style: TextStyle(fontSize: 12.5, color: C.muted)),
          ],
          if (warnings.isNotEmpty || infos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(warnings.isEmpty ? tr('ข้อมูลเพิ่มเติม') : tr('สิ่งที่ควรตรวจ ({0})', [warnings.length]),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: C.field,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(10),
                  children: [
                    for (final n in warnings) _line(n, C.warnText, Icons.warning_amber_rounded),
                    for (final n in infos) _line(n, C.muted, Icons.info_outline),
                  ],
                ),
              ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('ยกเลิก'))),
        FilledButton(
          onPressed: empty ? null : () => Navigator.pop(context, true),
          child: Text(tr('นำเข้า')),
        ),
      ],
    );
  }

  Widget _line(ImportNote n, Color color, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              n.line > 0 ? tr('บรรทัด {0}: {1}', [n.line, n.message]) : n.message,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ]),
      );
}
