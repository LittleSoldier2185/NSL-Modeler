import 'dart:math' as math;

import '../models/flowchart_model.dart';
import 'ortho_route.dart';

/// เรขาคณิตของ Flowchart (ใช้ร่วมกันทั้งบนจอ / PNG / SVG / การคลิก) — ฟังก์ชันล้วน

/// คำสั่งวาดเส้นแบบกลาง: 'M' (1 จุด), 'L' (1 จุด), 'C' (3 จุด: ควบคุม 2 + ปลาย), 'Z' (ไม่มีจุด)
typedef FcCmd = (String op, List<RoutePoint> pts);

/// ส่วนประกอบของรูปทรงหนึ่งรูป: เส้นรอบรูป (เติมสีได้) + เส้นตกแต่งด้านใน (เส้นอย่างเดียว)
class FcShapeGeom {
  const FcShapeGeom(this.outline, this.details);
  final List<FcCmd> outline;
  final List<FcCmd> details;
}

const double _k = 0.5522847498;

/// ความเอียงของสี่เหลี่ยมด้านขนาน (Input/Output)
double fcIoSkew(FcNode n) => math.min(n.w * 0.25, n.h * 0.45);

/// ขนาดมุมพับของโน้ต
double fcNoteFold(FcNode n) => math.min(16, math.min(n.w, n.h) * 0.3);

List<FcCmd> _ellipse(double x, double y, double w, double h) {
  final rx = w / 2, ry = h / 2, cx = x + rx, cy = y + ry;
  return [
    ('M', [(cx + rx, cy)]),
    ('C', [(cx + rx, cy + ry * _k), (cx + rx * _k, cy + ry), (cx, cy + ry)]),
    ('C', [(cx - rx * _k, cy + ry), (cx - rx, cy + ry * _k), (cx - rx, cy)]),
    ('C', [(cx - rx, cy - ry * _k), (cx - rx * _k, cy - ry), (cx, cy - ry)]),
    ('C', [(cx + rx * _k, cy - ry), (cx + rx, cy - ry * _k), (cx + rx, cy)]),
    ('Z', const []),
  ];
}

List<FcCmd> _roundRect(double x, double y, double w, double h, double r) {
  r = math.min(r, math.min(w, h) / 2);
  final rr = r * (1 - _k);
  return [
    ('M', [(x + r, y)]),
    ('L', [(x + w - r, y)]),
    ('C', [(x + w - rr, y), (x + w, y + rr), (x + w, y + r)]),
    ('L', [(x + w, y + h - r)]),
    ('C', [(x + w, y + h - rr), (x + w - rr, y + h), (x + w - r, y + h)]),
    ('L', [(x + r, y + h)]),
    ('C', [(x + rr, y + h), (x, y + h - rr), (x, y + h - r)]),
    ('L', [(x, y + r)]),
    ('C', [(x, y + rr), (x + rr, y), (x + r, y)]),
    ('Z', const []),
  ];
}

List<FcCmd> _poly(List<RoutePoint> pts) => [
      ('M', [pts.first]),
      for (final p in pts.skip(1)) ('L', [p]),
      ('Z', const []),
    ];

/// รูปทรงของสัญลักษณ์ [n] ในพิกัดแผนภาพ
FcShapeGeom fcShapeGeom(FcNode n) {
  final x = n.x, y = n.y, w = n.w, h = n.h, r = n.right, b = n.bottom;
  switch (n.shape) {
    case FcShape.start || FcShape.end:
      return FcShapeGeom(_roundRect(x, y, w, h, math.min(w, h) / 2), const []);
    case FcShape.process:
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b), (x, b)]), const []);
    case FcShape.rounded:
      return FcShapeGeom(_roundRect(x, y, w, h, math.min(12, math.min(w, h) / 4)), const []);
    case FcShape.decision:
      return FcShapeGeom(_poly([(n.cx, y), (r, n.cy), (n.cx, b), (x, n.cy)]), const []);
    case FcShape.io:
      final s = fcIoSkew(n);
      return FcShapeGeom(_poly([(x + s, y), (r, y), (r - s, b), (x, b)]), const []);
    case FcShape.subroutine:
      final i = math.min(12.0, w * 0.1);
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b), (x, b)]), [
        ('M', [(x + i, y)]),
        ('L', [(x + i, b)]),
        ('M', [(r - i, y)]),
        ('L', [(r - i, b)]),
      ]);
    case FcShape.connector || FcShape.ellipse:
      return FcShapeGeom(_ellipse(x, y, w, h), const []);
    case FcShape.note:
      final f = fcNoteFold(n);
      return FcShapeGeom(_poly([(x, y), (r - f, y), (r, y + f), (r, b), (x, b)]), [
        ('M', [(r - f, y)]),
        ('L', [(r - f, y + f)]),
        ('L', [(r, y + f)]),
      ]);
  }
}

