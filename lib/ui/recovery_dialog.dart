import 'package:flutter/material.dart';

import '../core/models/workspace.dart';
import '../core/storage/autosave.dart';
import 'theme.dart';
import '../core/l10n/l10n.dart';

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
    final w = info.workspace;
    final ers = [for (final d in w.documentsOf(DocType.er)) d.er!];
    final cols = ers.fold<int>(0, (s, p) => s + p.tables.fold<int>(0, (s, t) => s + t.columns.length));
    return AlertDialog(
      title: Text(tr('พบงานที่ยังไม่ได้บันทึก')),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('โปรแกรมปิดไปก่อนที่จะบันทึกงานครั้งก่อน ต้องการกู้คืนหรือไม่'),
              style: TextStyle(height: 1.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _row(tr('โปรเจกต์'), w.name),
              _row(tr('เนื้อหา'), tr('{0} ตาราง · {1} คอลัมน์ · {2} FK', [w.tableCount, cols, w.relationCount])),
              _row(tr('บันทึกอัตโนมัติเมื่อ'), formatDateTime(info.savedAt)),
              _row(tr('ไฟล์เดิม'), info.originalPath ?? tr('(ยังไม่เคยบันทึกเป็นไฟล์)')),
            ]),
          ),
          const SizedBox(height: 10),
          Text(tr('ถ้าเลือก "ทิ้ง" สำเนานี้จะถูกลบถาวร'),
              style: TextStyle(fontSize: 12.5, color: C.muted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('ทิ้ง'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('กู้คืน'))),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(fontSize: 12.5, color: C.muted))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
}
