import 'dart:math' as math;

import 'color_utils.dart';
import 'workspace.dart';

/// ชนิดของวัตถุใน DFD
enum DfdKind {
  /// ผู้ใช้/ระบบภายนอก (สี่เหลี่ยม)
  entity,

  /// กระบวนการ (สี่เหลี่ยมมุมมน มีเลขลำดับ เช่น 1.0)
  process,

  /// ที่เก็บข้อมูล (สี่เหลี่ยมเปิดด้านขวา มีรหัส เช่น D1)
  store,
}

const double kDfdMinW = 90;
const double kDfdMinH = 40;
const double kDfdMaxSide = 600;

/// ขนาดเริ่มต้นของแต่ละชนิด
(double, double) dfdDefaultSize(DfdKind k) => switch (k) {
      DfdKind.entity => (150, 56),
      DfdKind.process => (180, 64),
      DfdKind.store => (180, 48),
    };

class DfdNode {
  DfdNode({
    required this.id,
    required this.kind,
    this.name = '',
    this.number = '',
    this.x = 0,
    this.y = 0,
    double? w,
    double? h,
    this.color,
    this.tableId,
    this.tableDocId,
    this.childId,
  })  : w = w ?? dfdDefaultSize(kind).$1,
        h = h ?? dfdDefaultSize(kind).$2;

  final String id;
  final DfdKind kind;
  String name;

  /// เลขลำดับ process (1.0) หรือรหัส data store (D1) — entity ไม่ใช้
  String number;
  double x, y, w, h;

  /// สีกำหนดเอง (ARGB) — null = สีตามชนิด
  int? color;

  /// id ของตาราง ER ที่ที่เก็บข้อมูลนี้แทน (เฉพาะ [DfdKind.store]) — null = ยังไม่ผูก
  String? tableId;

  /// id ของเอกสาร ER ที่ [tableId] อยู่ (ไฟล์ v3) — null = ไม่ระบุ (ไฟล์เก่า / ยังไม่ผูก)
  String? tableDocId;

  /// id ของแท็บ DFD ที่แตกรายละเอียดของกระบวนการนี้ (เฉพาะ [DfdKind.process]) — null = ไม่มี
  String? childId;

  double get cx => x + w / 2;
  double get cy => y + h / 2;
  double get right => x + w;
  double get bottom => y + h;

  /// ข้อความที่แสดง: "1.0 ชื่อ" / "D1 ชื่อ" / "ชื่อ"
  String get title => number.isEmpty ? name : (name.isEmpty ? number : '$number $name');

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        if (number.isNotEmpty) 'number': number,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (color != null) 'color': color,
        if (tableId != null) 'table': tableId,
        if (tableId != null && tableDocId != null) 'tableDoc': tableDocId,
        if (childId != null) 'child': childId,
      };

  /// ค่าผิดปกติ = null (ข้ามวัตถุนั้น) หรือใช้ค่าปลอดภัย (ขนาด/ตำแหน่ง)
  static DfdNode? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = DfdKind.values.where((k) => k.name == j['kind']).firstOrNull;
    if (id is! String || id.isEmpty || kind == null) return null;
    double num0(Object? v, double fb) => v is num && v.isFinite ? v.toDouble() : fb;
    final d = dfdDefaultSize(kind);
    double side(Object? v, double min, double fb) {
      final n = num0(v, fb);
      return n < min ? fb : math.min(n, kDfdMaxSide);
    }

    return DfdNode(
      id: id,
      kind: kind,
      name: j['name'] is String ? j['name'] as String : '',
      number: j['number'] is String ? j['number'] as String : '',
      x: num0(j['x'], 0),
      y: num0(j['y'], 0),
      w: side(j['w'], kDfdMinW, d.$1),
      h: side(j['h'], kDfdMinH, d.$2),
      color: parseArgb(j['color']),
      tableId: kind == DfdKind.store && j['table'] is String && (j['table'] as String).isNotEmpty ? j['table'] as String : null,
      tableDocId: kind == DfdKind.store && j['table'] is String && (j['table'] as String).isNotEmpty && j['tableDoc'] is String && (j['tableDoc'] as String).isNotEmpty
          ? j['tableDoc'] as String
          : null,
      childId: kind == DfdKind.process && j['child'] is String && (j['child'] as String).isNotEmpty ? j['child'] as String : null,
    );
  }
}

class DfdFlow {
  DfdFlow({
    required this.id,
    required this.fromId,
    required this.toId,
    this.label = '',
    this.bidirectional = false,
    this.color,
  });

  final String id;
  String fromId;
  String toId;
  String label;

