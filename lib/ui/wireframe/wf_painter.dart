import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout/wireframe_render.dart';
import '../../core/models/wireframe_model.dart';
import '../canvas/box_canvas.dart' show paintMarquee, paintResizeHandles;
import '../flowchart/fc_painter.dart' show fcPath;
import '../theme.dart';

/// สีสำเร็จรูปให้เลือกในแผงขวาของ Wireframe
const List<int> kWfPalette = [
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

void _strokeDashed(Canvas canvas, Path path, Paint paint) {
  for (final m in path.computeMetrics()) {
    var dist = 0.0;
    var on = true;
    while (dist < m.length) {
      final len = on ? 6.0 : 4.0;
      if (on) canvas.drawPath(m.extractPath(dist, math.min(m.length, dist + len)), paint);
      dist += len;
      on = !on;
    }
  }
}

/// วาดชิ้นวาดกลางของ Wireframe ลงใน [canvas] (พิกัดหน้าจอ ผู้เรียกจัดการ translate/scale เอง) — ใช้ทั้งบนจอ PNG และภาพย่อ
void paintWfPrims(Canvas canvas, List<WfPrim> prims) {
  for (final p in prims) {
    switch (p) {
      case WfPathPrim():
        final path = fcPath(p.cmds);
        if (p.fill != null) canvas.drawPath(path, Paint()..color = Color(p.fill!));
        if (p.stroke != null) {
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = p.width
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..color = Color(p.stroke!);
          if (p.dashed) {
            _strokeDashed(canvas, path, paint);
          } else {
            canvas.drawPath(path, paint);
          }
        }
      case WfTextPrim():
        final lineH = p.size * 1.3;
        final maxLines = p.maxLines ?? math.max(1, (p.h / lineH).floor());
        final tp = TextPainter(
          text: TextSpan(
            text: p.text,
            style: TextStyle(
              fontFamily: kThai,
              fontFamilyFallback: kFontFallback,
              fontSize: p.size,
              color: Color(p.color),
              fontWeight: p.bold ? FontWeight.w700 : FontWeight.w400,
              height: 1.3,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: switch (p.align) { 1 => TextAlign.center, 2 => TextAlign.right, _ => TextAlign.left },
          maxLines: maxLines,
          ellipsis: '…',
        )..layout(maxWidth: math.max(4, p.w));
        final dx = switch (p.align) { 1 => p.x + (p.w - tp.width) / 2, 2 => p.x + p.w - tp.width, _ => p.x };
        final dy = p.top ? p.y : p.y + (p.h - tp.height) / 2;
        tp.paint(canvas, Offset(dx, dy));
    }
  }
}

/// วาดหน้าจอ Wireframe ทั้งกรอบ ([hideTextOf] = ชิ้นที่กำลังพิมพ์บนแคนวาส ไม่วาดข้อความซ้อน)
void paintWireframe(Canvas canvas, WireframeDiagram d, {String? hideTextOf}) {
  var src = d;
  if (hideTextOf != null && d.componentById(hideTextOf) != null) {
    src = WireframeDiagram(device: d.device, width: d.width, height: d.height, style: d.style, accent: d.accent, components: [
      for (final c in d.components) c.id == hideTextOf ? WfComponent.tryFromJson({...c.toJson(), 'text': ''})! : c,
    ]);
  }
  paintWfPrims(canvas, wireframePrims(src));
}

/// ตัวพิมพ์บนจอ: เลื่อน/ซูม แล้ววาดหน้าจอ + ป้ายขนาดหน้าจอ + ชิปข้อมูล ER + กรอบเลือก/จุดจับ + กรอบลากเลือก
class WireframeScreenPainter extends CustomPainter {
  WireframeScreenPainter({
    required this.diagram,
    required this.offset,
    required this.scale,
    required this.frameLabel,
    this.selected = const {},
    this.children = const {},
    this.chips = const {},
    this.marquee,
    this.hideTextOf,
  });

  final WireframeDiagram diagram;
  final Offset offset;
  final double scale;
  final String frameLabel;
  final Set<String> selected;

  /// ลูกในภาชนะของชิ้นที่เลือก (ไฮไลต์จาง ๆ ว่าจะย้ายตาม)
  final Set<String> children;

  /// ชิปข้อมูล ER: id ชิ้น -> (ข้อความ, ผูกขาด?)
  final Map<String, (String, bool)> chips;
  final Rect? marquee;
  final String? hideTextOf;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    // เงาใต้กรอบหน้าจอ
    canvas.drawRect(
      Rect.fromLTWH(0, 4, diagram.width, diagram.height),
      Paint()
        ..color = Colors.black.withValues(alpha: C.isDark ? 0.35 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    paintWireframe(canvas, diagram, hideTextOf: hideTextOf);

    final label = TextPainter(
      text: TextSpan(text: frameLabel, style: TextStyle(fontFamily: kThai, fontSize: 12 / scale, color: C.muted)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    label.paint(canvas, Offset(0, -label.height - 4 / scale));

    for (final c in diagram.components) {
      final chip = chips[c.id];
      if (chip == null) continue;
      final (text, broken) = chip;
      final color = broken ? C.danger : const Color(0xFF0D9488);
      final tp = TextPainter(
        text: TextSpan(text: '⛁ $text', style: TextStyle(fontFamily: kThai, fontFamilyFallback: kFontFallback, fontSize: 10.5 / scale, color: Colors.white, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(40 / scale, c.w));
      final r = Rect.fromLTWH(c.right - tp.width - 8 / scale, c.y - tp.height - 2 / scale, tp.width + 8 / scale, tp.height + 2 / scale);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(4 / scale)), Paint()..color = color);
      tp.paint(canvas, Offset(r.left + 4 / scale, r.top + 1 / scale));
    }

    for (final c in diagram.components) {
      if (children.contains(c.id)) {
        canvas.drawRect(
          Rect.fromLTWH(c.x, c.y, c.w, c.h).inflate(2 / scale),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / scale
            ..color = C.primary.withValues(alpha: 0.45),
        );
      }
      if (!selected.contains(c.id)) continue;
      canvas.drawRect(
        Rect.fromLTWH(c.x, c.y, c.w, c.h).inflate(3 / scale),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 / scale
          ..color = C.primary,
      );
    }
    if (selected.length == 1) {
      final c = diagram.componentById(selected.first);
      if (c != null) paintResizeHandles(canvas, Rect.fromLTWH(c.x, c.y, c.w, c.h), scale);
    }
    canvas.restore();
    paintMarquee(canvas, marquee);
  }

  @override
  bool shouldRepaint(WireframeScreenPainter old) => true;
}
