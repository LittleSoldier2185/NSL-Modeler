import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// แถบจับสำหรับลากขอบเพื่อปรับขนาดแผง — วางทับรอยต่อ (ไม่กินพื้นที่เลย์เอาต์)
/// [vertical] = เส้นตั้ง (ลากซ้าย-ขวา ปรับความกว้างแผงข้าง); false = เส้นนอน (ลากขึ้น-ลง ปรับความสูงแผงล่าง)
///
/// รายงานเป็น "ระยะรวมจากจุดที่กดเมาส์" ([onUpdate]) ไม่ใช่ระยะต่อเฟรม และนับตั้งแต่ตอนกดเมาส์
/// (ไม่เสียระยะช่วง slop ของท่าทาง) แผงจึงตามเมาส์ติดมือตลอดการลาก
/// ดับเบิลคลิก = คืนขนาดเริ่มต้น
class PanelSplitter extends StatefulWidget {
  const PanelSplitter({
    super.key,
    required this.vertical,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onReset,
  });

  final bool vertical;

  /// เริ่มลาก (ให้ผู้ใช้จำขนาดเริ่มต้นไว้)
  final VoidCallback onStart;

  /// ระยะรวม (px) ที่เมาส์เคลื่อนจากจุดเริ่มลาก ตามแกนของแถบ (+ = ขวา/ลง)
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onReset;

  @override
  State<PanelSplitter> createState() => _PanelSplitterState();
}

class _PanelSplitterState extends State<PanelSplitter> {
  bool _hover = false;
  bool _drag = false;
  double _origin = 0;

  double _axis(Offset p) => widget.vertical ? p.dx : p.dy;

  void _start(DragStartDetails d) {
    _origin = _axis(d.globalPosition);
    setState(() => _drag = true);
    widget.onStart();
  }

  void _update(DragUpdateDetails d) => widget.onUpdate(_axis(d.globalPosition) - _origin);

  void _end([Object? _]) {
    setState(() => _drag = false);
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    final active = _hover || _drag;
    final line = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: widget.vertical ? (active ? 3 : 0) : double.infinity,
      height: widget.vertical ? double.infinity : (active ? 3 : 0),
      color: C.primary.withValues(alpha: _drag ? 0.9 : 0.55),
    );
    return MouseRegion(
      cursor: widget.vertical ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: widget.vertical ? _start : null,
        onHorizontalDragUpdate: widget.vertical ? _update : null,
        onHorizontalDragEnd: widget.vertical ? _end : null,
        onHorizontalDragCancel: widget.vertical ? _end : null,
        onVerticalDragStart: widget.vertical ? null : _start,
        onVerticalDragUpdate: widget.vertical ? null : _update,
        onVerticalDragEnd: widget.vertical ? null : _end,
        onVerticalDragCancel: widget.vertical ? null : _end,
        child: Center(child: line),
      ),
    );
  }
}
