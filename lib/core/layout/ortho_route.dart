import 'dart:math' as math;

/// เรขาคณิตของเส้นหักมุมฉากที่ใช้ร่วมกันระหว่างแผนภาพ (DFD, Flowchart, …) — ฟังก์ชันล้วน ไม่ขึ้นกับโมเดลของแผนภาพใด

typedef RoutePoint = (double x, double y);

/// กล่องที่เส้นต่อได้ (พิกัดแผนภาพ)
class RouteBox {
  const RouteBox(this.id, this.x, this.y, this.w, this.h);
  final String id;
  final double x, y, w, h;
  double get cx => x + w / 2;
  double get cy => y + h / 2;
  double get right => x + w;
  double get bottom => y + h;
}

/// เส้นหนึ่งเส้นจากกล่อง [from] ไปกล่อง [to]
class RouteLink {
  const RouteLink(this.id, this.from, this.to);
  final String id, from, to;
}

enum RouteSide { left, right, top, bottom }

bool isHorizontalSide(RouteSide s) => s == RouteSide.left || s == RouteSide.right;

/// เส้นทางหักมุมฉากของทุกเส้น (key = id): ออกด้านที่หันหาอีกกล่อง กระจายช่องตามด้านของกล่อง
/// เส้นที่ออก/เข้าด้านเดียวกันของกล่องเดียวกันถูกเรียงเป็นช่องคนละระดับ จึงไม่ซ้อนกัน
/// เส้นที่วิ่งทับกันในช่องว่างเดียวกันถูกดันห่างกัน — ลำดับของ [links] มีผลต่อการดัน (ผลลัพธ์คงที่)
/// [gutter] = ระยะห่างขั้นต่ำระหว่างขอบที่ถือว่าอยู่คนละฝั่ง, [slotGap] = ระยะระหว่างช่องบนด้านเดียวกัน
/// [preferVertical] = กล่องเฉียงกันให้ออกแนวตั้งก่อน (Flowchart บนลงล่าง) ; false = ออกตามแกนที่ห่างกว่า (DFD)
Map<String, List<RoutePoint>> orthogonalRoutes(
  Map<String, RouteBox> boxes,
  List<RouteLink> links, {
  double gutter = 28,
  double slotGap = 18,
  bool preferVertical = false,
}) {
  final sides = <String, (RouteSide, RouteSide)>{};
  // (boxId, side) -> [(linkId, isStart, ตำแหน่งอ้างอิงตามแนวขนานขอบ)]
  final slots = <(String, RouteSide), List<(String, bool, double)>>{};

  for (final f in links) {
    final a = boxes[f.from], b = boxes[f.to];
    if (a == null || b == null) continue;
    final s = routeSidesFor(a, b, gutter: gutter, preferVertical: preferVertical);
    sides[f.id] = s;
    final horizontal = isHorizontalSide(s.$1);
    slots.putIfAbsent((a.id, s.$1), () => []).add((f.id, true, horizontal ? b.cy : b.cx));
    slots.putIfAbsent((b.id, s.$2), () => []).add((f.id, false, horizontal ? a.cy : a.cx));
  }

  // ตำแหน่งปลายเส้น: จุดกึ่งกลางด้าน + ระยะช่อง
  final start = <String, RoutePoint>{}, end = <String, RoutePoint>{};
  slots.forEach((key, list) {
    final n = boxes[key.$1]!;
    list.sort((p, q) {
      final c = p.$3.compareTo(q.$3);
      return c != 0 ? c : p.$1.compareTo(q.$1);
    });
    final horizontal = isHorizontalSide(key.$2);
    final extent = horizontal ? n.h : n.w;
    final gap = list.length <= 1 ? 0.0 : math.min(slotGap, (extent - 16) / (list.length - 1));
    for (var i = 0; i < list.length; i++) {
      final off = (i - (list.length - 1) / 2) * gap;
      final RoutePoint p = switch (key.$2) {
        RouteSide.left => (n.x, n.cy + off),
        RouteSide.right => (n.right, n.cy + off),
        RouteSide.top => (n.cx + off, n.y),
        RouteSide.bottom => (n.cx + off, n.bottom),
      };
      (list[i].$2 ? start : end)[list[i].$1] = p;
    }
  });

  List<RoutePoint> build(String id, double shift) {
    final s = sides[id]!;
    final p0 = start[id]!, p1 = end[id]!;
    final horizontal = isHorizontalSide(s.$1);
    if (horizontal) {
      if ((p0.$2 - p1.$2).abs() < 0.5) return [p0, (p1.$1, p0.$2)];
      final mx = (p0.$1 + p1.$1) / 2 + shift;
      return [p0, (mx, p0.$2), (mx, p1.$2), p1];
    }
    if ((p0.$1 - p1.$1).abs() < 0.5) return [p0, (p0.$1, p1.$2)];
    final my = (p0.$2 + p1.$2) / 2 + shift;
    return [p0, (p0.$1, my), (p1.$1, my), p1];
  }

  final ids = [for (final f in links) if (sides.containsKey(f.id)) f.id];
  final shifts = {for (final id in ids) id: 0.0};
  final routes = {for (final id in ids) id: build(id, 0)};

  // เส้นที่ช่วงกลาง (ตั้งฉากกับทิศออก) ทับกัน: ดันเส้นหลังออกไปทีละ 12 px
  for (var pass = 0; pass < 6; pass++) {
    var changed = false;
    for (var j = 1; j < ids.length; j++) {
      for (var i = 0; i < j; i++) {
        // เฉพาะช่วงกลาง (ไม่นับช่วงที่เริ่ม/จบที่กล่อง) ที่อยู่ในช่องว่างร่วมกัน
        if (routes[ids[j]]!.length > 2 &&
            routes[ids[i]]!.length > 2 &&
            routeSegmentsOverlap(routes[ids[i]]!.sublist(1, routes[ids[i]]!.length - 1),
                routes[ids[j]]!.sublist(1, routes[ids[j]]!.length - 1))) {
          shifts[ids[j]] = shifts[ids[j]]! + 12;
          routes[ids[j]] = build(ids[j], shifts[ids[j]]!);
          changed = true;
          break;
        }
      }
    }
    if (!changed) break;
  }
  return routes;
}

