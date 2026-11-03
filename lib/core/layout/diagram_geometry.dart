import 'dart:math' as math;

import '../models/column_model.dart';
import '../models/group_model.dart';
import '../models/note_model.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';

/// เรขาคณิตของแผนภาพที่ canvas / SVG / PNG ใช้ร่วมกัน เพื่อให้วาดตรงกันทุกที่
const double kCardHeaderHeight = 36;
const double kCardRowHeight = 28;

/// คอลัมน์นี้ไม่ซ้ำกันด้วยตัวเอง (UNIQUE หรือ PK คอลัมน์เดียว) — ใช้ตัดสินว่า FK เป็น 1:1 หรือ หลาย:1
/// คอลัมน์ที่เป็นเพียงส่วนหนึ่งของ PK หลายคอลัมน์ (ตารางเชื่อม) ไม่นับ
bool isUniqueAlone(TableModel t, ColumnModel c) =>
    c.unique || (c.isPrimaryKey && t.columns.where((x) => x.isPrimaryKey).length == 1);

double tableHeight(TableModel t) => kCardHeaderHeight + kCardRowHeight * t.columns.length;

/// จุดกึ่งกลางแนวตั้งของแถวคอลัมน์ที่ [index]
double rowCenterY(double tableY, int index) =>
    tableY + kCardHeaderHeight + kCardRowHeight * index + kCardRowHeight / 2;

/// เส้น FK หนึ่งเส้น: เริ่มที่คอลัมน์ลูก (fx,fy) จบที่คอลัมน์แม่ (tx,ty)
/// d0/d1 = ทิศที่เส้นออก/เข้า (+1 ขวา, -1 ซ้าย), k = ระยะดึงโค้ง
class RelationGeometry {
  const RelationGeometry({
    required this.fx,
    required this.fy,
    required this.tx,
    required this.ty,
    required this.d0,
    required this.d1,
    required this.k,
    required this.oneToOne,
    this.mandatory = true,
  });
  final double fx, fy, tx, ty, d0, d1, k;

  /// คอลัมน์ FK เป็น NOT NULL/PK -> ฝั่งแม่ต้องมีเสมอ ("หนึ่งเดียว" ขีดคู่); ถ้า NULL ได้ = "ศูนย์หรือหนึ่ง" (ขีด + วงกลม)
  final bool mandatory;

  /// คอลัมน์ FK เป็น PK/UNIQUE -> ปลายลูกเป็นขีดแทนตีนกา
  final bool oneToOne;
}

RelationGeometry? relationGeometry(Project p, RelationModel r) {
  final ft = p.tableById(r.fromTableId);
  final tt = p.tableById(r.toTableId);
  if (ft == null || tt == null) return null;
  final fi = ft.columns.indexWhere((c) => c.id == r.fromColumnId);
  final ti = tt.columns.indexWhere((c) => c.id == r.toColumnId);
  if (fi < 0 || ti < 0) return null;
  final fcol = ft.columns[fi];

  final double fx, tx, d0, d1;
  if (ft.x + ft.width <= tt.x) {
    fx = ft.x + ft.width;
    tx = tt.x;
    d0 = 1;
    d1 = -1;
  } else if (tt.x + tt.width <= ft.x) {
    fx = ft.x;
    tx = tt.x + tt.width;
    d0 = -1;
    d1 = 1;
  } else {
    // การ์ดซ้อนกันในแนวนอน (หรือตารางเดียวกัน): ออกด้านขวาทั้งคู่
    fx = ft.x + ft.width;
    tx = tt.x + tt.width;
    d0 = 1;
    d1 = 1;
  }
  return RelationGeometry(
    fx: fx,
    fy: rowCenterY(ft.y, fi),
    tx: tx,
    ty: rowCenterY(tt.y, ti),
    d0: d0,
    d1: d1,
    k: d0 == d1 ? 60.0 : math.max(40.0, (tx - fx).abs() / 2),
    oneToOne: isUniqueAlone(ft, fcol),
    mandatory: fcol.notNull || fcol.isPrimaryKey,
  );
}

/// ระยะที่เส้นยื่นออกจากขอบการ์ดก่อนหักมุม (พอให้พ้นตีนกา 14px)
const double kRouteStub = 22;

/// ระยะห่างระหว่างเส้นที่ต้องใช้ช่องทางเดียวกัน (กันเส้นทับกัน)
const double kRouteLaneGap = 12;

