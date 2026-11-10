import '../core/clipboard/screenflow_clipboard.dart';
import '../core/l10n/l10n.dart';
import '../core/layout/diagram_geometry.dart' show snapToGrid;
import '../core/layout/screenflow_geometry.dart';
import '../core/models/screenflow_model.dart';
import '../core/models/wireframe_model.dart';
import '../core/models/workspace.dart';
import '../core/validate/screenflow_validator.dart' show sfKindLabel;
import 'box_diagram_controller.dart';
import 'workspace_controller.dart';

/// เครื่องมือของแท็บ Screen Flow: เลือก / วางโหนด ([ScreenFlowController.toolKind]) / ลากเส้นการเปลี่ยนหน้า
enum SfTool { select, node, edge }

/// controller ของเอกสาร Screen Flow หนึ่งชิ้น: เนื้อหา + ประวัติ undo/redo + สถานะหน้าจอ (เลือก/เส้น/มุมมอง)
class ScreenFlowController extends BoxDiagramController<ScreenFlowDiagram, SfNode> {
  ScreenFlowController.forDoc(super.doc, super.workspace) : assert(doc.content is ScreenFlowDiagram);

  /// ตัวแทนตอนไม่มีเอกสาร Screen Flow ที่ใช้งานอยู่ (ว่าง แก้ไขไม่ได้)
  ScreenFlowController.detached(WorkspaceController workspace)
      : super(ProjectDocument.screenflow(id: '', name: '', content: ScreenFlowDiagram()), workspace);

  ScreenFlowDiagram get diagram => content;

  @override
  Object? encodeContent(ScreenFlowDiagram c) => c.toJson();

  @override
  ScreenFlowDiagram decodeContent(Object? j) => ScreenFlowDiagram.fromJson(j);

  @override
  List<SfNode> boxesOf(ScreenFlowDiagram c) => c.nodes;

  @override
  double get minSide => kSfMinSide;

  @override
  double get maxSide => kSfMaxSide;

  // ---------- เครื่องมือ / การเลือกเส้น ----------

  SfTool _tool = SfTool.select;
  SfKind _toolKind = SfKind.screen;
  String? _edge;
  String? _linkSource;

  SfTool get tool => _tool;
  SfKind get toolKind => _toolKind;
  String? get selectedEdgeId => _edge;
  SfEdge? get selectedEdge => _edge == null ? null : diagram.edgeById(_edge!);
  String? get linkSource => _linkSource;
  SfNode? get selectedNode => selectedBox;

  void setTool(SfTool t, {SfKind? kind}) {
    if (_tool == t && (kind == null || kind == _toolKind) && _linkSource == null) return;
    _tool = t;
    if (kind != null) _toolKind = kind;
    _linkSource = null;
    notifyListeners();
  }

  void setNodeTool(SfKind k) => setTool(SfTool.node, kind: k);

  /// คีย์ลัด "เริ่ม/จบ": ยังไม่มีจุดเริ่ม = วางเริ่ม ไม่งั้นวางจบ
  void setTerminatorTool() =>
      setNodeTool(diagram.nodes.any((n) => n.kind == SfKind.start) ? SfKind.end : SfKind.start);

  @override
  bool clearOtherSelection() {
    final had = _edge != null || _linkSource != null;
    _edge = null;
    _linkSource = null;
    return had;
  }

  @override
  bool get hasOtherSelection => _edge != null;

  void selectEdge(String? id) {
    if (id != null && diagram.edgeById(id) == null) return;
    dropBoxSelection();
    _edge = id;
    notifyListeners();
  }

  @override
  void prune() {
    super.prune();
    if (_edge != null && diagram.edgeById(_edge!) == null) _edge = null;
    if (_linkSource != null && diagram.nodeById(_linkSource!) == null) _linkSource = null;
  }