/// สองเส้นทางมีช่วงตรงที่วิ่งซ้อนทับกัน (แนวเดียวกัน ห่างกันไม่ถึง 6 px และทับกันเกิน 4 px) หรือไม่
bool routeSegmentsOverlap(List<RoutePoint> a, List<RoutePoint> b) {
  for (var i = 1; i < a.length; i++) {
    for (var j = 1; j < b.length; j++) {
      final av = (a[i - 1].$1 - a[i].$1).abs() < 0.001 && (a[i - 1].$2 - a[i].$2).abs() > 2;
      final bv = (b[j - 1].$1 - b[j].$1).abs() < 0.001 && (b[j - 1].$2 - b[j].$2).abs() > 2;
      final ah = (a[i - 1].$2 - a[i].$2).abs() < 0.001 && (a[i - 1].$1 - a[i].$1).abs() > 2;
      final bh = (b[j - 1].$2 - b[j].$2).abs() < 0.001 && (b[j - 1].$1 - b[j].$1).abs() > 2;
      if (av && bv && (a[i].$1 - b[j].$1).abs() < 6) {
        final lo = math.max(math.min(a[i - 1].$2, a[i].$2), math.min(b[j - 1].$2, b[j].$2));
        final hi = math.min(math.max(a[i - 1].$2, a[i].$2), math.max(b[j - 1].$2, b[j].$2));
        if (hi - lo > 4) return true;
      }
      if (ah && bh && (a[i].$2 - b[j].$2).abs() < 6) {
        final lo = math.max(math.min(a[i - 1].$1, a[i].$1), math.min(b[j - 1].$1, b[j].$1));
        final hi = math.min(math.max(a[i - 1].$1, a[i].$1), math.max(b[j - 1].$1, b[j].$1));
        if (hi - lo > 4) return true;
      }
    }
  }
  return false;
}

RouteSide _sideAxis(RouteBox a, RouteBox b, bool horizontal) {
  if (horizontal) return a.cx <= b.cx ? RouteSide.right : RouteSide.left;
  return a.cy <= b.cy ? RouteSide.bottom : RouteSide.top;
}