/// แนวตั้งของสองเส้นที่ช่วง y ซ้อนกัน ต้องห่างกันอย่างน้อยเท่านี้ (น้อยกว่านี้ตามองเห็นเป็นเส้นหนาซ้อนกัน)
const double kRouteMinSeparation = 7;

/// เส้นแนวตั้ง/แนวนอนต้องห่างจากขอบกรอบของกลุ่มอย่างน้อยเท่านี้ (ไม่วิ่งทับเส้นขอบประของกลุ่ม)
const double kGroupEdgeClear = 9;

typedef RoutePoint = (double x, double y);

/// ระยะห่างแนวตั้งระหว่างเส้นที่เข้าคอลัมน์แม่เดียวกัน (กระจายอยู่ภายในแถวของคอลัมน์นั้น)
/// และผลรวมสูงสุดที่กระจายได้ (แถวสูง 28 px ต้องเหลือขอบบนล่าง)
const double kEndSpread = 10;
const double kEndSpreadMax = 24;

/// ช่องที่เส้นนี้เข้าตารางแม่: [dy] = ระยะเลื่อนจากกึ่งกลางแถวคอลัมน์แม่ (ลบ = สูงขึ้น),
/// [count] = จำนวนเส้นที่เข้าคอลัมน์แม่เดียวกัน (ใช้ลดขนาดสัญลักษณ์ปลายเส้นไม่ให้ซ้อนกัน)
/// เส้นที่ต้นทางอยู่สูงกว่าจะเข้าช่องที่สูงกว่า เส้นจึงไม่ไขว้กันตอนเข้า — ไม่รวมเป็นเส้นเดียว
Map<String, ({double dy, int count})> parentEndSlots(Project p) {
  final groups = <String, List<(String, double)>>{};
  for (final r in p.relations) {
    final g = relationGeometry(p, r);
    if (g == null) continue;
    groups.putIfAbsent('${r.toTableId}:${r.toColumnId}:${g.d1}', () => []).add((r.id, g.fy));
  }
  final out = <String, ({double dy, int count})>{};
  for (final members in groups.values) {
    members.sort((a, b) {
      final c = a.$2.compareTo(b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    final n = members.length;
    final gap = n <= 1 ? 0.0 : math.min(kEndSpread, kEndSpreadMax / (n - 1));
    for (var k = 0; k < n; k++) {
      out[members[k].$1] = (dy: (k - (n - 1) / 2) * gap, count: n);
    }
  }
  return out;
}

/// เลื่อนช่วงท้ายของเส้นให้เข้าตารางแม่ที่ระดับ `ty + dy` (เส้นตรง 2 จุดจะหักเป็น 4 จุดที่กึ่งกลาง)
List<RoutePoint> _withEnd(List<RoutePoint> pts, double dy) {
  if (dy == 0) return pts;
  RoutePoint shift(RoutePoint q) => (q.$1, q.$2 + dy);
  if (pts.length == 2) {
    final mx = (pts[0].$1 + pts[1].$1) / 2;
    return [pts[0], (mx, pts[0].$2), (mx, pts[1].$2 + dy), shift(pts[1])];
  }
  final n = pts.length;
  return [...pts.sublist(0, n - 2), shift(pts[n - 2]), shift(pts[n - 1])];
}

/// เส้นทางของ FK ทุกเส้นแบบหักมุมฉาก (จุดต่อกันจากคอลัมน์ลูกไปคอลัมน์แม่) key = id ของความสัมพันธ์
///
/// - การ์ดอยู่คนละฝั่ง: ออกแนวนอน -> หักแนวตั้งกลางช่องว่างระหว่างการ์ด -> เข้าแนวนอน
/// - การ์ดซ้อนกันหรือเป็นตารางเดียวกัน: อ้อมออกด้านข้างแล้วกลับเข้ามา
/// - เส้นที่ใช้ช่องว่างเดียวกันจะถูกเรียงเป็นเลนขนาน ห่าง [kRouteLaneGap] ไม่ทับกัน
/// - เลี่ยงการ์ด/โน้ตที่ขวางทาง: ขยับแนวตั้งหาช่องว่าง ถ้าไม่ได้ให้อ้อมผ่านเหนือ/ใต้
Map<String, List<RoutePoint>> relationRoutes(Project p) {
  final boxes = _obstacles(p);
  final edges = _groupRects(p);
  final items = <({String id, String fromT, String toT, String toCol, RelationGeometry g, bool same, bool self, double base, double yKey})>[];
  for (final r in p.relations) {
    final g = relationGeometry(p, r);
    if (g == null) continue;
    final same = g.d0 == g.d1;
    final base = same ? (g.d0 > 0 ? math.max(g.fx, g.tx) : math.min(g.fx, g.tx)) : (g.fx + g.tx) / 2;
    items.add((
      id: r.id,
      fromT: r.fromTableId,
      toT: r.toTableId,
      toCol: r.toColumnId,
      g: g,
      same: same,
      self: r.fromTableId == r.toTableId,
      base: base,
      yKey: math.min(g.fy, g.ty),
    ));
  }

  // จัดกลุ่มเส้นที่ใช้ช่องทางเดียวกัน แล้วเรียงตามความสูงเพื่อให้เส้นไม่ตัดกันโดยไม่จำเป็น
  // (self-reference แยกกลุ่มของตัวเองต่อตาราง เพื่อไม่ไปปนกับเส้นอื่นที่ออกด้านเดียวกัน)
  final groups = <String, List<int>>{};
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final key = it.self ? 'self:${it.fromT}' : '${it.same ? it.g.d0 : 0}:${(it.base / 30).round()}';
    groups.putIfAbsent(key, () => []).add(i);
  }
  final lane = List<double>.filled(items.length, 0);
  for (final idx in groups.values) {
    // ทุกเส้นมีเลนของตัวเอง แม้จะไปหาคอลัมน์แม่เดียวกัน: ไม่รวมเป็นเส้นเดียว (อ่านได้ว่ามีกี่ความสัมพันธ์)
    // เรียงตามความสูงของเส้นเพื่อให้เส้นขนานไม่ตัดกันโดยไม่จำเป็น
    idx.sort((a, b) => items[a].yKey.compareTo(items[b].yKey));
    for (var k = 0; k < idx.length; k++) {
      final i = idx[k];
      // คนละฝั่ง: กระจายรอบกึ่งกลางช่อง; ฝั่งเดียวกัน: เรียงออกไปด้านนอก
      lane[i] = items[i].same ? k * kRouteLaneGap : (k - (idx.length - 1) / 2) * kRouteLaneGap;
    }
  }

  final slots = parentEndSlots(p);

  List<RoutePoint> build(int i, double extraLane) {
    final it = items[i];
    final g = it.g;
    final ignore = {it.fromT, it.toT};
    final List<RoutePoint> pts;
    if (it.same) {
      // ฝั่งเดียวกัน (การ์ดซ้อนกัน / ตารางเดียวกัน): อ้อมออกด้านข้าง self-reference ยื่นไกลกว่าเพื่อให้เห็นเป็นห่วง
      final stub = it.self ? kRouteSelfLoop : kRouteStub;
      pts = _sameSideRoute(g, it.base, stub + lane[i] + extraLane, boxes, ignore, edges);
    } else {
      pts = _gutterRoute(g, it.base + lane[i] + extraLane, boxes, ignore, edges);
    }
    return _withEnd(pts, slots[it.id]?.dy ?? 0);
  }

  final routes = [for (var i = 0; i < items.length; i++) build(i, 0)];

  // ---- เส้นที่วิ่งทับกัน: แนวตั้งของสองเส้นอยู่ x เดียวกันและช่วง y ซ้อนกัน -> ดันเลนของเส้นหลังออกไป ----
  // (เลนปกติแยกกันอยู่แล้วในกลุ่มเดียวกัน แต่เส้นต่างกลุ่ม/ถูกเลี่ยงสิ่งกีดขวางอาจไปตกที่ x เดียวกันได้)
  final extra = List<double>.filled(items.length, 0);
  bool overlapping(List<RoutePoint> a, List<RoutePoint> b) {
    for (var s = 1; s < a.length; s++) {
      if ((a[s - 1].$1 - a[s].$1).abs() > 0.001) continue; // ไม่ใช่แนวตั้ง
      final ax = a[s].$1;
      final a0 = math.min(a[s - 1].$2, a[s].$2), a1 = math.max(a[s - 1].$2, a[s].$2);
      if (a1 - a0 < 2) continue;
      for (var u = 1; u < b.length; u++) {
        if ((b[u - 1].$1 - b[u].$1).abs() > 0.001) continue;
        if ((b[u].$1 - ax).abs() > kRouteMinSeparation) continue;
        final b0 = math.min(b[u - 1].$2, b[u].$2), b1 = math.max(b[u - 1].$2, b[u].$2);
        if (math.min(a1, b1) - math.max(a0, b0) > 1.5) return true;
      }
    }
    return false;
  }

  for (var pass = 0; pass < 8; pass++) {
    var changed = false;
    for (var j = 1; j < routes.length; j++) {
      for (var i = 0; i < j; i++) {
        if (overlapping(routes[i], routes[j])) {
          extra[j] += kRouteLaneGap;
          routes[j] = build(j, extra[j]);
          changed = true;
          break;
        }
      }
    }
    if (!changed) break;
  }

  return {for (var i = 0; i < items.length; i++) items[i].id: routes[i]};
}

/// ระยะที่ self-reference ยื่นออกจากขอบการ์ด (ไกลกว่าเส้นทั่วไปให้เห็นเป็นห่วงชัด)
const double kRouteSelfLoop = 44;

/// ช่องไฟรอบการ์ด/โน้ตที่เส้นต้องเว้น และก้าวที่ใช้ลองหาช่องทางใหม่
const double kRoutePad = 6;
const double kRouteStep = 10;

typedef _Box = (String? id, double l, double t, double r, double b);

/// กรอบของกลุ่มทุกกลุ่ม (l, t, r, b) — เส้นข้ามได้ แต่ไม่ควรวิ่งเกาะขอบ
List<(double, double, double, double)> _groupRects(Project p) =>
    [for (final g in p.groups) (g.x, g.y, g.x + g.width, g.y + g.height)];

/// เส้นมีช่วงที่วิ่งเกาะขอบกรอบกลุ่ม (ห่างน้อยกว่า [kGroupEdgeClear] และขนานไปกับขอบ) หรือไม่
bool _hugsGroupEdge(List<RoutePoint> pts, List<(double, double, double, double)> rects) {
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final horizontal = (a.$2 - b.$2).abs() < 0.001;
    final lo = horizontal ? math.min(a.$1, b.$1) : math.min(a.$2, b.$2);
    final hi = horizontal ? math.max(a.$1, b.$1) : math.max(a.$2, b.$2);
    if (hi - lo < 2) continue;
    for (final (l, t, r, bt) in rects) {
      if (horizontal) {
        final y = a.$2;
        if ((y - t).abs() < kGroupEdgeClear || (y - bt).abs() < kGroupEdgeClear) {
          if (hi > l && lo < r) return true;
        }
      } else {
        final x = a.$1;
        if ((x - l).abs() < kGroupEdgeClear || (x - r).abs() < kGroupEdgeClear) {
          if (hi > t && lo < bt) return true;
        }
      }
    }
  }
  return false;
}

/// สิ่งกีดขวางของเส้น: การ์ดตารางและโน้ต (ขยายขอบเผื่อช่องไฟ)
List<_Box> _obstacles(Project p) => [
      for (final t in p.tables) (t.id, t.x - kRoutePad, t.y - kRoutePad, t.x + t.width + kRoutePad, t.y + tableHeight(t) + kRoutePad),
      for (final n in p.notes) (null, n.x - kRoutePad, n.y - kRoutePad, n.x + n.width + kRoutePad, n.y + noteHeight(n) + kRoutePad),
    ];

/// เส้นทางตัดผ่านสิ่งกีดขวางหรือไม่ (ข้ามการ์ดต้นทาง/ปลายทางใน [ignore]; แตะขอบไม่นับ)
bool _blocked(List<RoutePoint> pts, List<_Box> boxes, Set<String> ignore) {
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final horizontal = (a.$2 - b.$2).abs() < 0.001;
    final lo = horizontal ? math.min(a.$1, b.$1) : math.min(a.$2, b.$2);
    final hi = horizontal ? math.max(a.$1, b.$1) : math.max(a.$2, b.$2);
    for (final box in boxes) {
      if (box.$1 != null && ignore.contains(box.$1)) continue;
      if (horizontal) {
        if (a.$2 > box.$3 && a.$2 < box.$5 && hi > box.$2 && lo < box.$4) return true;
      } else {
        if (a.$1 > box.$2 && a.$1 < box.$4 && hi > box.$3 && lo < box.$5) return true;
      }
    }
  }
  return false;
}

