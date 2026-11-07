import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/layout/flowchart_geometry.dart';
import '../../core/models/flowchart_model.dart';
import '../flowchart/fc_painter.dart';
import '../theme.dart';
import 'diagram_png.dart' show PngExport, kMaxPngSide;

/// วาด Flowchart เป็นภาพ PNG (ตัดเฉพาะส่วนที่มีสัญลักษณ์) — คืน null ถ้าว่าง
/// ใช้ตัวพิมพ์ตัวเดียวกับบนจอ ([paintFlowchart]) ; [dark] = ธีมมืด ; [transparent] = ไม่มีพื้นหลัง (ไม่มีเงา)
Future<PngExport?> exportFlowchartPng(FlowchartDiagram d, {double scale = 2, bool dark = false, bool transparent = false}) async {
  final b = fcBounds(d, pad: 40);
  if (b == null) return null;
  final width = b.right - b.left, height = b.bottom - b.top;
  final s = math.min(scale, kMaxPngSide / math.max(width, height));
  final w = (width * s).ceil(), h = (height * s).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(s);
  canvas.translate(-b.left, -b.top);
  C.withPalette(dark ? kDarkPalette : kLightPalette, () {
    if (!transparent) canvas.drawRect(Rect.fromLTWH(b.left, b.top, width, height), Paint()..color = C.canvas);
    paintFlowchart(canvas, d, shadows: !transparent);
  });
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) return null;
  return PngExport(data.buffer.asUint8List(), w, h, s);
}
