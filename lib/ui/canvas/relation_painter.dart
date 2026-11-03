import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout/diagram_geometry.dart';
import '../../core/models/project.dart';
import '../theme.dart';

/// วาดเส้น FK แบบ crow's foot: ปลาย "many" (คอลัมน์ FK) เป็นตีนกา, ปลาย "one" เป็นขีด
/// ถ้าคอลัมน์ FK เป็น PK/UNIQUE จะเป็น 1:1 (ขีดทั้งสองปลาย)
/// เรขาคณิตมาจาก [relationGeometry] ซึ่ง SVG/PNG ใช้ตัวเดียวกัน
class RelationPainter extends CustomPainter {
  RelationPainter(
    this.project,
    this.highlightTableId, {
    this.origin = 0,
    this.focusRelationId,
    this.flow = false,
    this.flowPhase,
    super.repaint,
  });

  /// วาดเครื่องหมายทิศทางข้อมูล (วงกลมลูกศร) กลางเส้นทุกเส้น
  final bool flow;

  /// ไม่ null = เส้นประวิ่งตามทิศทางข้อมูลบนเส้นที่เด่นอยู่ (ตารางที่เลือก/เส้นที่เลือก); ค่าเป็นเฟส 0..1 ของรอบหนึ่ง
  final double? flowPhase;

  final Project project;
  final String? highlightTableId;

  /// เส้นที่ถูกเลือก (เช่นคลิกที่เส้น/เลือกคอลัมน์ FK): หนาและเด่น ส่วนเส้นอื่นจางลงให้ตามเส้นนี้ได้ง่าย
  final String? focusRelationId;

  /// เลื่อนจุดกำเนิดก่อนวาด (canvas ใช้ชดเชยจุด (0,0) ของ world; export ใช้ 0)
  final double origin;

  @override
  bool? hitTest(Offset position) => false; // ไม่บังการคลิกพื้นหลัง

  @override
  void paint(Canvas canvas, Size size) {
    if (origin != 0) canvas.translate(origin, origin);
    final routes = relationRoutes(project);

    // เส้นที่เข้าคอลัมน์แม่เดียวกันเข้าคนละระดับภายในแถว และแต่ละเส้นมีสัญลักษณ์ปลายแม่ของตัวเอง
    final slots = parentEndSlots(project);

    for (final r in project.relations) {
      final g = relationGeometry(project, r);
      final route = routes[r.id];
      if (g == null || route == null) continue;

      final active = highlightTableId != null &&
          (r.fromTableId == highlightTableId || r.toTableId == highlightTableId);
      // สีเส้น: ของความสัมพันธ์นี้ ก่อน สีเริ่มต้นของโปรเจกต์ ก่อน สีตามธีม
      final custom = r.color ?? project.lineColor;
      final lineColor = custom == null ? C.primary : Color(custom);
      final focused = focusRelationId == r.id;
      final dimmed = focusRelationId != null && !focused;
      final paint = Paint()
        ..color = focused || (active && !dimmed) ? lineColor : lineColor.withValues(alpha: dimmed ? 0.3 : 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = focused ? 3 : (active ? 2.2 : 1.6)
        ..strokeCap = StrokeCap.round;

      final path = Path();
      for (final (op, pts) in roundedRoute(route)) {
        switch (op) {
          case 'M':
            path.moveTo(pts[0].$1, pts[0].$2);
          case 'L':
            path.lineTo(pts[0].$1, pts[0].$2);
          case 'Q':
            path.quadraticBezierTo(pts[0].$1, pts[0].$2, pts[1].$1, pts[1].$2);
        }
      }
      paint.strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint);

      if (flowPhase != null && (active || focused) && !dimmed) _flowDashes(canvas, route, lineColor);
      if (flow) _flowMarker(canvas, route, lineColor, dimmed ? 0.3 : 1);

      if (g.oneToOne) {
        _bar(canvas, paint, g.fx, g.fy, g.d0);
      } else {
        _crow(canvas, paint, g.fx, g.fy, g.d0);
      }
      final end = route.last;
      _parentEnd(canvas, paint, end.$1, end.$2, g.d1, g.mandatory, crowded: (slots[r.id]?.count ?? 1) > 1);
    }
  }

