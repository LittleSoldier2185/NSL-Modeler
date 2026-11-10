import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../state/box_diagram_controller.dart';
import '../theme.dart';

/// ชิ้นส่วนหน้าตาที่ใช้ร่วมกันของแคนวาสแผนภาพแบบกล่อง (Wireframe, Screen Flow): แถบเครื่องมือลอย, แถบซูม, แถวสี

/// ปุ่มหนึ่งปุ่มในแถบเครื่องมือลอย
Widget canvasToolItem({
  required Key key,
  required String label,
  required IconData icon,
  required bool on,
  required VoidCallback onTap,
  bool showLabel = false,
}) =>
    Tooltip(
      message: label,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: on ? C.primaryTint : Colors.transparent, borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: on ? C.primaryDark : C.muted),
            if (showLabel) ...[
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12.5, color: on ? C.primaryDark : C.text)),
            ],
          ]),
        ),
      ),
    );

/// เส้นคั่นในแถบเครื่องมือ
Widget canvasToolDivider() => Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4), color: C.border);

/// กล่องลอยของแถบเครื่องมือ
class CanvasToolbarBox extends StatelessWidget {
  const CanvasToolbarBox({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: C.border),
          boxShadow: [BoxShadow(color: C.palette.shadow.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
}

/// แถบซูมมุมขวาล่าง: ย่อ / % / ขยาย / พอดีกับที่เลือก / พอดีหน้าจอ (+ ปุ่มเพิ่มเติม) — [keyPrefix] ใช้ตั้ง key ของปุ่ม
class CanvasZoomBar extends StatelessWidget {
  const CanvasZoomBar({super.key, required this.controller, required this.size, required this.keyPrefix, this.extra = const []});
  final BoxDiagramController controller;
  final Size size;
  final String keyPrefix;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final f = controller;
    Widget btn(IconData i, String tip, VoidCallback cb, String k) => IconButton(
        key: ValueKey('$keyPrefix-$k'), tooltip: tip, visualDensity: VisualDensity.compact, iconSize: 18, onPressed: cb, icon: Icon(i));
    return Container(
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove_rounded, tr('ย่อ'), () => f.zoomAt(size.center(Offset.zero), 1 / 1.2), 'zoom-out'),
        Text('${(f.scale * 100).round()}%', key: ValueKey('$keyPrefix-zoom-label'), style: const TextStyle(fontSize: 12.5)),
        btn(Icons.add_rounded, tr('ขยาย'), () => f.zoomAt(size.center(Offset.zero), 1.2), 'zoom-in'),
        btn(Icons.center_focus_strong_outlined, tr('พอดีกับที่เลือก'), () => f.fitSelection(size), 'fit-selection'),
        btn(Icons.fit_screen_outlined, tr('พอดีหน้าจอ'), () => f.fit(size), 'fit'),
        ...extra,
      ]),
    );
  }
}

/// แถวสีสำเร็จรูป + ปุ่มค่าเริ่มต้น (ถ้า [allowDefault]) + ปุ่มกำหนดเอง
class ColorSwatchRow extends StatelessWidget {
  const ColorSwatchRow({
    super.key,
    required this.keyPrefix,
    required this.palette,
    required this.current,
    required this.onPick,
    required this.onCustom,
    this.allowDefault = true,
  });
  final String keyPrefix;
  final List<int> palette;
  final int? current;
  final ValueChanged<int?> onPick;
  final VoidCallback onCustom;
  final bool allowDefault;

  @override
  Widget build(BuildContext context) {
    Widget sw(Key k, String tip, bool on, VoidCallback tap, Widget child) => Tooltip(
          message: tip,
          child: InkResponse(
            key: k,
            onTap: tap,
            radius: 16,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? C.text : C.border, width: on ? 2 : 1)),
              child: child,
            ),
          ),
        );
    final custom = current != null && !palette.contains(current);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      if (allowDefault)
        sw(ValueKey('$keyPrefix-default'), tr('ค่าเริ่มต้น'), current == null, () => onPick(null),
            Icon(Icons.format_color_reset_outlined, size: 13, color: C.muted)),
      for (var i = 0; i < palette.length; i++)
        sw(
          ValueKey('$keyPrefix-$i'),
          '#${(palette[i] & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}',
          current == palette[i],
          () => onPick(palette[i]),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Color(palette[i]), border: Border.all(color: C.border)),
          ),
        ),
      sw(ValueKey('$keyPrefix-custom'), tr('กำหนดสีเอง…'), custom, onCustom,
          custom
              ? Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(current!)))
              : Icon(Icons.colorize_rounded, size: 13, color: C.muted)),
    ]);
  }
}
