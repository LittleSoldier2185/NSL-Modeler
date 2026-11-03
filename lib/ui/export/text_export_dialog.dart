import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/export/diagram_text_export.dart';
import '../../core/export/markdown_export.dart';
import '../../core/export/sample_data.dart';
import '../../core/models/project.dart';
import '../file_actions.dart';
import '../sql_view.dart';
import '../theme.dart';

enum TextExportKind { dictionary, mermaid, dbml, sample }

extension on TextExportKind {
  String get label => switch (this) {
        TextExportKind.dictionary => 'Data dictionary',
        TextExportKind.mermaid => 'Mermaid',
        TextExportKind.dbml => 'DBML',
        TextExportKind.sample => 'ข้อมูลตัวอย่าง',
      };

  String get hint => switch (this) {
        TextExportKind.dictionary => 'เอกสาร Markdown อธิบายตาราง/คอลัมน์/ความสัมพันธ์ ใช้ส่งงานหรือแปะ README',
        TextExportKind.mermaid => 'แปะในบล็อก ```mermaid ของ GitHub / GitLab / Notion เพื่อแสดงแผนภาพ ER',
        TextExportKind.dbml => 'นำเข้า dbdiagram.io หรือเครื่องมือที่รองรับ DBML',
        TextExportKind.sample => 'INSERT ข้อมูลสุ่มไว้ทดสอบ ตามตัวเลือก dialect ปัจจุบัน (ตารางแม่ก่อนลูก, FK ถูกต้อง)',
      };
}

/// Export ข้อความ 4 แบบ: Data dictionary (Markdown) / Mermaid / DBML / INSERT ข้อมูลตัวอย่าง
class TextExportDialog extends StatefulWidget {
  const TextExportDialog({super.key, required this.project, this.initial = TextExportKind.dictionary});
  final Project project;
  final TextExportKind initial;

  @override
  State<TextExportDialog> createState() => _TextExportDialogState();
}

class _TextExportDialogState extends State<TextExportDialog> {
  late TextExportKind _kind = widget.initial;
  int _rows = 10;
  bool _copied = false;
  Timer? _timer;

  static const rowChoices = [5, 10, 25, 50, 100];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get text {
    final p = widget.project;
    return switch (_kind) {
      TextExportKind.dictionary => exportDataDictionary(p),
      TextExportKind.mermaid => exportMermaid(p),
      TextExportKind.dbml => exportDbml(p),
      TextExportKind.sample => exportSampleData(p, rows: _rows),
    };
  }

  String get fileName {
    final base = FileActions.safeName(widget.project.name);
    return switch (_kind) {
      TextExportKind.dictionary => '${base}_dictionary.md',
      TextExportKind.mermaid => '$base.mmd',
      TextExportKind.dbml => '$base.dbml',
      TextExportKind.sample => '${base}_sample_${widget.project.dialect.name}.sql',
    };
  }

  Future<void> _copy(String t) async {
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = text;
    final lines = SqlCodeView.splitLines(t);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Export เอกสาร / ข้อมูล', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SegmentedButton<TextExportKind>(
              showSelectedIcon: false,
              segments: [
                for (final k in TextExportKind.values) ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(_kind.hint, style: const TextStyle(fontSize: 12.5, color: C.muted))),
              if (_kind == TextExportKind.sample) ...[
                const SizedBox(width: 12),
                const Text('แถวต่อตาราง', style: TextStyle(fontSize: 12.5, color: C.muted)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _rows,
                  isDense: true,
                  items: [for (final n in rowChoices) DropdownMenuItem(value: n, child: Text('$n'))],
                  onChanged: (v) => setState(() => _rows = v ?? _rows),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            Flexible(
              child: SizedBox(
                height: 420,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: const Color(0xFF0F172A),
                    child: SqlCodeView(lines: lines, highlight: _kind == TextExportKind.sample),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => _copy(t), child: Text(_copied ? 'คัดลอกแล้ว ✓' : 'คัดลอก')),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => FileActions.saveText(context, t, fileName, 'บันทึก ${_kind.label}'),
                child: const Text('บันทึกเป็นไฟล์'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด')),
            ]),
          ]),
        ),
      ),
    );
  }
}
