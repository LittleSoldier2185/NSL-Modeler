import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout/dfd_resize.dart' show DfdHandle, dfdHandlePos;
import '../../core/layout/diagram_geometry.dart' show roundedRoute;
import '../../core/layout/flowchart_geometry.dart';
import '../../core/layout/ortho_route.dart';
import '../../core/models/flowchart_model.dart';
import '../theme.dart';

/// สีสำเร็จรูปให้เลือกในแผงขวา
const List<int> kFcPalette = [
  0xFF2563EB,
  0xFF16A34A,
  0xFFDC2626,
  0xFFD97706,
  0xFF0D9488,
  0xFF7C3AED,
  0xFFDB2777,
  0xFF475569,
  0xFFFFFFFF,
  0xFF000000,
];

/// สีเส้นขอบของสัญลักษณ์
int fcStrokeColor(FcNode n) => n.stroke ?? kFcShapeColors[n.shape]!;

/// ขนาดป้ายชื่อเส้น
const double kFcLabelSize = 12;

Path fcPath(List<FcCmd> cmds) {
  final p = Path();
  for (final (op, pts) in cmds) {
    switch (op) {
      case 'M':
        p.moveTo(pts[0].$1, pts[0].$2);
      case 'L':
        p.lineTo(pts[0].$1, pts[0].$2);
      case 'C':
        p.cubicTo(pts[0].$1, pts[0].$2, pts[1].$1, pts[1].$2, pts[2].$1, pts[2].$2);
      case 'Q':
        p.quadraticBezierTo(pts[0].$1, pts[0].$2, pts[1].$1, pts[1].$2);
      case 'Z':
        p.close();
    }
  }
  return p;
}

/// ลายเส้นประของ [d] (null = เส้นทึบ)
List<double>? fcDashPattern(FcDash d, double width) => switch (d) {
      FcDash.solid => null,
      FcDash.dashed => [8, 5],
      FcDash.dotted => [math.max(1.5, width), 4],
    };

void _strokePath(Canvas canvas, Path path, Paint paint, FcDash dash) {
  final pattern = fcDashPattern(dash, paint.strokeWidth);
  if (pattern == null) {
    canvas.drawPath(path, paint);
    return;
  }
  for (final m in path.computeMetrics()) {
    var dist = 0.0;
    var on = true;
    var i = 0;
    while (dist < m.length) {
      final len = pattern[i % pattern.length];
      if (on) canvas.drawPath(m.extractPath(dist, math.min(m.length, dist + len)), paint);
      dist += len;
      on = !on;
      i++;
    }
  }
}

TextPainter fcTextPainter(FcNode n, double maxWidth, {Color? color}) => TextPainter(
      text: TextSpan(
        text: n.text,
        style: TextStyle(
          fontFamily: kThai,
          fontFamilyFallback: kFontFallback,
          fontSize: n.fontSize,
          color: color ?? (n.textColor != null ? Color(n.textColor!) : C.text),
          fontWeight: n.bold ? FontWeight.w700 : FontWeight.w500,
          fontStyle: n.italic ? FontStyle.italic : FontStyle.normal,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: switch (n.align) {
        FcAlign.left => TextAlign.left,
        FcAlign.center => TextAlign.center,
        FcAlign.right => TextAlign.right,
      },
      ellipsis: '…',
      maxLines: math.max(1, (fcTextBox(n).height / (n.fontSize * 1.25)).floor()),
    )..layout(maxWidth: math.max(4, maxWidth));

TextPainter _labelPainter(String text, Color color) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: kThai, fontFamilyFallback: kFontFallback, fontSize: kFcLabelSize, color: color, fontWeight: FontWeight.w500, height: 1.25),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 200);

/// สี่เหลี่ยมของป้ายชื่อเส้น (ใช้ทั้งวาดและตรวจการคลิก) ; ไม่มีป้าย = null
Rect? fcLabelRect(FcEdge e, List<RoutePoint> route) {
  if (e.label.trim().isEmpty) return null;
  final (ax, ay) = routeLabelAnchor(route);
  final tp = _labelPainter(e.label, C.text);
  return Rect.fromCenter(center: Offset(ax, ay), width: tp.width + 10, height: tp.height + 4);
}

/// วาด Flowchart ลงใน [canvas] ที่พิกัดแผนภาพ (ผู้เรียกจัดการ translate/scale เอง) — ใช้ร่วมกันทั้งบนจอและ export PNG
/// ใช้สีจากพาเลตต์ [C] ปัจจุบัน ; [hideTextOf] = id ที่กำลังพิมพ์บนแคนวาส (ไม่วาดข้อความซ้อน)
void paintFlowchart(
  Canvas canvas,
  FlowchartDiagram d, {
  Set<String> selectedNodes = const {},
  String? selectedEdge,
  String? linkSource,
  String? hideTextOf,
  bool shadows = true,
}) {
  final routes = fcRoutes(d);

  // ---- สัญลักษณ์ ----
  for (final n in d.nodes) {
    _paintNode(canvas, n, shadows: shadows, hideText: n.id == hideTextOf);
  }

  // ---- เส้น (อยู่บนสัญลักษณ์ ให้หัวลูกศรไม่ถูกบัง) ----
  for (final e in d.edges) {
    final r = routes[e.id];
    if (r == null) continue;
    final selected = e.id == selectedEdge;
    final color = Color(e.color ?? C.text.withValues(alpha: 0.75).toARGB32());
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? e.width + 1.4 : e.width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (selected) {
      canvas.drawPath(fcPath(roundedRoute(r, radius: 6)), Paint()
        ..color = C.primary.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.width + 6);
    }
    _strokePath(canvas, fcPath(roundedRoute(r, radius: 6)), paint, e.dash);
    _arrow(canvas, e.endArrow, r[r.length - 2], r.last, paint);
    _arrow(canvas, e.startArrow, r[1], r.first, paint);
  }

  // ---- ป้ายชื่อเส้น (บนสุด) ----
  for (final e in d.edges) {
    final r = routes[e.id];
    if (r == null || e.id == hideTextOf) continue;
    final rect = fcLabelRect(e, r);
    if (rect == null) continue;
    final selected = e.id == selectedEdge;
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rr, Paint()..color = C.canvas);
    if (selected) {
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = C.primary);
    }
    final tp = _labelPainter(e.label, e.color != null ? Color(e.color!) : C.text);
    tp.paint(canvas, Offset(rect.left + 5, rect.center.dy - tp.height / 2));
  }

  // ---- กรอบเลือก ----
  for (final n in d.nodes) {
    final sel = selectedNodes.contains(n.id), link = n.id == linkSource;
    if (!sel && !link) continue;
    canvas.drawRect(
      Rect.fromLTWH(n.x, n.y, n.w, n.h).inflate(4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sel ? 1.6 : 2
        ..color = link ? C.warnText : C.primary,
    );
  }
}

