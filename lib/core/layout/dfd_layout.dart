import 'dart:math' as math;

import '../models/dfd_model.dart';

/// ระยะห่างระหว่างชั้น (แนวนอน) และระหว่างวัตถุในชั้นเดียวกัน (แนวตั้ง) ตอนจัดวางอัตโนมัติ
const double kDfdLayerGap = 140;
const double kDfdRowGap = 50;

/// จัดวาง DFD เป็นชั้นซ้าย→ขวาตามทิศทางข้อมูล คืนตำแหน่งมุมซ้ายบนใหม่ของทุกวัตถุ (ไม่แก้แผนภาพ)
///
/// - ชั้น = ระยะทางยาวสุดจากวัตถุต้นทาง (ไม่มีข้อมูลเข้า) ; เส้นที่วนกลับ (ทำให้เกิดวงจร) ไม่นับ
/// - ลำดับในชั้นเรียงตามค่าเฉลี่ยตำแหน่งของเพื่อนบ้าน (barycenter) เพื่อลดเส้นตัดกัน
/// - ผลลัพธ์ถูกเลื่อนให้มุมซ้ายบนของทั้งชุดอยู่ที่เดิม และเหมือนเดิมทุกครั้งที่เรียก (deterministic)
Map<String, ({double x, double y})> dfdAutoLayout(DfdDiagram d) {
  if (d.nodes.isEmpty) return {};
  final ids = [for (final n in d.nodes) n.id];
  final index = {for (var i = 0; i < ids.length; i++) ids[i]: i};

  // ทิศทางของเส้น: ปกติ from->to ; สองทางถือว่าตามลำดับที่ขีดไว้
  final out = <String, List<String>>{for (final id in ids) id: []};
  for (final f in d.flows) {
    if (!index.containsKey(f.fromId) || !index.containsKey(f.toId) || f.fromId == f.toId) continue;
    out[f.fromId]!.add(f.toId);
  }

  // ตัดเส้นย้อนกลับ (back edge) ด้วย DFS เพื่อให้เป็น DAG
  final dag = <String, List<String>>{for (final id in ids) id: []};
  final state = <String, int>{}; // 0 ยังไม่เยี่ยม 1 กำลังเยี่ยม 2 เสร็จ
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

  // ลำดับในชั้น: เริ่มตามลำดับวัตถุ แล้วเรียงด้วย barycenter ของเพื่อนบ้านสลับซ้าย/ขวาหลายรอบ
  final nb = <String, List<String>>{for (final id in ids) id: []};
  for (final e in dag.entries) {
    for (final v in e.value) {
      nb[e.key]!.add(v);
      nb[v]!.add(e.key);
    }
  }
  final pos = <String, double>{};
  void renumber() {
    for (final l in order) {
      for (var i = 0; i < layers[l]!.length; i++) {
        pos[layers[l]![i]] = i.toDouble();
      }
    }
  }

  renumber();
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

  // พิกัด: ความกว้างชั้น = วัตถุที่กว้างสุดในชั้น ; แต่ละชั้นจัดกึ่งกลางแนวตั้งรอบเดียวกัน
  final byId = {for (final n in d.nodes) n.id: n};
  final colX = <int, double>{};
  var x = 0.0;
  for (final l in order) {
    colX[l] = x;
    x += layers[l]!.map((id) => byId[id]!.w).reduce(math.max) + kDfdLayerGap;
  }
  final heights = {
    for (final l in order) l: layers[l]!.fold<double>(0, (s, id) => s + byId[id]!.h) + kDfdRowGap * (layers[l]!.length - 1),
  };
  final maxH = heights.values.reduce(math.max);

  final res = <String, ({double x, double y})>{};
  for (final l in order) {
    var y = (maxH - heights[l]!) / 2;
    final colW = layers[l]!.map((id) => byId[id]!.w).reduce(math.max);
    for (final id in layers[l]!) {
      final n = byId[id]!;
      res[id] = (x: colX[l]! + (colW - n.w) / 2, y: y);
      y += n.h + kDfdRowGap;
    }
  }

  // ย้ายให้มุมซ้ายบนของชุดอยู่ตำแหน่งเดิม
  final ox = d.nodes.map((n) => n.x).reduce(math.min);
  final oy = d.nodes.map((n) => n.y).reduce(math.min);
  return {for (final e in res.entries) e.key: (x: e.value.x + ox, y: e.value.y + oy)};
}
