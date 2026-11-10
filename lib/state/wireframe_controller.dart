import '../core/clipboard/wireframe_clipboard.dart';
import '../core/l10n/l10n.dart';
import '../core/layout/box_ops.dart';
import '../core/layout/diagram_geometry.dart' show snapToGrid;
import '../core/models/wireframe_model.dart';
import '../core/models/workspace.dart';
import 'box_diagram_controller.dart';
import 'workspace_controller.dart';

/// เครื่องมือของแท็บ Wireframe: เลือก / วางชิ้นส่วน ([WireframeController.toolKind])
enum WfTool { select, place }

/// controller ของเอกสาร Wireframe หนึ่งชิ้น (หน้าจอหนึ่งหน้า): เนื้อหา + ประวัติ undo/redo + สถานะหน้าจอ
/// การเปลี่ยนรูปแบบการแสดงผล/สีเน้น/ขนาดหน้าจอเข้าประวัติ undo เหมือนการแก้อื่น
class WireframeController extends BoxDiagramController<WireframeDiagram, WfComponent> {
  WireframeController.forDoc(super.doc, super.workspace) : assert(doc.content is WireframeDiagram);

  /// ตัวแทนตอนไม่มีเอกสาร Wireframe ที่ใช้งานอยู่: หน้าจอว่างที่ไม่อยู่ในโปรเจกต์ แก้ไขไม่ได้
  WireframeController.detached(WorkspaceController workspace)
      : super(ProjectDocument.wireframe(id: '', name: '', content: WireframeDiagram()), workspace);

  WireframeDiagram get diagram => content;

  @override
  Object? encodeContent(WireframeDiagram c) => c.toJson();

  @override
  WireframeDiagram decodeContent(Object? j) => WireframeDiagram.fromJson(j);

  @override
  List<WfComponent> boxesOf(WireframeDiagram c) => c.components;

  @override
  double get minSide => kWfMinSide;

  @override
  double get maxSide => kWfMaxSide;

  // ---------- เครื่องมือ ----------

  WfTool _tool = WfTool.select;
  WfKind _toolKind = WfKind.button;
  WfTool get tool => _tool;
  WfKind get toolKind => _toolKind;

  void setTool(WfTool t, {WfKind? kind}) {
    if (_tool == t && (kind == null || kind == _toolKind)) return;
    _tool = t;
    if (kind != null) _toolKind = kind;
    notifyListeners();
  }

  /// เครื่องมือวางชิ้นส่วน [k]
  void setPlaceTool(WfKind k) => setTool(WfTool.place, kind: k);

  /// Esc: ยกเลิกการพิมพ์ -> ยกเลิกเครื่องมือ -> ล้างการเลือก
  void escape() {
    if (escapeEditing()) return;
    if (_tool != WfTool.select) {
      _tool = WfTool.select;
      notifyListeners();
      return;
    }
    clearSelection();
  }

  // ---------- ลูกในภาชนะ ----------

  @override
  Set<String> moveSet(Set<String> ids) => {...ids, ...wfDescendants(diagram, ids)};

  // ---------- ข้อความ ----------

  /// ข้อความที่แก้บนแคนวาส: ตาราง = หัวคอลัมน์บรรทัดละคอลัมน์ ; อื่น ๆ = ข้อความของชิ้น
  String inlineText(WfComponent c) => c.kind == WfKind.table ? c.columns.join('\n') : c.text;

  @override
  void applyEditedText(({String id, bool isEdge}) t, String text) {
    final c = diagram.componentById(t.id);
    if (c == null) return;
    if (c.kind == WfKind.table) {
      setColumns(t.id, [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()]);
    } else {
      setText(t.id, text);
    }
  }

  /// หัวคอลัมน์ของตาราง (undo ขั้นเดียว)
  void setColumns(String id, List<String> columns) => updateComponents([id], (c) {
        c.columns
          ..clear()
          ..addAll(columns.take(30));
      });

  void setText(String id, String text) {
    final c = diagram.componentById(id);
    if (c == null || c.text == text) return;
    edit((d) => d.componentById(id)!.text = text);
  }

