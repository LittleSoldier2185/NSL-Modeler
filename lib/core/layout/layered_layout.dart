import 'dart:math' as math;

/// กล่องหนึ่งกล่องที่จะจัดวาง (ขนาดคงที่ ตำแหน่งเดิมใช้หาจุดอ้างอิง)
class LayoutBox {
  const LayoutBox(this.id, this.x, this.y, this.w, this.h);
  final String id;
  final double x, y, w, h;
}

/// จัดวางแบบชั้น (Sugiyama อย่างง่าย) ใช้ร่วมกันระหว่างแผนภาพ — คืนมุมซ้ายบนใหม่ของทุกกล่อง (ไม่แก้ข้อมูล)
///
/// - ชั้น = ระยะทางยาวสุดจากกล่องต้นทาง (ไม่มีเส้นเข้า) ; เส้นที่วนกลับ (ทำให้เกิดวงจร) ไม่นับ
/// - ลำดับในชั้นเรียงตามค่าเฉลี่ยตำแหน่งของเพื่อนบ้าน (barycenter) เพื่อลดเส้นตัดกัน
/// - [horizontal] = ชั้นเรียงซ้าย→ขวา (ในชั้นเรียงบน→ล่าง) ; false = ชั้นเรียงบน→ล่าง (ในชั้นเรียงซ้าย→ขวา)
/// - [layerGap] ระยะระหว่างชั้น, [rowGap] ระยะระหว่างกล่องในชั้นเดียวกัน
/// - ผลลัพธ์ถูกเลื่อนให้มุมซ้ายบนของทั้งชุดอยู่ที่เดิม และเหมือนเดิมทุกครั้งที่เรียก (deterministic)
Map<String, ({double x, double y})> layeredLayout(
  List<LayoutBox> boxes,
  List<(String from, String to)> edges, {
  bool horizontal = true,
  double layerGap = 140,
  double rowGap = 50,
}) {
  if (boxes.isEmpty) return {};
  final ids = [for (final n in boxes) n.id];
  final index = {for (var i = 0; i < ids.length; i++) ids[i]: i};

  final out = <String, List<String>>{for (final id in ids) id: []};
  for (final (from, to) in edges) {
    if (!index.containsKey(from) || !index.containsKey(to) || from == to) continue;
    out[from]!.add(to);
  }

  // ตัดเส้นย้อนกลับ (back edge) ด้วย DFS เพื่อให้เป็น DAG
  final dag = <String, List<String>>{for (final id in ids) id: []};
  final state = <String, int>{}; // 1 กำลังเยี่ยม 2 เสร็จ
  void dfs(String u) {
    state[u] = 1;
    for (final v in out[u]!) {
      if (state[v] == 1) continue; // วงจร
      dag[u]!.add(v);
      if (state[v] != 2 && state[v] != 1) dfs(v);
    }
    state[u] = 2;
  }

  final hasIn = <String>{for (final e in out.entries) ...e.value};
  for (final id in ids.where((i) => !hasIn.contains(i))) {
    if (state[id] == null) dfs(id);
  }
  for (final id in ids) {
    if (state[id] == null) dfs(id);
  }

  // ชั้นด้วยเส้นทางยาวสุด
  final layer = {for (final id in ids) id: 0};
  final indeg = {for (final id in ids) id: 0};
  for (final e in dag.entries) {
    for (final v in e.value) {
      indeg[v] = indeg[v]! + 1;
    }
  }
  final queue = [for (final id in ids) if (indeg[id] == 0) id];
  var qi = 0;
  while (qi < queue.length) {
    final u = queue[qi++];
    for (final v in dag[u]!) {
      layer[v] = math.max(layer[v]!, layer[u]! + 1);
      indeg[v] = indeg[v]! - 1;
      if (indeg[v] == 0) queue.add(v);
    }
  }

  final layers = <int, List<String>>{};
  for (final id in ids) {
    layers.putIfAbsent(layer[id]!, () => []).add(id);
  }
  final order = layers.keys.toList()..sort();

  final nb = <String, List<String>>{for (final id in ids) id: []};
  for (final e in dag.entries) {
    for (final v in e.value) {
      nb[e.key]!.add(v);
      nb[v]!.add(e.key);
    }
  }
  final pos = <String, double>{};
  for (final l in order) {
    for (var i = 0; i < layers[l]!.length; i++) {
      pos[layers[l]![i]] = i.toDouble();
    }
  }

  void sweep(Iterable<int> ls, bool useLeft) {
    for (final l in ls) {
      final list = layers[l]!;
      double bary(String id) {
        final ns = nb[id]!.where((n) => useLeft ? layer[n]! < l : layer[n]! > l).toList();
        if (ns.isEmpty) return pos[id]!;
        return ns.map((n) => pos[n]!).reduce((a, b) => a + b) / ns.length;
      }

      final keyed = {for (final id in list) id: bary(id)};
      list.sort((a, b) {
        final c = keyed[a]!.compareTo(keyed[b]!);
        return c != 0 ? c : index[a]!.compareTo(index[b]!);
      });
      for (var i = 0; i < list.length; i++) {
        pos[list[i]] = i.toDouble();
      }
    }
  }

  for (var pass = 0; pass < 4; pass++) {
    sweep(order.skip(1), true);
    sweep(order.reversed.skip(1), false);
  }

  // main = แกนของชั้น, cross = แกนในชั้น
  final byId = {for (final n in boxes) n.id: n};
  double mainSize(String id) => horizontal ? byId[id]!.w : byId[id]!.h;
  double crossSize(String id) => horizontal ? byId[id]!.h : byId[id]!.w;
  final colMain = <int, double>{};
  var m = 0.0;
  for (final l in order) {
    colMain[l] = m;
    m += layers[l]!.map(mainSize).reduce(math.max) + layerGap;
  }
  final extents = {
    for (final l in order) l: layers[l]!.fold<double>(0, (s, id) => s + crossSize(id)) + rowGap * (layers[l]!.length - 1),
  };
  final maxExtent = extents.values.reduce(math.max);

  final res = <String, ({double x, double y})>{};
  for (final l in order) {
    var c = (maxExtent - extents[l]!) / 2;
    final colSize = layers[l]!.map(mainSize).reduce(math.max);
    for (final id in layers[l]!) {
      final mm = colMain[l]! + (colSize - mainSize(id)) / 2;
      res[id] = horizontal ? (x: mm, y: c) : (x: c, y: mm);
      c += crossSize(id) + rowGap;
    }
  }

  final ox = boxes.map((n) => n.x).reduce(math.min);
  final oy = boxes.map((n) => n.y).reduce(math.min);
  return {for (final e in res.entries) e.key: (x: e.value.x + ox, y: e.value.y + oy)};
}

