import 'dart:math' as math;

import '../models/group_model.dart';
import '../models/project.dart';
import '../models/table_model.dart';

typedef Pos = ({double x, double y});
typedef GroupRect = ({double x, double y, double width, double height});

class LayoutOptions {
  const LayoutOptions({
    this.gapX = 90,
    this.gapY = 40,
    this.margin = 40,
    this.headerHeight = 36,
    this.rowHeight = 28,
    this.groupPad = 28,
  });

  /// ช่องว่างแนวนอนต่ำสุดระหว่างชั้น (ขยายเองตามจำนวนเส้นที่ผ่านช่องนั้น)
  final double gapX;
  final double gapY;
  final double margin;
  final double headerHeight;
  final double rowHeight;

  /// ระยะเผื่อรอบตารางในกลุ่ม (ด้านบนเผื่อแถบชื่อกลุ่มเพิ่ม)
  final double groupPad;
}

/// ผลการจัด: ตำแหน่งตาราง และกรอบใหม่ของกลุ่ม (ที่ครอบตารางสมาชิกพอดี)
class AutoLayoutResult {
  const AutoLayoutResult(this.tables, this.groups);
  final Map<String, Pos> tables;
  final Map<String, GroupRect> groups;
}

/// จัดตำแหน่งตารางเป็นชั้นตามสาย FK: ตารางที่ถูกอ้างถึง (แม่) อยู่ซ้าย ตารางลูกอยู่ขวา
/// - ตารางแม่ที่ไม่มีแม่ (เช่นตารางอ้างอิง) ถูกดึงเข้ามาชิดลูกที่อยู่ลึกสุด เส้นจึงสั้นลง
/// - สลับลำดับในแต่ละชั้นด้วย barycenter เพื่อลดเส้นไขว้
/// - จัดแนวตั้งให้ตารางอยู่ระดับเดียวกับตารางที่เชื่อมกัน (เส้นตรงขึ้น) โดยไม่ทับกัน
/// - ช่องว่างระหว่างชั้นกว้างตามจำนวนเส้นที่ผ่าน (เส้นแยกเลนขนานจึงมีที่)
/// - FK วนเป็นวงถูกตัดวงอัตโนมัติ (ไม่ค้าง) ; FK ชี้ตัวเองไม่นับ
/// - ชุดตารางที่เชื่อมกันหลายชุดเรียงเป็นแถวห่อบรรทัด (ไม่ต่อกันยาวเป็นแนวตั้ง)
/// - ตารางที่ไม่มี FK กับใครเลย วางเป็นตารางด้านล่าง
/// - ตารางที่อยู่ในกลุ่ม (group) จัดภายในกลุ่มของตัวเอง แล้วปรับกรอบกลุ่มให้ครอบพอดี
/// ผลลัพธ์คงที่ (ข้อมูลเดิม -> ตำแหน่งเดิม) และไม่แก้ [p]
Map<String, Pos> autoLayout(Project p, {LayoutOptions opts = const LayoutOptions()}) =>
    autoLayoutAll(p, opts: opts).tables;

