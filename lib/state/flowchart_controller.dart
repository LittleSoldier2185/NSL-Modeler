import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/clipboard/flowchart_clipboard.dart';
import '../core/l10n/l10n.dart';
import '../core/layout/dfd_resize.dart' show DfdHandle, dfdHandleAtRect, resizeDfdRect;
import '../core/layout/diagram_geometry.dart' show snapToGrid, kGridSize;
import '../core/layout/flowchart_geometry.dart';
import '../core/layout/flowchart_layout.dart';
import '../core/models/flowchart_model.dart';
import '../core/models/workspace.dart';
import '../core/validate/flowchart_validator.dart' show fcShapeLabel;
import 'diagram_viewport.dart';
import 'doc_controller.dart';
import 'workspace_controller.dart';

/// เครื่องมือของแท็บ Flowchart: เลือก / วางสัญลักษณ์ ([FlowchartController.toolShape]) / ลากเส้นเชื่อม
enum FcTool { select, shape, edge }

/// วิธีจัดแนวสัญลักษณ์ที่เลือก
enum FcAlignKind { left, centerH, right, top, middle, bottom }

/// controller ของเอกสาร Flowchart หนึ่งชิ้น: เนื้อหา + ประวัติ undo/redo ของเอกสารนี้ และสถานะหน้าจอ
/// (เครื่องมือ การเลือก ข้อความที่กำลังแก้ มุมมอง) — สถานะหน้าจอแยกต่อแท็บ ไม่ถูกบันทึกในไฟล์
class FlowchartController extends DocController with DiagramViewport {
  FlowchartController.forDoc(super.doc, this.workspace) : assert(doc.content is FlowchartDiagram);

  /// ตัวแทนตอนไม่มีเอกสาร Flowchart ที่ใช้งานอยู่: แผนภาพว่างที่ไม่อยู่ในโปรเจกต์ แก้ไขไม่ได้
  FlowchartController.detached(this.workspace)
      : super(ProjectDocument.flowchart(id: '', name: '', content: FlowchartDiagram()));

  final WorkspaceController workspace;

  /// เอกสารนี้ยังอยู่ในโปรเจกต์ (ตัวแทน/เอกสารที่ถูกลบ = false แก้ไขไม่ได้)
  bool get active => !disposed && identical(workspace.documentById(docId), doc);

  FlowchartDiagram get diagram => doc.flowchart!;

  @override
  @protected
  String snapshot() => jsonEncode(diagram.toJson());

  @override
  @protected
  void restoreSnapshot(String snap) => doc.content = FlowchartDiagram.fromJson(jsonDecode(snap));

  @override
  @protected
  void afterRestore() => _prune();

  void _edit(void Function(FlowchartDiagram d) change) {
    if (!active) return;
    editWithHistory(() => change(diagram));
  }

  void _live(void Function(FlowchartDiagram d) change) {
    if (!active) return;
    change(diagram);
    markLive();
    notifyListeners();
  }

  @override
  void beginGesture() {
    if (!active) return;
    super.beginGesture();
  }

  // ---------- เครื่องมือ / การเลือก ----------

  FcTool _tool = FcTool.select;
  FcShape _toolShape = FcShape.process;
  FcTool get tool => _tool;

  /// รูปทรงที่จะวางเมื่อ [tool] = [FcTool.shape]
  FcShape get toolShape => _toolShape;

  final Set<String> _nodes = {};
  String? _edge;
  String? _linkSource;

  Set<String> get selectedNodeIds => Set.unmodifiable(_nodes);
  String? get selectedEdgeId => _edge;
  String? get linkSource => _linkSource;
  FcNode? get selectedNode => _nodes.length == 1 ? diagram.nodeById(_nodes.first) : null;
  FcEdge? get selectedEdge => _edge == null ? null : diagram.edgeById(_edge!);
  List<FcNode> get selectedNodes => [for (final n in diagram.nodes) if (_nodes.contains(n.id)) n];

  void setTool(FcTool t, {FcShape? shape}) {
    if (_tool == t && (shape == null || shape == _toolShape) && _linkSource == null) return;
    _tool = t;
    if (shape != null) _toolShape = shape;
    _linkSource = null;
    notifyListeners();
  }

  /// เครื่องมือวางสัญลักษณ์ [s]
  void setShapeTool(FcShape s) => setTool(FcTool.shape, shape: s);

  /// คีย์ลัด "Start/End": ยังไม่มีจุดเริ่มต้น = วางเริ่มต้น ไม่งั้นวางสิ้นสุด
  void setTerminatorTool() =>
      setShapeTool(diagram.nodes.any((n) => n.shape == FcShape.start) ? FcShape.end : FcShape.start);

