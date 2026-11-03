import 'package:flutter/material.dart';

import '../core/storage/autosave.dart';
import 'theme.dart';

String formatDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// ถามว่าจะกู้คืนงานที่ค้างจากครั้งก่อนหรือไม่ — คืน true = กู้คืน, false = ทิ้ง
class RecoveryDialog extends StatelessWidget {
  const RecoveryDialog({super.key, required this.info});
  final AutosaveInfo info;

  @override
  Widget build(BuildContext context) {
    final p = info.project;
    final cols = p.tables.fold<int>(0, (s, t) => s + t.columns.length);
    return AlertDialog(
      title: const Text('พบงานที่ยังไม่ได้บันทึก'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('โปรแกรมปิดไปก่อนที่จะบันทึกงานครั้งก่อน ต้องการกู้คืนหรือไม่',
              style: TextStyle(height: 1.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _row('โปรเจกต์', p.name),
              _row('เนื้อหา', '${p.tables.length} ตาราง · $cols คอลัมน์ · ${p.relations.length} FK'),
              _row('บันทึกอัตโนมัติเมื่อ', formatDateTime(info.savedAt)),
              _row('ไฟล์เดิม', info.originalPath ?? '(ยังไม่เคยบันทึกเป็นไฟล์)'),
            ]),
          ),
          const SizedBox(height: 10),
          const Text('ถ้าเลือก "ทิ้ง" สำเนานี้จะถูกลบถาวร',
              style: TextStyle(fontSize: 12.5, color: C.muted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ทิ้ง')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('กู้คืน')),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(fontSize: 12.5, color: C.muted))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
}