/// จัดวางแบบต้นไม้ (ลูกเรียงใต้/ข้างพ่อ พ่ออยู่กึ่งกลางของลูก) — กล่องที่ถูกชี้ซ้ำหรือวนกลับใช้พ่อคนแรกที่พบ
/// ราก = กล่องที่ไม่มีเส้นเข้า (ไม่มีเลย = กล่องแรก) ; กล่องที่ไม่ถูกเชื่อมเป็นต้นไม้แยกเรียงต่อกัน
Map<String, ({double x, double y})> treeLayout(
  List<LayoutBox> boxes,
  List<(String from, String to)> edges, {
  bool horizontal = false,
  double levelGap = 70,
  double siblingGap = 40,
}) {
  if (boxes.isEmpty) return {};
  final byId = {for (final b in boxes) b.id: b};
  final children = <String, List<String>>{for (final b in boxes) b.id: []};
  final hasIn = <String>{};
  for (final (f, t) in edges) {
    if (!byId.containsKey(f) || !byId.containsKey(t) || f == t) continue;
    hasIn.add(t);
    children[f]!.add(t);
  }
  final roots = [for (final b in boxes) if (!hasIn.contains(b.id)) b.id];
  if (roots.isEmpty) roots.add(boxes.first.id);
  final seen = <String>{};
  final kids = <String, List<String>>{};
  void claim(String u) {
    seen.add(u);
    kids[u] = [];
  }

  // BFS เพื่อให้แต่ละกล่องมีพ่อคนเดียว (ระดับตื้นสุด)
  final queue = <String>[];
  for (final r in roots) {
    if (seen.contains(r)) continue;
    claim(r);
    queue.add(r);
  }
  for (var i = 0; i < queue.length; i++) {
    final u = queue[i];
    for (final v in children[u]!) {
      if (seen.contains(v)) continue;
      claim(v);
      kids[u]!.add(v);
      queue.add(v);
    }
  }
  for (final b in boxes) {
    if (!seen.contains(b.id)) {
      claim(b.id);
      roots.add(b.id);
    }
  }

  double main(String id) => horizontal ? byId[id]!.w : byId[id]!.h;
  double cross(String id) => horizontal ? byId[id]!.h : byId[id]!.w;
  final width = <String, double>{};
  double measure(String u) {
    final ks = kids[u]!;
    final own = cross(u);
    if (ks.isEmpty) return width[u] = own;
    final sum = ks.map(measure).reduce((a, b) => a + b) + siblingGap * (ks.length - 1);
    return width[u] = math.max(own, sum);
  }

  // ระยะของแต่ละระดับ = กล่องที่ใหญ่สุดของระดับนั้น
  final depth = <String, int>{};
  final levelSize = <int, double>{};
  void depths(String u, int d) {
    depth[u] = d;
    levelSize[d] = math.max(levelSize[d] ?? 0, main(u));
    for (final k in kids[u]!) {
      depths(k, d + 1);
    }
  }

  final res = <String, ({double x, double y})>{};
  var offset = 0.0;
  for (final r in roots) {
    measure(r);
    depths(r, 0);
  }
  final levelStart = <int, double>{};
  var acc = 0.0;
  for (var d = 0; levelSize.containsKey(d); d++) {
    levelStart[d] = acc;
    acc += levelSize[d]! + levelGap;
  }
  void place(String u, double start) {
    final w = width[u]!;
    final c = start + (w - cross(u)) / 2;
    final mm = levelStart[depth[u]]! + (levelSize[depth[u]]! - main(u)) / 2;
    res[u] = horizontal ? (x: mm, y: c) : (x: c, y: mm);
    final ks = kids[u]!;
    if (ks.isEmpty) return;
    final total = ks.map((k) => width[k]!).reduce((a, b) => a + b) + siblingGap * (ks.length - 1);
    var s = start + (w - total) / 2;
    for (final k in ks) {
      place(k, s);
      s += width[k]! + siblingGap;
    }
  }

  for (final r in roots) {
    place(r, offset);
    offset += width[r]! + siblingGap;
  }
  final ox = boxes.map((n) => n.x).reduce(math.min);
  final oy = boxes.map((n) => n.y).reduce(math.min);
  return {for (final e in res.entries) e.key: (x: e.value.x + ox, y: e.value.y + oy)};
}