/// กรอบวางข้อความภายในสัญลักษณ์ (left, top, width, height)
({double left, double top, double width, double height}) fcTextBox(FcNode n) {
  final (l, t, rr, bb) = switch (n.shape) {
    FcShape.decision => (n.w * 0.2, n.h * 0.18, n.w * 0.2, n.h * 0.18),
    FcShape.io => (fcIoSkew(n) * 0.75 + 4, 4.0, fcIoSkew(n) * 0.75 + 4, 4.0),
    FcShape.subroutine => (math.min(12.0, n.w * 0.1) + 6, 4.0, math.min(12.0, n.w * 0.1) + 6, 4.0),
    FcShape.start || FcShape.end => (math.min(n.w, n.h) / 4 + 4, 4.0, math.min(n.w, n.h) / 4 + 4, 4.0),
    FcShape.ellipse || FcShape.connector => (n.w * 0.14, n.h * 0.14, n.w * 0.14, n.h * 0.14),
    FcShape.note => (10.0, 8.0, fcNoteFold(n) + 4, 8.0),
    _ => (10.0, 6.0, 10.0, 6.0),
  };
  return (left: n.x + l, top: n.y + t, width: math.max(4, n.w - l - rr), height: math.max(4, n.h - t - bb));
}

/// จุด ([x],[y]) อยู่ในรูปทรงของ [n] หรือไม่ (เผื่อขอบ [tol])
bool fcNodeContains(FcNode n, double x, double y, {double tol = 0}) {
  if (x < n.x - tol || x > n.right + tol || y < n.y - tol || y > n.bottom + tol) return false;
  switch (n.shape) {
    case FcShape.decision:
      final dx = (x - n.cx).abs() / (n.w / 2 + tol), dy = (y - n.cy).abs() / (n.h / 2 + tol);
      return dx + dy <= 1;
    case FcShape.ellipse || FcShape.connector:
      final dx = (x - n.cx) / (n.w / 2 + tol), dy = (y - n.cy) / (n.h / 2 + tol);
      return dx * dx + dy * dy <= 1;
    default:
      return true;
  }
}

/// เลื่อนปลายเส้น [p] ที่อยู่บนด้าน [side] ของกรอบ เข้าไปแตะเส้นรอบรูปจริง (เลื่อนตามแกนที่ออกเท่านั้น เส้นยังตั้งฉาก)
RoutePoint fcSnapToOutline(FcNode n, RouteSide side, RoutePoint p) {
  final horizontal = isHorizontalSide(side);
  final sign = (side == RouteSide.left || side == RouteSide.top) ? 1.0 : -1.0;
  double inset; // ระยะจากขอบกรอบเข้าไปถึงเส้นรอบรูป
  switch (n.shape) {
    case FcShape.decision:
      final f = horizontal ? ((p.$2 - n.cy).abs() / (n.h / 2)) : ((p.$1 - n.cx).abs() / (n.w / 2));
      inset = (horizontal ? n.w / 2 : n.h / 2) * f.clamp(0.0, 1.0);
    case FcShape.ellipse || FcShape.connector:
      final a = horizontal ? n.w / 2 : n.h / 2, bb = horizontal ? n.h / 2 : n.w / 2;
      final d = horizontal ? (p.$2 - n.cy) : (p.$1 - n.cx);
      final q = (d / bb).clamp(-1.0, 1.0);
      inset = a - a * math.sqrt(1 - q * q);
    case FcShape.start || FcShape.end:
      final rad = math.min(n.w, n.h) / 2;
      if (horizontal && n.w >= n.h || !horizontal && n.h > n.w) {
        final d = horizontal ? (p.$2 - n.cy) : (p.$1 - n.cx);
        final q = d.abs().clamp(0.0, rad);
        inset = rad - math.sqrt(rad * rad - q * q);
      } else {
        inset = 0;
      }
    case FcShape.io:
      if (!horizontal) {
        inset = 0;
      } else {
        final s = fcIoSkew(n);
        final t = ((p.$2 - n.y) / n.h).clamp(0.0, 1.0);
        inset = side == RouteSide.left ? s * (1 - t) : s * t;
      }
    default:
      inset = 0;
  }
  return horizontal ? (p.$1 + sign * inset, p.$2) : (p.$1, p.$2 + sign * inset);
}