  void escape() {
    if (escapeEditing()) return;
    if (_linkSource != null || _tool != SfTool.select) {
      _linkSource = null;
      _tool = SfTool.select;
      notifyListeners();
      return;
    }
    clearSelection();
  }

  // ---------- ข้อความ ----------

  @override
  bool editTargetExists(({String id, bool isEdge}) t) =>
      t.isEdge ? diagram.edgeById(t.id) != null : diagram.nodeById(t.id) != null;

  @override
  void applyEditedText(({String id, bool isEdge}) t, String text) {
    if (t.isEdge) {
      updateEdge(t.id, (e) => e.label = text.trim());
    } else {
      setTitle(t.id, text.trim());
    }
  }

  void beginEditEdge(String id) {
    if (!active || diagram.edgeById(id) == null) return;
    dropBoxSelection();
    _edge = id;
    beginEdit(id, isEdge: true);
  }

  void setTitle(String id, String title) {
    final n = diagram.nodeById(id);
    if (n == null || n.title == title) return;
    edit((d) => d.nodeById(id)!.title = title);
  }

  // ---------- โหนด ----------

  String _defaultTitle(SfKind k) => switch (k) {
        SfKind.screen => tr('หน้าจอใหม่'),
        _ => sfKindLabel(k),
      };

  /// วางโหนดใหม่ให้ศูนย์กลางอยู่ที่ ([cx],[cy]) แล้วเลือกมัน
  SfNode? addNode(SfKind kind, double cx, double cy, {bool snap = false, String? title, String? wireframeId}) {
    if (!active) return null;
    final (w, h) = sfDefaultSize(kind);
    var x = cx - w / 2, y = cy - h / 2;
    if (snap) {
      x = snapToGrid(x);
      y = snapToGrid(y);
    }
    late SfNode node;
    edit((d) {
      node = SfNode(id: workspace.newId('s'), kind: kind, title: title ?? _defaultTitle(kind), x: x, y: y, wireframeId: wireframeId);
      d.nodes.add(node);
    });
    setSelection([node.id]);
    _tool = SfTool.select;
    notifyListeners();
    return node;
  }

  void updateNodes(Iterable<String> ids, void Function(SfNode n) change) {
    final list = {for (final id in ids) if (diagram.nodeById(id) != null) id};
    if (list.isEmpty) return;
    editIfChanged((d) {
      for (final n in d.nodes) {
        if (list.contains(n.id)) change(n);
      }
    });
  }

  @override
  void removeBoxes(ScreenFlowDiagram c, Set<String> ids) {
    c.nodes.removeWhere((n) => ids.contains(n.id));
    c.edges.removeWhere((e) => ids.contains(e.fromId) || ids.contains(e.toId));
  }

  /// ลบโหนดที่เลือก (พร้อมเส้นที่ต่ออยู่) หรือเส้นที่เลือก — คืนจำนวนที่ลบ
  int deleteSelection() {
    if (_edge != null) {
      final id = _edge!;
      if (diagram.edgeById(id) == null) return 0;
      edit((d) => d.edges.removeWhere((e) => e.id == id));
      _edge = null;
      notifyListeners();
      return 1;
    }
    return deleteSelectedBoxes();
  }

  // ---------- ผูก Wireframe ----------

  /// ผูก/เลิกผูก ([wireframeId] = null) หน้าจอ [id] กับเอกสาร Wireframe
  void linkWireframe(String id, String? wireframeId) => updateNodes([id], (n) => n.wireframeId = wireframeId);

  /// สร้างเอกสาร Wireframe ใหม่ (ชื่อตามหน้าจอ) แล้วผูกกับหน้าจอ [id] — เอกสารใหม่ถูกเปิดเป็นแท็บที่ใช้งาน
  /// (การสร้างเอกสารไม่เข้าประวัติ undo ; การผูกเข้าประวัติของ Screen Flow นี้)
  ProjectDocument? createWireframeFor(String id) {
    final n = diagram.nodeById(id);
    if (!active || n == null) return null;
    final doc = workspace.addDocument(DocType.wireframe, name: n.title.trim().isEmpty ? null : n.title.trim());
    if (doc == null) return null;
    linkWireframe(id, doc.id);
    return doc;
  }

