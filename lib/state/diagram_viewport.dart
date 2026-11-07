import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// มุมมอง (เลื่อน/ซูม) ของแคนวาสแผนภาพหนึ่งแท็บ — ใช้ร่วมกันได้กับ controller ของแผนภาพชนิดใดก็ได้
/// (ตอนนี้ใช้กับ Flowchart ; DFD ยังมีโค้ดเดิมของตัวเองซึ่งทำงานเหมือนกัน ย้ายมาใช้ภายหลังได้)
mixin DiagramViewport on ChangeNotifier {
  static const minScale = 0.2, maxScale = 3.0;

  /// ขนาดพื้นที่แสดงแคนวาส (กำหนดโดย widget ตอน layout)
  Size viewport = Size.zero;

  Offset _offset = const Offset(120, 90);
  double _scale = 1;

  Offset get offset => _offset;
  double get scale => _scale;

  @protected
  void setView(Offset o, double s) {
    _offset = o;
    _scale = s.clamp(minScale, maxScale).toDouble();
    notifyListeners();
  }

  Offset toWorld(Offset screen) => (screen - offset) / scale;
  Offset toScreen(Offset world) => world * scale + offset;

  void panBy(Offset d) => setView(offset + d, scale);

  void zoomAt(Offset focus, double factor) {
    final s = (scale * factor).clamp(minScale, maxScale).toDouble();
    if (s == scale) return;
    final w = toWorld(focus);
    setView(focus - w * s, s);
  }

  void resetZoom(Size viewport) {
    final w = toWorld(viewport.center(Offset.zero));
    setView(viewport.center(Offset.zero) - w, 1);
  }

  /// ให้กรอบ [l],[t],[r],[b] (พิกัดแผนภาพ) อยู่กลางจอพอดี (ซูมไม่เกิน [maxZoom]) ; null = กลับมุมมองเริ่มต้น
  void fitRect(({double left, double top, double right, double bottom})? b, Size viewport, {double maxZoom = 1.2}) {
    if (b == null || viewport.isEmpty) {
      setView(const Offset(120, 90), 1);
      return;
    }
    final w = b.right - b.left, h = b.bottom - b.top;
    final s = math.min(maxZoom, math.min(viewport.width / w, viewport.height / h)).clamp(minScale, maxScale).toDouble();
    setView(Offset((viewport.width - w * s) / 2 - b.left * s, (viewport.height - h * s) / 2 - b.top * s), s);
  }

  /// เลื่อนมุมมองให้จุด [p] (พิกัดแผนภาพ) อยู่กลางจอ
  void revealPoint(Offset p, Size viewport) {
    if (viewport.isEmpty) return;
    setView(viewport.center(Offset.zero) - p * scale, scale);
  }
}
