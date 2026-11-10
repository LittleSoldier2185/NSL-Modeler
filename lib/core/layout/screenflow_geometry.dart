import 'dart:math' as math;

import '../models/screenflow_model.dart';
import 'layered_layout.dart';
import 'ortho_route.dart';

/// เรขาคณิตของ Screen Flow (ใช้ร่วมกันทั้งบนจอ / PNG / SVG / การคลิก) — ฟังก์ชันล้วน
/// เส้นใช้ตัวจัดเส้นหักมุมฉากกลาง ([orthogonalRoutes]) และจัดวางอัตโนมัติด้วย [layeredLayout] (ซ้ายไปขวา)

/// ความสูงแถบชื่อของหน้าจอ (ส่วนล่างเป็นภาพย่อ Wireframe)
const double kSfTitleBar = 28;

/// สีประจำชนิดโหนด (ใช้เมื่อไม่ได้กำหนดสีเอง) — ใช้ร่วมกันทั้งบนจอ PNG และ SVG
const Map<SfKind, int> kSfKindColors = {
  SfKind.start: 0xFF16A34A,
  SfKind.screen: 0xFF2563EB,
  SfKind.external: 0xFF7C3AED,
  SfKind.end: 0xFFDC2626,
};

/// สีเส้นขอบของโหนด
int sfNodeColor(SfNode n) => n.color ?? kSfKindColors[n.kind]!;

/// กรอบภาพย่อ Wireframe ภายในหน้าจอ [n] (left, top, width, height) — ภาพจริงย่อให้พอดีโดยคงสัดส่วน
({double left, double top, double width, double height}) sfThumbBox(SfNode n) =>
    (left: n.x + 6, top: n.y + kSfTitleBar + 2, width: math.max(4, n.w - 12), height: math.max(4, n.h - kSfTitleBar - 8));

/// สเกลและจุดเริ่มของภาพย่อหน้าจอขนาด [fw]×[fh] ในกรอบ [box] (จัดกึ่งกลาง คงสัดส่วน)
({double scale, double dx, double dy}) sfThumbFit(({double left, double top, double width, double height}) box, double fw, double fh) {
  final s = math.min(box.width / fw, box.height / fh);
  return (scale: s, dx: box.left + (box.width - fw * s) / 2, dy: box.top + (box.height - fh * s) / 2);
}

/// ระยะห่างระหว่างชั้น/ระหว่างโหนดตอนจัดวางอัตโนมัติ
const double kSfLayerGap = 110;
const double kSfRowGap = 50;

/// เส้นทางของเส้นทุกเส้น (key = id) — หักมุมฉาก ; เส้นวนเข้าตัวเองเป็นห่วงทางขวา
Map<String, List<RoutePoint>> sfRoutes(ScreenFlowDiagram d) {
  final boxes = <String, RouteBox>{};
  final byId = <String, SfNode>{};
  for (final n in d.nodes) {
    boxes.putIfAbsent(n.id, () => RouteBox(n.id, n.x, n.y, n.w, n.h));
    byId.putIfAbsent(n.id, () => n);
  }
  final links = [for (final e in d.edges) if (e.fromId != e.toId) RouteLink(e.id, e.fromId, e.toId)];
  final raw = orthogonalRoutes(boxes, links, gutter: 30, slotGap: 16);
  final out = <String, List<RoutePoint>>{};
  for (final e in d.edges) {
    final a = byId[e.fromId], b = byId[e.toId];
    if (a == null || b == null) continue;
    if (e.fromId == e.toId) {
      final r = a.right, y0 = a.cy - math.min(14, a.h / 4), y1 = a.cy + math.min(14, a.h / 4);
      out[e.id] = [(r, y0), (r + 30, y0), (r + 30, y1), (r, y1)];
      continue;
    }
    final pts = raw[e.id];
    if (pts != null && pts.length >= 2) out[e.id] = pts;
  }
  return out;
}

/// โหนดบนสุดที่ ([x],[y]) อยู่ในกรอบ
SfNode? sfNodeAt(ScreenFlowDiagram d, double x, double y, {double tol = 0}) {
  for (final n in d.nodes.reversed) {
    if (x >= n.x - tol && x <= n.right + tol && y >= n.y - tol && y <= n.bottom + tol) return n;
  }
  return null;
}

/// เส้นที่อยู่ใกล้จุดภายใน [tolerance] (ใกล้สุดก่อน)
String? sfEdgeAt(ScreenFlowDiagram d, double x, double y, {double tolerance = 7, Map<String, List<RoutePoint>>? routes}) {
  String? best;
  var bestD = tolerance;
  (routes ?? sfRoutes(d)).forEach((id, pts) {
    final dist = distanceToRoute(pts, x, y);
    if (dist <= bestD) {
      bestD = dist;
      best = id;
    }
  });
  return best;
}

/// ขอบเขตของแผนผัง (โหนด + เส้น) เผื่อขอบ [pad] ; ว่าง = null
({double left, double top, double right, double bottom})? sfBounds(ScreenFlowDiagram d, {double pad = 40, Set<String>? only}) {
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
    for (final pts in sfRoutes(d).values) {
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

/// จัดวางอัตโนมัติเป็นชั้นจากซ้ายไปขวาตามทิศเส้น — คืนมุมซ้ายบนใหม่ (ไม่แก้ข้อมูล ; ผลคงที่)
Map<String, ({double x, double y})> sfAutoLayout(ScreenFlowDiagram d) => layeredLayout(
      [for (final n in d.nodes) LayoutBox(n.id, n.x, n.y, n.w, n.h)],
      [for (final e in d.edges) (e.fromId, e.toId)],
      horizontal: true,
      layerGap: kSfLayerGap,
      rowGap: kSfRowGap,
    );