  /// ข้อความเริ่มต้นของชิ้นใหม่
  static String defaultText(WfKind k) => switch (k) {
        WfKind.heading => tr('หัวข้อหน้า'),
        WfKind.label => tr('ป้ายข้อความ'),
        WfKind.paragraph => tr('ข้อความย่อหน้าตัวอย่าง อธิบายเนื้อหาของส่วนนี้'),
        WfKind.button => tr('ปุ่ม'),
        WfKind.input => tr('กรอกข้อความ'),
        WfKind.textarea => tr('กรอกรายละเอียด'),
        WfKind.checkbox => tr('จดจำฉันไว้'),
        WfKind.radio => tr('ตัวเลือก'),
        WfKind.toggle => tr('เปิดใช้งาน'),
        WfKind.select => tr('เลือก…'),
        WfKind.search => tr('ค้นหา…'),
        WfKind.card => tr('ชื่อการ์ด'),
        WfKind.tabs => tr('แท็บ 1\nแท็บ 2\nแท็บ 3'),
        WfKind.navbar => tr('ชื่อแอป'),
        WfKind.sidebar => tr('เมนู 1\nเมนู 2\nเมนู 3'),
        WfKind.modal => tr('หัวข้อหน้าต่าง'),
        WfKind.badge => tr('ใหม่'),
        WfKind.breadcrumb => tr('หน้าแรก\nหมวดหมู่\nหน้านี้'),
        WfKind.list => tr('รายการที่ 1\nรายการที่ 2\nรายการที่ 3'),
        _ => '',
      };

  // ---------- ชิ้นส่วน ----------

  /// วางชิ้นส่วนใหม่ให้ศูนย์กลางอยู่ที่ ([cx],[cy]) แล้วเลือกมัน
  WfComponent? addComponent(WfKind kind, double cx, double cy, {bool snap = false, String? text}) {
    if (!active) return null;
    var (w, h) = wfDefaultSize(kind);
    // แถบนำทางบน: กว้างเต็มหน้าจอ
    if (kind == WfKind.navbar) w = diagram.width;
    var x = cx - w / 2, y = cy - h / 2;
    if (kind == WfKind.navbar) x = 0;
    if (snap) {
      x = snapToGrid(x);
      y = snapToGrid(y);
    }
    late WfComponent c;
    edit((d) {
      c = WfComponent(
        id: workspace.newId('w'),
        kind: kind,
        text: text ?? defaultText(kind),
        x: x,
        y: y,
        w: w,
        h: h,
        columns: kind == WfKind.table ? [tr('ชื่อ'), tr('สถานะ'), tr('วันที่')] : null,
        align: kind == WfKind.button || kind == WfKind.badge ? WfAlign.center : WfAlign.left,
      );
      d.components.add(c);
    });
    clearOtherSelection();
    dropBoxSelection();
    setSelection([c.id]);
    _tool = WfTool.select;
    notifyListeners();
    return c;
  }

  /// แก้ชิ้นส่วนหลายชิ้นพร้อมกัน — undo ขั้นเดียว ; ไม่มีอะไรเปลี่ยน = ไม่เข้าประวัติ
  void updateComponents(Iterable<String> ids, void Function(WfComponent c) change) {
    final list = {for (final id in ids) if (diagram.componentById(id) != null) id};
    if (list.isEmpty) return;
    editIfChanged((d) {
      for (final c in d.components) {
        if (list.contains(c.id)) change(c);
      }
    });
  }

  @override
  void removeBoxes(WireframeDiagram c, Set<String> ids) => c.components.removeWhere((x) => ids.contains(x.id));

  /// ลบชิ้นที่เลือก (ลูกในภาชนะไม่ถูกลบ — ยังอยู่ที่เดิม)
  int deleteSelection() => deleteSelectedBoxes();

  // ---------- หน้าจอ / รูปแบบ ----------

  /// เปลี่ยนรูปแบบการแสดงผล (มีผลเฉพาะการวาด) — undo ได้
  void setStyle(WfStyle s) => editIfChanged((d) => d.style = s);

  /// สีเน้นของเอกสาร — undo ได้
  void setAccent(int argb) => editIfChanged((d) => d.accent = argb | 0xFF000000);

