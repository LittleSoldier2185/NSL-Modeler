import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout/diagram_geometry.dart' show kGridSize;
import '../theme.dart';

/// พื้นหลังลายจุดตามช่องตาราง เลื่อน/ซูมตามมุมมอง — ใช้ร่วมกันระหว่างแคนวาส DFD และ Flowchart
/// [showDots] = false วาดแค่สีพื้น
class DotGridPainter extends CustomPainter {
  const DotGridPainter(this.offset, this.scale, {this.showDots = true});
  final Offset offset;
  final double scale;
  final bool showDots;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = C.canvas);
    final step = kGridSize * scale;
    if (!showDots || step < 8) return;
    final dot = Paint()..color = C.border.withValues(alpha: 0.8);
    final startX = offset.dx % step, startY = offset.dy % step;
    for (var x = startX; x < size.width; x += step) {
      for (var y = startY; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), math.max(0.8, scale * 0.9), dot);
      }
    }
  }

  @override
  bool shouldRepaint(DotGridPainter old) => old.offset != offset || old.scale != scale || old.showDots != showDots;
}