/// การ์ดอยู่คนละฝั่ง: หาแนวตั้งที่ว่างในช่องระหว่างการ์ด (เริ่มจากตำแหน่งเลนที่ต้องการ แล้วลองขยับซ้าย/ขวา)
/// ถ้าช่องถูกขวางทั้งหมดให้อ้อมผ่านช่องว่างเหนือ/ใต้ ถ้าอ้อมไม่ได้ก็ใช้เส้นตามเลนเดิม
List<RoutePoint> _gutterRoute(RelationGeometry g, double preferred, List<_Box> boxes, Set<String> ignore,
    [List<(double, double, double, double)> edges = const []]) {
  final lo = math.min(g.fx, g.tx), hi = math.max(g.fx, g.tx);
  final straight = (g.fy - g.ty).abs() < 0.5;

  List<RoutePoint> viaX(double x) => [(g.fx, g.fy), (x, g.fy), (x, g.ty), (g.tx, g.ty)];

  final fallback = straight ? <RoutePoint>[(g.fx, g.fy), (g.tx, g.ty)] : viaX(_clampGutter(preferred, lo, hi));
  if (straight) {
    if (!_blocked(fallback, boxes, ignore) && !_hugsGroupEdge(fallback, edges)) return fallback;
  } else {
    // ลองไล่จากเลนที่ต้องการออกไปทั้งสองข้าง
    final span = hi - lo;
    final tries = hi - lo > 2 * kRouteLaneGap ? (span / kRouteStep).ceil() : 0;
    for (var k = 0; k <= tries; k++) {
      for (final sign in k == 0 ? const [1] : const [1, -1]) {
        final x = _clampGutter(preferred + sign * k * kRouteStep, lo, hi);
        final pts = viaX(x);
        if (!_blocked(pts, boxes, ignore) && !_hugsGroupEdge(pts, edges)) return pts;
      }
    }
    // ไม่มีเลนที่พ้นขอบกลุ่ม: ยอมเกาะขอบดีกว่าอ้อมไกล (เลือกที่ไม่ชนการ์ดอย่างเดียว)
    for (var k = 0; k <= tries; k++) {
      for (final sign in k == 0 ? const [1] : const [1, -1]) {
        final pts = viaX(_clampGutter(preferred + sign * k * kRouteStep, lo, hi));
        if (!_blocked(pts, boxes, ignore)) return pts;
      }
    }
  }
  if (straight && !_blocked(fallback, boxes, ignore)) return fallback;

  // อ้อมผ่านช่องว่างเหนือหรือใต้สิ่งกีดขวางทั้งหมดในแนวนั้น
  final detour = _detourRoute(g, boxes, ignore);
  return detour ?? fallback;
}

