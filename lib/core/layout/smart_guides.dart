import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// เส้นช่วยจัดแนวหนึ่งเส้น (พิกัดแผนภาพ): [vertical] = เส้นตั้งที่ x = [pos] ; ไม่งั้นเป็นเส้นนอนที่ y = [pos]
/// ยาวจาก [from] ถึง [to] ตามแกนอีกด้าน
class GuideLine {
  const GuideLine({required this.vertical, required this.pos, required this.from, required this.to});

  final bool vertical;
  final double pos, from, to;

  @override
  bool operator ==(Object other) =>
      other is GuideLine && other.vertical == vertical && other.pos == pos && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(vertical, pos, from, to);
}

/// ผลของการหาแนวช่วยจัด: ต้องเลื่อนเพิ่ม ([dx],[dy]) เพื่อให้ชิดแนว และเส้นที่จะวาดหลังเลื่อน
class GuideResult {
  const GuideResult(this.dx, this.dy, this.lines);

  final double dx, dy;
  final List<GuideLine> lines;

  static const none = GuideResult(0, 0, []);
}

/// หาแนวช่วยจัด (smart guide) ของกรอบ [moving] เทียบกับกรอบ [others]:
/// ขอบซ้าย/กึ่งกลาง/ขอบขวา เทียบกัน และขอบบน/กึ่งกลาง/ขอบล่าง เทียบกัน ; ใกล้กว่า [tol] = ชิดแนว
/// (แต่ละแกนเลือกแนวที่ใกล้ที่สุดแนวเดียว) — คำนวณล้วน ๆ ไม่แก้อะไร
GuideResult computeGuides(Rect moving, Iterable<Rect> others, {required double tol}) {
  final list = others.toList();
  if (list.isEmpty) return GuideResult.none;

  double? bestX, bestY;
  for (final o in list) {
    for (final m in _xs(moving)) {
      for (final t in _xs(o)) {
        final d = t - m;
        if (d.abs() <= tol && (bestX == null || d.abs() < bestX.abs())) bestX = d;
      }
    }
    for (final m in _ys(moving)) {
      for (final t in _ys(o)) {
        final d = t - m;
        if (d.abs() <= tol && (bestY == null || d.abs() < bestY.abs())) bestY = d;
      }
    }
  }
  final dx = bestX ?? 0, dy = bestY ?? 0;
  final snapped = moving.shift(Offset(dx, dy));

  final lines = <GuideLine>[];
  const eps = 0.001;
  for (final o in list) {
    if (bestX != null) {
      for (final m in _xs(snapped)) {
        for (final t in _xs(o)) {
          if ((t - m).abs() <= eps) {
            lines.add(GuideLine(
              vertical: true,
              pos: t,
              from: math.min(snapped.top, o.top),
              to: math.max(snapped.bottom, o.bottom),
            ));
          }
        }
      }
    }
    if (bestY != null) {
      for (final m in _ys(snapped)) {
        for (final t in _ys(o)) {
          if ((t - m).abs() <= eps) {
            lines.add(GuideLine(
              vertical: false,
              pos: t,
              from: math.min(snapped.left, o.left),
              to: math.max(snapped.right, o.right),
            ));
          }
        }
      }
    }
  }
  return GuideResult(dx, dy, _merge(lines));
}

List<double> _xs(Rect r) => [r.left, r.center.dx, r.right];
List<double> _ys(Rect r) => [r.top, r.center.dy, r.bottom];

/// รวมเส้นที่อยู่ตำแหน่งเดียวกันและแกนเดียวกันให้เหลือเส้นเดียว (ครอบช่วงทั้งหมด)
List<GuideLine> _merge(List<GuideLine> lines) {
  final out = <GuideLine>[];
  for (final l in lines) {
    final i = out.indexWhere((g) => g.vertical == l.vertical && (g.pos - l.pos).abs() <= 0.001);
    if (i < 0) {
      out.add(l);
    } else {
      final g = out[i];
      out[i] = GuideLine(vertical: g.vertical, pos: g.pos, from: math.min(g.from, l.from), to: math.max(g.to, l.to));
    }
  }
  return out;
}