  /// ลูกศรทั้งสองปลาย (ข้อมูลไหลสองทาง)
  bool bidirectional;
  int? color;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': fromId,
        'to': toId,
        'label': label,
        if (bidirectional) 'both': true,
        if (color != null) 'color': color,
      };

  static DfdFlow? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], from = j['from'], to = j['to'];
    if (id is! String || id.isEmpty || from is! String || to is! String) return null;
    return DfdFlow(
      id: id,
      fromId: from,
      toId: to,
      label: j['label'] is String ? j['label'] as String : '',
      bidirectional: j['both'] == true,
      color: parseArgb(j['color']),
    );
  }
}

/// กรอบขอบเขตระบบ / กลุ่ม วาดเป็นเส้นประรอบวัตถุ (อยู่ใต้วัตถุและเส้นข้อมูล ไม่มีผลต่อกฎของ DFD)
class DfdBoundary {
  DfdBoundary({required this.id, this.name = '', this.x = 0, this.y = 0, this.w = 300, this.h = 200, this.color});

  final String id;
  String name;
  double x, y, w, h;
  int? color;

  double get right => x + w;
  double get bottom => y + h;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (color != null) 'color': color,
      };

  static DfdBoundary? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    double num0(Object? v, double fb) => v is num && v.isFinite ? v.toDouble() : fb;
    double side(Object? v, double fb) {
      final n = num0(v, fb);
      return n < 40 ? fb : math.min(n, 4000);
    }

    return DfdBoundary(
      id: id,
      name: j['name'] is String ? j['name'] as String : '',
      x: num0(j['x'], 0),
      y: num0(j['y'], 0),
      w: side(j['w'], 300),
      h: side(j['h'], 200),
      color: parseArgb(j['color']),
    );
  }
}

/// เนื้อหาของแผนภาพ DFD หนึ่งแท็บ
class DfdDiagram implements DocContent {
  DfdDiagram({List<DfdNode>? nodes, List<DfdFlow>? flows, List<DfdBoundary>? boundaries})
      : nodes = nodes ?? [],
        flows = flows ?? [],
        boundaries = boundaries ?? [];

  final List<DfdNode> nodes;
  final List<DfdFlow> flows;
  final List<DfdBoundary> boundaries;

  DfdBoundary? boundaryById(String id) {
    for (final b in boundaries) {
      if (b.id == id) return b;
    }
    return null;
  }

  DfdNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  DfdFlow? flowById(String id) {
    for (final f in flows) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// เลขลำดับ process ถัดไป ("1.0", "2.0", ...) ที่ยังไม่มีใครใช้
  String nextProcessNumber() {
    final used = {for (final n in nodes) if (n.kind == DfdKind.process) n.number};
    for (var i = 1;; i++) {
      if (!used.contains('$i.0')) return '$i.0';
    }
  }

  /// รหัส data store ถัดไป ("D1", "D2", ...)
  String nextStoreNumber() {
    final used = {for (final n in nodes) if (n.kind == DfdKind.store) n.number};
    for (var i = 1;; i++) {
      if (!used.contains('D$i')) return 'D$i';
    }
  }

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'flows': flows.map((f) => f.toJson()).toList(),
        if (boundaries.isNotEmpty) 'boundaries': boundaries.map((b) => b.toJson()).toList(),
      };

  @override
  Map<String, dynamic> toContentJson() => toJson();

  /// ซ่อมข้อมูลผิดปกติ: ข้ามวัตถุที่อ่านไม่ได้/id ซ้ำ, ตัดเส้นที่ชี้ไปวัตถุที่ไม่มี หรือชี้ไปที่ตัวเอง
  factory DfdDiagram.fromJson(Object? j) {
    if (j is! Map) return DfdDiagram();
    final ids = <String>{};
    final nodes = [
      for (final e in (j['nodes'] as List? ?? const []))
        if (DfdNode.tryFromJson(e) case final n? when ids.add(n.id)) n,
    ];
    final nodeIds = {for (final n in nodes) n.id};
    final fids = <String>{};
    final flows = [
      for (final e in (j['flows'] as List? ?? const []))
        if (DfdFlow.tryFromJson(e) case final f?
            when nodeIds.contains(f.fromId) && nodeIds.contains(f.toId) && f.fromId != f.toId && fids.add(f.id))
          f,
    ];
    final bids = <String>{};
    final boundaries = [
      for (final e in (j['boundaries'] as List? ?? const []))
        if (DfdBoundary.tryFromJson(e) case final b? when bids.add(b.id)) b,
    ];
    return DfdDiagram(nodes: nodes, flows: flows, boundaries: boundaries);
  }
}

// ---------------------------------------------------------------------------------------------
// เรขาคณิตของเส้น data flow (ใช้ร่วมกันทั้งบนจอ / PNG / SVG)
// ---------------------------------------------------------------------------------------------