double _clampGutter(double x, double lo, double hi) =>
    hi - lo > 2 * kRouteLaneGap ? x.clamp(lo + kRouteLaneGap, hi - kRouteLaneGap) : (lo + hi) / 2;

/// เส้น 5 ช่วง: ยื่นออกจากการ์ดต้นทาง -> ขึ้น/ลงไปยังช่องว่างเหนือ(ใต้)สิ่งกีดขวาง -> ข้าม -> ลงมาเข้าการ์ดปลายทาง
List<RoutePoint>? _detourRoute(RelationGeometry g, List<_Box> boxes, Set<String> ignore) {
  final s = kRouteStub;
  final x0 = g.fx + g.d0 * s, x1 = g.tx + g.d1 * s;
  final left = math.min(x0, x1), right = math.max(x0, x1);

  // สิ่งกีดขวางทั้งหมดที่คาบเกี่ยวช่วงแนวนอนที่เส้นต้องข้าม
  var top = math.min(g.fy, g.ty), bottom = math.max(g.fy, g.ty);
  for (final b in boxes) {
    if (b.$4 > left - kRoutePad && b.$2 < right + kRoutePad) {
      top = math.min(top, b.$3);
      bottom = math.max(bottom, b.$5);
    }
  }
  final candidates = [top - 14, bottom + 14]
    ..sort((a, c) => ((a - g.fy).abs() + (a - g.ty).abs()).compareTo((c - g.fy).abs() + (c - g.ty).abs()));
  for (final yc in candidates) {
    final pts = <RoutePoint>[(g.fx, g.fy), (x0, g.fy), (x0, yc), (x1, yc), (x1, g.ty), (g.tx, g.ty)];
    if (!_blocked(pts, boxes, ignore)) return pts;
  }
  return null;
}