  /// เส้นประสีสว่างวิ่งบนเส้น จากตารางแม่ไปตารางลูก (เส้นรอบนอกจริงยังเป็นเส้นทึบเดิมอยู่ข้างใต้)
  void _flowDashes(Canvas canvas, List<RoutePoint> route, Color color) {
    const dash = 7.0, gap = 9.0, period = dash + gap;
    final path = Path();
    final reversed = route.reversed.toList(); // เริ่มที่แม่ จบที่ลูก
    for (final (op, pts) in roundedRoute(reversed, radius: 9)) {
      switch (op) {
        case 'M':
          path.moveTo(pts[0].$1, pts[0].$2);
        case 'L':
          path.lineTo(pts[0].$1, pts[0].$2);
        case 'Q':
          path.quadraticBezierTo(pts[0].$1, pts[0].$2, pts[1].$1, pts[1].$2);
      }
    }
    final paint = Paint()
      ..color = Color.lerp(color, C.isDark ? Colors.white : Colors.black, 0.55)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final shift = (flowPhase! % 1) * period;
    for (final m in path.computeMetrics()) {
      for (var d = shift - period; d < m.length; d += period) {
        final from = math.max(0.0, d), to = math.min(m.length, d + dash);
        if (to > from) canvas.drawPath(m.extractPath(from, to), paint);
      }
    }
  }

  /// วงกลมลูกศรกลางเส้น ชี้จากตารางแม่ (PK) ไปหาตารางลูก (FK)
  void _flowMarker(Canvas canvas, List<RoutePoint> route, Color color, double opacity) {
    final m = relationFlowMarker(route);
    if (m == null) return;
    final c = Offset(m.x, m.y);
    final stroke = color.withValues(alpha: opacity);
    canvas.drawCircle(c, 9.5, Paint()..color = C.canvas);
    canvas.drawCircle(
      c,
      9.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = stroke,
    );
    final ux = m.dx, uy = m.dy, nx = -m.dy, ny = m.dx;
    final tip = Offset(c.dx + ux * 3.6, c.dy + uy * 3.6);
    final chevron = Path()
      ..moveTo(tip.dx - ux * 5 + nx * 4.6, tip.dy - uy * 5 + ny * 4.6)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - ux * 5 - nx * 4.6, tip.dy - uy * 5 - ny * 4.6);
    canvas.drawPath(
      chevron,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = stroke,
    );
  }

  /// ปลายฝั่งแม่: "หนึ่งเดียว" = ขีดคู่ ; "ศูนย์หรือหนึ่ง" = ขีดเดียวแล้ววงกลมถัดออกไป
  /// [crowded] = มีเส้นอื่นเข้าคอลัมน์เดียวกัน -> ย่อสัญลักษณ์ลงไม่ให้ซ้อนกับของเส้นข้างเคียง
  void _parentEnd(Canvas canvas, Paint p, double x, double y, double dir, bool mandatory, {bool crowded = false}) {
    final s = crowded ? 0.6 : 1.0;
    _bar(canvas, p, x, y, dir, half: 8 * s);
    if (mandatory) {
      _bar(canvas, p, x + dir * 5, y, dir, half: 8 * s);
    } else {
      final c = Offset(x + dir * (crowded ? 13 : 17), y);
      canvas.drawCircle(c, 4.5 * s, Paint()..color = C.canvas);
      canvas.drawCircle(c, 4.5 * s, p);
    }
  }

  void _crow(Canvas canvas, Paint p, double x, double y, double dir) {
    final tip = x + dir * 14;
    canvas.drawLine(Offset(tip, y), Offset(x, y - 8), p);
    canvas.drawLine(Offset(tip, y), Offset(x, y), p);
    canvas.drawLine(Offset(tip, y), Offset(x, y + 8), p);
  }

  void _bar(Canvas canvas, Paint p, double x, double y, double dir, {double half = 8}) {
    final bx = x + dir * 8;
    canvas.drawLine(Offset(bx, y - half), Offset(bx, y + half), p);
  }

  @override
  bool shouldRepaint(RelationPainter old) => true;
}

/// จุดพื้นหลัง เลื่อน/ย่อขยายตามมุมมอง
class DotsPainter extends CustomPainter {
  DotsPainter(this.scale, this.offset, this.board, this.base,
      {this.nearEdges = const {}, this.extendedEdges = const {}});
  final double scale;
  final Offset offset;

  /// กรอบกระดานปัจจุบันในพิกัดโปรเจกต์ — วาดเป็นกรอบเหนือพื้นนอกกรอบ
  final DiagramBounds board;

