import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/dfd_model.dart';
import '../dfd/dfd_painter.dart';
import '../theme.dart';
import 'diagram_png.dart' show PngExport, kMaxPngSide;

/// วาดแผนภาพ DFD เป็นภาพ PNG (ตัดเฉพาะส่วนที่มีวัตถุ) — คืน null ถ้าไม่มีวัตถุ
/// ใช้ตัวพิมพ์ตัวเดียวกับบนจอ ([paintDfd]) ภาพจึงเหมือนที่เห็น; [dark] = ธีมมืดไม่ขึ้นกับธีมของแอป
Future<PngExport?> exportDfdPng(DfdDiagram d, {double scale = 2, bool dark = false}) async {
  final b = dfdBounds(d, pad: 48);
  if (b == null) return null;
  final width = b.right - b.left, height = b.bottom - b.top;
  final s = math.min(scale, kMaxPngSide / math.max(width, height));
  final w = (width * s).ceil(), h = (height * s).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(s);
  canvas.translate(-b.left, -b.top);
  C.withPalette(dark ? kDarkPalette : kLightPalette, () {
    canvas.drawRect(Rect.fromLTWH(b.left, b.top, width, height), Paint()..color = C.canvas);
    paintDfd(canvas, d);
  });
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) return null;
  return PngExport(data.buffer.asUint8List(), w, h, s);
}