/// เส้นทางของเส้นเชื่อมทุกเส้น (key = id) — หักมุมฉาก ชอบออกแนวตั้ง (บนลงล่าง) ปลายเส้นแตะเส้นรอบรูปจริง
/// เส้นวนเข้าตัวเองวาดเป็นห่วงเล็กทางขวาของสัญลักษณ์
Map<String, List<RoutePoint>> fcRoutes(FlowchartDiagram d) {
  final boxes = <String, RouteBox>{};
  final byId = <String, FcNode>{};
  for (final n in d.nodes) {
    boxes.putIfAbsent(n.id, () => RouteBox(n.id, n.x, n.y, n.w, n.h));
    byId.putIfAbsent(n.id, () => n);
  }
  final links = [for (final e in d.edges) if (e.fromId != e.toId) RouteLink(e.id, e.fromId, e.toId)];
  final raw = orthogonalRoutes(boxes, links, gutter: 24, slotGap: 16, preferVertical: true);
  final out = <String, List<RoutePoint>>{};
  for (final e in d.edges) {
    final a = byId[e.fromId], b = byId[e.toId];
    if (a == null || b == null) continue;
    if (e.fromId == e.toId) {
      final r = a.right, y0 = a.cy - math.min(12, a.h / 4), y1 = a.cy + math.min(12, a.h / 4);
      out[e.id] = [(r, y0), (r + 28, y0), (r + 28, y1), (r, y1)];
      continue;
    }
    final pts = raw[e.id];
    if (pts == null || pts.length < 2) continue;
    final route = List.of(pts);
    route[0] = fcSnapToOutline(a, _sideOf(a, pts.first), pts.first);
    route[route.length - 1] = fcSnapToOutline(b, _sideOf(b, pts.last), pts.last);
    out[e.id] = route;
  }
  return out;
}

RouteSide _sideOf(FcNode n, RoutePoint p) {
  final dl = (p.$1 - n.x).abs(), dr = (p.$1 - n.right).abs(), dt = (p.$2 - n.y).abs(), db = (p.$2 - n.bottom).abs();
  final m = [dl, dr, dt, db].reduce(math.min);
  if (m == dt) return RouteSide.top;
  if (m == db) return RouteSide.bottom;
  if (m == dl) return RouteSide.left;
  return RouteSide.right;
}

/// สัญลักษณ์บนสุดที่ ([x],[y]) อยู่ในรูปทรง (ท้ายรายการก่อน)
FcNode? fcNodeAt(FlowchartDiagram d, double x, double y, {double tol = 0}) {
  for (final n in d.nodes.reversed) {
    if (fcNodeContains(n, x, y, tol: tol)) return n;
  }
  return null;
}

/// เส้นที่อยู่ใกล้จุดภายใน [tolerance] (ใกล้สุดก่อน) ; ไม่มี = null
String? fcEdgeAt(FlowchartDiagram d, double x, double y, {double tolerance = 7, Map<String, List<RoutePoint>>? routes}) {
  String? best;
  var bestD = tolerance;
  (routes ?? fcRoutes(d)).forEach((id, pts) {
    final dist = distanceToRoute(pts, x, y);
    if (dist <= bestD) {
      bestD = dist;
      best = id;
    }
  });
  return best;
}

/// ขอบเขตของแผนภาพ (สัญลักษณ์ + เส้น) เผื่อขอบ [pad] ; ว่าง = null
({double left, double top, double right, double bottom})? fcBounds(FlowchartDiagram d, {double pad = 40, Set<String>? only}) {
  final nodes = only == null ? d.nodes : d.nodes.where((n) => only.contains(n.id)).toList();
  if (nodes.isEmpty) return null;
  var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  for (final n in nodes) {
    l = math.min(l, n.x);
    t = math.min(t, n.y);
    r = math.max(r, n.right);
    b = math.max(b, n.bottom);
  }
  if (only == null) {
    for (final pts in fcRoutes(d).values) {
      for (final (x, y) in pts) {
        l = math.min(l, x);
        t = math.min(t, y);
        r = math.max(r, x);
        b = math.max(b, y);
      }
    }
  }
  return (left: l - pad, top: t - pad, right: r + pad, bottom: b + pad);
}

/// รูปหัวลูกศรที่ปลาย [to] ของช่วง [from]→[to] : (เส้นปิดเติมสี?, จุด) — none = ว่าง
(bool filled, List<RoutePoint>) fcArrowHead(FcArrow a, RoutePoint from, RoutePoint to, {double size = 10}) {
  if (a == FcArrow.none) return (false, const []);
  final dx = to.$1 - from.$1, dy = to.$2 - from.$2;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 0.001) return (false, const []);
  final ux = dx / len, uy = dy / len;
  final bx = to.$1 - ux * size, by = to.$2 - uy * size;
  final nx = -uy, ny = ux;
  final p1 = (bx + nx * size * 0.45, by + ny * size * 0.45), p2 = (bx - nx * size * 0.45, by - ny * size * 0.45);
  return a == FcArrow.arrow ? (true, [to, p1, p2]) : (false, [p1, to, p2]);
}