  void clearSelection() {
    if (_nodes.isEmpty && _edge == null && _linkSource == null) return;
    _nodes.clear();
    _edge = null;
    _linkSource = null;
    notifyListeners();
  }

  void selectNode(String id, {bool add = false}) {
    if (diagram.nodeById(id) == null) return;
    _edge = null;
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
    if (next.length == _nodes.length && next.containsAll(_nodes) && _edge == null) return;
    _edge = null;
    _nodes
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectEdge(String? id) {
    if (id != null && diagram.edgeById(id) == null) return;
    _nodes.clear();
    _edge = id;
    notifyListeners();
  }

  void selectAll() {
    _edge = null;
    _nodes
      ..clear()
      ..addAll(diagram.nodes.map((n) => n.id));
    notifyListeners();
  }

  /// Esc: ยกเลิกการต่อเส้น/เครื่องมือก่อน แล้วค่อยล้างการเลือก
  void escape() {
    if (_editing != null) {
      cancelEditing();
    } else if (_linkSource != null || _tool != FcTool.select) {
      _linkSource = null;
      _tool = FcTool.select;
      notifyListeners();
    } else {
      clearSelection();
    }
  }

  void _prune() {
    final d = diagram;
    _nodes.removeWhere((id) => d.nodeById(id) == null);
    if (_edge != null && d.edgeById(_edge!) == null) _edge = null;
    if (_linkSource != null && d.nodeById(_linkSource!) == null) _linkSource = null;
    final e = _editing;
    if (e != null && (e.isEdge ? d.edgeById(e.id) == null : d.nodeById(e.id) == null)) _editing = null;
  }

  // ---------- แก้ข้อความบนแคนวาส ----------

  ({String id, bool isEdge})? _editing;

  /// สัญลักษณ์/เส้นที่กำลังพิมพ์ข้อความบนแคนวาส (null = ไม่ได้แก้)
  ({String id, bool isEdge})? get editing => _editing;

  void beginEditNode(String id) {
    final n = diagram.nodeById(id);
    if (!active || n == null) return;
    _edge = null;
    _nodes
      ..clear()
      ..add(id);
    _editing = (id: id, isEdge: false);
    notifyListeners();
  }

  void beginEditEdge(String id) {
    if (!active || diagram.edgeById(id) == null) return;
    _nodes.clear();
    _edge = id;
    _editing = (id: id, isEdge: true);
    notifyListeners();
  }

  /// จบการพิมพ์และบันทึกข้อความ (undo ขั้นเดียว ; ไม่เปลี่ยน = ไม่เข้าประวัติ)
  void commitEditing(String text) {
    final e = _editing;
    _editing = null;
    if (e == null) return;
    if (e.isEdge) {
      setEdgeLabel(e.id, text.trim());
    } else {
      setText(e.id, text);
    }
    notifyListeners();
  }

  void cancelEditing() {
    if (_editing == null) return;
    _editing = null;
    notifyListeners();
  }

  // ---------- สัญลักษณ์ ----------

  String _defaultText(FcShape s) => switch (s) {
        FcShape.connector => '',
        FcShape.decision => tr('เงื่อนไข?'),
        FcShape.io => tr('ข้อมูล'),
        _ => fcShapeLabel(s),
      };

  /// วางสัญลักษณ์ใหม่โดยให้ศูนย์กลางอยู่ที่ ([cx],[cy]) แล้วเลือกมัน
  FcNode? addNode(FcShape shape, double cx, double cy, {bool snap = false, String? text}) {
    if (!active) return null;
    final (w, h) = fcDefaultSize(shape);
    var x = cx - w / 2, y = cy - h / 2;
    if (snap) {
      x = snapToGrid(x);
      y = snapToGrid(y);
    }
    late FcNode node;
    _edit((d) {
      node = FcNode(id: workspace.newId('c'), shape: shape, text: text ?? _defaultText(shape), x: x, y: y);
      d.nodes.add(node);
    });
    _edge = null;
    _nodes
      ..clear()
      ..add(node.id);
    _tool = FcTool.select;
    notifyListeners();
    return node;
  }

  void updateNode(String id, void Function(FcNode n) change) {
    if (diagram.nodeById(id) == null) return;
    _edit((d) => change(d.nodeById(id)!));
  }

  void setText(String id, String text) {
    final n = diagram.nodeById(id);
    if (n == null || n.text == text) return;
    updateNode(id, (n) => n.text = text);
  }

  /// เปลี่ยนรูปทรงของสัญลักษณ์ที่เลือก (คงตำแหน่ง/ขนาด/ข้อความ)
  void setShape(Iterable<String> ids, FcShape shape) => setNodesStyle(ids, (n) => n.shape = shape);

  /// แก้รูปแบบของสัญลักษณ์หลายอันพร้อมกัน — undo ขั้นเดียว ; ไม่มีอะไรเปลี่ยน = ไม่เข้าประวัติ
  void setNodesStyle(Iterable<String> ids, void Function(FcNode n) change) {
    final list = [for (final id in ids) if (diagram.nodeById(id) != null) id];
    if (list.isEmpty) return;
    _editIfChanged((d) {
      for (final id in list) {
        change(d.nodeById(id)!);
      }
    });
  }

  /// ลบสัญลักษณ์ที่เลือก (พร้อมเส้นที่ต่ออยู่) หรือเส้นที่เลือก — คืนจำนวนที่ลบ
  int deleteSelection() {
    if (_edge != null) {
      final id = _edge!;
      if (diagram.edgeById(id) == null) return 0;
      _edit((d) => d.edges.removeWhere((e) => e.id == id));
      _edge = null;
      notifyListeners();
      return 1;
    }
    final ids = _nodes.where((id) => diagram.nodeById(id) != null).toSet();
    if (ids.isEmpty) return 0;
    _edit((d) {
      d.nodes.removeWhere((n) => ids.contains(n.id));
      d.edges.removeWhere((e) => ids.contains(e.fromId) || ids.contains(e.toId));
    });
    _nodes.clear();
    notifyListeners();
    return ids.length;
  }

  // ---------- ย้าย / ขยับ ----------

  Map<String, (double, double)>? _origin;
  double _rawDx = 0, _rawDy = 0;

  void beginMove() {
    beginGesture();
    _origin = {for (final n in selectedNodes) n.id: (n.x, n.y)};
    _rawDx = 0;
    _rawDy = 0;
  }

  /// ย้ายสัญลักษณ์ที่เลือกแบบสด ([grid] != null = ปัดเข้าช่อง โดยทุกชิ้นเลื่อนเท่ากัน)
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
    _live((d) {
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
    endGesture();
  }

  /// ขยับสัญลักษณ์ที่เลือกด้วยปุ่มลูกศร (undo ต่อการกด)
  bool nudge(double dx, double dy) {
    final ids = [for (final n in selectedNodes) n.id];
    if (ids.isEmpty) return false;
    _edit((d) {
      for (final id in ids) {
        final n = d.nodeById(id)!;
        n.x += dx;
        n.y += dy;
      }
    });
    return true;
  }

  // ---------- ปรับขนาด ----------

  String? _resizeId;
  DfdHandle? _resizeHandle;
  Rect? _resizeStart;
  double _resizeDx = 0, _resizeDy = 0;

  /// จุดจับของสัญลักษณ์ที่เลือกอยู่ตัวเดียวที่ [world] ชี้อยู่ ; รัศมีเป็นพิกเซลจอ
  DfdHandle? handleAt(Offset world, {double tolPx = 8}) {
    final n = selectedNode;
    return n == null ? null : dfdHandleAtRect(Rect.fromLTWH(n.x, n.y, n.w, n.h), world, tolPx / scale);
  }

  void beginResize(DfdHandle h) {
    final n = selectedNode;
    if (n == null) return;
    beginGesture();
    _resizeId = n.id;
    _resizeHandle = h;
    _resizeStart = Rect.fromLTWH(n.x, n.y, n.w, n.h);
    _resizeDx = 0;
    _resizeDy = 0;
  }

  void resizeBy(double dx, double dy, {double? grid}) {
    final id = _resizeId, h = _resizeHandle, r0 = _resizeStart;
    if (id == null || h == null || r0 == null) return;
    _resizeDx += dx;
    _resizeDy += dy;
    final r = resizeDfdRect(r0, h, _resizeDx, _resizeDy, grid: grid, minW: kFcMinSide, minH: kFcMinSide, maxSide: kFcMaxSide);
    _live((d) {
      d.nodeById(id)
        ?..x = r.left
        ..y = r.top
        ..w = r.width
        ..h = r.height;
    });
  }

  void endResize() {
    _resizeId = null;
    _resizeHandle = null;
    _resizeStart = null;
    endGesture();
  }

  // ---------- จัดแนว / กระจาย / ขนาดเท่ากัน / ลำดับการซ้อน ----------

  /// จัดแนวสัญลักษณ์ที่เลือก (อย่างน้อย 2 อัน) ตามขอบ/กึ่งกลางของกรอบที่ครอบทั้งหมด — คืน false ถ้าไม่ได้ทำ
  bool align(FcAlignKind k) {
    final sel = selectedNodes;
    if (sel.length < 2) return false;
    final l = sel.map((n) => n.x).reduce(math.min), r = sel.map((n) => n.right).reduce(math.max);
    final t = sel.map((n) => n.y).reduce(math.min), b = sel.map((n) => n.bottom).reduce(math.max);
    _editIfChanged((d) {
      for (final s in sel) {
        final n = d.nodeById(s.id)!;
        switch (k) {
          case FcAlignKind.left:
            n.x = l;
          case FcAlignKind.centerH:
            n.x = (l + r) / 2 - n.w / 2;
          case FcAlignKind.right:
            n.x = r - n.w;
          case FcAlignKind.top:
            n.y = t;
          case FcAlignKind.middle:
            n.y = (t + b) / 2 - n.h / 2;
          case FcAlignKind.bottom:
            n.y = b - n.h;
        }
      }
    });
    return true;
  }

  /// กระจายสัญลักษณ์ที่เลือก (อย่างน้อย 3 อัน) ให้ช่องว่างระหว่างกันเท่ากัน ([horizontal] = แนวนอน)
  bool distribute({required bool horizontal}) {
    final sel = selectedNodes;
    if (sel.length < 3) return false;
    sel.sort((a, b) => horizontal ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    final first = sel.first, last = sel.last;
    final span = horizontal ? last.right - first.x : last.bottom - first.y;
    final total = sel.fold<double>(0, (s, n) => s + (horizontal ? n.w : n.h));
    final gap = (span - total) / (sel.length - 1);
    _editIfChanged((d) {
      var p = horizontal ? first.x : first.y;
      for (final s in sel) {
        final n = d.nodeById(s.id)!;
        if (horizontal) {
          n.x = p;
          p += n.w + gap;
        } else {
          n.y = p;
          p += n.h + gap;
        }
      }
    });
    return true;
  }

  /// ให้สัญลักษณ์ที่เลือกมีความกว้าง/สูงเท่ากับอันแรกที่เลือก (ตามลำดับการเลือก)
  bool sameSize({bool width = true, bool height = true}) {
    if (_nodes.length < 2) return false;
    final ref = diagram.nodeById(_nodes.first);
    if (ref == null) return false;
    setNodesStyle(_nodes, (n) {
      if (width) n.w = ref.w;
      if (height) n.h = ref.h;
    });
    return true;
  }

  /// ยกสัญลักษณ์ที่เลือกขึ้นบนสุด ([front]) หรือลงล่างสุด
  bool reorder({required bool front}) {
    final sel = selectedNodes;
    if (sel.isEmpty) return false;
    final ids = {for (final n in sel) n.id};
    _editIfChanged((d) {
      final moving = [for (final n in d.nodes) if (ids.contains(n.id)) n];
      d.nodes.removeWhere((n) => ids.contains(n.id));
      if (front) {
        d.nodes.addAll(moving);
      } else {
        d.nodes.insertAll(0, moving);
      }
    });
    return true;
  }

  /// แก้แบบมีประวัติเฉพาะเมื่อเนื้อหาเปลี่ยนจริง (ลองกับสำเนาก่อน — ไม่ให้มี Ctrl+Z ว่าง ๆ) ; คืน true ถ้าเปลี่ยน
  bool _editIfChanged(void Function(FlowchartDiagram d) change) {
    if (!active) return false;
    final before = snapshot();
    final probe = FlowchartDiagram.fromJson(jsonDecode(before));
    change(probe);
    if (jsonEncode(probe.toJson()) == before) return false;
    _edit(change);
    return true;
  }

  // ---------- ทำสำเนา / คลิปบอร์ด ----------

  /// ทำสำเนาสัญลักษณ์ที่เลือก (พร้อมเส้นระหว่างกันเอง) เลื่อนไป 30 px แล้วเลือกสำเนา
  int duplicateSelection() {
    final ids = {for (final n in selectedNodes) n.id};
    if (ids.isEmpty) return 0;
    return pasteText(encodeFlowchartClipboard(diagram, ids));
  }

  /// ข้อความสำหรับคลิปบอร์ด (null = ไม่มีอะไรเลือก)
  String? copySelectionText() {
    final ids = {for (final n in selectedNodes) n.id};
    return ids.isEmpty ? null : encodeFlowchartClipboard(diagram, ids);
  }

  /// วางจากคลิปบอร์ดของโปรแกรม (ข้ามแท็บ/ข้ามโปรเจกต์ได้) ; [offset] = ระยะเลื่อนจากตำแหน่งเดิม
  /// คืนจำนวนสัญลักษณ์ที่วาง (0 = ไม่ใช่ข้อมูล Flowchart) ; undo ขั้นเดียว ; id ใหม่ทั้งหมด
  int pasteText(String? text, {double offset = 30}) {
    final src = decodeFlowchartClipboard(text);
    if (!active || src == null) return 0;
    final map = <String, String>{};
    _edit((d) {
      for (final n in src.nodes) {
        final copy = FcNode.tryFromJson(n.toJson())!;
        final id = workspace.newId('c');
        map[n.id] = id;
        d.nodes.add(FcNode.tryFromJson({...copy.toJson(), 'id': id, 'x': n.x + offset, 'y': n.y + offset})!);
      }
      for (final e in src.edges) {
        final a = map[e.fromId], b = map[e.toId];
        if (a == null || b == null) continue;
        d.edges.add(FcEdge.tryFromJson({...e.toJson(), 'id': workspace.newId('k'), 'from': a, 'to': b})!);
      }
    });
    _edge = null;
    _nodes
      ..clear()
      ..addAll(map.values);
    notifyListeners();
    return map.length;
  }

  // ---------- เส้นเชื่อม ----------

  /// กดสัญลักษณ์ด้วยเครื่องมือเส้น: ครั้งแรก = ต้นทาง ครั้งที่สอง = ปลายทาง (สร้างเส้น) — คืนเส้นที่สร้าง
  FcEdge? linkClick(String nodeId) {
    if (diagram.nodeById(nodeId) == null) return null;
    final from = _linkSource;
    if (from == null) {
      _linkSource = nodeId;
      notifyListeners();
      return null;
    }
    final e = addEdge(from, nodeId);
    _linkSource = null;
    notifyListeners();
    return e;
  }

  /// สร้างเส้นจาก [fromId] ไป [toId] แล้วเลือกเส้นนั้น (วนเข้าตัวเองได้ แต่ตัวตรวจจะเตือน)
  FcEdge? addEdge(String fromId, String toId, {String label = ''}) {
    if (!active || diagram.nodeById(fromId) == null || diagram.nodeById(toId) == null) return null;
    late FcEdge e;
    _edit((d) {
      e = FcEdge(id: workspace.newId('k'), fromId: fromId, toId: toId, label: label);
      d.edges.add(e);
    });
    _nodes.clear();
    _edge = e.id;
    notifyListeners();
    return e;
  }

  void updateEdge(String id, void Function(FcEdge e) change) {
    final e = diagram.edgeById(id);
    if (e == null) return;
    final before = jsonEncode(e.toJson());
    final probe = FcEdge.tryFromJson(e.toJson())!;
    change(probe);
    if (jsonEncode(probe.toJson()) == before) return;
    _edit((d) => change(d.edgeById(id)!));
  }

  void setEdgeLabel(String id, String label) => updateEdge(id, (e) => e.label = label);

  void reverseEdge(String id) => updateEdge(id, (e) {
        final t = e.fromId;
        e.fromId = e.toId;
        e.toId = t;
      });

  // ---------- จัดวางอัตโนมัติ / มุมมอง ----------

  /// จัดวางอัตโนมัติ (undo ขั้นเดียว) ; คืน false ถ้าว่างหรือไม่มีอะไรขยับ
  bool autoLayout({FcLayoutKind kind = FcLayoutKind.topDown}) {
    if (!active || diagram.nodes.isEmpty) return false;
    final pos = fcAutoLayout(diagram, kind: kind);
    final moved = diagram.nodes.any((n) {
      final p = pos[n.id];
      return p != null && (p.x != n.x || p.y != n.y);
    });
    if (!moved) return false;
    _edit((d) {
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

  /// ปรับให้เห็นทั้งแผนภาพ (ซูมไม่เกิน 1.2 เท่า) ; ว่าง = กลับมุมมองเริ่มต้น
  void fit(Size viewport) => fitRect(fcBounds(diagram, pad: 60), viewport);

  /// ปรับให้เห็นเฉพาะที่เลือก (ไม่ได้เลือก = ทั้งแผนภาพ)
  void fitSelection(Size viewport) {
    final ids = {for (final n in selectedNodes) n.id};
    if (ids.isEmpty) return fit(viewport);
    fitRect(fcBounds(diagram, pad: 60, only: ids), viewport, maxZoom: 2);
  }

  /// เลื่อนมุมมองให้สัญลักษณ์ [id] อยู่กลางจอ
  void reveal(String id, Size viewport) {
    final n = diagram.nodeById(id);
    if (n == null) return;
    revealPoint(Offset(n.cx, n.cy), viewport);
  }

  static const grid = kGridSize;
}