  /// กรอบตั้งต้นที่ผู้ใช้เลือก (ส่วนที่ขยายเพิ่มเกินจากนี้จะถูกแรเงา)
  final DiagramBounds base;

  /// ขอบที่ตารางที่กำลังลากเข้าใกล้ (ถ้าลากชนจะขยาย) / ขอบที่ถูกขยายอยู่แล้ว
  final Set<BoardEdge> nearEdges, extendedEdges;

  double get boardWidth => board.width;
  double get boardHeight => board.height;

  @override
  void paint(Canvas canvas, Size size) {
    // พื้นนอกกรอบ + กระดาน (เงา, พื้น, ขอบ)
    canvas.drawRect(Offset.zero & size, Paint()..color = C.boardOutside);
    final screen = Rect.fromLTWH(
        offset.dx + board.left * scale, offset.dy + board.top * scale, boardWidth * scale, boardHeight * scale);
    final rrect = RRect.fromRectAndRadius(screen, const Radius.circular(4));
    canvas.drawRRect(
      rrect.shift(const Offset(0, 6)),
      Paint()
        ..color = C.palette.shadow.withValues(alpha: C.isDark ? 0.55 : 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(rrect, Paint()..color = C.canvas);

    final baseScreen = Rect.fromLTWH(
        offset.dx + base.left * scale, offset.dy + base.top * scale, base.width * scale, base.height * scale);
    final extended = extendedEdges.isNotEmpty;
    if (extended) {
      // ส่วนที่ขยายเพิ่มจากขนาดตั้งต้น: แรเงาด้วยสีหลักจาง ๆ
      canvas.drawPath(
        Path.combine(PathOperation.difference, Path()..addRect(screen), Path()..addRect(baseScreen)),
        Paint()..color = C.primary.withValues(alpha: C.isDark ? 0.14 : 0.08),
      );
    }

    canvas.save();
    canvas.clipRect(screen);
    _dots(canvas, size);
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = C.boardEdge,
    );

    // ขอบตั้งต้นเป็นเส้นประเมื่อกระดานถูกขยายออก
    if (extended) {
      _dashedRect(
        canvas,
        baseScreen,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = C.boardEdge,
      );
    }

    // ขอบที่กำลังจะขยาย (ตารางที่ลากเข้าใกล้) / ขยายอยู่แล้ว ไฮไลต์ด้วยสีหลัก
    void edge(BoardEdge e, Rect r, double alpha, double width) {
      final p = Paint()
        ..color = C.primary.withValues(alpha: alpha)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      switch (e) {
        case BoardEdge.left:
          canvas.drawLine(r.topLeft, r.bottomLeft, p);
        case BoardEdge.top:
          canvas.drawLine(r.topLeft, r.topRight, p);
        case BoardEdge.right:
          canvas.drawLine(r.topRight, r.bottomRight, p);
        case BoardEdge.bottom:
          canvas.drawLine(r.bottomLeft, r.bottomRight, p);
      }
    }

    for (final e in nearEdges) {
      if (!extendedEdges.contains(e)) edge(e, baseScreen, 0.55, 3);
    }
    for (final e in extendedEdges) {
      edge(e, screen, 0.9, 3);
    }

    // ป้ายขนาดกระดานเหนือมุมซ้ายบน
    if (screen.top > 18 && screen.left > -200 && screen.left < size.width - 60) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${boardWidth.round()} × ${boardHeight.round()}',
          style: TextStyle(fontSize: 11, color: C.muted, fontFamily: kMono, fontFamilyFallback: const ['Consolas']),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(math.max(screen.left, 8), screen.top - 16));
    }
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const dash = 7.0, gap = 5.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len == 0) return;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len), p);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  void _dots(Canvas canvas, Size size) {
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
  bool shouldRepaint(DotsPainter old) =>
      old.scale != scale ||
      old.offset != offset ||
      old.board.left != board.left ||
      old.board.top != board.top ||
      old.board.right != board.right ||
      old.board.bottom != board.bottom ||
      old.base.right != base.right ||
      old.base.bottom != base.bottom ||
      old.nearEdges.length != nearEdges.length ||
      old.extendedEdges.length != extendedEdges.length ||
      !old.nearEdges.containsAll(nearEdges) ||
      !old.extendedEdges.containsAll(extendedEdges);
}
