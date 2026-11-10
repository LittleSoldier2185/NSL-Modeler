import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout/diagram_geometry.dart' show roundedRoute;
import '../../core/layout/flowchart_geometry.dart' show fcArrowHead;
import '../../core/layout/ortho_route.dart';
import '../../core/layout/screenflow_geometry.dart';
import '../../core/layout/wireframe_render.dart';
import '../../core/models/flowchart_model.dart' show FcArrow;
import '../../core/models/screenflow_model.dart';
import '../../core/models/wireframe_model.dart';
import '../canvas/box_canvas.dart' show paintMarquee, paintResizeHandles;
import '../flowchart/fc_painter.dart' show fcPath;
import '../theme.dart';
import '../wireframe/wf_painter.dart' show paintWfPrims;

const double kSfLabelSize = 12;

TextPainter _label(String text, Color color, {double max = 220}) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: kThai, fontFamilyFallback: kFontFallback, fontSize: kSfLabelSize, color: color, fontWeight: FontWeight.w500, height: 1.25),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: max);

/// สี่เหลี่ยมป้ายเส้น (ใช้ทั้งวาดและตรวจการคลิก) ; ไม่มีป้าย = null
Rect? sfLabelRect(SfEdge e, List<RoutePoint> route) {
  final cap = e.caption;
  if (cap.isEmpty) return null;
  final (ax, ay) = routeLabelAnchor(route);
  final tp = _label(cap, C.text);
  return Rect.fromCenter(center: Offset(ax, ay), width: tp.width + 10, height: tp.height + 4);
}

/// วาด Screen Flow ลงใน [canvas] ที่พิกัดแผนภาพ — ใช้ร่วมกันทั้งบนจอและ PNG ; [wireframeOf] = ภาพย่อหน้าจอที่ผูกไว้
void paintScreenFlow(
  Canvas canvas,
  ScreenFlowDiagram d, {
  WireframeDiagram? Function(String id)? wireframeOf,
  Set<String> selectedNodes = const {},
  String? selectedEdge,
  String? linkSource,
  String? hideTextOf,
  bool shadows = true,
}) {
  for (final n in d.nodes) {
    _paintNode(canvas, n, wireframeOf: wireframeOf, shadows: shadows, hideText: n.id == hideTextOf);
  }

  final routes = sfRoutes(d);
  for (final e in d.edges) {
    final r = routes[e.id];
    if (r == null) continue;
    final selected = e.id == selectedEdge;
    final color = C.text.withValues(alpha: 0.75);
    final path = fcPath(roundedRoute(r, radius: 6));
    if (selected) {
      canvas.drawPath(path, Paint()
        ..color = C.primary.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3.2 : 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round);
    final (_, pts) = fcArrowHead(FcArrow.arrow, r[r.length - 2], r.last, size: 10.8);
    if (pts.isNotEmpty) {
      final p = Path()..moveTo(pts[0].$1, pts[0].$2);
      for (final q in pts.skip(1)) {
        p.lineTo(q.$1, q.$2);
      }
      p.close();
      canvas.drawPath(p, Paint()..color = color);
    }
  }

  for (final e in d.edges) {
    final r = routes[e.id];
    if (r == null || e.id == hideTextOf) continue;
    final rect = sfLabelRect(e, r);
    if (rect == null) continue;
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rr, Paint()..color = C.canvas);
    if (e.id == selectedEdge) {
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = C.primary);
    }
    final tp = _label(e.caption, C.text);
    tp.paint(canvas, Offset(rect.left + 5, rect.center.dy - tp.height / 2));
  }

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

