import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout/diagram_geometry.dart' show roundedRoute;
import '../../core/models/color_utils.dart';
import '../../core/models/dfd_model.dart';
import '../theme.dart';

/// สีประจำชนิดวัตถุ (ใช้เมื่อไม่ได้กำหนดสีเอง)
const Map<DfdKind, int> kDfdKindColors = {
  DfdKind.entity: 0xFF3B82F6,
  DfdKind.process: 0xFF9333EA,
  DfdKind.store: 0xFFF59E0B,
};

/// สีสำเร็จรูปให้เลือกในแผงขวา
const List<int> kDfdPalette = [
  0xFF3B82F6,
  0xFF9333EA,
  0xFFF59E0B,
  0xFF14B8A6,
  0xFF22C55E,
  0xFFF43F5E,
  0xFF64748B,
];

int dfdNodeColor(DfdNode n) => n.color ?? kDfdKindColors[n.kind]!;

TextPainter _tp(String text, double size, Color color,
    {FontWeight weight = FontWeight.w400, double maxWidth = double.infinity, int maxLines = 1, TextAlign align = TextAlign.left}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: kThai,
        fontFamilyFallback: kFontFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: 1.25,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  return tp;
}

/// ขนาดป้ายชื่อ flow (ใช้ทั้งวาดและวัดขอบเขต)
const double kDfdLabelSize = 12;

/// วาดแผนภาพ DFD ลงใน [canvas] ที่พิกัดแผนภาพ (ผู้เรียกจัดการ translate/scale เอง) — ใช้ร่วมกันทั้งบนจอและ export PNG
/// ใช้สีจากพาเลตต์ [C] ปัจจุบัน (ผู้เรียกครอบ [C.withPalette] ถ้าต้องการธีมอื่น)
void paintDfd(
  Canvas canvas,
  DfdDiagram d, {
  Set<String> selectedNodes = const {},
  String? selectedFlow,
  String? linkSource,
}) {
  final routes = dfdRoutes(d);

  // ---- เส้น ----
  for (final f in d.flows) {
    final route = routes[f.id];
    if (route == null) continue;
    final selected = f.id == selectedFlow;
    final color = Color(f.color ?? C.primary.toARGB32());
    final paint = Paint()
      ..color = selected ? color : color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3 : 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (final (op, pts) in roundedRoute(route, radius: 8)) {
      switch (op) {
        case 'M':
          path.moveTo(pts[0].$1, pts[0].$2);
        case 'L':
          path.lineTo(pts[0].$1, pts[0].$2);
        case 'Q':
          path.quadraticBezierTo(pts[0].$1, pts[0].$2, pts[1].$1, pts[1].$2);
      }
    }
    canvas.drawPath(path, paint);
    _arrow(canvas, route[route.length - 2], route.last, paint);
    if (f.bidirectional) _arrow(canvas, route[1], route.first, paint);
  }

  // ---- วัตถุ ----
  for (final n in d.nodes) {
    _paintNode(canvas, n, selected: selectedNodes.contains(n.id), linkSource: n.id == linkSource);
  }

  // ---- ป้ายชื่อ flow (อยู่บนสุด) ----
  for (final f in d.flows) {
    final route = routes[f.id];
    if (route == null || f.label.trim().isEmpty) continue;
    final rect = dfdLabelRect(f, route);
    final selected = f.id == selectedFlow;
    final color = Color(f.color ?? C.primary.toARGB32());
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rr, Paint()..color = C.canvas);
    if (selected) {
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color);
    }
    final tp = _tp(f.label, kDfdLabelSize, selected ? color : C.text, weight: FontWeight.w500, maxWidth: rect.width - 8);
    tp.paint(canvas, Offset(rect.left + 4, rect.center.dy - tp.height / 2));
  }
}

/// สี่เหลี่ยมของป้ายชื่อ flow (ใช้ทั้งวาดและตรวจการคลิก)
Rect dfdLabelRect(DfdFlow f, List<DfdPoint> route) {
  final (ax, ay) = dfdLabelAnchor(route);
  final tp = _tp(f.label, kDfdLabelSize, C.text, weight: FontWeight.w500, maxWidth: 220);
  final w = tp.width + 8, h = tp.height + 4;
  return Rect.fromCenter(center: Offset(ax, ay), width: w, height: h);
}

void _arrow(Canvas canvas, DfdPoint from, DfdPoint to, Paint line) {
  final dx = to.$1 - from.$1, dy = to.$2 - from.$2;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 0.001) return;
  final ux = dx / len, uy = dy / len;
  const size = 10.0;
  final base = Offset(to.$1 - ux * size, to.$2 - uy * size);
  final nx = -uy, ny = ux;
  final path = Path()
    ..moveTo(to.$1, to.$2)
    ..lineTo(base.dx + nx * size * 0.45, base.dy + ny * size * 0.45)
    ..lineTo(base.dx - nx * size * 0.45, base.dy - ny * size * 0.45)
    ..close();
  canvas.drawPath(path, Paint()..color = line.color);
}

