import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/board_presets.dart';
import '../core/models/project.dart';
import 'theme.dart';

/// ขนาดกระดานที่ผู้ใช้เลือก
typedef BoardSize = ({double width, double height});

/// เลือกขนาดกระดานจาก preset หรือกำหนดเอง — คืน null ถ้ายกเลิก
Future<BoardSize?> showBoardSizeDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  double width = kDefaultBoardWidth,
  double height = kDefaultBoardHeight,
}) =>
    showDialog<BoardSize>(
      context: context,
      builder: (_) => BoardSizeDialog(title: title, confirmLabel: confirmLabel, width: width, height: height),
    );

class BoardSizeDialog extends StatefulWidget {
  const BoardSizeDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.width = kDefaultBoardWidth,
    this.height = kDefaultBoardHeight,
  });

  final String title;
  final String confirmLabel;
  final double width;
  final double height;

  @override
  State<BoardSizeDialog> createState() => _BoardSizeDialogState();
}

class _BoardSizeDialogState extends State<BoardSizeDialog> {
  /// id ของ preset ที่เลือก หรือ 'custom'
  late String _choice;
  late final TextEditingController _w;
  late final TextEditingController _h;

  @override
  void initState() {
    super.initState();
    final match = kBoardPresets.where((p) => p.matches(widget.width, widget.height));
    _choice = match.isEmpty ? 'custom' : match.first.id;
    _w = TextEditingController(text: widget.width.round().toString());
    _h = TextEditingController(text: widget.height.round().toString());
  }

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  bool get _custom => _choice == 'custom';

  String? _error(TextEditingController c) {
    final e = validateBoardSide(c.text);
    return e == null ? null : tr(e, [kMinBoardSide.round(), kMaxBoardSide.round()]);
  }

  BoardSize? get _result {
    if (_custom) {
      if (_error(_w) != null || _error(_h) != null) return null;
      return (width: double.parse(_w.text.trim()), height: double.parse(_h.text.trim()));
    }
    final p = kBoardPresets.firstWhere((x) => x.id == _choice);
    return (width: p.width, height: p.height);
  }

  void _pick(String id) => setState(() {
        _choice = id;
        if (id != 'custom') {
          final p = kBoardPresets.firstWhere((x) => x.id == id);
          _w.text = p.width.round().toString();
          _h.text = p.height.round().toString();
        }
      });

  @override
  Widget build(BuildContext context) {
    final res = _result;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('เลือกขนาดกระดานเริ่มต้น กระดานจะขยายเองเมื่อวางของเกินขอบ'),
                style: TextStyle(fontSize: 12.5, color: C.muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final p in kBoardPresets)
                _Tile(
                  key: ValueKey('preset-${p.id}'),
                  title: tr(p.label),
                  size: '${p.width.round()} × ${p.height.round()}',
                  hint: tr(p.hint),
                  ratio: p.width / p.height,
                  selected: _choice == p.id,
                  onTap: () => _pick(p.id),
                ),
              _Tile(
                key: const ValueKey('preset-custom'),
                title: tr('กำหนดเอง'),
                size: res == null ? '—' : '${res.width.round()} × ${res.height.round()}',
                hint: tr('ระบุความกว้าง × ความสูงเอง'),
                ratio: res == null ? 1.6 : res.width / res.height,
                selected: _custom,
                onTap: () => _pick('custom'),
              ),
            ]),
            if (_custom) ...[
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _field(_w, tr('กว้าง (px)'), 'board-width')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                  child: Text('×', style: TextStyle(fontSize: 16, color: C.muted)),
                ),
                Expanded(child: _field(_h, tr('สูง (px)'), 'board-height')),
              ]),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        FilledButton(
          onPressed: res == null ? null : () => Navigator.pop(context, res),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, String key) => TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          errorText: _error(c),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.title,
    required this.size,
    required this.hint,
    required this.ratio,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String size;
  final String hint;
  final double ratio;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // กรอบจำลองสัดส่วนกระดาน
    final w = ratio >= 1 ? 54.0 : 54.0 * ratio;
    final h = ratio >= 1 ? 54.0 / ratio : 54.0;
    return Material(
      color: selected ? C.primaryTint : C.field,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? C.primary : C.border, width: selected ? 1.6 : 1),
            boxShadow: selected ? C.shadowSm : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 56,
              child: Center(
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: C.canvas,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: selected ? C.primary : C.boardEdge, width: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Text(size, style: monoStyle.copyWith(fontSize: 11.5, color: C.muted)),
            const SizedBox(height: 4),
            Text(hint, style: TextStyle(fontSize: 11.5, color: C.muted, height: 1.3)),
          ]),
        ),
      ),
    );
  }
}