void _paintNode(Canvas canvas, SfNode n, {WireframeDiagram? Function(String id)? wireframeOf, required bool shadows, required bool hideText}) {
  final accent = Color(sfNodeColor(n));
  final r = switch (n.kind) { SfKind.start || SfKind.end => n.h / 2, _ => 8.0 };
  final rr = RRect.fromRectAndRadius(Rect.fromLTWH(n.x, n.y, n.w, n.h), Radius.circular(r));
  if (shadows) {
    canvas.drawRRect(rr.shift(const Offset(0, 2)), Paint()
      ..color = Colors.black.withValues(alpha: C.isDark ? 0.35 : 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }
  canvas.drawRRect(rr, Paint()..color = C.surface);
  canvas.drawRRect(rr, Paint()..color = accent.withValues(alpha: C.isDark ? 0.18 : 0.10));
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7
    ..color = accent;
  if (n.kind == SfKind.external) {
    final path = Path()..addRRect(rr);
    for (final m in path.computeMetrics()) {
      for (var dist = 0.0; dist < m.length; dist += 11) {
        canvas.drawPath(m.extractPath(dist, math.min(m.length, dist + 7)), stroke);
      }
    }
  } else {
    canvas.drawRRect(rr, stroke);
  }
  final title = n.title.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.kind == SfKind.screen) {
    canvas.drawLine(Offset(n.x, n.y + kSfTitleBar), Offset(n.right, n.y + kSfTitleBar), Paint()
      ..color = accent.withValues(alpha: 0.5)
      ..strokeWidth = 1);
    if (!hideText && title.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
            text: title,
            style: TextStyle(fontFamily: kThai, fontFamilyFallback: kFontFallback, fontSize: 13, fontWeight: FontWeight.w600, color: C.text)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(4, n.w - 16));
      tp.paint(canvas, Offset(n.x + 8, n.y + (kSfTitleBar - tp.height) / 2));
    }
    final box = sfThumbBox(n);
    final wf = n.wireframeId == null ? null : wireframeOf?.call(n.wireframeId!);
    if (wf != null) {
      final f = sfThumbFit(box, wf.width, wf.height);
      canvas.save();
      canvas.translate(f.dx, f.dy);
      canvas.scale(f.scale);
      canvas.clipRect(Rect.fromLTWH(0, 0, wf.width, wf.height));
      paintWfPrims(canvas, wireframePrims(wf));
      canvas.restore();
    } else {
      final tp = TextPainter(
        text: TextSpan(
            text: n.wireframeId == null ? '—' : '?',
            style: TextStyle(fontFamily: kThai, fontSize: 16, color: n.wireframeId == null ? C.muted : C.danger)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(box.left + (box.width - tp.width) / 2, box.top + (box.height - tp.height) / 2));
    }
    return;
  }
  if (hideText || title.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(
        text: title,
        style: TextStyle(fontFamily: kThai, fontFamilyFallback: kFontFallback, fontSize: 13, fontWeight: FontWeight.w600, color: C.text, height: 1.25)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: math.max(4, n.w - 20));
  tp.paint(canvas, Offset(n.cx - tp.width / 2, n.cy - tp.height / 2));
}

/// ตัวพิมพ์บนจอ: เลื่อน/ซูม แล้ววาดแผนผัง + จุดจับ + เส้นที่กำลังลาก + กรอบลากเลือก
class ScreenFlowScreenPainter extends CustomPainter {
  ScreenFlowScreenPainter({
    required this.diagram,
    required this.offset,
    required this.scale,
    this.wireframeOf,
    this.selectedNodes = const {},
    this.selectedEdge,
    this.linkSource,
    this.linkCursor,
    this.marquee,
    this.hideTextOf,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ScreenFlowDiagram diagram;
  final Offset offset;
  final double scale;
  final WireframeDiagram? Function(String id)? wireframeOf;
  final Set<String> selectedNodes;
  final String? selectedEdge;
  final String? linkSource;
  final ValueNotifier<Offset?>? linkCursor;
  final Rect? marquee;
  final String? hideTextOf;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    paintScreenFlow(canvas, diagram,
        wireframeOf: wireframeOf,
        selectedNodes: selectedNodes,
        selectedEdge: selectedEdge,
        linkSource: linkSource,
        hideTextOf: hideTextOf);
    if (selectedNodes.length == 1) {
      final n = diagram.nodeById(selectedNodes.first);
      if (n != null) paintResizeHandles(canvas, Rect.fromLTWH(n.x, n.y, n.w, n.h), scale);
    }
    final src = linkSource == null ? null : diagram.nodeById(linkSource!);
    final cur = linkCursor?.value;
    if (src != null && cur != null) {
      canvas.drawLine(Offset(src.cx, src.cy), cur, Paint()
        ..color = C.primary
        ..strokeWidth = 1.6 / scale);
    }
    canvas.restore();
    paintMarquee(canvas, marquee);
  }

  @override
  bool shouldRepaint(ScreenFlowScreenPainter old) => true;
}