/// ฝั่งเดียวกัน: อ้อมออกด้านข้างระยะ [out] จากขอบนอกสุด ถ้าชนอะไรให้ถอยออกไปไกลขึ้นทีละก้าว
List<RoutePoint> _sameSideRoute(RelationGeometry g, double base, double out, List<_Box> boxes, Set<String> ignore,
    [List<(double, double, double, double)> edges = const []]) {
  List<RoutePoint> viaX(double x) => [(g.fx, g.fy), (x, g.fy), (x, g.ty), (g.tx, g.ty)];
  final first = viaX(base + g.d0 * out);
  if (!_blocked(first, boxes, ignore) && !_hugsGroupEdge(first, edges)) return first;
  // ถอยออกไปไกลขึ้นทีละก้าว: รอบแรกเลี่ยงทั้งการ์ดและขอบกลุ่ม ไม่ได้ค่อยยอมเกาะขอบกลุ่ม
  for (final strict in const [true, false]) {
    for (var k = 1; k <= 30; k++) {
      final pts = viaX(base + g.d0 * (out + k * kRouteStep * 2));
      if (!_blocked(pts, boxes, ignore) && (!strict || !_hugsGroupEdge(pts, edges))) return pts;
    }
  }
  return first;
}

/// คำสั่งวาดเส้น: 'M'/'L' มี 1 จุด, 'Q' มี 2 จุด (จุดควบคุม, จุดปลาย)
typedef PathCmd = (String op, List<RoutePoint> pts);

