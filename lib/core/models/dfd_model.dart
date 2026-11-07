import 'dart:math' as math;

import '../layout/ortho_route.dart';
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

/// เส้นทางของ flow ทุกเส้น (key = id) แบบหักมุมฉาก: ออกด้านที่หันหาอีกกล่อง กระจายช่องตามด้านของกล่อง
/// เส้นที่ออก/เข้าด้านเดียวกันของกล่องเดียวกันถูกเรียงเป็นช่องคนละระดับ จึงไม่ซ้อนกัน
/// เส้นที่วิ่งแนวตั้งทับกันในช่องว่างเดียวกันถูกดันห่างกัน (อัลกอริทึมร่วม: [orthogonalRoutes])
Map<String, List<DfdPoint>> dfdRoutes(DfdDiagram d) {
  final boxes = <String, RouteBox>{};
  for (final n in d.nodes) {
    boxes.putIfAbsent(n.id, () => RouteBox(n.id, n.x, n.y, n.w, n.h));
  }
  return orthogonalRoutes(
    boxes,
    [for (final f in d.flows) RouteLink(f.id, f.fromId, f.toId)],
    gutter: kDfdGutter,
    slotGap: kDfdSlotGap,
  );
}

/// จุดวางป้ายชื่อ: กึ่งกลางช่วงที่ยาวที่สุดของเส้น
DfdPoint dfdLabelAnchor(List<DfdPoint> pts) => routeLabelAnchor(pts);

/// ระยะจากจุดถึงเส้นทาง (ช่วงสั้นสุด)
double dfdDistanceToRoute(List<DfdPoint> pts, double x, double y) => distanceToRoute(pts, x, y);

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
