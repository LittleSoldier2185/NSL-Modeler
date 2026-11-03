import 'package:flutter/material.dart';

class PromptResult {
  const PromptResult(this.text, {this.deleted = false});

  /// ข้อความที่กรอก (ตัดช่องว่างหัวท้ายแล้วเมื่อบรรทัดเดียว)
  final String text;

  /// ผู้ใช้กดปุ่มลบ (ถ้ามี [TextPromptDialog.deleteLabel])
  final bool deleted;
}

/// กล่องรับข้อความ — เป็นเจ้าของ controller เอง จึง dispose หลังแอนิเมชันปิดหน้าต่างจบ
/// (ห้าม dispose controller ที่ส่งให้ dialog ทันทีหลัง showDialog คืนค่า เพราะ TextField ยังวาดอยู่ช่วงปิด)
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.initial,
    this.label,
    this.maxLines = 1,
    this.minLines = 1,
    this.confirmLabel = 'ตกลง',
    this.deleteLabel,
  });

  final String title;
  final String initial;
  final String? label;
  final int maxLines;
  final int minLines;
  final String confirmLabel;
  final String? deleteLabel;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String get _value => widget.maxLines == 1 ? _ctl.text.trim() : _ctl.text;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: _ctl,
            autofocus: true,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            decoration: InputDecoration(labelText: widget.label),
            onSubmitted: widget.maxLines == 1 ? (_) => Navigator.pop(context, PromptResult(_value)) : null,
          ),
        ),
        actions: [
          if (widget.deleteLabel != null)
            TextButton(
              onPressed: () => Navigator.pop(context, const PromptResult('', deleted: true)),
              child: Text(widget.deleteLabel!, style: const TextStyle(color: Color(0xFFB42318))),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(context, PromptResult(_value)),
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}

/// กล่องรับข้อความบรรทัดเดียว — คืน null ถ้ายกเลิก
Future<String?> promptText(BuildContext context,
    {required String title, required String initial, String? label}) async {
  final r = await showDialog<PromptResult>(
    context: context,
    builder: (_) => TextPromptDialog(title: title, initial: initial, label: label),
  );
  return r?.text;
}