void _arrow(Canvas canvas, FcArrow a, RoutePoint from, RoutePoint to, Paint line) {
  final (filled, pts) = fcArrowHead(a, from, to, size: 9 + line.strokeWidth);
  if (pts.isEmpty) return;
  final p = Path()..moveTo(pts[0].$1, pts[0].$2);
  for (final q in pts.skip(1)) {
    p.lineTo(q.$1, q.$2);
  }
  if (filled) {
    p.close();
    canvas.drawPath(p, Paint()..color = line.color);
  } else {
    canvas.drawPath(p, Paint()
      ..color = line.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = line.strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round);
  }
}

void _paintNode(Canvas canvas, FcNode n, {required bool shadows, required bool hideText}) {
  final g = fcShapeGeom(n);
  final outline = fcPath(g.outline);
  final accent = Color(fcStrokeColor(n));
  if (shadows) {
    canvas.drawPath(
      outline.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: C.isDark ? 0.35 : 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }
  if (n.fill != null) {
    canvas.drawPath(outline, Paint()..color = Color(n.fill!));
  } else {
    canvas.drawPath(outline, Paint()..color = C.surface);
    canvas.drawPath(outline, Paint()..color = accent.withValues(alpha: C.isDark ? 0.18 : 0.10));
  }
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7
    ..strokeJoin = StrokeJoin.round
    ..color = accent;
  _strokePath(canvas, outline, stroke, n.dash);
  if (g.details.isNotEmpty) canvas.drawPath(fcPath(g.details), stroke);

  if (hideText || n.text.isEmpty) return;
  final box = fcTextBox(n);
  final tp = fcTextPainter(n, box.width);
  final dx = switch (n.align) {
    FcAlign.left => box.left,
    FcAlign.center => box.left + (box.width - tp.width) / 2,
    FcAlign.right => box.left + box.width - tp.width,
  };
  canvas.save();
  canvas.clipRect(Rect.fromLTWH(n.x, n.y, n.w, n.h));
  tp.paint(canvas, Offset(dx, box.top + (box.height - tp.height) / 2));
  canvas.restore();
}

/// ตัวพิมพ์บนจอ: แปลงพิกัด (เลื่อน + ซูม) แล้ววาดแผนภาพ + จุดจับ + เส้นที่กำลังต่อ + กรอบลากเลือก
class FlowchartScreenPainter extends CustomPainter {
  FlowchartScreenPainter({
    required this.diagram,
    required this.offset,
    required this.scale,
    this.selectedNodes = const {},
    this.selectedEdge,
    this.linkSource,
    this.linkCursor,
    this.marquee,
    this.hideTextOf,
    required this.repaint,
  }) : super(repaint: repaint);

  final FlowchartDiagram diagram;
  final Offset offset;
  final double scale;
  final Set<String> selectedNodes;
  final String? selectedEdge;
  final String? linkSource;
  final Offset? linkCursor;
  final Rect? marquee;
  final String? hideTextOf;
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    paintFlowchart(canvas, diagram,
        selectedNodes: selectedNodes, selectedEdge: selectedEdge, linkSource: linkSource, hideTextOf: hideTextOf);
    if (selectedNodes.length == 1) {
      final n = diagram.nodeById(selectedNodes.first);
      if (n != null) {
        final hs = 4.5 / scale;
        final r = Rect.fromLTWH(n.x, n.y, n.w, n.h);
        for (final h in DfdHandle.values) {
          final box = Rect.fromCenter(center: dfdHandlePos(r, h), width: hs * 2, height: hs * 2);
          canvas.drawRect(box, Paint()..color = C.surface);
          canvas.drawRect(box, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4 / scale
            ..color = C.primary);
        }
      }
    }
    final src = linkSource == null ? null : diagram.nodeById(linkSource!);
    if (src != null && linkCursor != null) {
      canvas.drawLine(
        Offset(src.cx, src.cy),
        linkCursor!,
        Paint()
          ..color = C.primary
          ..strokeWidth = 1.6 / scale
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
    final m = marquee;
    if (m != null) {
      canvas.drawRect(m, Paint()..color = C.primary.withValues(alpha: 0.10));
      canvas.drawRect(m, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = C.primary);
    }
  }

  @override
  bool shouldRepaint(FlowchartScreenPainter old) => true;
}
