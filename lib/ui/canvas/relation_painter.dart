import 'package:flutter/material.dart';

import '../../core/layout/diagram_geometry.dart';
import '../../core/models/project.dart';
import '../theme.dart';

/// วาดเส้น FK แบบ crow's foot: ปลาย "many" (คอลัมน์ FK) เป็นตีนกา, ปลาย "one" เป็นขีด
/// ถ้าคอลัมน์ FK เป็น PK/UNIQUE จะเป็น 1:1 (ขีดทั้งสองปลาย)
/// เรขาคณิตมาจาก [relationGeometry] ซึ่ง SVG/PNG ใช้ตัวเดียวกัน
class RelationPainter extends CustomPainter {
  RelationPainter(this.project, this.highlightTableId);

  final Project project;
  final String? highlightTableId;

  @override
  bool? hitTest(Offset position) => false; // ไม่บังการคลิกพื้นหลัง

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in project.relations) {
      final g = relationGeometry(project, r);
      if (g == null) continue;

      final active = highlightTableId != null &&
          (r.fromTableId == highlightTableId || r.toTableId == highlightTableId);
      final paint = Paint()
        ..color = active ? C.primary : C.primary.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.2 : 1.6
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(g.fx, g.fy)
        ..cubicTo(g.fx + g.d0 * g.k, g.fy, g.tx + g.d1 * g.k, g.ty, g.tx, g.ty);
      canvas.drawPath(path, paint);

      if (g.oneToOne) {
        _bar(canvas, paint, g.fx, g.fy, g.d0);
      } else {
        _crow(canvas, paint, g.fx, g.fy, g.d0);
      }
      _bar(canvas, paint, g.tx, g.ty, g.d1);
    }
  }

  void _crow(Canvas canvas, Paint p, double x, double y, double dir) {
    final tip = x + dir * 14;
    canvas.drawLine(Offset(tip, y), Offset(x, y - 8), p);
    canvas.drawLine(Offset(tip, y), Offset(x, y), p);
    canvas.drawLine(Offset(tip, y), Offset(x, y + 8), p);
  }

  void _bar(Canvas canvas, Paint p, double x, double y, double dir) {
    final bx = x + dir * 8;
    canvas.drawLine(Offset(bx, y - 8), Offset(bx, y + 8), p);
  }

  @override
  bool shouldRepaint(RelationPainter old) => true;
}

/// จุดพื้นหลัง เลื่อน/ย่อขยายตามมุมมอง
class DotsPainter extends CustomPainter {
  DotsPainter(this.scale, this.offset);
  final double scale;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final step = 20 * scale;
    if (step < 6) return; // ย่อมากจนจุดถี่เกินไป
    final paint = Paint()..color = C.dot;
    final startX = offset.dx % step;
    final startY = offset.dy % step;
    for (var x = startX; x < size.width; x += step) {
      for (var y = startY; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DotsPainter old) => old.scale != scale || old.offset != offset;
}