/// แปลงเส้นหักมุมฉากเป็นคำสั่งวาดที่มุมโค้งมน (รัศมี [radius] ลดลงเองถ้าช่วงสั้น)
/// ใช้ร่วมกันทั้ง canvas / PNG / SVG เพื่อให้หน้าตาเหมือนกัน
List<PathCmd> roundedRoute(List<RoutePoint> pts, {double radius = 9}) {
  final cmds = <PathCmd>[('M', [pts.first])];
  for (var i = 1; i < pts.length - 1; i++) {
    final a = pts[i - 1], b = pts[i], c = pts[i + 1];
    final l1 = math.sqrt(math.pow(b.$1 - a.$1, 2) + math.pow(b.$2 - a.$2, 2));
    final l2 = math.sqrt(math.pow(c.$1 - b.$1, 2) + math.pow(c.$2 - b.$2, 2));
    if (l1 == 0 || l2 == 0) continue;
    final r = math.min(radius, math.min(l1, l2) / 2);
    final p1 = (b.$1 - (b.$1 - a.$1) / l1 * r, b.$2 - (b.$2 - a.$2) / l1 * r);
    final p2 = (b.$1 + (c.$1 - b.$1) / l2 * r, b.$2 + (c.$2 - b.$2) / l2 * r);
    cmds
      ..add(('L', [p1]))
      ..add(('Q', [b, p2]));
  }
  cmds.add(('L', [pts.last]));
  return cmds;
}

/// ตัดข้อความโน้ตเป็นบรรทัดโดยประมาณ (ไม่รู้ความกว้างฟอนต์จริง) — ใช้ร่วมกันทั้ง SVG และ PNG
List<String> wrapNoteText(String text, double width) {
  final perLine = math.max(8, ((width - 24) / 6.8).floor());
  final out = <String>[];
  for (final raw in text.split('\n')) {
    var line = raw;
    if (line.isEmpty) {
      out.add('');
      continue;
    }
    while (line.length > perLine) {
      var cut = line.lastIndexOf(' ', perLine);
      if (cut <= 0) cut = perLine;
      out.add(line.substring(0, cut).trimRight());
      line = line.substring(cut).trimLeft();
    }
    out.add(line);
  }
  return out;
}

const double kNoteLineHeight = 16;
const double kNoteChrome = 34; // หัว "โน้ต" + ช่องว่างบนล่าง

double noteHeight(NoteModel n) {
  final lines = n.text.isEmpty ? 1 : wrapNoteText(n.text, n.width).length;
  return kNoteChrome + kNoteLineHeight * lines;
}

