import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/layout/diagram_geometry.dart' show snapToGrid, kGridSize;
import '../core/models/dfd_model.dart';
import '../core/models/diagram.dart';
import 'project_controller.dart';

enum DfdTool { select, entity, process, store, flow }

/// สถานะหน้าจอและคำสั่งแก้ไขของแท็บ DFD ที่เปิดอยู่ (เครื่องมือ การเลือก มุมมอง) — เนื้อหาและประวัติ undo อยู่ที่ [ProjectController]
class DfdController extends ChangeNotifier {
  DfdController(this.pc) {
    pc.addListener(_onProject);
  }

  final ProjectController pc;

  @override
  void dispose() {
    pc.removeListener(_onProject);
    super.dispose();
  }

  // ---------- ข้อมูล ----------

  bool get active => pc.activeDiagram.kind == DiagramKind.dfd;

  DfdDiagram get diagram => pc.project.dfdOf(pc.activeDiagramId);

  // ---------- เครื่องมือ / การเลือก ----------

  DfdTool _tool = DfdTool.select;
  DfdTool get tool => _tool;

  final Set<String> _nodes = {};
  String? _flow;
  String? _linkSource;

  Set<String> get selectedNodeIds => Set.unmodifiable(_nodes);
  String? get selectedFlowId => _flow;
  String? get linkSource => _linkSource;

  DfdNode? get selectedNode => _nodes.length == 1 ? diagram.nodeById(_nodes.first) : null;
  DfdFlow? get selectedFlow => _flow == null ? null : diagram.flowById(_flow!);

  void setTool(DfdTool t) {
    if (_tool == t && _linkSource == null) return;
    _tool = t;
    _linkSource = null;
    notifyListeners();
  }

  void clearSelection() {
    if (_nodes.isEmpty && _flow == null && _linkSource == null) return;
    _nodes.clear();
    _flow = null;
    _linkSource = null;
    notifyListeners();
  }

  void selectNode(String id, {bool add = false}) {
    if (diagram.nodeById(id) == null) return;
    _flow = null;
    if (add) {
      if (!_nodes.remove(id)) _nodes.add(id);
    } else {
      _nodes
        ..clear()
        ..add(id);
    }
    notifyListeners();
  }

