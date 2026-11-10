import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/layout/screenflow_geometry.dart';
import '../../core/models/screenflow_model.dart';
import '../../core/models/wireframe_model.dart';
import '../screenflow/sf_painter.dart';
import '../theme.dart';
import '../wireframe/wf_painter.dart';
import 'diagram_png.dart' show PngExport, kMaxPngSide;

Future<PngExport?> _render(double left, double top, double width, double height, double scale, void Function(Canvas) draw) async {
  final s = math.min(scale, kMaxPngSide / math.max(width, height));
  final w = (width * s).ceil(), h = (height * s).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(s);
  canvas.translate(-left, -top);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) return null;
  return PngExport(data.buffer.asUint8List(), w, h, s);
}

/// วาดหน้าจอ Wireframe ทั้งกรอบเป็นภาพ PNG ตามรูปแบบการแสดงผลของเอกสาร (ไม่ขึ้นกับธีมของแอป)
/// [transparent] = ไม่มีพื้นหลังรอบกรอบหน้าจอ
Future<PngExport?> exportWireframePng(WireframeDiagram d, {double scale = 2, bool transparent = false}) {
  const pad = 24.0;
  var l = 0.0, t = 0.0, r = d.width, b = d.height;
  for (final c in d.components) {
    l = math.min(l, c.x);
    t = math.min(t, c.y);
    r = math.max(r, c.right);
    b = math.max(b, c.bottom);
  }
  l -= pad;
  t -= pad;
  r += pad;
  b += pad;
  return _render(l, t, r - l, b - t, scale, (canvas) {
    if (!transparent) {
      canvas.drawRect(Rect.fromLTRB(l, t, r, b), Paint()..color = Color(d.style == WfStyle.sketch ? 0xFFF4F4F2 : 0xFFEEF1F5));
    }
    paintWireframe(canvas, d);
  });
}

/// วาด Screen Flow เป็นภาพ PNG (ตัดเฉพาะส่วนที่มีโหนด) — คืน null ถ้าว่าง ; [wireframeOf] = ภาพย่อหน้าจอที่ผูกไว้
Future<PngExport?> exportScreenFlowPng(ScreenFlowDiagram d,
    {WireframeDiagram? Function(String id)? wireframeOf, double scale = 2, bool dark = false, bool transparent = false}) async {
  final b = sfBounds(d, pad: 40);
  if (b == null) return null;
  return _render(b.left, b.top, b.right - b.left, b.bottom - b.top, scale, (canvas) {
    C.withPalette(dark ? kDarkPalette : kLightPalette, () {
      if (!transparent) canvas.drawRect(Rect.fromLTRB(b.left, b.top, b.right, b.bottom), Paint()..color = C.canvas);
      paintScreenFlow(canvas, d, wireframeOf: wireframeOf, shadows: !transparent);
    });
  });
}
