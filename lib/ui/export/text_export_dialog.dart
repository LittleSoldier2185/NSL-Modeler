import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/export/diagram_text_export.dart';
import '../../core/export/markdown_export.dart';
import '../../core/export/html_doc_export.dart';
import '../../core/export/sample_data.dart';
import '../../core/export/sql_export.dart';
import '../../core/models/project.dart';
import '../../core/models/workspace.dart';
import '../file_actions.dart';
import '../sql_view.dart';
import '../theme.dart';
import '../../core/l10n/l10n.dart';

enum TextExportKind { dictionary, mermaid, dbml, sample, html, sqlAll }

extension on TextExportKind {
  String get label => switch (this) {
        TextExportKind.dictionary => 'Data dictionary',
        TextExportKind.mermaid => 'Mermaid',
        TextExportKind.dbml => 'DBML',
        TextExportKind.sample => tr('ข้อมูลตัวอย่าง'),
        TextExportKind.html => 'HTML',
        TextExportKind.sqlAll => tr('SQL ทั้งโปรเจกต์'),
      };

  /// ใช้ข้อมูลของ ER ที่เปิดอยู่ ER เดียว (ต่างจากแบบทั้งโปรเจกต์)
  bool get perEr => this == TextExportKind.mermaid || this == TextExportKind.dbml || this == TextExportKind.sample;

  String get hint => switch (this) {
        TextExportKind.dictionary => tr('เอกสาร Markdown อธิบายตาราง/คอลัมน์/ความสัมพันธ์ ใช้ส่งงานหรือแปะ README'),
        TextExportKind.mermaid => tr('แปะในบล็อก ```mermaid ของ GitHub / GitLab / Notion เพื่อแสดงแผนภาพ ER'),
        TextExportKind.dbml => tr('นำเข้า dbdiagram.io หรือเครื่องมือที่รองรับ DBML'),
        TextExportKind.sample => tr('INSERT ข้อมูลสุ่มไว้ทดสอบ ตามตัวเลือก dialect ปัจจุบัน (ตารางแม่ก่อนลูก, FK ถูกต้อง)'),
        TextExportKind.html => tr('เอกสาร HTML ไฟล์เดียวทั้งโปรเจกต์ (ภาพแผนภาพ ER/DFD ฝังในไฟล์ พิมพ์เป็น PDF ได้) — ตัวอย่างแสดงเฉพาะส่วนต้น'),
        TextExportKind.sqlAll => tr('SQL ของทุก ER รวมเป็นไฟล์เดียว แยกหัวคอมเมนต์ต่อ ER และใช้ dialect ของแต่ละ ER (ไม่รวมข้อมูลตั้งต้น)'),
      };
}

/// Export ข้อความ 4 แบบ: Data dictionary (Markdown) / Mermaid / DBML / INSERT ข้อมูลตัวอย่าง
class TextExportDialog extends StatefulWidget {
  const TextExportDialog({super.key, required this.project, this.workspace, this.erName, this.initial = TextExportKind.dictionary});

  /// ER ที่ใช้กับ Mermaid / DBML / ข้อมูลตัวอย่าง (ER ที่เปิดอยู่)
  final Project project;

  /// ทั้งโปรเจกต์ (Data dictionary / HTML / SQL ทั้งโปรเจกต์) — null = มีเฉพาะ [project] ER เดียว
  final Workspace? workspace;

  /// ชื่อเอกสารของ [project] (แสดงเมื่อโปรเจกต์มีหลาย ER)
  final String? erName;
  final TextExportKind initial;

  @override
  State<TextExportDialog> createState() => _TextExportDialogState();
}

class _TextExportDialogState extends State<TextExportDialog> {
  late TextExportKind _kind = widget.initial;
  int _rows = 10;
  bool _copied = false;
  Timer? _timer;
  final _cache = <TextExportKind, String>{};

  Workspace get _ws => widget.workspace ?? Workspace.single(widget.project);

  static const rowChoices = [5, 10, 25, 50, 100];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get text {
    final p = widget.project;
    return switch (_kind) {
      TextExportKind.dictionary => exportWorkspaceDictionary(_ws),
      TextExportKind.html => _cache.putIfAbsent(_kind, () => exportHtmlDocument(_ws)),
      TextExportKind.sqlAll => _cache.putIfAbsent(_kind, () => buildWorkspaceSql(_ws)),
      TextExportKind.mermaid => exportMermaid(p),
      TextExportKind.dbml => exportDbml(p),
      TextExportKind.sample => exportSampleData(p, rows: _rows),
    };
  }

  String get fileName {
    final base = FileActions.safeName(_kind.perEr ? widget.project.name : _ws.name);
    return switch (_kind) {
      TextExportKind.dictionary => '${base}_dictionary.md',
      TextExportKind.html => '$base.html',
      TextExportKind.sqlAll => '${base}_all.sql',
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
    // HTML ยาวมาก (SVG ฝัง) : ตัวอย่างแสดงแค่ส่วนต้น แต่คัดลอก/บันทึกได้ครบ
    final preview = _kind == TextExportKind.html ? t.split(RegExp(r'\r?\n')).take(200).join('\n') : t;
    final lines = SqlCodeView.splitLines(preview);
    final multiEr = _ws.documentsOf(DocType.er).length > 1;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Export เอกสาร / ข้อมูล'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
              Expanded(
                child: Text(
                  [
                    _kind.hint,
                    if (multiEr && _kind.perEr && widget.erName != null) tr('ใช้เฉพาะ ER: {0}', [widget.erName]),
                  ].join('  ·  '),
                  key: const ValueKey('export-hint'),
                  style: TextStyle(fontSize: 12.5, color: C.muted),
                ),
              ),
              if (_kind == TextExportKind.sample) ...[
                const SizedBox(width: 12),
                Text(tr('แถวต่อตาราง'), style: TextStyle(fontSize: 12.5, color: C.muted)),
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
                    child: SqlCodeView(lines: lines, highlight: _kind == TextExportKind.sample || _kind == TextExportKind.sqlAll),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => _copy(t), child: Text(_copied ? tr('คัดลอกแล้ว ✓') : tr('คัดลอก'))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => FileActions.saveText(context, t, fileName, tr('บันทึก {0}', [_kind.label])),
                child: Text(tr('บันทึกเป็นไฟล์')),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('ปิด'))),
            ]),
          ]),
        ),
      ),
    );
  }
}
