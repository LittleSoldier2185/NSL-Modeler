import 'dart:ui';

import '../models/dfd_model.dart';
import 'diagram_geometry.dart' show snapToGrid;

/// จุดจับปรับขนาดรอบวัตถุ DFD (มุมทั้ง 4 + กึ่งกลางด้านทั้ง 4)
enum DfdHandle { nw, n, ne, e, se, s, sw, w }

/// ตำแหน่งของจุดจับบนกรอบ [r]
Offset dfdHandlePos(Rect r, DfdHandle h) => switch (h) {
      DfdHandle.nw => r.topLeft,
      DfdHandle.n => r.topCenter,
      DfdHandle.ne => r.topRight,
      DfdHandle.e => r.centerRight,
      DfdHandle.se => r.bottomRight,
      DfdHandle.s => r.bottomCenter,
      DfdHandle.sw => r.bottomLeft,
      DfdHandle.w => r.centerLeft,
    };

/// จุดจับของกรอบสี่เหลี่ยม [r] ที่ [p] อยู่ใกล้ที่สุดภายในรัศมี [tol]
DfdHandle? dfdHandleAtRect(Rect r, Offset p, double tol) {
  DfdHandle? best;
  var bestD = tol * tol;
  for (final h in DfdHandle.values) {
    final c = dfdHandlePos(r, h);
    final d = (c.dx - p.dx) * (c.dx - p.dx) + (c.dy - p.dy) * (c.dy - p.dy);
    if (d <= bestD) {
      bestD = d;
      best = h;
    }
  }
  return best;
}

/// จุดจับที่ [p] อยู่ใกล้ที่สุดภายในรัศมี [tol] (พิกัดแผนภาพ) ; ไม่มี = null
DfdHandle? dfdHandleAt(DfdNode n, Offset p, double tol) {
  final r = Rect.fromLTWH(n.x, n.y, n.w, n.h);
  DfdHandle? best;
  var bestD = tol * tol;
  for (final h in DfdHandle.values) {
    final c = dfdHandlePos(r, h);
    final d = (c.dx - p.dx) * (c.dx - p.dx) + (c.dy - p.dy) * (c.dy - p.dy);
    if (d <= bestD) {
      bestD = d;
      best = h;
    }
  }
  return best;
}

/// กรอบใหม่หลังลากจุดจับ [h] ไป ([dx],[dy]) จากกรอบเดิม [r] : ขอบฝั่งตรงข้ามอยู่กับที่
/// ขอบที่ขยับปัดเข้าช่อง [grid] (ถ้ามี) และถูกจำกัดขนาดระหว่าง [kDfdMinW]/[kDfdMinH] ถึง [kDfdMaxSide]
Rect resizeDfdRect(
  Rect r,
  DfdHandle h,
  double dx,
  double dy, {
  double? grid,
  double minW = kDfdMinW,
  double minH = kDfdMinH,
  double maxSide = kDfdMaxSide,
}) {
  var l = r.left, t = r.top, rt = r.right, b = r.bottom;
  final west = h == DfdHandle.nw || h == DfdHandle.w || h == DfdHandle.sw;
  final east = h == DfdHandle.ne || h == DfdHandle.e || h == DfdHandle.se;
  final north = h == DfdHandle.nw || h == DfdHandle.n || h == DfdHandle.ne;
  final south = h == DfdHandle.sw || h == DfdHandle.s || h == DfdHandle.se;
  double sn(double v) => grid == null ? v : snapToGrid(v, grid);
  if (west) l = sn(l + dx);
  if (east) rt = sn(rt + dx);
  if (north) t = sn(t + dy);
  if (south) b = sn(b + dy);
  // จำกัดขนาด โดยให้ขอบที่ขยับเป็นฝ่ายถอย
  if (west) {
    l = l.clamp(rt - maxSide, rt - minW).toDouble();
  } else if (east) {
    rt = rt.clamp(l + minW, l + maxSide).toDouble();
  }
  if (north) {
    t = t.clamp(b - maxSide, b - minH).toDouble();
  } else if (south) {
    b = b.clamp(t + minH, t + maxSide).toDouble();
  }
  return Rect.fromLTRB(l, t, rt, b);
}