void _paintNode(Canvas canvas, DfdNode n, {required bool selected, required bool linkSource}) {
  final accent = Color(dfdNodeColor(n));
  final rect = Rect.fromLTWH(n.x, n.y, n.w, n.h);
  final fill = Paint()..color = C.surface;
  final border = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7
    ..color = accent.withValues(alpha: 0.95);
  final tint = Paint()..color = accent.withValues(alpha: C.isDark ? 0.18 : 0.10);

  // เงาเบา ๆ ให้ลอยจากพื้น
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect.shift(const Offset(0, 2)), Radius.circular(n.kind == DfdKind.process ? 16 : 6)),
    Paint()
      ..color = Colors.black.withValues(alpha: C.isDark ? 0.35 : 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );

  switch (n.kind) {
    case DfdKind.entity:
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, tint);
      canvas.drawRRect(rr, border);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(n.x + 12, n.cy - 7, 16, 14), const Radius.circular(3)), Paint()..color = accent);
      _text(canvas, n.name, Rect.fromLTWH(n.x + 38, n.y + 4, n.w - 46, n.h - 8), weight: FontWeight.w600);
    case DfdKind.process:
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(16));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, tint);
      canvas.drawRRect(rr, border);
      // ป้ายเลขลำดับเป็นแคปซูลด้านซ้าย
      final num = n.number.isEmpty ? '·' : n.number;
      final badge = _tp(num, 11.5, onColorOf(accent), weight: FontWeight.w700, maxWidth: 46);
      final bw = math.max(30.0, badge.width + 14);
      final br = RRect.fromRectAndRadius(Rect.fromLTWH(n.x + 10, n.cy - 11, bw, 22), const Radius.circular(11));
      canvas.drawRRect(br, Paint()..color = accent);
      badge.paint(canvas, Offset(br.left + (bw - badge.width) / 2, br.top + (22 - badge.height) / 2));
      _text(canvas, n.name, Rect.fromLTWH(n.x + 10 + bw + 8, n.y + 4, n.w - bw - 28, n.h - 8), weight: FontWeight.w600);
    case DfdKind.store:
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, tint);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..color = accent.withValues(alpha: 0.95);
      // เปิดด้านขวา: เส้นบน/ล่าง/ซ้าย
      canvas.drawLine(Offset(n.x, n.y), Offset(n.right, n.y), line);
      canvas.drawLine(Offset(n.x, n.bottom), Offset(n.right, n.bottom), line);
      canvas.drawLine(Offset(n.x, n.y), Offset(n.x, n.bottom), line);
      final code = n.number.isEmpty ? '' : n.number;
      const cw = 44.0;
      canvas.drawRect(Rect.fromLTWH(n.x, n.y, cw, n.h), Paint()..color = accent.withValues(alpha: C.isDark ? 0.30 : 0.18));
      canvas.drawLine(Offset(n.x + cw, n.y), Offset(n.x + cw, n.bottom), line);
      if (code.isNotEmpty) {
        final tp = _tp(code, 12, accent, weight: FontWeight.w700, maxWidth: cw - 6);
        tp.paint(canvas, Offset(n.x + (cw - tp.width) / 2, n.cy - tp.height / 2));
      }
      _text(canvas, n.name, Rect.fromLTWH(n.x + cw + 10, n.y + 4, n.w - cw - 18, n.h - 8), weight: FontWeight.w600);
  }

  if (selected || linkSource) {
    final r = n.kind == DfdKind.process ? 18.0 : 8.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(4), Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.4 : 2
        ..color = linkSource ? C.warnText : C.primary,
    );
  }
}

/// สีตัวอักษรที่อ่านออกบนพื้น [bg]
Color onColorOf(Color bg) => Color(onColor(bg.toARGB32()));

void _text(Canvas canvas, String text, Rect box, {FontWeight weight = FontWeight.w400}) {
  if (text.isEmpty) return;
  final tp = _tp(text, 13, C.text, weight: weight, maxWidth: math.max(10, box.width), maxLines: 2);
  tp.paint(canvas, Offset(box.left, box.center.dy - tp.height / 2));
}

/// ตัวพิมพ์ที่ใช้บนจอ: แปลงพิกัด (เลื่อน + ซูม) แล้ววาดแผนภาพ + กรอบเลือก + เส้นที่กำลังต่อ
class DfdScreenPainter extends CustomPainter {
  DfdScreenPainter({
    required this.diagram,
    required this.offset,
    required this.scale,
    this.selectedNodes = const {},
    this.selectedFlow,
    this.linkSource,
    this.linkCursor,
    this.marquee,
    required this.repaint,
  }) : super(repaint: repaint);

  final DfdDiagram diagram;
  final Offset offset;
  final double scale;
  final Set<String> selectedNodes;
  final String? selectedFlow;
  final String? linkSource;
  final Offset? linkCursor; // พิกัดแผนภาพ
  final Rect? marquee; // พิกัดจอ
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    paintDfd(canvas, diagram, selectedNodes: selectedNodes, selectedFlow: selectedFlow, linkSource: linkSource);
    final src = linkSource == null ? null : diagram.nodeById(linkSource!);
    if (src != null && linkCursor != null) {
      canvas.drawLine(
        Offset(src.cx, src.cy),
        linkCursor!,
        Paint()
          ..color = C.primary
          ..strokeWidth = 1.6
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
  bool shouldRepaint(DfdScreenPainter old) => true;
}