typedef DfdPoint = (double x, double y);

/// ระยะห่างขั้นต่ำระหว่างขอบสองกล่องที่จะถือว่า "อยู่คนละฝั่ง" (พอให้มีช่องหักมุมและหัวลูกศร)
const double kDfdGutter = 28;

/// ระยะห่างระหว่างเส้นที่ออก/เข้าด้านเดียวกันของกล่องเดียวกัน
const double kDfdSlotGap = 18;

enum _Side { left, right, top, bottom }

/// เส้นทางของ flow ทุกเส้น (key = id) แบบหักมุมฉาก: ออกด้านที่หันหาอีกกล่อง กระจายช่องตามด้านของกล่อง
/// เส้นที่ออก/เข้าด้านเดียวกันของกล่องเดียวกันถูกเรียงเป็นช่องคนละระดับ จึงไม่ซ้อนกัน
/// เส้นที่วิ่งแนวตั้งทับกันในช่องว่างเดียวกันถูกดันห่างกัน
Map<String, List<DfdPoint>> dfdRoutes(DfdDiagram d) {
  final sides = <String, (_Side, _Side)>{};
  // (nodeId, side) -> [(flowId, isStart, ตำแหน่งอ้างอิงตามแนวขนานขอบ)]
  final slots = <(String, _Side), List<(String, bool, double)>>{};

  for (final f in d.flows) {
    final a = d.nodeById(f.fromId), b = d.nodeById(f.toId);
    if (a == null || b == null) continue;
    final s = _sidesFor(a, b);
    sides[f.id] = s;
    final horizontal = s.$1 == _Side.left || s.$1 == _Side.right;
    slots.putIfAbsent((a.id, s.$1), () => []).add((f.id, true, horizontal ? b.cy : b.cx));
    slots.putIfAbsent((b.id, s.$2), () => []).add((f.id, false, horizontal ? a.cy : a.cx));
  }

  // ตำแหน่งปลายเส้น: จุดกึ่งกลางด้าน + ระยะช่อง
  final start = <String, DfdPoint>{}, end = <String, DfdPoint>{};
  slots.forEach((key, list) {
    final n = d.nodeById(key.$1)!;
    list.sort((p, q) {
      final c = p.$3.compareTo(q.$3);
      return c != 0 ? c : p.$1.compareTo(q.$1);
    });
    final horizontal = key.$2 == _Side.left || key.$2 == _Side.right;
    final extent = horizontal ? n.h : n.w;
    final gap = list.length <= 1 ? 0.0 : math.min(kDfdSlotGap, (extent - 16) / (list.length - 1));
    for (var i = 0; i < list.length; i++) {
      final off = (i - (list.length - 1) / 2) * gap;
      final DfdPoint p = switch (key.$2) {
        _Side.left => (n.x, n.cy + off),
        _Side.right => (n.right, n.cy + off),
        _Side.top => (n.cx + off, n.y),
        _Side.bottom => (n.cx + off, n.bottom),
      };
      (list[i].$2 ? start : end)[list[i].$1] = p;
    }
  });

  List<DfdPoint> build(String id, double shift) {
    final s = sides[id]!;
    final p0 = start[id]!, p1 = end[id]!;
    final horizontal = s.$1 == _Side.left || s.$1 == _Side.right;
    if (horizontal) {
      if ((p0.$2 - p1.$2).abs() < 0.5) return [p0, (p1.$1, p0.$2)];
      final mx = (p0.$1 + p1.$1) / 2 + shift;
      return [p0, (mx, p0.$2), (mx, p1.$2), p1];
    }
    if ((p0.$1 - p1.$1).abs() < 0.5) return [p0, (p0.$1, p1.$2)];
    final my = (p0.$2 + p1.$2) / 2 + shift;
    return [p0, (p0.$1, my), (p1.$1, my), p1];
  }

  final ids = [for (final f in d.flows) if (sides.containsKey(f.id)) f.id];
  final shifts = {for (final id in ids) id: 0.0};
  final routes = {for (final id in ids) id: build(id, 0)};

  // เส้นที่ช่วงกลาง (ตั้งฉากกับทิศออก) ทับกัน: ดันเส้นหลังออกไปทีละ 12 px
  bool overlaps(List<DfdPoint> a, List<DfdPoint> b) {
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

  for (var pass = 0; pass < 6; pass++) {
    var changed = false;
    for (var j = 1; j < ids.length; j++) {
      for (var i = 0; i < j; i++) {
        // เฉพาะช่วงกลาง (ไม่นับช่วงที่เริ่ม/จบที่กล่อง) ที่อยู่ในช่องว่างร่วมกัน
        if (routes[ids[j]]!.length > 2 && routes[ids[i]]!.length > 2 && overlaps(routes[ids[i]]!.sublist(1, routes[ids[i]]!.length - 1), routes[ids[j]]!.sublist(1, routes[ids[j]]!.length - 1))) {
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

_Side _sidesAxis(DfdNode a, DfdNode b, bool horizontal) {
  if (horizontal) return a.cx <= b.cx ? _Side.right : _Side.left;
  return a.cy <= b.cy ? _Side.bottom : _Side.top;
}

(_Side, _Side) _sidesFor(DfdNode a, DfdNode b) {
  final gapX = math.max(a.x - b.right, b.x - a.right); // บวก = มีช่องว่างแนวนอน
  final gapY = math.max(a.y - b.bottom, b.y - a.bottom);
  final bool horizontal;
  if (gapX >= kDfdGutter && gapY >= kDfdGutter) {
    horizontal = gapX >= gapY; // เฉียง: ออกตามแกนที่ห่างกว่า
  } else if (gapX >= kDfdGutter) {
    horizontal = true;
  } else if (gapY >= kDfdGutter) {
    horizontal = false;
  } else {
    // ซ้อน/ชิดกัน: ใช้แกนที่ศูนย์กลางห่างกว่า
    horizontal = (a.cx - b.cx).abs() >= (a.cy - b.cy).abs();
  }
  final sa = _sidesAxis(a, b, horizontal);
  final sb = _sidesAxis(b, a, horizontal);
  return (sa, sb);
}

/// จุดวางป้ายชื่อ: กึ่งกลางช่วงที่ยาวที่สุดของเส้น
DfdPoint dfdLabelAnchor(List<DfdPoint> pts) {
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

/// ระยะจากจุดถึงเส้นทาง (ช่วงสั้นสุด)
double dfdDistanceToRoute(List<DfdPoint> pts, double x, double y) {
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

/// flow ที่เส้นอยู่ใกล้จุด (พิกัดแผนภาพ) ภายใน [tolerance] — ใกล้สุดก่อน; ไม่มี = null
String? dfdFlowAt(DfdDiagram d, double x, double y, {double tolerance = 7}) {
  String? best;
  var bestD = tolerance;
  dfdRoutes(d).forEach((id, pts) {
    final dist = dfdDistanceToRoute(pts, x, y);
    if (dist <= bestD) {
      bestD = dist;
      best = id;
    }
  });
  return best;
}

/// วัตถุที่อยู่บนจุด (ชิ้นที่อยู่บนสุด = ท้ายรายการก่อน)
DfdNode? dfdNodeAt(DfdDiagram d, double x, double y) {
  for (final n in d.nodes.reversed) {
    if (x >= n.x && x <= n.right && y >= n.y && y <= n.bottom) return n;
  }
  return null;
}

/// ขอบเขตของแผนภาพ (วัตถุ + ป้ายชื่อ flow โดยประมาณ) เผื่อขอบ [pad]; ว่าง = null
({double left, double top, double right, double bottom})? dfdBounds(DfdDiagram d, {double pad = 40}) {
  if (d.nodes.isEmpty && d.boundaries.isEmpty) return null;
  var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  for (final n in d.nodes) {
    l = math.min(l, n.x);
    t = math.min(t, n.y);
    r = math.max(r, n.right);
    b = math.max(b, n.bottom);
  }
  for (final k in d.boundaries) {
    l = math.min(l, k.x);
    t = math.min(t, k.y);
    r = math.max(r, k.right);
    b = math.max(b, k.bottom);
  }
  for (final pts in dfdRoutes(d).values) {
    for (final (x, y) in pts) {
      l = math.min(l, x);
      t = math.min(t, y);
      r = math.max(r, x);
      b = math.max(b, y);
    }
  }
  return (left: l - pad, top: t - pad, right: r + pad, bottom: b + pad);
}

/// ขอบเขตระบบที่ (x,y) ชี้โดน : แถบขอบกว้าง [tol] หรือแถบชื่อด้านบน (ข้างในกรอบคลิกทะลุเพื่อลากเลือกวัตถุ)
DfdBoundary? dfdBoundaryAt(DfdDiagram d, double x, double y, {double tol = 7}) {
  for (final b in d.boundaries.reversed) {
    final outer = x >= b.x - tol && x <= b.right + tol && y >= b.y - tol && y <= b.bottom + tol;
    if (!outer) continue;
    final inner = x > b.x + tol && x < b.right - tol && y > b.y + tol && y < b.bottom - tol;
    final inLabel = x >= b.x && x <= b.right && y >= b.y && y <= b.y + kDfdBoundaryLabelH;
    if (!inner || inLabel) return b;
  }
  return null;
}

/// ความสูงแถบชื่อของขอบเขตระบบ
const double kDfdBoundaryLabelH = 26;