/// ด้านที่เส้นออกจาก [a] และเข้า [b]
(RouteSide, RouteSide) routeSidesFor(RouteBox a, RouteBox b, {double gutter = 28, bool preferVertical = false}) {
  final gapX = math.max(a.x - b.right, b.x - a.right); // บวก = มีช่องว่างแนวนอน
  final gapY = math.max(a.y - b.bottom, b.y - a.bottom);
  final bool horizontal;
  if (gapX >= gutter && gapY >= gutter) {
    horizontal = preferVertical ? false : gapX >= gapY; // เฉียง
  } else if (gapX >= gutter) {
    horizontal = true;
  } else if (gapY >= gutter) {
    horizontal = false;
  } else {
    // ซ้อน/ชิดกัน: ใช้แกนที่ศูนย์กลางห่างกว่า
    horizontal = (a.cx - b.cx).abs() >= (a.cy - b.cy).abs();
  }
  return (_sideAxis(a, b, horizontal), _sideAxis(b, a, horizontal));
}

/// จุดวางป้ายชื่อ: กึ่งกลางช่วงที่ยาวที่สุดของเส้น
RoutePoint routeLabelAnchor(List<RoutePoint> pts) {
  var best = 0, bestLen = -1.0;
  for (var i = 1; i < pts.length; i++) {
    final len = (pts[i].$1 - pts[i - 1].$1).abs() + (pts[i].$2 - pts[i - 1].$2).abs();
    if (len > bestLen) {
      bestLen = len;
      best = i;
    }
  }
  final a = pts[best - 1], b = pts[best];
  return ((a.$1 + b.$1) / 2, (a.$2 + b.$2) / 2);
}

/// จุดที่สัดส่วน [t] (0..1) ของความยาวเส้นทาง
RoutePoint routePointAt(List<RoutePoint> pts, double t) {
  if (pts.length == 1) return pts.first;
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += _len(pts[i - 1], pts[i]);
  }
  if (total == 0) return pts.first;
  var want = t.clamp(0.0, 1.0) * total;
  for (var i = 1; i < pts.length; i++) {
    final l = _len(pts[i - 1], pts[i]);
    if (want <= l || i == pts.length - 1) {
      final k = l == 0 ? 0.0 : (want / l).clamp(0.0, 1.0);
      return (pts[i - 1].$1 + (pts[i].$1 - pts[i - 1].$1) * k, pts[i - 1].$2 + (pts[i].$2 - pts[i - 1].$2) * k);
    }
    want -= l;
  }
  return pts.last;
}

/// สัดส่วน (0..1) ตามความยาวเส้นทางของจุดบนเส้นที่ใกล้ ([x],[y]) ที่สุด
double routeParamAt(List<RoutePoint> pts, double x, double y) {
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += _len(pts[i - 1], pts[i]);
  }
  if (total == 0) return 0.5;
  var best = double.infinity, bestT = 0.5, acc = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final (ax, ay) = pts[i - 1];
    final (bx, by) = pts[i];
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final k = len2 == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / len2).clamp(0.0, 1.0);
    final px = ax + k * dx - x, py = ay + k * dy - y;
    final d = px * px + py * py;
    final l = math.sqrt(len2);
    if (d < best) {
      best = d;
      bestT = (acc + k * l) / total;
    }
    acc += l;
  }
  return bestT;
}

double _len(RoutePoint a, RoutePoint b) {
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
  return math.sqrt(dx * dx + dy * dy);
}

/// ระยะจากจุดถึงเส้นทาง (ช่วงสั้นสุด)
double distanceToRoute(List<RoutePoint> pts, double x, double y) {
  var best = double.infinity;
  for (var i = 1; i < pts.length; i++) {
    final (ax, ay) = pts[i - 1];
    final (bx, by) = pts[i];
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / len2).clamp(0.0, 1.0);
    final px = ax + t * dx - x, py = ay + t * dy - y;
    best = math.min(best, math.sqrt(px * px + py * py));
  }
  return best;
}