/// ขนาดกระดานเริ่มต้น (ดู [Project.boardWidth])
const double kBoardMinWidth = kDefaultBoardWidth;
const double kBoardMinHeight = kDefaultBoardHeight;

/// ช่วงพิกัดที่ตาราง/โน้ตอยู่ได้ (ซ้าย/บนติดลบได้ เพื่อให้กระดานขยายออกทุกด้าน)
const double kWorldMin = -9600;
const double kWorldMax = 19600;

/// ขนาดช่องตาราง (px) ตรงกับระยะห่างของจุดพื้นหลัง — ใช้ snap ตอนลาก/วางของ
const double kGridSize = 20;

/// ปัดค่าให้ลงช่องตารางที่ใกล้ที่สุด
double snapToGrid(double v, [double grid = kGridSize]) => (v / grid).round() * grid;

/// ระยะที่ถือว่า "ใกล้ขอบ" ใช้แสดง hint ว่าถ้าลากชนขอบกระดานจะขยาย
const double kBoardNearEdge = 120;

enum BoardEdge { left, top, right, bottom }

/// กรอบตั้งต้นของกระดาน (0,0)–(boardWidth,boardHeight) ตามที่ผู้ใช้เลือกตอนสร้างโปรเจกต์
DiagramBounds baseBoard(Project p) => DiagramBounds(0, 0, p.boardWidth, p.boardHeight);

/// ตำแหน่งและขนาดของตาราง/โน้ต/กลุ่มทุกชิ้น (x, y, กว้าง, สูง)
Iterable<(double, double, double, double)> _objectRects(Project p) sync* {
  for (final g in p.groups) {
    yield (g.x, g.y, g.width, g.height);
  }
  for (final t in p.tables) {
    yield (t.x, t.y, t.width, tableHeight(t));
  }
  for (final n in p.notes) {
    yield (n.x, n.y, n.width, noteHeight(n));
  }
}

/// กรอบกระดานสำหรับวาด: ขนาดตั้งต้น และจะขยายก็ต่อเมื่อมีตาราง/โน้ตชนและล้ำขอบออกไป
/// (ขยายพอดีให้ครอบชิ้นนั้น ไม่เผื่อล่วงหน้า) เมื่อลากกลับเข้ามากรอบก็หดกลับถึงขนาดตั้งต้น
DiagramBounds boardBounds(Project p) {
  var l = 0.0, t = 0.0, r = p.boardWidth, b = p.boardHeight;
  for (final (x, y, w, h) in _objectRects(p)) {
    l = math.min(l, x);
    t = math.min(t, y);
    r = math.max(r, x + w);
    b = math.max(b, y + h);
  }
  return DiagramBounds(l, t, r, b);
}

/// ขอบที่ถูกดันออกจากกรอบตั้งต้นอยู่ตอนนี้
Set<BoardEdge> extendedEdges(Project p) {
  final base = baseBoard(p);
  final cur = boardBounds(p);
  return {
    if (cur.left < base.left) BoardEdge.left,
    if (cur.top < base.top) BoardEdge.top,
    if (cur.right > base.right) BoardEdge.right,
    if (cur.bottom > base.bottom) BoardEdge.bottom,
  };
}

/// ขอบกรอบตั้งต้นที่ตารางใน [tableIds] (เช่นที่กำลังลาก) เข้าใกล้ภายใน [kBoardNearEdge] หรือล้ำออกไปแล้ว
Set<BoardEdge> edgesNearTables(Project p, Iterable<String> tableIds, {double within = kBoardNearEdge}) {
  final base = baseBoard(p);
  final out = <BoardEdge>{};
  for (final id in tableIds) {
    final t = p.tableById(id);
    if (t == null) continue;
    if (t.x < base.left + within) out.add(BoardEdge.left);
    if (t.y < base.top + within) out.add(BoardEdge.top);
    if (t.x + t.width > base.right - within) out.add(BoardEdge.right);
    if (t.y + tableHeight(t) > base.bottom - within) out.add(BoardEdge.bottom);
  }
  return out;
}