  /// เนื้อหา Wireframe ที่หน้าจอ [n] ผูกอยู่ (null = ไม่ผูก/ไม่มีแล้ว)
  WireframeDiagram? linkedWireframe(SfNode n) => n.wireframeId == null ? null : workspace.documentById(n.wireframeId!)?.wireframe;

  // ---------- ทำสำเนา / คลิปบอร์ด ----------

  int duplicateSelection() {
    final text = copySelectionText();
    return text == null ? 0 : pasteText(text, offset: 30);
  }

  String? copySelectionText() {
    final ids = {for (final n in selectedBoxes) n.id};
    return ids.isEmpty ? null : encodeScreenFlowClipboard(diagram, ids);
  }

  /// วางจากคลิปบอร์ด ; คืนจำนวนโหนดที่วาง (0 = ไม่ใช่ข้อมูล Screen Flow) ; id ใหม่ทั้งหมด ; ลิงก์ Wireframe คงเดิม
  int pasteText(String? text, {double offset = 30}) {
    final src = decodeScreenFlowClipboard(text);
    if (!active || src == null) return 0;
    final map = <String, String>{};
    edit((d) {
      for (final n in src.nodes) {
        final id = workspace.newId('s');
        map[n.id] = id;
        d.nodes.add(SfNode.tryFromJson({...n.toJson(), 'id': id, 'x': n.x + offset, 'y': n.y + offset})!);
      }
      for (final e in src.edges) {
        final a = map[e.fromId], b = map[e.toId];
        if (a == null || b == null) continue;
        d.edges.add(SfEdge.tryFromJson({...e.toJson(), 'id': workspace.newId('n'), 'from': a, 'to': b})!);
      }
    });
    setSelection(map.values);
    return map.length;
  }

  // ---------- เส้น ----------

  /// กดโหนดด้วยเครื่องมือเส้น: ครั้งแรก = ต้นทาง ครั้งที่สอง = ปลายทาง (สร้างเส้น)
  SfEdge? linkClick(String nodeId) {
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

  SfEdge? addEdge(String fromId, String toId, {String label = '', String condition = ''}) {
    if (!active || diagram.nodeById(fromId) == null || diagram.nodeById(toId) == null) return null;
    late SfEdge e;
    edit((d) {
      e = SfEdge(id: workspace.newId('n'), fromId: fromId, toId: toId, label: label, condition: condition);
      d.edges.add(e);
    });
    dropBoxSelection();
    _edge = e.id;
    notifyListeners();
    return e;
  }

  void updateEdge(String id, void Function(SfEdge e) change) {
    if (diagram.edgeById(id) == null) return;
    editIfChanged((d) {
      final e = d.edgeById(id);
      if (e != null) change(e);
    });
  }

  void reverseEdge(String id) => updateEdge(id, (e) {
        final t = e.fromId;
        e.fromId = e.toId;
        e.toId = t;
      });

  // ---------- จัดวางอัตโนมัติ / มุมมอง ----------

  /// จัดวางอัตโนมัติซ้ายไปขวา (undo ขั้นเดียว) ; คืน false ถ้าว่างหรือไม่มีอะไรขยับ
  bool autoLayout() {
    if (!active || diagram.nodes.isEmpty) return false;
    final pos = sfAutoLayout(diagram);
    return editIfChanged((d) {
      for (final n in d.nodes) {
        final p = pos[n.id];
        if (p == null) continue;
        n
          ..x = p.x
          ..y = p.y;
      }
    });
  }

  @override
  ({double left, double top, double right, double bottom})? contentBounds({Set<String>? only}) =>
      sfBounds(diagram, pad: 60, only: only);
}
