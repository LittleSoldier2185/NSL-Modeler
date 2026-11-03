import 'package:flutter/material.dart';

import 'theme.dart';

/// ช่องกรอกที่บันทึกค่าตอนกด Enter หรือออกจากช่อง (ไม่สร้างประวัติ undo ทุกตัวอักษร)
/// ใส่ key ที่ผูกกับ id ของข้อมูล เพื่อให้ค่าในช่องรีเซ็ตเมื่อเปลี่ยนรายการที่เลือก
class CommitField extends StatefulWidget {
  const CommitField({
    super.key,
    required this.value,
    required this.onCommit,
    this.hint,
    this.mono = false,
    this.height = 34,
    this.label,
  });

  final String value;
  final ValueChanged<String> onCommit;
  final String? hint;
  final bool mono;
  final double height;
  final String? label;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final TextEditingController _ctl = TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_ctl.text != widget.value) widget.onCommit(_ctl.text);
  }

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    // ค่าเปลี่ยนจากภายนอก (undo ฯลฯ) และผู้ใช้ไม่ได้กำลังพิมพ์อยู่
    if (widget.value != old.value && !_focus.hasFocus && _ctl.text != widget.value) {
      _ctl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = SizedBox(
      height: widget.height,
      child: TextField(
        controller: _ctl,
        focusNode: _focus,
        onSubmitted: (_) => _commit(),
        style: (widget.mono ? monoStyle : const TextStyle()).copyWith(fontSize: 13, color: C.text),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(fontSize: 13, color: C.muted),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: C.inputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: C.primary, width: 1.5),
          ),
        ),
      ),
    );
    return widget.label == null ? field : LabeledField(label: widget.label!, child: field);
  }
}

class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          child,
        ],
      );
}

class Dropdown<T> extends StatelessWidget {
  const Dropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelOf,
    this.height = 34,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: C.inputBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 13, color: C.text, fontFamily: kThai),
            items: [
              for (final i in items) DropdownMenuItem(value: i, child: Text(labelOf(i))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}

/// ปุ่มเล็กขอบบาง ใช้ซ้ำทั้งแอป
class SmallButton extends StatelessWidget {
  const SmallButton({super.key, required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 15),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: C.primary,
          side: const BorderSide(color: C.border),
          minimumSize: const Size(0, 28),
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 8),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
}

class Chip2 extends StatelessWidget {
  const Chip2(this.text, this.bg, this.fg, {super.key});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: monoStyle.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}