/// สมาชิกของกลุ่ม ณ ตอนนี้: ตาราง/โน้ต/กลุ่มอื่นที่จุดกึ่งกลางอยู่ในกรอบของกลุ่ม
/// (กลุ่มซ้อนกลุ่มนับเฉพาะกลุ่มที่เล็กกว่า)
({List<String> tables, List<String> notes, List<String> groups}) groupMembers(Project p, GroupModel g) {
  bool inside(double cx, double cy) => cx >= g.x && cx <= g.x + g.width && cy >= g.y && cy <= g.y + g.height;
  return (
    tables: [
      for (final t in p.tables)
        if (inside(t.x + t.width / 2, t.y + tableHeight(t) / 2)) t.id,
    ],
    notes: [
      for (final n in p.notes)
        if (inside(n.x + n.width / 2, n.y + noteHeight(n) / 2)) n.id,
    ],
    groups: [
      for (final o in p.groups)
        if (o.id != g.id && o.width * o.height < g.width * g.height && inside(o.x + o.width / 2, o.y + o.height / 2)) o.id,
    ],
  );
}

class DiagramBounds {
  const DiagramBounds(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  double get width => right - left;
  double get height => bottom - top;
}

/// กรอบที่ครอบตาราง (และโน้ต) ทั้งหมด — null ถ้าไม่มีอะไรเลย
DiagramBounds? diagramBounds(Project p, {bool includeNotes = true}) {
  double? l, t, r, b;
  void add(double x, double y, double w, double h) {
    l = l == null ? x : math.min(l!, x);
    t = t == null ? y : math.min(t!, y);
    r = r == null ? x + w : math.max(r!, x + w);
    b = b == null ? y + h : math.max(b!, y + h);
  }

  for (final tb in p.tables) {
    add(tb.x, tb.y, tb.width, tableHeight(tb));
  }
  if (includeNotes) {
    for (final n in p.notes) {
      add(n.x, n.y, n.width, noteHeight(n));
    }
  }
  for (final g in p.groups) {
    add(g.x, g.y, g.width, g.height);
  }
  if (l == null) return null;
  // เส้น FK ที่โค้งออกนอกการ์ดสุดขอบ (ตีนกา 14 + โค้ง ~ 60)
  return DiagramBounds(l! - 24, t! - 24, r! + 24 + (p.relations.isEmpty ? 0 : 40), b! + 24);
}

/// เครื่องหมายทิศทางข้อมูลกลางเส้น FK: จุดกึ่งกลางของช่วงที่ยาวที่สุด + ทิศ (หน่วย) ที่ชี้จากตารางแม่ (PK) ไปหาตารางลูก (FK)
/// [route] เรียงจากคอลัมน์ FK (ลูก) ไปคอลัมน์ PK (แม่) จึงชี้ย้อนทิศของเส้น; เส้นสั้นกว่า [minLength] = ไม่วาง (null)
({double x, double y, double dx, double dy})? relationFlowMarker(List<RoutePoint> route, {double minLength = 56}) {
  var best = -1;
  var bestLen = 0.0;
  for (var i = 1; i < route.length; i++) {
    final len = math.sqrt(math.pow(route[i].$1 - route[i - 1].$1, 2) + math.pow(route[i].$2 - route[i - 1].$2, 2));
    if (len > bestLen) {
      bestLen = len;
      best = i;
    }
  }
  if (best < 0 || bestLen < minLength) return null;
  final a = route[best - 1], b = route[best];
  // ทิศจากแม่ไปลูก = จาก b กลับไป a
  return (x: (a.$1 + b.$1) / 2, y: (a.$2 + b.$2) / 2, dx: (a.$1 - b.$1) / bestLen, dy: (a.$2 - b.$2) / bestLen);
}

/// id ของความสัมพันธ์ที่เส้นอยู่ใกล้จุด ([x],[y] พิกัดโปรเจกต์) ภายใน [tolerance] พิกเซล — ใกล้สุดก่อน; ไม่มี = null
String? relationAt(Project p, double x, double y, {double tolerance = 7}) {
  String? best;
  var bestD = tolerance;
  relationRoutes(p).forEach((id, pts) {
    for (var i = 0; i + 1 < pts.length; i++) {
      final (ax, ay) = pts[i];
      final (bx, by) = pts[i + 1];
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / len2).clamp(0.0, 1.0);
      final px = ax + t * dx - x, py = ay + t * dy - y;
      final d = math.sqrt(px * px + py * py);
      if (d <= bestD) {
        bestD = d;
        best = id;
      }
    }
  });
  return best;
}
