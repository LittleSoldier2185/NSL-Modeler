import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/color_utils.dart';
import 'theme.dart';

/// ผลของกล่องเลือกสี: [argb] = null หมายถึง "ล้างสี/ใช้ค่าเริ่มต้น"
class ColorChoice {
  const ColorChoice(this.argb);
  final int? argb;
}

/// เลือกสีอิสระ (Hue/Saturation/Value + ฮีกซ์) — คืน null ถ้ายกเลิก
Future<ColorChoice?> showColorPickerDialog(BuildContext context,
        {required String title, int? initial, List<int> presets = const []}) =>
    showDialog<ColorChoice>(
        context: context, builder: (_) => _ColorPickerDialog(title: title, initial: initial, presets: presets));

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, this.initial, required this.presets});
  final String title;
  final int? initial;
  final List<int> presets;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _h, _s, _v;
  late final TextEditingController _hex;

  int get _argb => hsvToArgb(_h, _s, _v);

  @override
  void initState() {
    super.initState();
    final (h, s, v) = argbToHsv(widget.initial ?? 0xFF0F766E);
    _h = h;
    _s = s;
    _v = v;
    _hex = TextEditingController(text: hexRgb(_argb));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setArgb(int argb, {bool fromHex = false}) {
    final (h, s, v) = argbToHsv(argb);
    setState(() {
      _h = h;
      _s = s;
      _v = v;
      if (!fromHex) _hex.text = hexRgb(_argb);
    });
  }

  void _slide({double? h, double? s, double? v}) => setState(() {
        _h = h ?? _h;
        _s = s ?? _s;
        _v = v ?? _v;
        _hex.text = hexRgb(_argb);
      });

  @override
  Widget build(BuildContext context) {
    final color = Color(_argb);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            key: const ValueKey('color-preview'),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.border)),
            child: Text(hexRgb(_argb), style: TextStyle(color: Color(onColor(_argb)), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          // พื้นที่เลือกความเข้ม (แนวนอน) / ความสว่าง (แนวตั้ง) ของเฉดสีที่เลือก
          _Drag(
            key: const ValueKey('color-sv'),
            height: 160,
            onChanged: (x, y) => _slide(s: x, v: 1 - y),
            painter: _SvPainter(_h, _s, _v),
          ),
          const SizedBox(height: 12),
          // แถบเฉดสีรุ้ง
          _Drag(
            key: const ValueKey('color-h'),
            height: 18,
            onChanged: (x, _) => _slide(h: x * 360),
            painter: _HuePainter(_h),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('color-hex'),
            controller: _hex,
            decoration: InputDecoration(isDense: true, labelText: tr('รหัสสี (HEX)')),
            onChanged: (v) {
              final c = parseHexColor(v);
              if (c != null) _setArgb(c, fromHex: true);
            },
          ),
          if (widget.presets.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in widget.presets)
                InkResponse(
                  onTap: () => _setArgb(p),
                  child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Color(p), border: Border.all(color: C.border))),
                ),
            ]),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        TextButton(
            key: const ValueKey('color-reset'),
            onPressed: () => Navigator.pop(context, const ColorChoice(null)),
            child: Text(tr('ใช้ค่าเริ่มต้น'))),
        FilledButton(
            key: const ValueKey('color-ok'), onPressed: () => Navigator.pop(context, ColorChoice(_argb)), child: Text(tr('ตกลง'))),
      ],
    );
  }
}

/// พื้นที่ลากที่ส่งตำแหน่งสัมพัทธ์ 0..1 (x, y) กลับมา
class _Drag extends StatelessWidget {
  const _Drag({super.key, required this.height, required this.onChanged, required this.painter});
  final double height;
  final void Function(double x, double y) onChanged;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, box) {
        void at(Offset o) => onChanged((o.dx / box.maxWidth).clamp(0.0, 1.0), (o.dy / height).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          child: SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: painter)),
        );
      });
}

void _thumb(Canvas canvas, Offset c, double r, Color fill) {
  canvas.drawCircle(c, r, Paint()..color = fill);
  canvas.drawCircle(c, r, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = Colors.white);
  canvas.drawCircle(c, r + 1.2, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0x55000000));
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.h, this.s, this.v);
  final double h, s, v;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(r);
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [Colors.white, Color(hsvToArgb(h, 1, 1))]).createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Colors.black])
              .createShader(rect));
    canvas.restore();
    _thumb(canvas, Offset(s * size.width, (1 - v) * size.height), 9, Color(hsvToArgb(h, s, v)));
  }

  @override
  bool shouldRepaint(_SvPainter o) => o.h != h || o.s != s || o.v != v;
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.h);
  final double h;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
        Paint()
          ..shader = LinearGradient(colors: [for (var i = 0; i <= 6; i++) Color(hsvToArgb(i * 60.0, 1, 1))]).createShader(rect));
    _thumb(canvas, Offset(h / 360 * size.width, size.height / 2), size.height / 2 + 1, Color(hsvToArgb(h, 1, 1)));
  }

  @override
  bool shouldRepaint(_HuePainter o) => o.h != h;
}