  void setNodeSelection(Iterable<String> ids) {
    final next = {for (final id in ids) if (diagram.nodeById(id) != null) id};
    if (next.length == _nodes.length && next.containsAll(_nodes) && _flow == null) return;
    _flow = null;
    _nodes
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectFlow(String? id) {
    if (id != null && diagram.flowById(id) == null) return;
    _nodes.clear();
    _flow = id;
    notifyListeners();
  }

  void selectAll() {
    _flow = null;
    _nodes
      ..clear()
      ..addAll(diagram.nodes.map((n) => n.id));
    notifyListeners();
  }

  /// Esc: ยกเลิกการต่อเส้น/เครื่องมือ ก่อน แล้วค่อยล้างการเลือก
  void escape() {
    if (_linkSource != null || _tool != DfdTool.select) {
      _linkSource = null;
      _tool = DfdTool.select;
      notifyListeners();
    } else {
      clearSelection();
    }
  }

  void _onProject() {
    // undo/ลบแท็บอาจทำให้ของที่เลือกหายไป
    if (!active) return;
    final d = diagram;
    final before = _nodes.length;
    _nodes.removeWhere((id) => d.nodeById(id) == null);
    final lostFlow = _flow != null && d.flowById(_flow!) == null;
    if (lostFlow) _flow = null;
    if (_linkSource != null && d.nodeById(_linkSource!) == null) _linkSource = null;
    if (before != _nodes.length || lostFlow) notifyListeners();
  }

  // ---------- วัตถุ ----------

  String _defaultName(DfdKind k) => switch (k) {
        DfdKind.entity => tr('ผู้ใช้ภายนอก'),
        DfdKind.process => tr('กระบวนการ'),
        DfdKind.store => tr('ที่เก็บข้อมูล'),
      };

  /// วางวัตถุใหม่โดยให้ศูนย์กลางอยู่ที่ ([cx],[cy]) (พิกัดแผนภาพ) แล้วเลือกมัน
  DfdNode? addNode(DfdKind kind, double cx, double cy, {bool snap = false}) {
    if (!active) return null;
    final (w, h) = dfdDefaultSize(kind);
    var x = cx - w / 2, y = cy - h / 2;
    if (snap) {
      x = snapToGrid(x);
      y = snapToGrid(y);
    }
    late DfdNode node;
    pc.dfdEdit((d) {
      node = DfdNode(
        id: pc.newId('n'),
        kind: kind,
        name: _defaultName(kind),
        number: switch (kind) {
          DfdKind.process => d.nextProcessNumber(),
          DfdKind.store => d.nextStoreNumber(),
          DfdKind.entity => '',
        },
        x: x,
        y: y,
      );
      d.nodes.add(node);
    });
    _flow = null;
    _nodes
      ..clear()
      ..add(node.id);
    _tool = DfdTool.select;
    notifyListeners();
    return node;
  }

  void updateNode(String id, void Function(DfdNode n) change) {
    final n = diagram.nodeById(id);
    if (n == null) return;
    pc.dfdEdit((d) => change(d.nodeById(id)!));
  }

  void renameNode(String id, String name) {
    final n = diagram.nodeById(id);
    if (n == null || n.name == name) return;
    updateNode(id, (n) => n.name = name);
  }

  void setNodeNumber(String id, String number) {
    final n = diagram.nodeById(id);
    if (n == null || n.kind == DfdKind.entity || n.number == number.trim()) return;
    updateNode(id, (n) => n.number = number.trim());
  }

  /// สีของวัตถุที่เลือกทั้งหมด (null = สีตามชนิด) — undo ขั้นเดียว
  void setNodesColor(Iterable<String> ids, int? argb) {
    final list = [for (final id in ids) if (diagram.nodeById(id) != null) id];
    if (list.isEmpty || list.every((id) => diagram.nodeById(id)!.color == argb)) return;
    pc.dfdEdit((d) {
      for (final id in list) {
        d.nodeById(id)!.color = argb;
      }
    });
  }

  /// ลบวัตถุที่เลือก (พร้อม flow ที่ต่ออยู่) หรือ flow ที่เลือก — คืนจำนวนที่ลบ
  int deleteSelection() {
    if (_flow != null) {
      final id = _flow!;
      if (diagram.flowById(id) == null) return 0;
      pc.dfdEdit((d) => d.flows.removeWhere((f) => f.id == id));
      _flow = null;
      notifyListeners();
      return 1;
    }
    final ids = _nodes.where((id) => diagram.nodeById(id) != null).toSet();
    if (ids.isEmpty) return 0;
    pc.dfdEdit((d) {
      d.nodes.removeWhere((n) => ids.contains(n.id));
      d.flows.removeWhere((f) => ids.contains(f.fromId) || ids.contains(f.toId));
    });
    _nodes.clear();
    notifyListeners();
    return ids.length;
  }

  // ---------- ย้าย ----------

  Map<String, (double, double)>? _origin;
  double _rawDx = 0, _rawDy = 0;

  void beginMove() {
    pc.dfdBeginGesture();
    _origin = {
      for (final id in _nodes)
        if (diagram.nodeById(id) != null) id: (diagram.nodeById(id)!.x, diagram.nodeById(id)!.y),
    };
    _rawDx = 0;
    _rawDy = 0;
  }

  /// ย้ายวัตถุที่เลือกแบบสด ([grid] != null = ปัดเข้าช่อง โดยทุกชิ้นเลื่อนเท่ากัน)
  void moveBy(double dx, double dy, {double? grid}) {
    final o = _origin;
    if (o == null || o.isEmpty) return;
    _rawDx += dx;
    _rawDy += dy;
    var sx = _rawDx, sy = _rawDy;
    if (grid != null) {
      final ref = o.values.first;
      sx = snapToGrid(ref.$1 + _rawDx, grid) - ref.$1;
      sy = snapToGrid(ref.$2 + _rawDy, grid) - ref.$2;
    }
    pc.dfdLive((d) {
      for (final e in o.entries) {
        final n = d.nodeById(e.key);
        if (n == null) continue;
        n.x = (e.value.$1 + sx).clamp(-9600, 19600).toDouble();
        n.y = (e.value.$2 + sy).clamp(-9600, 19600).toDouble();
      }
    });
  }

  void endMove() {
    _origin = null;
    pc.dfdEndGesture();
  }

  /// ขยับวัตถุที่เลือกด้วยปุ่มลูกศร (undo ต่อการกด)
  bool nudge(double dx, double dy) {
    final ids = _nodes.where((id) => diagram.nodeById(id) != null).toList();
    if (ids.isEmpty) return false;
    pc.dfdEdit((d) {
      for (final id in ids) {
        final n = d.nodeById(id)!;
        n.x += dx;
        n.y += dy;
      }
    });
    return true;
  }

  /// ทำสำเนาวัตถุที่เลือก (พร้อม flow ระหว่างกันเอง) เลื่อนไป 30 px แล้วเลือกสำเนา; process/store ได้เลขใหม่
  int duplicateSelection() {
    final src = [for (final id in _nodes) if (diagram.nodeById(id) != null) diagram.nodeById(id)!];
    if (src.isEmpty) return 0;
    final map = <String, String>{};
    final created = <String>[];
    pc.dfdEdit((d) {
      for (final n in src) {
        final copy = DfdNode(
          id: pc.newId('n'),
          kind: n.kind,
          name: n.name,
          number: switch (n.kind) {
            DfdKind.process => d.nextProcessNumber(),
            DfdKind.store => d.nextStoreNumber(),
            DfdKind.entity => '',
          },
          x: n.x + 30,
          y: n.y + 30,
          w: n.w,
          h: n.h,
          color: n.color,
        );
        map[n.id] = copy.id;
        d.nodes.add(copy);
        created.add(copy.id);
      }
      for (final f in List.of(d.flows)) {
        if (map.containsKey(f.fromId) && map.containsKey(f.toId)) {
          d.flows.add(DfdFlow(
            id: pc.newId('f'),
            fromId: map[f.fromId]!,
            toId: map[f.toId]!,
            label: f.label,
            bidirectional: f.bidirectional,
            color: f.color,
          ));
        }
      }
    });
    _flow = null;
    _nodes
      ..clear()
      ..addAll(created);
    notifyListeners();
    return created.length;
  }

  // ---------- เส้นข้อมูล ----------

  /// กดวัตถุด้วยเครื่องมือ Flow: ครั้งแรก = ต้นทาง ครั้งที่สอง = ปลายทาง (สร้างเส้น) — คืน flow ที่สร้างใหม่
  DfdFlow? linkClick(String nodeId) {
    if (diagram.nodeById(nodeId) == null) return null;
    final from = _linkSource;
    if (from == null) {
      _linkSource = nodeId;
      notifyListeners();
      return null;
    }
    if (from == nodeId) {
      _linkSource = null; // กดซ้ำตัวเดิม = ยกเลิก
      notifyListeners();
      return null;
    }
    final f = addFlow(from, nodeId);
    _linkSource = null;
    notifyListeners();
    return f;
  }

  /// สร้างเส้นข้อมูลจาก [fromId] ไป [toId] (ตัวเองไป/มาหาตัวเองไม่ได้) แล้วเลือกเส้นนั้น
  DfdFlow? addFlow(String fromId, String toId, {String label = ''}) {
    if (!active || fromId == toId || diagram.nodeById(fromId) == null || diagram.nodeById(toId) == null) return null;
    late DfdFlow f;
    pc.dfdEdit((d) {
      f = DfdFlow(id: pc.newId('f'), fromId: fromId, toId: toId, label: label);
      d.flows.add(f);
    });
    _nodes.clear();
    _flow = f.id;
    notifyListeners();
    return f;
  }

  void updateFlow(String id, void Function(DfdFlow f) change) {
    if (diagram.flowById(id) == null) return;
    pc.dfdEdit((d) => change(d.flowById(id)!));
  }

  void setFlowLabel(String id, String label) {
    final f = diagram.flowById(id);
    if (f == null || f.label == label) return;
    updateFlow(id, (f) => f.label = label);
  }

  void reverseFlow(String id) => updateFlow(id, (f) {
        final t = f.fromId;
        f.fromId = f.toId;
        f.toId = t;
      });

  void setFlowBidirectional(String id, bool v) {
    final f = diagram.flowById(id);
    if (f == null || f.bidirectional == v) return;
    updateFlow(id, (f) => f.bidirectional = v);
  }

  void setFlowColor(String id, int? argb) {
    final f = diagram.flowById(id);
    if (f == null || f.color == argb) return;
    updateFlow(id, (f) => f.color = argb);
  }

  /// ขนาดพื้นที่แสดงแคนวาส (กำหนดโดย widget ตอน layout)
  Size viewport = Size.zero;

  // ---------- มุมมอง (เลื่อน/ซูม) แยกต่อแท็บ ----------

  static const minScale = 0.2, maxScale = 3.0;
  final Map<String, ({Offset offset, double scale})> _views = {};

  Offset get offset => _views[pc.activeDiagramId]?.offset ?? const Offset(120, 90);
  double get scale => _views[pc.activeDiagramId]?.scale ?? 1;

  void _setView(Offset o, double s) {
    _views[pc.activeDiagramId] = (offset: o, scale: s.clamp(minScale, maxScale).toDouble());
    notifyListeners();
  }

  Offset toWorld(Offset screen) => (screen - offset) / scale;

  void panBy(Offset d) => _setView(offset + d, scale);

  void zoomAt(Offset focus, double factor) {
    final s = (scale * factor).clamp(minScale, maxScale).toDouble();
    if (s == scale) return;
    final w = toWorld(focus);
    _setView(focus - w * s, s);
  }

  void resetZoom(Size viewport) {
    final w = toWorld(viewport.center(Offset.zero));
    _setView(viewport.center(Offset.zero) - w, 1);
  }

  /// ปรับให้เห็นทั้งแผนภาพ (ซูมไม่เกิน 1.2 เท่า); ว่าง = กลับมุมมองเริ่มต้น
  void fit(Size viewport) {
    final b = dfdBounds(diagram, pad: 60);
    if (b == null || viewport.isEmpty) {
      _setView(const Offset(120, 90), 1);
      return;
    }
    final w = b.right - b.left, h = b.bottom - b.top;
    final s = math.min(1.2, math.min(viewport.width / w, viewport.height / h));
    _setView(Offset((viewport.width - w * s) / 2 - b.left * s, (viewport.height - h * s) / 2 - b.top * s), s);
  }

  /// เลื่อนมุมมองให้จุด [p] (พิกัดแผนภาพ) อยู่กลางจอ
  void revealPoint(Offset p, Size viewport) {
    if (viewport.isEmpty) return;
    _setView(viewport.center(Offset.zero) - p * scale, scale);
  }

  /// เลื่อนมุมมองให้วัตถุ [id] อยู่กลางจอ (ใช้ตอนคลิกรายการในแผงซ้าย)
  void reveal(String id, Size viewport) {
    final n = diagram.nodeById(id);
    if (n == null || viewport.isEmpty) return;
    _setView(viewport.center(Offset.zero) - Offset(n.cx, n.cy) * scale, scale);
  }

  /// ขนาดช่องตาราง (ใช้ปัดตำแหน่งเมื่อเปิด snap)
  static const grid = kGridSize;
}
