import 'package:flutter/material.dart';

import '../core/parser/sql_importer.dart';
import 'theme.dart';

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
      title: Text('นำเข้า $fileName'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            empty
                ? 'ไม่พบ CREATE TABLE ในไฟล์นี้'
                : 'พบ ${p.tables.length} ตาราง · $cols คอลัมน์ · ${p.relations.length} ความสัมพันธ์ FK\n'
                    'ตรวจพบ dialect: ${result.detected.label}',
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
          if (!empty) ...[
            const SizedBox(height: 6),
            const Text('การนำเข้าจะแทนที่โปรเจกต์ที่เปิดอยู่',
                style: TextStyle(fontSize: 12.5, color: C.muted)),
          ],
          if (warnings.isNotEmpty || infos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(warnings.isEmpty ? 'ข้อมูลเพิ่มเติม' : 'สิ่งที่ควรตรวจ (${warnings.length})',
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
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: empty ? null : () => Navigator.pop(context, true),
          child: const Text('นำเข้า'),
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
              n.line > 0 ? 'บรรทัด ${n.line}: ${n.message}' : n.message,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ]),
      );
}
