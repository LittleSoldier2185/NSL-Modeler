import 'package:flutter/material.dart';

import '../theme.dart';

enum ImageFormat { png, svg }

class ImageExportOptions {
  const ImageExportOptions(this.format, this.scale, this.includeNotes);
  final ImageFormat format;
  final double scale;
  final bool includeNotes;
}

/// เลือกรูปแบบภาพที่จะ export (PNG พร้อมสเกล หรือ SVG) — คืน null ถ้ายกเลิก
class ExportImageDialog extends StatefulWidget {
  const ExportImageDialog({super.key, required this.hasNotes});
  final bool hasNotes;

  @override
  State<ExportImageDialog> createState() => _ExportImageDialogState();
}

class _ExportImageDialogState extends State<ExportImageDialog> {
  ImageFormat _format = ImageFormat.png;
  double _scale = 2;
  bool _notes = true;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Export ภาพแผนภาพ'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  ? 'ภาพทั่วไป เปิดได้ทุกที่ เหมาะกับแนบรายงาน/สไลด์'
                  : 'ภาพเวกเตอร์ ขยายแล้วไม่แตก เหมาะกับ README และเอกสาร',
              style: const TextStyle(fontSize: 12.5, color: C.muted),
            ),
            if (_format == ImageFormat.png) ...[
              const SizedBox(height: 14),
              const Text('ความละเอียด', style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
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
            if (widget.hasNotes)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _notes,
                onChanged: (v) => setState(() => _notes = v ?? true),
                title: const Text('รวมโน้ตในภาพ', style: TextStyle(fontSize: 13)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ImageExportOptions(_format, _scale, _notes)),
            child: const Text('Export'),
          ),
        ],
      );
}