AutoLayoutResult autoLayoutAll(Project p, {LayoutOptions opts = const LayoutOptions()}) {
  final byId = {for (final t in p.tables) t.id: t};
  final order = [for (final t in p.tables) t.id];

  // ---- แบ่งตารางเข้ากลุ่ม: ตารางอยู่กลุ่มที่เล็กสุดที่ครอบจุดกึ่งกลางของมัน ----
  final groupOf = <String, String>{};
  final groupsBySize = [...p.groups]..sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));
  for (final t in p.tables) {
    final cx = t.x + t.width / 2, cy = t.y + (opts.headerHeight + opts.rowHeight * t.columns.length) / 2;
    for (final g in groupsBySize) {
      if (cx >= g.x && cx <= g.x + g.width && cy >= g.y && cy <= g.y + g.height) {
        groupOf[t.id] = g.id;
        break;
      }
    }
  }

  final blocks = <_Block>[];
  final groupBlocks = <String, _Block>{};
  for (final g in p.groups) {
    final ids = [for (final id in order) if (groupOf[id] == g.id) id];
    if (ids.isEmpty) continue;
    final inner = _layoutSet(p, byId, ids, order, opts, maxRowWidth: 1500);
    final b = _Block(
      inner.pos,
      inner.w + opts.groupPad * 2,
      inner.h + opts.groupPad * 2 + kGroupHeader,
      groupId: g.id,
      inset: (x: opts.groupPad, y: opts.groupPad + kGroupHeader),
    );
    blocks.add(b);
    groupBlocks[g.id] = b;
  }
  final free = [for (final id in order) if (!groupOf.containsKey(id)) id];
  if (free.isNotEmpty) {
    final inner = _layoutSet(p, byId, free, order, opts, maxRowWidth: 2600);
    blocks.add(_Block(inner.pos, inner.w, inner.h));
  }

  // ---- วางบล็อก (กลุ่ม / ตารางอิสระ) เป็นแถวห่อบรรทัด ----
  final area = blocks.fold<double>(0, (s, b) => s + b.w * b.h);
  final maxW = math.max(1800.0, math.sqrt(area) * 1.7);
  final tables = <String, Pos>{};
  final groups = <String, GroupRect>{};
  var x = opts.margin, y = opts.margin, rowH = 0.0;
  for (final b in blocks) {
    if (x > opts.margin && x + b.w > maxW) {
      x = opts.margin;
      y += rowH + opts.gapY * 1.5;
      rowH = 0;
    }
    b.pos.forEach((id, q) => tables[id] = (x: x + b.inset.x + q.x, y: y + b.inset.y + q.y));
    if (b.groupId != null) groups[b.groupId!] = (x: x, y: y, width: b.w, height: b.h);
    x += b.w + opts.gapX;
    rowH = math.max(rowH, b.h);
  }
  return AutoLayoutResult(tables, groups);
}

class _Block {
  _Block(this.pos, this.w, this.h, {this.groupId, this.inset = (x: 0, y: 0)});
  final Map<String, Pos> pos;
  final double w, h;
  final String? groupId;
  final ({double x, double y}) inset;
}

class _Set {
  const _Set(this.pos, this.w, this.h);
  final Map<String, Pos> pos;
  final double w, h;
}

/// จัดชุดตาราง [ids] (เฉพาะ FK ภายในชุด): ชุดที่เชื่อมกันเป็นชั้น แล้วห่อเป็นแถว; ตารางโดดเดี่ยวเป็นตารางด้านล่าง
/// คืนตำแหน่งที่นับจาก (0,0) ของชุด และขนาดรวม
_Set _layoutSet(Project p, Map<String, TableModel> byId, List<String> ids, List<String> order, LayoutOptions opts,
    {required double maxRowWidth}) {
  final inSet = ids.toSet();
  final parents = {for (final id in ids) id: <String>{}};
  final children = {for (final id in ids) id: <String>{}};
  // จำนวนความสัมพันธ์ต่อคู่ (ใช้กำหนดความกว้างช่องว่างระหว่างชั้น)
  final edges = <(String, String)>[];
  for (final r in p.relations) {
    final c = r.fromTableId, pa = r.toTableId;
    if (c == pa || !inSet.contains(c) || !inSet.contains(pa)) continue;
    parents[c]!.add(pa);
    children[pa]!.add(c);
    edges.add((pa, c));
  }
  bool connected(String id) => parents[id]!.isNotEmpty || children[id]!.isNotEmpty;

  double heightOf(String id) => opts.headerHeight + opts.rowHeight * byId[id]!.columns.length;

  // ---- แยกชุดที่เชื่อมกัน ----
  final seen = <String>{};
  final components = <List<String>>[];
  for (final id in ids) {
    if (!connected(id) || seen.contains(id)) continue;
    final comp = <String>[];
    final queue = [id];
    seen.add(id);
    while (queue.isNotEmpty) {
      final n = queue.removeLast();
      comp.add(n);
      for (final m in [...parents[n]!, ...children[n]!]) {
        if (seen.add(m)) queue.add(m);
      }
    }
    comp.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    components.add(comp);
  }

  // ---- จัดแต่ละชุดเป็นชั้น (พิกัดนับจาก 0,0 ของชุดนั้น) ----
  final laid = <({Map<String, Pos> pos, double w, double h})>[];
  for (final comp in components) {
    laid.add(_layoutComponent(comp, parents, children, edges, byId, heightOf, opts));
  }

  // ---- วางชุดเป็นแถวห่อบรรทัด ----
  final pos = <String, Pos>{};
  var x = 0.0, y = 0.0, rowH = 0.0, totalW = 0.0;
  for (final c in laid) {
    if (x > 0 && x + c.w > maxRowWidth) {
      x = 0;
      y += rowH + opts.gapY * 2;
      rowH = 0;
    }
    c.pos.forEach((id, q) => pos[id] = (x: x + q.x, y: y + q.y));
    x += c.w + opts.gapX;
    rowH = math.max(rowH, c.h);
    totalW = math.max(totalW, x - opts.gapX);
  }
  var cursorY = laid.isEmpty ? 0.0 : y + rowH + opts.gapY * 2;
  var totalH = laid.isEmpty ? 0.0 : y + rowH;

  // ---- ตารางโดดเดี่ยว: จัดเป็นตารางด้านล่าง ----
  final loners = [for (final id in ids) if (!connected(id)) id];
  if (loners.isNotEmpty) {
    final cols = math.min(4, math.sqrt(loners.length).ceil());
    final colW = loners.map((id) => byId[id]!.width).reduce(math.max) + opts.gapX;
    var ly = cursorY;
    for (var i = 0; i < loners.length; i += cols) {
      final row = loners.sublist(i, math.min(i + cols, loners.length));
      for (var j = 0; j < row.length; j++) {
        pos[row[j]] = (x: j * colW, y: ly);
      }
      totalW = math.max(totalW, (row.length - 1) * colW + row.map((id) => byId[id]!.width).reduce(math.max));
      final h = row.map(heightOf).reduce(math.max);
      totalH = ly + h;
      ly += h + opts.gapY;
    }
  }
  return _Set(pos, totalW, totalH);
}

