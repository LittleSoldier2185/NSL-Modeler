import 'dart:math' as math;

import '../models/project.dart';
import '../models/table_model.dart';

typedef Pos = ({double x, double y});

class LayoutOptions {
  const LayoutOptions({
    this.gapX = 90,
    this.gapY = 40,
    this.margin = 40,
    this.headerHeight = 36,
    this.rowHeight = 28,
  });
  final double gapX;
  final double gapY;
  final double margin;
  final double headerHeight;
  final double rowHeight;
}

/// จัดตำแหน่งตารางเป็นชั้นตามสาย FK: ตารางที่ถูกอ้างถึง (แม่) อยู่ซ้าย ตารางลูกอยู่ขวา
/// - สลับลำดับในแต่ละชั้นด้วย barycenter เพื่อลดเส้นไขว้
/// - FK วนเป็นวงถูกตัดวงอัตโนมัติ (ไม่ค้าง)
/// - ตารางที่ไม่มี FK กับใครเลย วางเป็นตารางด้านล่าง
/// ผลลัพธ์คงที่ (ข้อมูลเดิม -> ตำแหน่งเดิม) และไม่แก้ [p]
Map<String, Pos> autoLayout(Project p, {LayoutOptions opts = const LayoutOptions()}) {
  final byId = {for (final t in p.tables) t.id: t};
  final order = [for (final t in p.tables) t.id];

  // parents[child] = ตารางที่ child อ้างถึง
  final parents = {for (final id in order) id: <String>{}};
  final children = {for (final id in order) id: <String>{}};
  for (final r in p.relations) {
    final c = r.fromTableId, pa = r.toTableId;
    if (c == pa || !byId.containsKey(c) || !byId.containsKey(pa)) continue;
    parents[c]!.add(pa);
    children[pa]!.add(c);
  }
  bool connected(String id) => parents[id]!.isNotEmpty || children[id]!.isNotEmpty;

  double heightOf(TableModel t) => opts.headerHeight + opts.rowHeight * t.columns.length;

  // ---- แยกกลุ่มที่เชื่อมกัน ----
  final seen = <String>{};
  final components = <List<String>>[];
  for (final id in order) {
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

  final out = <String, Pos>{};
  var cursorY = opts.margin;

  for (final comp in components) {
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

    // ---- พิกัด ----
    final layerH = [
      for (final l in layers)
        l.fold<double>(0, (s, id) => s + heightOf(byId[id]!)) + opts.gapY * (l.length - 1),
    ];
    final blockH = layerH.reduce(math.max);
    var x = opts.margin;
    for (var k = 0; k < layerCount; k++) {
      var y = cursorY + (blockH - layerH[k]) / 2;
      var w = 0.0;
      for (final id in layers[k]) {
        final t = byId[id]!;
        out[id] = (x: x, y: y);
        y += heightOf(t) + opts.gapY;
        w = math.max(w, t.width);
      }
      x += w + opts.gapX;
    }
    cursorY += blockH + opts.gapY * 2;
  }

  // ---- ตารางโดดเดี่ยว: จัดเป็นตารางด้านล่าง ----
  final loners = [for (final id in order) if (!connected(id)) id];
  if (loners.isNotEmpty) {
    final cols = math.min(4, math.sqrt(loners.length).ceil());
    final colW = loners.map((id) => byId[id]!.width).reduce(math.max) + opts.gapX;
    var y = cursorY;
    for (var i = 0; i < loners.length; i += cols) {
      final row = loners.sublist(i, math.min(i + cols, loners.length));
      for (var j = 0; j < row.length; j++) {
        out[row[j]] = (x: opts.margin + j * colW, y: y);
      }
      y += row.map((id) => heightOf(byId[id]!)).reduce(math.max) + opts.gapY;
    }
  }
  return out;
}