  /// เลือกขนาดหน้าจอสำเร็จรูป (custom = คงขนาดเดิมแต่ปลดล็อกให้กำหนดเอง)
  void setDevice(WfDevice dev) => editIfChanged((d) {
        d.device = dev;
        if (dev != WfDevice.custom) {
          d.width = dev.width;
          d.height = dev.height;
        }
      });

  /// กำหนดขนาดหน้าจอเอง (เปลี่ยนเป็นแบบกำหนดเอง) — ค่าถูกจำกัดในช่วงที่รองรับ
  void setFrameSize(double w, double h) => editIfChanged((d) {
        final nw = w.clamp(WireframeDiagram.minFrame, WireframeDiagram.maxFrame).toDouble();
        final nh = h.clamp(WireframeDiagram.minFrame, WireframeDiagram.maxFrame).toDouble();
        if (nw == d.width && nh == d.height) return;
        d.width = nw;
        d.height = nh;
        d.device = WfDevice.values.firstWhere((x) => x != WfDevice.custom && x.width == nw && x.height == nh,
            orElse: () => WfDevice.custom);
      });

  // ---------- ผูกข้อมูล ER ----------

  /// ผูก/เลิกผูก ([ref] = null) ชิ้น [id] กับตาราง/คอลัมน์ใน ER
  void setRef(String id, WfDataRef? ref) => updateComponents([id], (c) => c.ref = ref);

  /// เปิดเอกสาร ER ที่ชิ้น [id] ผูกไว้แล้วเลือกตาราง (และคอลัมน์) — คืน false ถ้าไม่ได้ผูก/หาไม่พบ
  bool gotoBoundTable(String id) {
    final r = diagram.componentById(id)?.ref;
    if (r == null) return false;
    final er = workspace.erController(r.docId);
    if (er == null || er.project.tableById(r.tableId) == null) return false;
    workspace.openDocument(er.docId);
    er.selectTable(r.tableId, columnId: r.columnId);
    return true;
  }

  // ---------- ทำสำเนา / คลิปบอร์ด ----------

  /// ทำสำเนาชิ้นที่เลือก (พร้อมลูกในภาชนะ) เลื่อนไป 20 px แล้วเลือกสำเนา
  int duplicateSelection() {
    final text = copySelectionText();
    return text == null ? 0 : pasteText(text, offset: 20);
  }

  /// ข้อความสำหรับคลิปบอร์ด (null = ไม่มีอะไรเลือก) — ลูกในภาชนะติดไปด้วย
  String? copySelectionText() {
    final ids = moveSet({for (final c in selectedBoxes) c.id});
    return ids.isEmpty ? null : encodeWireframeClipboard(diagram, ids);
  }

  /// วางจากคลิปบอร์ดของโปรแกรม (ข้ามแท็บ/โปรเจกต์ได้) ; คืนจำนวนชิ้นที่วาง (0 = ไม่ใช่ข้อมูล Wireframe) ; id ใหม่ทั้งหมด
  int pasteText(String? text, {double offset = 20}) {
    final src = decodeWireframeClipboard(text);
    if (!active || src == null) return 0;
    final ids = <String>[];
    edit((d) {
      for (final c in src) {
        final id = workspace.newId('w');
        ids.add(id);
        d.components.add(WfComponent.tryFromJson({...c.toJson(), 'id': id, 'x': c.x + offset, 'y': c.y + offset})!);
      }
    });
    // เลือกเฉพาะชิ้นบนสุด (ไม่ใช่ลูก) เพื่อให้ลากย้ายทั้งก้อนได้ทันที
    final parents = wfParentMap(diagram);
    final top = [for (final id in ids) if (!ids.contains(parents[id])) id];
    setSelection(top);
    return ids.length;
  }

  // ---------- มุมมอง ----------

  @override
  ({double left, double top, double right, double bottom})? contentBounds({Set<String>? only}) {
    if (only != null) return boxesBounds(diagram.components.where((c) => only.contains(c.id)), pad: 40);
    final b = boxesBounds([...diagram.components, WfComponent(id: '', kind: WfKind.container, w: diagram.width, h: diagram.height)],
        pad: 40);
    return b;
  }
}