({Map<String, Pos> pos, double w, double h}) _layoutComponent(
  List<String> comp,
  Map<String, Set<String>> parents,
  Map<String, Set<String>> children,
  List<(String, String)> edges,
  Map<String, TableModel> byId,
  double Function(String) heightOf,
  LayoutOptions opts,
) {
  // ---- ชั้น = เส้นทางยาวสุดจากตารางที่ไม่มีแม่ (ตัดวงด้วยชุด visiting) ----
  final depth = <String, int>{};
  final visiting = <String>{};
  int depthOf(String n) {
    final known = depth[n];
    if (known != null) return known;
    visiting.add(n);
    var d = 0;
    for (final pa in parents[n]!) {
      if (visiting.contains(pa)) continue; // ตัดวง
      d = math.max(d, depthOf(pa) + 1);
    }
    visiting.remove(n);
    return depth[n] = d;
  }

  for (final n in comp) {
    depthOf(n);
  }

  // ---- ดึงตารางแม่ที่ไม่มีแม่เข้ามาชิดลูกที่อยู่ลึกสุด (เส้นสั้นลง) ----
  for (var pass = 0; pass < comp.length; pass++) {
    var changed = false;
    for (final n in comp) {
      if (parents[n]!.isNotEmpty || children[n]!.isEmpty) continue;
      final closest = children[n]!.map((c) => depth[c]!).reduce(math.min) - 1;
      if (closest > depth[n]!) {
        depth[n] = closest;
        changed = true;
      }
    }
    if (!changed) break;
  }

  final layerCount = comp.map((n) => depth[n]!).reduce(math.max) + 1;
  final layers = List.generate(layerCount, (_) => <String>[]);
  for (final n in comp) {
    layers[depth[n]!].add(n);
  }

  // ---- ลดเส้นไขว้: barycenter กวาดไปข้างหน้า/ถอยหลังสลับกัน ----
  double bary(String n, List<String> ref) {
    final idx = <int>[];
    for (final m in [...parents[n]!, ...children[n]!]) {
      final i = ref.indexOf(m);
      if (i >= 0) idx.add(i);
    }
    return idx.isEmpty ? -1 : idx.reduce((a, b) => a + b) / idx.length;
  }

  void reorder(List<String> layer, List<String> ref) {
    final keyed = [
      for (var i = 0; i < layer.length; i++) (id: layer[i], i: i, b: bary(layer[i], ref)),
    ];
    // ไม่มีเพื่อนบ้านในชั้นอ้างอิง -> คงตำแหน่งเดิม
    keyed.sort((x, y) {
      final bx = x.b < 0 ? x.i.toDouble() : x.b;
      final by = y.b < 0 ? y.i.toDouble() : y.b;
      final c = bx.compareTo(by);
      return c != 0 ? c : x.i.compareTo(y.i);
    });
    layer
      ..clear()
      ..addAll(keyed.map((k) => k.id));
  }

  for (var sweep = 0; sweep < 4; sweep++) {
    for (var k = 1; k < layerCount; k++) {
      reorder(layers[k], layers[k - 1]);
    }
    for (var k = layerCount - 2; k >= 0; k--) {
      reorder(layers[k], layers[k + 1]);
    }
  }

  // ---- แนวตั้ง: เริ่มจากกองกลางชั้น แล้วดึงแต่ละตารางเข้าหาระดับเฉลี่ยของตารางที่เชื่อมกัน ----
  final top = <String, double>{};
  double layerHeight(List<String> l) => l.fold<double>(0, (s, id) => s + heightOf(id)) + opts.gapY * (l.length - 1);
  final blockH0 = layers.map(layerHeight).reduce(math.max);
  for (final l in layers) {
    var y = (blockH0 - layerHeight(l)) / 2;
    for (final id in l) {
      top[id] = y;
      y += heightOf(id) + opts.gapY;
    }
  }

  double centerOf(String id) => top[id]! + heightOf(id) / 2;

  /// วางชั้น [layer] ให้ใกล้ระดับที่ต้องการที่สุด โดยรักษาลำดับและช่องว่างต่ำสุด (isotonic regression / PAV)
  void place(List<String> layer, Map<String, double> desiredTop) {
    final n = layer.length;
    if (n == 0) return;
    // q_i = top_i - sum_{j<i} (h_j + gap): ข้อจำกัดกลายเป็น q ไม่ลดลง
    final offset = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      offset[i] = offset[i - 1] + heightOf(layer[i - 1]) + opts.gapY;
    }
    final blocks = <({double sum, int count})>[];
    for (var i = 0; i < n; i++) {
      var b = (sum: desiredTop[layer[i]]! - offset[i], count: 1);
      while (blocks.isNotEmpty && blocks.last.sum / blocks.last.count > b.sum / b.count) {
        final prev = blocks.removeLast();
        b = (sum: prev.sum + b.sum, count: prev.count + b.count);
      }
      blocks.add(b);
    }
    var i = 0;
    for (final b in blocks) {
      final q = b.sum / b.count;
      for (var k = 0; k < b.count; k++, i++) {
        top[layer[i]] = q + offset[i];
      }
    }
  }

  Map<String, double> desired(List<String> layer, Set<String> Function(String) neighbors, Set<String> refLayer) {
    final out = <String, double>{};
    for (final id in layer) {
      final ns = neighbors(id).where(refLayer.contains).toList();
      out[id] = ns.isEmpty ? top[id]! : ns.map(centerOf).reduce((a, b) => a + b) / ns.length - heightOf(id) / 2;
    }
    return out;
  }

  for (var sweep = 0; sweep < 4; sweep++) {
    for (var k = 1; k < layerCount; k++) {
      place(layers[k], desired(layers[k], (id) => parents[id]!, layers[k - 1].toSet()));
    }
    for (var k = layerCount - 2; k >= 0; k--) {
      place(layers[k], desired(layers[k], (id) => children[id]!, layers[k + 1].toSet()));
    }
  }
  final minTop = top.values.reduce(math.min);
  for (final id in top.keys.toList()) {
    top[id] = top[id]! - minTop;
  }

  // ---- แนวนอน: ช่องว่างระหว่างชั้นกว้างตามจำนวนเส้นที่ผ่านช่องนั้น (เส้นแยกเลนขนานจึงมีที่) ----
  final xOfLayer = List<double>.filled(layerCount, 0);
  final layerW = [for (final l in layers) l.map((id) => byId[id]!.width).reduce(math.max)];
  for (var k = 1; k < layerCount; k++) {
    var crossing = 0;
    for (final (pa, ch) in edges) {
      if (!depth.containsKey(pa) || !depth.containsKey(ch)) continue;
      if (depth[pa]! <= k - 1 && depth[ch]! >= k) crossing++;
    }
    final gap = math.min(260.0, math.max(opts.gapX, 56.0 + 11 * crossing));
    xOfLayer[k] = xOfLayer[k - 1] + layerW[k - 1] + gap;
  }

  final pos = <String, Pos>{};
  var maxBottom = 0.0;
  for (var k = 0; k < layerCount; k++) {
    for (final id in layers[k]) {
      pos[id] = (x: xOfLayer[k], y: top[id]!);
      maxBottom = math.max(maxBottom, top[id]! + heightOf(id));
    }
  }
  return (pos: pos, w: xOfLayer.last + layerW.last, h: maxBottom);
}
