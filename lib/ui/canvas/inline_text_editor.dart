import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// ช่องพิมพ์ข้อความบนแคนวาส (วางทับวัตถุที่กำลังแก้) ใช้ร่วมกันระหว่างแผนภาพแบบกล่อง (Wireframe, Screen Flow)
/// - หลายบรรทัด: Enter ขึ้นบรรทัดใหม่, Ctrl+Enter = บันทึก ; บรรทัดเดียว: Enter = บันทึก
/// - คลิกที่อื่น (ช่องเสียโฟกัส) = บันทึก ; Esc = ยกเลิก
class InlineTextEditor extends StatefulWidget {
  const InlineTextEditor({
    super.key,
    required this.rect,
    required this.initial,
    required this.onCommit,
    required this.onCancel,
    this.onDone,
    this.multiline = true,
    this.fontSize = 13,
    this.align = TextAlign.center,
    this.fieldKey = const ValueKey('inline-field'),
  });

  /// ตำแหน่งบนจอ (พิกัดของ Stack แคนวาส)
  final Rect rect;
  final String initial;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;

  /// เรียกเมื่อผู้ใช้จบการพิมพ์ด้วยคีย์ (ให้หน้าหลักขอโฟกัสคืน)
  final VoidCallback? onDone;
  final bool multiline;

  /// ขนาดตัวอักษรบนจอ (คูณซูมแล้ว)
  final double fontSize;
  final TextAlign align;
  final Key fieldKey;

  @override
  State<InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<InlineTextEditor> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initial);
  final _focus = FocusNode(debugLabel: 'inline-editor');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctl.selection = TextSelection(baseOffset: 0, extentOffset: _ctl.text.length);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _finish() {
    if (widget.onDone == null) {
      _focus.unfocus();
    } else {
      widget.onDone!();
    }
  }

  void _commit() {
    if (_done) return;
    _done = true;
    widget.onCommit(_ctl.text);
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
        left: widget.rect.left,
        top: widget.rect.top,
        width: widget.rect.width,
        height: widget.rect.height,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true): _finish,
            const SingleActivator(LogicalKeyboardKey.escape): () {
              _done = true;
              widget.onCancel();
              widget.onDone?.call();
            },
          },
          child: Material(
            color: C.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(4),
            child: TextField(
              key: widget.fieldKey,
              controller: _ctl,
              focusNode: _focus,
              textAlign: widget.align,
              textAlignVertical: TextAlignVertical.center,
              maxLines: widget.multiline ? null : 1,
              expands: widget.multiline,
              keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
              onSubmitted: widget.multiline ? null : (_) => _finish(),
              style: TextStyle(fontSize: widget.fontSize, color: C.text, height: 1.25),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: C.primary)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: C.primary, width: 1.5)),
              ),
            ),
          ),
        ),
      );
}
