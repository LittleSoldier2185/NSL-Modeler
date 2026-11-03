import 'package:flutter/material.dart';

import '../theme.dart';
import '../../core/l10n/l10n.dart';

enum ImageFormat { png, svg }

/// พื้นที่ที่จะส่งออก
enum ImageArea {
  /// เฉพาะส่วนที่มีตาราง/โน้ต (ตัดพื้นที่ว่างรอบนอกออก)
  content,

  /// ทั้งกรอบกระดาน รวมพื้นที่ว่าง
  board,

  /// เฉพาะตารางที่เลือกอยู่
  selection,
}

class ImageExportOptions {
  const ImageExportOptions(this.format, this.scale, this.includeNotes, {this.area = ImageArea.content, this.dark = false});
  final ImageFormat format;

  /// ภาพธีมมืด (ไม่ขึ้นกับธีมของแอป)
  final bool dark;
  final double scale;
  final bool includeNotes;
  final ImageArea area;
}

/// เลือกรูปแบบภาพที่จะ export (PNG พร้อมสเกล หรือ SVG) — คืน null ถ้ายกเลิก
class ExportImageDialog extends StatefulWidget {
  const ExportImageDialog({super.key, required this.hasNotes, this.hasSelection = false, this.initialArea});
  final bool hasNotes;

  /// มีตารางที่เลือกอยู่ -> เปิดตัวเลือก "เฉพาะตารางที่เลือก"
  final bool hasSelection;

  /// พื้นที่ที่เลือกไว้ตอนเปิด (เช่นมาจากเมนูคลิกขวา "Export เฉพาะตารางที่เลือก")
  final ImageArea? initialArea;

  @override
  State<ExportImageDialog> createState() => _ExportImageDialogState();
}

class _ExportImageDialogState extends State<ExportImageDialog> {
  ImageFormat _format = ImageFormat.png;
  double _scale = 2;
  bool _notes = true;
  bool _dark = false;
  late ImageArea _area =
      widget.initialArea == ImageArea.selection && !widget.hasSelection ? ImageArea.content : (widget.initialArea ?? ImageArea.content);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Export ภาพแผนภาพ')),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<ImageFormat>(
              segments: const [
                ButtonSegment(value: ImageFormat.png, label: Text('PNG'), icon: Icon(Icons.image_outlined)),
                ButtonSegment(value: ImageFormat.svg, label: Text('SVG'), icon: Icon(Icons.polyline_outlined)),
              ],
              selected: {_format},
              onSelectionChanged: (s) => setState(() => _format = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _format == ImageFormat.png
                  ? tr('ภาพทั่วไป เปิดได้ทุกที่ เหมาะกับแนบรายงาน/สไลด์')
                  : tr('ภาพเวกเตอร์ ขยายแล้วไม่แตก เหมาะกับ README และเอกสาร'),
              style: TextStyle(fontSize: 12.5, color: C.muted),
            ),
            if (_format == ImageFormat.png) ...[
              const SizedBox(height: 14),
              Text(tr('ความละเอียด'), style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1x')),
                  ButtonSegment(value: 2, label: Text('2x')),
                  ButtonSegment(value: 3, label: Text('3x')),
                ],
                selected: {_scale},
                onSelectionChanged: (s) => setState(() => _scale = s.first),
              ),
            ],
            const SizedBox(height: 14),
            Text(tr('ธีมของภาพ'), style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              key: const ValueKey('export-theme'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(tr('สว่าง')), icon: const Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: true, label: Text(tr('มืด')), icon: const Icon(Icons.dark_mode_outlined)),
              ],
              selected: {_dark},
              onSelectionChanged: (s) => setState(() => _dark = s.first),
            ),
            const SizedBox(height: 14),
            Text(tr('พื้นที่ที่ส่งออก'), style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            SegmentedButton<ImageArea>(
              key: const ValueKey('export-area'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ImageArea.content, label: Text(tr('เฉพาะส่วนที่มีตาราง'))),
                ButtonSegment(value: ImageArea.board, label: Text(tr('ทั้งกระดาน'))),
                if (widget.hasSelection) ButtonSegment(value: ImageArea.selection, label: Text(tr('เฉพาะที่เลือก'))),
              ],
              selected: {_area},
              onSelectionChanged: (s) => setState(() => _area = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              switch (_area) {
                ImageArea.content => tr('ตัดพื้นที่ว่างรอบนอกออก เหลือเฉพาะบริเวณที่มีตารางและโน้ต'),
                ImageArea.board => tr('รวมพื้นที่ว่างทั้งหมดภายในกรอบกระดาน'),
                ImageArea.selection => tr('เฉพาะตารางที่เลือกอยู่ (และเส้น FK ระหว่างกัน)'),
              },
              style: TextStyle(fontSize: 12, color: C.muted),
            ),
            if (widget.hasNotes && _area != ImageArea.selection)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _notes,
                onChanged: (v) => setState(() => _notes = v ?? true),
                title: Text(tr('รวมโน้ตในภาพ'), style: TextStyle(fontSize: 13)),
              ),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, ImageExportOptions(_format, _scale, _notes, area: _area, dark: _dark)),
            child: const Text('Export'),
          ),
        ],
      );
}
