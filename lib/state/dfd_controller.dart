import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/clipboard/dfd_clipboard.dart';
import '../core/layout/dfd_layout.dart';
import '../core/layout/dfd_resize.dart';
import '../core/layout/diagram_geometry.dart' show snapToGrid, kGridSize;
import '../core/models/dfd_model.dart';
import '../core/models/workspace.dart';
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

  bool get active => pc.activeDiagram.type == DocType.dfd;

  DfdDiagram get diagram => pc.dfdOf(pc.activeDiagramId);

  // ---------- เครื่องมือ / การเลือก ----------

  DfdTool _tool = DfdTool.select;
  DfdTool get tool => _tool;

  final Set<String> _nodes = {};
  String? _flow;
  String? _boundary;
  String? _linkSource;

  Set<String> get selectedNodeIds => Set.unmodifiable(_nodes);
  String? get selectedFlowId => _flow;
  String? get selectedBoundaryId => _boundary;
  DfdBoundary? get selectedBoundary => _boundary == null ? null : diagram.boundaryById(_boundary!);
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
    if (_nodes.isEmpty && _flow == null && _boundary == null && _linkSource == null) return;
    _nodes.clear();
    _flow = null;
    _boundary = null;
    _linkSource = null;
    notifyListeners();
  }

  void selectNode(String id, {bool add = false}) {
    if (diagram.nodeById(id) == null) return;
    _flow = null;
    _boundary = null;
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
    if (next.length == _nodes.length && next.containsAll(_nodes) && _flow == null && _boundary == null) return;
    _flow = null;
    _boundary = null;
    _nodes
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectFlow(String? id) {
    if (id != null && diagram.flowById(id) == null) return;
    _nodes.clear();
    _boundary = null;
    _flow = id;
    notifyListeners();
  }

  void selectBoundary(String? id) {
    if (id != null && diagram.boundaryById(id) == null) return;
    _nodes.clear();
    _flow = null;
    _boundary = id;
    notifyListeners();
  }

  void selectAll() {
    _flow = null;
    _boundary = null;
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
    final lostBoundary = _boundary != null && d.boundaryById(_boundary!) == null;
    if (lostBoundary) _boundary = null;
    if (before != _nodes.length || lostFlow || lostBoundary) notifyListeners();
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

  /// ผูกที่เก็บข้อมูลกับตาราง ER ([tableId] null = เลิกผูก) ; ถ้าที่เก็บข้อมูลยังไม่มีชื่อ ใช้ชื่อตารางให้ — undo ขั้นเดียว
  void setStoreTable(String id, String? tableId) {
    final n = diagram.nodeById(id);
    if (n == null || n.kind != DfdKind.store || n.tableId == tableId) return;
    final t = tableId == null ? null : pc.project.tableById(tableId);
    updateNode(id, (n) {
      n.tableId = t?.id;
      n.tableDocId = t == null ? null : pc.erDocumentId;
      if (t != null && n.name.trim().isEmpty) n.name = t.name;
    });
  }

  /// สลับไปแท็บ ER แรก แล้วเลือกตารางที่ที่เก็บข้อมูลนี้ผูกอยู่
  void gotoLinkedTable(String id) {
    final tid = diagram.nodeById(id)?.tableId;
    if (tid == null || pc.project.tableById(tid) == null) return;
    final er = pc.documents.where((t) => t.type == DocType.er).firstOrNull;
    if (er == null) return;
    pc.selectDiagram(er.id);
    pc.selectTable(tid);
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
    if (_boundary != null) {
      final id = _boundary!;
      if (diagram.boundaryById(id) == null) return 0;
      pc.dfdEdit((d) => d.boundaries.removeWhere((b) => b.id == id));
      _boundary = null;
      notifyListeners();
      return 1;
    }
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

  // ---------- ปรับขนาดด้วยการลากจุดจับ ----------

  String? _resizeId;
  DfdHandle? _resizeHandle;
  Rect? _resizeStart;
  double _resizeDx = 0, _resizeDy = 0;

  /// จุดจับที่ [world] ชี้อยู่ของวัตถุที่เลือกอยู่ตัวเดียว (null = ไม่มี) ; รัศมีเป็นพิกเซลจอ
  DfdHandle? handleAt(Offset world, {double tolPx = 8}) {
    final b = selectedBoundary;
    if (b != null) return dfdHandleAtRect(Rect.fromLTWH(b.x, b.y, b.w, b.h), world, tolPx / scale);
    final n = selectedNode;
    return n == null ? null : dfdHandleAt(n, world, tolPx / scale);
  }

  bool _resizeIsBoundary = false;

  void beginResize(DfdHandle h) {
    final b = selectedBoundary;
    final n = selectedNode;
    if (b == null && n == null) return;
    pc.dfdBeginGesture();
    _resizeIsBoundary = b != null;
    _resizeId = b?.id ?? n!.id;
    _resizeHandle = h;
    _resizeStart = b != null ? Rect.fromLTWH(b.x, b.y, b.w, b.h) : Rect.fromLTWH(n!.x, n.y, n.w, n.h);
    _resizeDx = 0;
    _resizeDy = 0;
  }

  /// ลากจุดจับแบบสด ([dx],[dy] = ระยะที่ขยับเพิ่มในพิกัดแผนภาพ) — undo ขั้นเดียวต่อการลากหนึ่งครั้ง
  void resizeBy(double dx, double dy, {double? grid}) {
    final id = _resizeId, h = _resizeHandle, r0 = _resizeStart;
    if (id == null || h == null || r0 == null) return;
    _resizeDx += dx;
    _resizeDy += dy;
    final isB = _resizeIsBoundary;
    final r = isB
        ? resizeDfdRect(r0, h, _resizeDx, _resizeDy, grid: grid, minW: 80, minH: kDfdBoundaryLabelH + 20, maxSide: 4000)
        : resizeDfdRect(r0, h, _resizeDx, _resizeDy, grid: grid);
    pc.dfdLive((d) {
      if (isB) {
        d.boundaryById(id)
          ?..x = r.left
          ..y = r.top
          ..w = r.width
          ..h = r.height;
        return;
      }
      final n = d.nodeById(id);
      if (n == null) return;
      n
        ..x = r.left
        ..y = r.top
        ..w = r.width
        ..h = r.height;
    });
  }

  void endResize() {
    _resizeId = null;
    _resizeHandle = null;
    _resizeStart = null;
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
          tableId: n.tableId,
          tableDocId: n.tableDocId,
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

  // ---------- ขอบเขตระบบ ----------

  /// ครอบวัตถุที่เลือก (เผื่อขอบและแถบชื่อ) ด้วยขอบเขตระบบใหม่ ; ไม่ได้เลือกอะไร = null
  DfdBoundary? addBoundaryAround({String? name}) {
    final sel = [for (final id in _nodes) if (diagram.nodeById(id) != null) diagram.nodeById(id)!];
    if (!active || sel.isEmpty) return null;
    final l = sel.map((n) => n.x).reduce(math.min), t = sel.map((n) => n.y).reduce(math.min);
    final r = sel.map((n) => n.right).reduce(math.max), b = sel.map((n) => n.bottom).reduce(math.max);
    return _addBoundary(l - 32, t - 32 - kDfdBoundaryLabelH, r - l + 64, b - t + 64 + kDfdBoundaryLabelH, name);
  }

  /// วางขอบเขตระบบเปล่าขนาดมาตรฐานโดยให้ศูนย์กลางอยู่ที่ ([cx],[cy])
  DfdBoundary? addBoundaryAt(double cx, double cy, {String? name, bool snap = false}) {
    if (!active) return null;
    var x = cx - 160, y = cy - 110;
    if (snap) {
      x = snapToGrid(x);
      y = snapToGrid(y);
    }
    return _addBoundary(x, y, 320, 220, name);
  }

  DfdBoundary _addBoundary(double x, double y, double w, double h, String? name) {
    late DfdBoundary b;
    pc.dfdEdit((d) {
      b = DfdBoundary(id: pc.newId('b'), name: name ?? tr('ขอบเขตระบบ'), x: x, y: y, w: w, h: h);
      d.boundaries.add(b);
    });
    _nodes.clear();
    _flow = null;
    _boundary = b.id;
    notifyListeners();
    return b;
  }

  void renameBoundary(String id, String name) {
    final b = diagram.boundaryById(id);
    if (b == null || b.name == name) return;
    pc.dfdEdit((d) => d.boundaryById(id)!.name = name);
  }

  void setBoundaryColor(String id, int? argb) {
    final b = diagram.boundaryById(id);
    if (b == null || b.color == argb) return;
    pc.dfdEdit((d) => d.boundaryById(id)!.color = argb);
  }

  Map<String, (double, double)>? _bOrigin; // วัตถุที่อยู่ในกรอบตอนเริ่มลาก
  (double, double)? _bStart;
  double _bDx = 0, _bDy = 0;

  /// เริ่มลากขอบเขตที่เลือก : วัตถุที่อยู่ในกรอบทั้งชิ้นเลื่อนตามไปด้วย
  void beginBoundaryMove() {
    final b = selectedBoundary;
    if (b == null) return;
    pc.dfdBeginGesture();
    _bStart = (b.x, b.y);
    _bOrigin = {
      for (final n in diagram.nodes)
        if (n.x >= b.x && n.y >= b.y && n.right <= b.right && n.bottom <= b.bottom) n.id: (n.x, n.y),
    };
    _bDx = 0;
    _bDy = 0;
  }

  void moveBoundaryBy(double dx, double dy, {double? grid}) {
    final id = _boundary, start = _bStart, o = _bOrigin;
    if (id == null || start == null || o == null) return;
    _bDx += dx;
    _bDy += dy;
    var sx = _bDx, sy = _bDy;
    if (grid != null) {
      sx = snapToGrid(start.$1 + _bDx, grid) - start.$1;
      sy = snapToGrid(start.$2 + _bDy, grid) - start.$2;
    }
    pc.dfdLive((d) {
      final b = d.boundaryById(id);
      if (b == null) return;
      b
        ..x = start.$1 + sx
        ..y = start.$2 + sy;
      for (final e in o.entries) {
        d.nodeById(e.key)
          ?..x = e.value.$1 + sx
          ..y = e.value.$2 + sy;
      }
    });
  }

  void endBoundaryMove() {
    _bOrigin = null;
    _bStart = null;
    pc.dfdEndGesture();
  }

  // ---------- แตกรายละเอียด Level 0 → Level 1 ----------

  /// แท็บ DFD อื่นที่ลิงก์เป็นแผนภาพย่อยของกระบวนการในแท็บ [fromTabId] ได้ (ไม่ใช่ตัวเอง และไม่ทำให้ลิงก์วนเป็นวง)
  List<ProjectDocument> childCandidates(String fromTabId) {
    final w = pc.workspace;
    return [
      for (final t in w.documents)
        if (t.type == DocType.dfd && t.id != fromTabId && !_reaches(w, t.id, fromTabId)) t,
    ];
  }

  /// จาก [from] ตามลิงก์แผนภาพย่อยไปถึง [target] ได้หรือไม่ (กันลิงก์วนเป็นวง)
  bool _reaches(Workspace w, String from, String target, [Set<String>? seen]) {
    final s = seen ?? <String>{};
    if (!s.add(from)) return false;
    final d = w.documentById(from)?.dfd;
    if (d == null) return false;
    for (final n in d.nodes) {
      final c = n.childId;
      if (c == null) continue;
      if (c == target || _reaches(w, c, target, s)) return true;
    }
    return false;
  }

  /// ตั้ง/ยกเลิก ([childTabId] null) แผนภาพย่อยของกระบวนการ [nodeId] ในแท็บที่เปิดอยู่ — คืน false ถ้าไม่อนุญาต
  bool setProcessChild(String nodeId, String? childTabId) {
    final n = diagram.nodeById(nodeId);
    if (!active || n == null || n.kind != DfdKind.process) return false;
    if (childTabId != null && !childCandidates(pc.activeDiagramId).any((t) => t.id == childTabId)) return false;
    if (n.childId == childTabId) return true;
    updateNode(nodeId, (n) => n.childId = childTabId);
    return true;
  }

  /// สร้างแผนภาพย่อยใหม่ของกระบวนการ [nodeId] : ใส่ผู้ใช้ภายนอก/ที่เก็บข้อมูลที่ต่ออยู่ + กระบวนการย่อย 1 ตัว
  /// และเส้นข้อมูลเดียวกับแม่ (เริ่มต้นสมดุลพอดี ให้ผู้ใช้แตกกระบวนการต่อเอง) แล้วลิงก์และเปิดแท็บนั้น
  ProjectDocument? createChildFor(String nodeId) {
    final parentTab = pc.activeDiagramId;
    final parent = diagram;
    final proc = parent.nodeById(nodeId);
    if (!active || proc == null || proc.kind != DfdKind.process) return null;
    final base = proc.name.trim().isEmpty ? proc.number : proc.name.trim();
    final tab = pc.addDiagram(DocType.dfd, name: 'L1 – $base');
    if (tab == null) return null;
    final dot = proc.number.indexOf('.');
    final prefix = proc.number.trim().isEmpty ? null : (dot > 0 ? proc.number.substring(0, dot) : proc.number.trim());
    pc.dfdEdit((d) {
      final map = <String, String>{}; // วัตถุแม่ -> วัตถุในแผนภาพย่อย (รวมกระบวนการแม่ -> กระบวนการย่อย)
      final sub = DfdNode(
        id: pc.newId('n'),
        kind: DfdKind.process,
        name: proc.name,
        number: prefix == null ? d.nextProcessNumber() : '$prefix.1',
        color: proc.color,
      );
      d.nodes.add(sub);
      map[proc.id] = sub.id;
      for (final f in parent.flows) {
        if (f.fromId != proc.id && f.toId != proc.id) continue;
        final otherId = f.fromId == proc.id ? f.toId : f.fromId;
        final other = parent.nodeById(otherId);
        if (other == null || other.kind == DfdKind.process) continue; // เพื่อนบ้านที่เป็นกระบวนการอื่นไม่มีตัวแทนในแผนภาพย่อย
        final copyId = map.putIfAbsent(otherId, () {
          final c = DfdNode(
            id: pc.newId('n'),
            kind: other.kind,
            name: other.name,
            number: other.kind == DfdKind.store ? other.number : '',
            color: other.color,
            tableId: other.tableId,
            tableDocId: other.tableDocId,
          );
          d.nodes.add(c);
          return c.id;
        });
        d.flows.add(DfdFlow(
          id: pc.newId('f'),
          fromId: f.fromId == proc.id ? sub.id : copyId,
          toId: f.toId == proc.id ? sub.id : copyId,
          label: f.label,
          bidirectional: f.bidirectional,
          color: f.color,
        ));
      }
    });
    autoLayout();
    pc.selectDiagram(parentTab);
    updateNode(nodeId, (n) => n.childId = tab.id);
    pc.selectDiagram(tab.id);
    return tab;
  }

  /// เปิดแท็บแผนภาพย่อยของกระบวนการ [nodeId] ; คืน false ถ้าไม่มี
  bool openChild(String nodeId) {
    final cid = diagram.nodeById(nodeId)?.childId;
    if (cid == null || pc.documentById(cid) == null) return false;
    pc.selectDiagram(cid);
    return true;
  }

  /// กระบวนการ (และแท็บของมัน) ที่ลิงก์มาที่แท็บ [tabId] เป็นแผนภาพย่อย
  List<(ProjectDocument, DfdNode)> parentsOf(String tabId) => [
        for (final t in pc.documents)
          if (t.type == DocType.dfd)
            for (final n in pc.dfdOf(t.id).nodes)
              if (n.kind == DfdKind.process && n.childId == tabId) (t, n),
      ];

  // ---------- คลิปบอร์ด (ข้ามแท็บ / ข้ามโปรเจกต์) ----------

  /// ข้อความสำหรับคลิปบอร์ด (null = ไม่มีอะไรเลือก)
  String? copySelectionText() {
    final ids = {for (final id in _nodes) if (diagram.nodeById(id) != null) id};
    if (ids.isEmpty && selectedBoundary == null) return null;
    return encodeDfdClipboard(diagram, nodeIds: ids, boundaryId: ids.isEmpty ? _boundary : null);
  }

  /// วางจากคลิปบอร์ดของโปรแกรม [offset] = ระยะเลื่อนจากตำแหน่งเดิม ; คืนจำนวนวัตถุ/ขอบเขตที่วาง (0 = ไม่ใช่ข้อมูล DFD)
  /// process/store ที่เลขซ้ำกับแผนภาพนี้ได้เลขใหม่ ; tableId ที่ไม่มีอยู่ในโปรเจกต์นี้ถูกตัดออก ; ทั้งหมด undo ขั้นเดียว
  int pasteText(String? text, {double offset = 30}) {
    final payload = decodeDfdClipboard(text);
    if (!active || payload == null) return 0;
    final map = <String, String>{};
    final created = <String>[];
    String? createdBoundary;
    pc.dfdEdit((d) {
      for (final src in payload.nodes) {
        final newId = pc.newId('n');
        map[src.id] = newId;
        final number = switch (src.kind) {
          DfdKind.process => d.nodes.any((n) => n.kind == DfdKind.process && n.number == src.number) || src.number.isEmpty
              ? d.nextProcessNumber()
              : src.number,
          DfdKind.store => d.nodes.any((n) => n.kind == DfdKind.store && n.number == src.number) || src.number.isEmpty
              ? d.nextStoreNumber()
              : src.number,
          DfdKind.entity => '',
        };
        final tid = src.tableId;
        final keep = tid != null && pc.project.tableById(tid) != null;
        d.nodes.add(DfdNode(
          id: newId,
          kind: src.kind,
          name: src.name,
          number: number,
          x: src.x + offset,
          y: src.y + offset,
          w: src.w,
          h: src.h,
          color: src.color,
          tableId: keep ? tid : null,
          tableDocId: keep ? pc.erDocumentId : null,
        ));
        created.add(newId);
      }
      for (final f in payload.flows) {
        final a = map[f.fromId], b = map[f.toId];
        if (a == null || b == null) continue;
        d.flows.add(DfdFlow(
          id: pc.newId('f'),
          fromId: a,
          toId: b,
          label: f.label,
          bidirectional: f.bidirectional,
          color: f.color,
        ));
      }
      for (final b in payload.boundaries) {
        final nb = DfdBoundary(
          id: pc.newId('b'),
          name: b.name,
          x: b.x + offset,
          y: b.y + offset,
          w: b.w,
          h: b.h,
          color: b.color,
        );
        d.boundaries.add(nb);
        createdBoundary = nb.id;
      }
    });
    _flow = null;
    _nodes
      ..clear()
      ..addAll(created);
    _boundary = created.isEmpty ? createdBoundary : null;
    notifyListeners();
    return created.length + (createdBoundary == null ? 0 : 1);
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

  /// จัดวางวัตถุอัตโนมัติเป็นชั้นตามทิศทางข้อมูล (undo ขั้นเดียว) ; คืน false ถ้าว่างหรือไม่มีอะไรขยับ
  bool autoLayout() {
    if (!active || diagram.nodes.isEmpty) return false;
    final pos = dfdAutoLayout(diagram);
    final moved = diagram.nodes.any((n) {
      final p = pos[n.id];
      return p != null && (p.x != n.x || p.y != n.y);
    });
    if (!moved) return false;
    pc.dfdEdit((d) {
      for (final n in d.nodes) {
        final p = pos[n.id];
        if (p == null) continue;
        n
          ..x = p.x
          ..y = p.y;
      }
    });
    return true;
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
