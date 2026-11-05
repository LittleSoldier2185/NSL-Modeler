import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/layout/diagram_geometry.dart';
import '../core/models/group_model.dart';

import '../core/clipboard/table_clipboard.dart';
import '../core/layout/auto_layout.dart';
import '../core/models/column_model.dart';
import '../core/models/dfd_model.dart';
import '../core/models/diagram.dart';
import '../core/models/enums.dart';
import '../core/models/index_model.dart';
import '../core/models/note_model.dart';
import '../core/models/project.dart';
import '../core/models/relation_model.dart';
import '../core/models/table_model.dart';
import '../core/models/workspace.dart';
import '../core/validate/issue.dart';
import '../core/validate/validator.dart';
import 'snapshot_history.dart';

/// ถือโปรเจกต์ปัจจุบัน ([Workspace] — เอกสาร ER + DFD) + selection + undo/redo (แบบ snapshot แยกต่อเอกสาร)
///
/// [project] คือเนื้อหาของเอกสาร ER ที่โปรแกรมแก้อยู่ (ตอนนี้มี ER เอกสารเดียวและลบไม่ได้)
class ProjectController extends ChangeNotifier {
  ProjectController([Project? project]) : _workspace = Workspace.single(project ?? Project()) {
    _erDoc = _ensureEr(_workspace);
  }

  static const _maxHistory = 100;

  Workspace _workspace;

  /// เอกสาร ER ที่แก้อยู่ — undo/redo เปลี่ยนเนื้อหา ([ProjectDocument.content]) เป็น object ใหม่ทุกครั้ง
  late ProjectDocument _erDoc;
  String? _filePath;
  bool _dirty = false;
  String? _selectedTableId;
  String? _selectedColumnId;

  /// ตารางที่เลือกเพิ่มจากตัวหลัก [_selectedTableId] (เลือกหลายตารางด้วย Ctrl/Shift+คลิก หรือ Ctrl+A)
  final Set<String> _extra = {};

  /// ประวัติ undo/redo แยกต่อเอกสาร (key = id เอกสาร; snapshot = เนื้อหาของเอกสารนั้นเท่านั้น)
  final Map<String, SnapshotHistory> _histories = {};
  int _idCounter = 0;

  SnapshotHistory _hist(String docId) => _histories.putIfAbsent(docId, () => SnapshotHistory(max: _maxHistory));

  /// ประวัติของเอกสาร ER
  SnapshotHistory get _history => _hist(_erDoc.id);

  /// เนื้อหาของเอกสาร ER ที่แก้อยู่ (object จริงในเอกสาร — undo/redo เปลี่ยน object นี้)
  Project get _project => _erDoc.content as Project;

  Project get project => _project;

  /// id ของเอกสาร ER ที่แก้อยู่ (ที่เก็บข้อมูลใน DFD ที่ผูกตารางชี้มาที่เอกสารนี้)
  String get erDocumentId => _erDoc.id;
  String? get filePath => _filePath;
  bool get dirty => _dirty;
  String? get selectedTableId => _selectedTableId;
  String? get selectedColumnId => _selectedColumnId;
  bool get canUndo => _histories[activeDiagramId]?.canUndo ?? false;
  bool get canRedo => _histories[activeDiagramId]?.canRedo ?? false;

  List<Issue>? _issues;

  /// ผลตรวจ schema (แคช — คำนวณใหม่เมื่อข้อมูลเปลี่ยน ไม่ใช่ตอนลากตาราง)
  List<Issue> get issues => _issues ??= validateProject(_project);

  TableModel? get selectedTable =>
      _selectedTableId == null ? null : _project.tableById(_selectedTableId!);

  ColumnModel? get selectedColumn {
    final c = _selectedColumnId;
    return c == null ? null : selectedTable?.columnById(c);
  }

  // ---------- helpers ----------

  String newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_idCounter++}';

  String _snapshot() => jsonEncode(_project.toContentJson());

  /// แก้ข้อมูลแบบมีประวัติ
  void _edit(void Function() change) {
    _history.push(_snapshot());
    change();
    _syncWorkspaceName();
    _dirty = true;
    _issues = null;
    notifyListeners();
  }

  /// ชื่อโปรเจกต์ (ชื่อ workspace ในไฟล์) ตามชื่อของเอกสาร ER — ตอนนี้แก้ชื่อได้ที่ ER อย่างเดียว
  void _syncWorkspaceName() {
    if (_workspace.documentsOf(DocType.er).length == 1) _workspace.name = _project.name;
  }

  void _fixSelection() {
    _attached.removeWhere((id) => _project.groupById(id) == null);
    _extra.removeWhere((id) => _project.tableById(id) == null);
    if (_selectedTableId != null && _project.tableById(_selectedTableId!) == null) {
      // ตัวหลักหาย: ถ้ายังเหลือที่เลือกอยู่ ให้ตัวอื่นขึ้นมาเป็นตัวหลัก
      if (_extra.isNotEmpty) {
        _selectedTableId = _extra.first;
        _extra.remove(_selectedTableId);
      } else {
        _selectedTableId = null;
      }
      _selectedColumnId = null;
    } else if (_selectedColumnId != null && selectedColumn == null) {
      _selectedColumnId = null;
    }
  }

  // ---------- ไฟล์ ----------

  void newProject({double boardWidth = kDefaultBoardWidth, double boardHeight = kDefaultBoardHeight}) =>
      _replace(Workspace.single(Project(boardWidth: boardWidth, boardHeight: boardHeight)), null, dirty: false);

  /// เปิดโปรเจกต์ (เช่น จากไฟล์) — [w] ถูกใช้เป็นข้อมูลจริงของ controller (ไม่คัดลอก)
  void loadWorkspace(Workspace w, String? path) => _replace(w, path, dirty: false);

  /// เปิดโปรเจกต์ที่มีแต่ ER (สะดวกสำหรับเทสต์/ข้อมูลที่สร้างในโปรแกรม)
  void loadProject(Project p, String? path) => _replace(Workspace.single(p), path, dirty: false);

  /// กู้คืนงานที่ auto-save ไว้ — ยังไม่ได้บันทึกลงไฟล์จริง จึงถือว่ายังมีการแก้ค้างอยู่
  void restoreWorkspace(Workspace w, String? originalPath) => _replace(w, originalPath, dirty: true);

  /// โปรเจกต์ที่ได้จากการ import .sql — ยังไม่มีไฟล์โปรเจกต์ จึงถือว่ายังไม่ได้บันทึก
  void loadImported(Project p) => _replace(Workspace.single(p), null, dirty: true);

  /// ให้ workspace มีเอกสาร ER เสมอ (ไฟล์ v3 อาจไม่มี) — ไม่มี = เพิ่มเอกสาร ER ว่างไว้หน้าสุด ; คืน ER แรก
  static ProjectDocument _ensureEr(Workspace w) {
    final er = w.firstEr;
    if (er != null) return er;
    var id = kErDiagramId;
    for (var n = 2; w.documentById(id) != null; n++) {
      id = '$kErDiagramId$n';
    }
    final doc = ProjectDocument.er(id: id, name: w.uniqueDocumentName('ER'), content: Project(name: w.name));
    w.documents.insert(0, doc);
    return doc;
  }

  void _replace(Workspace w, String? path, {required bool dirty}) {
    _workspace = w;
    _erDoc = _ensureEr(w);
    _activeDiagramId = _erDoc.id;
    _filePath = path;
    _dirty = dirty;
    _issues = null;
    _selectedTableId = null;
    _selectedGroupId = null;
    _attached.clear();
    _extra.clear();
    _selectedColumnId = null;
    _histories.clear();
    _dfdGestureId = null;
    notifyListeners();
  }

  void markSaved(String path) {
    _filePath = path;
    _dirty = false;
    notifyListeners();
  }

  // ---------- เอกสาร (workspace) ----------
  //
  // UI อ่านรายการเอกสาร/เนื้อหา DFD ผ่าน accessor เหล่านี้ — คืน object จริงของโปรเจกต์ (ไม่ใช่สำเนา)

  /// โปรเจกต์ทั้งหมด (ข้อมูลจริงที่บันทึกลงไฟล์)
  Workspace get workspace => _workspace;

  /// เอกสารทั้งหมดตามลำดับในไฟล์ (รวมชนิดที่โปรแกรมรุ่นนี้ไม่รู้จัก)
  List<ProjectDocument> get documents => _workspace.documents;

  /// เอกสารที่แสดงเป็นแท็บ (ชนิดที่รู้จัก) ตามลำดับ
  List<ProjectDocument> get tabDocuments => [for (final d in _workspace.documents) if (d.type != null) d];

  ProjectDocument? documentById(String id) => _workspace.documentById(id);

  /// เนื้อหา DFD ของเอกสาร [id] — ไม่ใช่เอกสาร DFD/ไม่มีอยู่ = แผนภาพว่างชั่วคราว (ไม่ถูกเก็บในโปรเจกต์)
  DfdDiagram dfdOf(String id) => _workspace.documentById(id)?.dfd ?? DfdDiagram();

  // ---------- แท็บแผนภาพ ----------
  //
  // การเพิ่ม/ลบ/เปลี่ยนชื่อ/เรียงแท็บไม่เข้าประวัติ undo (เหมือนแท็บเอกสารของโปรแกรมกราฟิก — ลบแท็บมีกล่องยืนยัน)
  // และ undo/redo ของเนื้อหาไม่ย้อนรายการแท็บ

  String _activeDiagramId = kErDiagramId;

  /// เอกสารที่เปิดอยู่ (ถ้าเอกสารนั้นหายไปจะกลับเป็น ER)
  ProjectDocument get activeDiagram {
    final d = _workspace.documentById(_activeDiagramId);
    return d != null && d.type != null ? d : _erDoc;
  }

  String get activeDiagramId => activeDiagram.id;

  void selectDiagram(String id) {
    final d = _workspace.documentById(id);
    if (d == null || d.type == null || id == _activeDiagramId) return;
    _activeDiagramId = id;
    notifyListeners();
  }

  void _tabsChanged() {
    _dirty = true;
    notifyListeners();
  }

  /// เพิ่มแผนภาพใหม่ต่อท้ายและเปิดทันที (ตอนนี้เพิ่มได้เฉพาะ DFD — ER มีอันเดียว) ชื่อซ้ำจะต่อเลขให้
  ProjectDocument? addDiagram(DocType type, {String? name}) {
    if (type != DocType.dfd) return null;
    final base = cleanDiagramName(name ?? '');
    final doc = ProjectDocument.dfd(
      id: newId('d'),
      name: _workspace.uniqueDocumentName(base.isEmpty ? 'DFD' : base),
      content: DfdDiagram(),
    );
    _workspace.documents.add(doc);
    _activeDiagramId = doc.id;
    _tabsChanged();
    return doc;
  }

  /// เปลี่ยนชื่อแท็บ — คืน false ถ้าชื่อว่าง/ซ้ำกับเอกสารอื่น (ไม่สนตัวพิมพ์)
  bool renameDiagram(String id, String name) {
    final t = _workspace.documentById(id);
    final n = cleanDiagramName(name);
    if (t == null || n.isEmpty) return false;
    if (_workspace.documents.any((d) => d.id != id && d.name.toLowerCase() == n.toLowerCase())) return false;
    if (t.name == n) return true;
    t.name = n;
    _tabsChanged();
    return true;
  }

  /// ลบแท็บ (ลบ ER ไม่ได้) — ถ้าเป็นแท็บที่เปิดอยู่ จะย้ายไปแท็บข้างเคียง
  bool deleteDiagram(String id) {
    final tabs = tabDocuments;
    final i = tabs.indexWhere((d) => d.id == id);
    if (i < 0 || tabs[i].type != DocType.dfd) return false;
    _workspace.documents.remove(tabs[i]);
    tabs.removeAt(i);
    _histories.remove(id);
    if (_activeDiagramId == id) {
      _activeDiagramId = tabs[i > 0 ? i - 1 : 0].id;
    }
    _tabsChanged();
    return true;
  }

  /// ย้ายแท็บไปตำแหน่ง [toIndex] (ตำแหน่งในรายการแท็บหลังเอาแท็บนั้นออกแล้ว)
  /// เอกสารชนิดที่ไม่รู้จัก (ไม่มีแท็บ) คงตำแหน่งสัมพัทธ์เดิมในไฟล์
  void moveDiagram(String id, int toIndex) {
    final tabs = tabDocuments;
    final from = tabs.indexWhere((d) => d.id == id);
    if (from < 0) return;
    final to = toIndex.clamp(0, tabs.length - 1);
    if (to == from) return;
    final doc = tabs.removeAt(from);
    final docs = _workspace.documents..remove(doc);
    if (to < tabs.length) {
      docs.insert(docs.indexOf(tabs[to]), doc);
    } else {
      docs.insert(docs.indexOf(tabs.last) + 1, doc);
    }
    _tabsChanged();
  }

  // ---------- undo / redo ----------

  // --- ประวัติของแท็บ DFD: แยกต่อเอกสาร (snapshot เฉพาะเนื้อหาของเอกสารนั้น) ---

  /// แท็บ DFD ที่กำลังลากอยู่ (ลากได้ทีละแท็บ)
  String? _dfdGestureId;

  /// เอกสาร DFD ที่เปิดอยู่ (null = แท็บที่เปิดไม่ใช่ DFD)
  ProjectDocument? get _activeDfdDoc {
    final d = activeDiagram;
    return d.type == DocType.dfd ? d : null;
  }

  String _dfdSnapshot(ProjectDocument doc) => jsonEncode(doc.dfd!.toJson());

  /// แก้เนื้อหา DFD ของแท็บที่เปิดอยู่แบบมีประวัติ (undo ขั้นเดียว)
  void dfdEdit(void Function(DfdDiagram d) change) {
    final doc = _activeDfdDoc;
    if (doc == null) return;
    _hist(doc.id).push(_dfdSnapshot(doc));
    change(doc.dfd!);
    _dirty = true;
    notifyListeners();
  }

  /// แก้ DFD แบบสดระหว่างลาก — ครอบด้วย dfdBeginGesture / dfdEndGesture (undo ขั้นเดียว)
  void dfdLive(void Function(DfdDiagram d) change) {
    final doc = _activeDfdDoc;
    if (doc == null) return;
    change(doc.dfd!);
    notifyListeners();
  }

  void dfdBeginGesture() {
    final doc = _activeDfdDoc;
    if (_dfdGestureId != null || doc == null) return;
    _dfdGestureId = doc.id;
    _hist(doc.id).beginGesture(_dfdSnapshot(doc));
  }

  void dfdEndGesture() {
    final id = _dfdGestureId;
    _dfdGestureId = null;
    if (id == null) return;
    final h = _histories[id];
    final doc = _workspace.documentById(id);
    if (h == null || !h.gestureActive || doc?.dfd == null) {
      h?.cancelGesture();
      return;
    }
    if (h.endGesture(_dfdSnapshot(doc!))) _dirty = true;
    notifyListeners();
  }

  void _dfdUndoRedo(ProjectDocument doc, bool undo) {
    final h = _histories[doc.id];
    if (h == null || !(undo ? h.canUndo : h.canRedo)) return;
    final cur = _dfdSnapshot(doc);
    final snap = undo ? h.undo(cur)! : h.redo(cur)!;
    doc.content = DfdDiagram.fromJson(jsonDecode(snap));
    _dirty = true;
    notifyListeners();
  }

  /// ใส่เนื้อหา ER จาก snapshot กลับเข้าเอกสาร ER (object ใหม่ — สิ่งที่บันทึกลงไฟล์คือค่านี้)
  /// undo ไม่ย้อนรายการแท็บ/เนื้อหา DFD
  void _restoreEr(String snap) {
    _erDoc.content = Project.fromContentJson(jsonDecode(snap) as Map<String, dynamic>);
    _syncWorkspaceName();
    _dirty = true;
    _issues = null;
    _fixSelection();
    notifyListeners();
  }

  void undo() {
    final dfd = _activeDfdDoc;
    if (dfd != null) {
      _dfdUndoRedo(dfd, true);
      return;
    }
    if (!_history.canUndo) return;
    _restoreEr(_history.undo(_snapshot())!);
  }

  void redo() {
    final dfd = _activeDfdDoc;
    if (dfd != null) {
      _dfdUndoRedo(dfd, false);
      return;
    }
    if (!_history.canRedo) return;
    _restoreEr(_history.redo(_snapshot())!);
  }

  // ---------- gesture (ลาก) : นับเป็น 1 ขั้น undo ----------

  void beginGesture() {
    if (_history.gestureActive) return;
    _history.beginGesture(_snapshot());
    _dragOrigin = null;
    _attOrigin = null;
  }

  /// ตำแหน่งเริ่มลากของตารางที่เลือก + ระยะที่ลากสะสม (ไว้ปัดเข้าช่องตารางโดยไม่สะสมความคลาดเคลื่อน)
  Map<String, (double, double)>? _dragOrigin;
  double _rawDx = 0, _rawDy = 0;

  /// กำลังลากอยู่ (ตั้งแต่ beginGesture ถึง endGesture)
  bool get gestureActive => _history.gestureActive;

  void endGesture() {
    final had = _history.gestureActive;
    _dragOrigin = null;
    _attOrigin = null;
    _groupOrigin = null;
    _resizeOrigin = null;
    if (had && _history.endGesture(_snapshot())) {
      _dirty = true;
      _issues = null;
    }
    if (had) notifyListeners(); // ให้ hint ตอนลากหายไป
  }

  /// ตั้งข้อมูลตั้งต้นของตาราง (แทนที่ทั้งชุด) เป็น undo ขั้นเดียว — ไม่เปลี่ยนถ้าเหมือนเดิม
  void setSeedRows(String tableId, List<Map<String, String?>> rows) {
    final t = _project.tableById(tableId);
    if (t == null) return;
    final next = [for (final r in rows) Map<String, String?>.of(r)];
    bool same() {
      if (next.length != t.seedRows.length) return false;
      for (var i = 0; i < next.length; i++) {
        final a = next[i], b = t.seedRows[i];
        if (a.length != b.length) return false;
        for (final k in a.keys) {
          if (!b.containsKey(k) || b[k] != a[k]) return false;
        }
      }
      return true;
    }

    if (same()) return;
    _edit(() => t.seedRows = next);
  }

  /// ตั้งสีตาราง (null = สีเริ่มต้น) ให้ทุกตารางใน [ids] เป็น undo ขั้นเดียว
  void setTablesColor(Iterable<String> ids, int? index) {
    if (index != null && (index < 0 || index >= kTableColors.length)) return;
    final ts = [for (final id in ids) if (_project.tableById(id) != null) _project.tableById(id)!];
    if (ts.isEmpty || ts.every((t) => t.colorIndex == index && t.customColor == null)) return;
    _edit(() {
      for (final t in ts) {
        t.colorIndex = index;
        t.customColor = null; // เลือกสีสำเร็จรูป/ล้างสี = เลิกใช้สีกำหนดเอง
      }
    });
  }

  /// ตั้งสีกำหนดเอง (ARGB) ให้ทุกตารางใน [ids] เป็น undo ขั้นเดียว (null = ล้างสี)
  void setTablesCustomColor(Iterable<String> ids, int? argb) {
    if (argb != null && (argb < 0 || argb > 0xFFFFFFFF)) return;
    final ts = [for (final id in ids) if (_project.tableById(id) != null) _project.tableById(id)!];
    if (ts.isEmpty || ts.every((t) => t.customColor == argb && (argb != null || t.colorIndex == null))) return;
    _edit(() {
      for (final t in ts) {
        t.customColor = argb;
        if (argb != null || t.customColor == null) t.colorIndex = null;
      }
    });
  }

  /// ตั้งฟอนต์ของตาราง (null = ฟอนต์หลักของแอป) ให้ทุกตารางใน [ids] เป็น undo ขั้นเดียว
  void setTablesFont(Iterable<String> ids, String? family) {
    final f = family == null || family.trim().isEmpty ? null : family.trim();
    final ts = [for (final id in ids) if (_project.tableById(id) != null) _project.tableById(id)!];
    if (ts.isEmpty || ts.every((t) => t.fontFamily == f)) return;
    _edit(() {
      for (final t in ts) {
        t.fontFamily = f;
      }
    });
  }

  /// สีเส้นของความสัมพันธ์เดียว (null = ใช้สีเริ่มต้น)
  void setRelationColor(String id, int? argb) {
    final r = _project.relations.where((r) => r.id == id).firstOrNull;
    if (r == null || r.color == argb) return;
    if (argb != null && (argb < 0 || argb > 0xFFFFFFFF)) return;
    _edit(() => r.color = argb);
  }

  /// สีเส้นเริ่มต้นของทั้งโปรเจกต์ (null = สีตามธีม)
  void setLineColor(int? argb) {
    if (_project.lineColor == argb) return;
    if (argb != null && (argb < 0 || argb > 0xFFFFFFFF)) return;
    _edit(() => _project.lineColor = argb);
  }

  // ---------- กลุ่ม ----------

  /// ระยะเผื่อรอบตารางตอนจัดกลุ่มจากตารางที่เลือก (ด้านบนเผื่อแถบชื่อเพิ่ม)
  static const double _groupPad = 28;

  String _nextGroupName() {
    final used = _project.groups.map((g) => g.name.toLowerCase()).toSet();
    var i = 1;
    while (used.contains('group $i')) {
      i++;
    }
    return 'Group $i';
  }

  GroupModel addGroup({
    double x = 40,
    double y = 40,
    double width = kGroupDefaultWidth,
    double height = kGroupDefaultHeight,
    String? name,
  }) {
    final g = GroupModel(
      id: newId('g'),
      name: name ?? _nextGroupName(),
      x: x,
      y: y,
      width: width,
      height: height,
      colorIndex: _project.groups.length % kGroupColors.length,
    );
    _edit(() => _project.groups.add(g));
    return g;
  }

  /// จัดกลุ่มจากตารางที่เลือกอยู่: สร้างกรอบครอบตารางเหล่านั้นพร้อมระยะเผื่อ (undo ขั้นเดียว)
  /// คืน null ถ้าไม่มีตารางที่เลือก
  GroupModel? groupSelectedTables() {
    final ts = [for (final id in selectedTableIds) if (_project.tableById(id) != null) _project.tableById(id)!];
    if (ts.isEmpty) return null;
    var l = ts.first.x, t = ts.first.y, r = ts.first.x + ts.first.width, b = ts.first.y + tableHeight(ts.first);
    for (final e in ts) {
      l = l < e.x ? l : e.x;
      t = t < e.y ? t : e.y;
      r = r > e.x + e.width ? r : e.x + e.width;
      b = b > e.y + tableHeight(e) ? b : e.y + tableHeight(e);
    }
    return addGroup(
      x: l - _groupPad,
      y: t - _groupPad - kGroupHeader,
      width: (r - l) + _groupPad * 2,
      height: (b - t) + _groupPad * 2 + kGroupHeader,
    );
  }

  void renameGroup(String id, String name) {
    final g = _project.groupById(id);
    if (g == null || g.name == name) return;
    _edit(() => g.name = name);
  }

  void setGroupColor(String id, int index) {
    final g = _project.groupById(id);
    if (g == null || (g.colorIndex == index && g.customColor == null) || index < 0 || index >= kGroupColors.length) return;
    _edit(() {
      g.colorIndex = index;
      g.customColor = null; // เลือกสีสำเร็จรูป = เลิกใช้สีกำหนดเอง
    });
  }

  /// ตั้งสีกำหนดเองของกลุ่ม (ARGB); null = กลับไปใช้สีสำเร็จรูปเดิม
  void setGroupCustomColor(String id, int? argb) {
    final g = _project.groupById(id);
    if (g == null || g.customColor == argb) return;
    if (argb != null && (argb < 0 || argb > 0xFFFFFFFF)) return;
    _edit(() => g.customColor = argb);
  }

  /// ลบกลุ่ม (ตาราง/โน้ตข้างในไม่ถูกลบ)
  void removeGroup(String id) {
    if (_project.groupById(id) == null) return;
    if (_selectedGroupId == id) _selectedGroupId = null;
    _edit(() => _project.groups.removeWhere((g) => g.id == id));
  }

  /// เลือกตารางทั้งหมดที่อยู่ในกลุ่ม
  void selectGroupMembers(String id) {
    final g = _project.groupById(id);
    if (g == null) return;
    setTableSelection(groupMembers(_project, g).tables);
  }

  // --- ลากกลุ่ม: สมาชิกเลื่อนตาม ---
  Map<String, (double, double)>? _groupOrigin; // 'g:id' / 't:id' / 'n:id' -> ตำแหน่งตอนเริ่มลาก
  double _groupRawDx = 0, _groupRawDy = 0;

  /// เริ่มลากกลุ่ม: จดสมาชิก ณ ตอนนี้ไว้ (ครอบด้วย endGesture เป็น undo ขั้นเดียว)
  void beginGroupDrag(String id) {
    final g = _project.groupById(id);
    if (g == null) return;
    selectGroup(id); // กลุ่มที่กำลังลากถือว่าถูกเลือก
    beginGesture();
    final m = groupMembers(_project, g);
    _groupOrigin = {
      'g:$id': (g.x, g.y),
      for (final tid in m.tables) 't:$tid': (_project.tableById(tid)!.x, _project.tableById(tid)!.y),
      for (final nid in m.notes) ...{
        'n:$nid': (
          _project.notes.firstWhere((n) => n.id == nid).x,
          _project.notes.firstWhere((n) => n.id == nid).y,
        ),
      },
      for (final gid in m.groups) 'g:$gid': (_project.groupById(gid)!.x, _project.groupById(gid)!.y),
    };
    _groupRawDx = 0;
    _groupRawDy = 0;
  }

  /// ลากกลุ่มไป (dx,dy) จากครั้งก่อน; [grid] != null = ปัดตำแหน่งกลุ่มเข้าช่อง แล้วสมาชิกเลื่อนด้วยระยะเท่ากัน
  void moveGroupBy(String id, double dx, double dy, {double? grid}) {
    final origin = _groupOrigin;
    final g = _project.groupById(id);
    if (origin == null || g == null) return;
    _groupRawDx += dx;
    _groupRawDy += dy;
    final o = origin['g:$id']!;
    var nx = o.$1 + _groupRawDx, ny = o.$2 + _groupRawDy;
    if (grid != null) {
      nx = snapToGrid(nx, grid);
      ny = snapToGrid(ny, grid);
    }
    nx = nx.clamp(kWorldMin, kWorldMax).toDouble();
    ny = ny.clamp(kWorldMin, kWorldMax).toDouble();
    final sx = nx - o.$1, sy = ny - o.$2;
    for (final e in origin.entries) {
      final kind = e.key.substring(0, 1);
      final key = e.key.substring(2);
      final x = (e.value.$1 + sx).clamp(kWorldMin, kWorldMax).toDouble();
      final y = (e.value.$2 + sy).clamp(kWorldMin, kWorldMax).toDouble();
      switch (kind) {
        case 'g':
          final t = _project.groupById(key);
          if (t != null) {
            t.x = x;
            t.y = y;
          }
        case 't':
          final t = _project.tableById(key);
          if (t != null) {
            t.x = x;
            t.y = y;
          }
        case 'n':
          final n = _project.notes.where((n) => n.id == key).firstOrNull;
          if (n != null) {
            n.x = x;
            n.y = y;
          }
      }
    }
    notifyListeners();
  }

  (double, double)? _resizeOrigin;
  double _resizeRawW = 0, _resizeRawH = 0;

  /// เริ่มปรับขนาดกลุ่มจากมุมขวาล่าง (ครอบด้วย endGesture เป็น undo ขั้นเดียว)
  void beginGroupResize(String id) {
    final g = _project.groupById(id);
    if (g == null) return;
    beginGesture();
    _resizeOrigin = (g.width, g.height);
    _resizeRawW = 0;
    _resizeRawH = 0;
  }

  /// ปรับขนาดกลุ่ม (live ระหว่างลาก) คิดจากขนาดตอนเริ่ม + ระยะสะสม — ไม่เล็กกว่าขนาดต่ำสุด
  void resizeGroupBy(String id, double dw, double dh, {double? grid}) {
    final g = _project.groupById(id);
    final o = _resizeOrigin;
    if (g == null || o == null) return;
    _resizeRawW += dw;
    _resizeRawH += dh;
    var w = o.$1 + _resizeRawW, h = o.$2 + _resizeRawH;
    if (grid != null) {
      w = snapToGrid(g.x + w, grid) - g.x;
      h = snapToGrid(g.y + h, grid) - g.y;
    }
    g.width = w < kGroupMinWidth ? kGroupMinWidth : w;
    g.height = h < kGroupMinHeight ? kGroupMinHeight : h;
    notifyListeners();
  }

  // ---------- selection ----------

  /// กลุ่มที่ "ติด" ไปกับตารางที่เลือก (กรอบเลือกที่ครอบกลุ่มทั้งกลุ่ม): ลากตารางแล้วกรอบกลุ่มและโน้ตข้างในเลื่อนตาม
  /// ต่างจาก [selectedGroupId] ที่เป็นการคลิกเลือกกลุ่มเดี่ยว ๆ
  final Set<String> _attached = {};

  Set<String> get attachedGroupIds => {for (final id in _attached) if (_project.groupById(id) != null) id};

  /// กลุ่มทั้งหมดที่ถือว่าถูกเลือก: ที่คลิกเลือก + ที่ติดไปกับตารางที่เลือก
  Set<String> get selectedGroupIds => {?selectedGroupId, ...attachedGroupIds};

  String? _selectedGroupId;

  /// กลุ่มที่ถูกเลือกอยู่ (null = ไม่มี) — เลือกกลุ่มแล้วจะไม่มีตารางที่ถูกเลือก และกลับกัน
  String? get selectedGroupId =>
      _selectedGroupId != null && _project.groupById(_selectedGroupId!) != null ? _selectedGroupId : null;

  GroupModel? get selectedGroup => selectedGroupId == null ? null : _project.groupById(selectedGroupId!);

  void selectGroup(String? id) {
    if (id != null && _project.groupById(id) == null) return;
    if (_selectedGroupId == id && (id == null || selectedTableIds.isEmpty)) return;
    _selectedGroupId = id;
    _attached.clear();
    if (id != null) {
      _selectedTableId = null;
      _selectedColumnId = null;
      _extra.clear();
    }
    notifyListeners();
  }

  void selectTable(String? id, {String? columnId}) {
    _selectedGroupId = null;
    _attached.clear();
    _selectedTableId = id;
    _extra.clear();
    _selectedColumnId = columnId;
    notifyListeners();
  }

  void selectColumn(String? id) {
    _selectedColumnId = id;
    notifyListeners();
  }

  /// ตารางที่เลือกทั้งหมด (ตัวหลัก + ตัวที่เลือกเพิ่ม)
  Set<String> get selectedTableIds => {?_selectedTableId, ..._extra};

  int get selectionCount => selectedTableIds.length;

  bool isTableSelected(String id) => id == _selectedTableId || _extra.contains(id);

  /// Ctrl/Shift+คลิก: เพิ่ม/เอาตารางออกจากที่เลือก (ตารางที่เพิ่งเพิ่มกลายเป็นตัวหลักที่แผงขวาแสดง)
  void toggleTableSelection(String id) {
    if (_project.tableById(id) == null) return;
    _selectedGroupId = null;
    _attached.clear();
    if (isTableSelected(id)) {
      if (id == _selectedTableId) {
        _selectedTableId = _extra.isEmpty ? null : _extra.first;
        _extra.remove(_selectedTableId);
        _selectedColumnId = null;
      } else {
        _extra.remove(id);
      }
    } else {
      if (_selectedTableId != null) _extra.add(_selectedTableId!);
      _selectedTableId = id;
      _selectedColumnId = null;
    }
    notifyListeners();
  }

  /// ตั้งชุดตารางที่เลือกทั้งหมด (ใช้ตอนลากกรอบเลือก) — ไม่แตะ undo
  void setTableSelection(Iterable<String> ids, {Iterable<String> groups = const []}) {
    final valid = [for (final id in ids) if (_project.tableById(id) != null) id];
    if (valid.isEmpty) {
      clearSelection();
      return;
    }
    final next = valid.toSet();
    final nextGroups = {for (final g in groups) if (_project.groupById(g) != null) g};
    _selectedGroupId = null;
    final sameGroups = nextGroups.length == _attached.length && _attached.containsAll(nextGroups);
    if (next.length == selectedTableIds.length && next.containsAll(selectedTableIds)) {
      if (!sameGroups) {
        _attached
          ..clear()
          ..addAll(nextGroups);
        notifyListeners();
      }
      return;
    }
    _attached
      ..clear()
      ..addAll(nextGroups);
    // คงตัวหลักเดิมไว้ถ้ายังอยู่ในชุดใหม่ (แผงขวาจะได้ไม่กระโดด)
    final primary = _selectedTableId != null && next.contains(_selectedTableId) ? _selectedTableId! : valid.first;
    _selectedTableId = primary;
    _extra
      ..clear()
      ..addAll(next.where((id) => id != primary));
    _selectedColumnId = null;
    notifyListeners();
  }

  /// Ctrl+A
  void selectAllTables() {
    if (_project.tables.isEmpty) return;
    _selectedGroupId = null;
    _attached
      ..clear()
      ..addAll(_project.groups.map((g) => g.id)); // เลือกทั้งหมด = กรอบกลุ่มติดไปด้วย
    final keepPrimary = _selectedTableId != null && _project.tableById(_selectedTableId!) != null;
    _selectedTableId = keepPrimary ? _selectedTableId : _project.tables.first.id;
    _extra
      ..clear()
      ..addAll(_project.tables.map((t) => t.id).where((id) => id != _selectedTableId));
    if (!keepPrimary) _selectedColumnId = null;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedTableId == null && _extra.isEmpty && _selectedGroupId == null && _attached.isEmpty) return;
    _selectedGroupId = null;
    _attached.clear();
    _selectedTableId = null;
    _selectedColumnId = null;
    _extra.clear();
    notifyListeners();
  }

  // ---------- โปรเจกต์ ----------

  /// เปลี่ยนขนาดกระดานขั้นต่ำ (undo ได้)
  void setBoardSize(double width, double height) {
    final w = width.clamp(kMinBoardSide, kMaxBoardSide).toDouble();
    final h = height.clamp(kMinBoardSide, kMaxBoardSide).toDouble();
    if (w == _project.boardWidth && h == _project.boardHeight) return;
    _edit(() {
      _project.boardWidth = w;
      _project.boardHeight = h;
    });
  }

  void setName(String name) => _edit(() => _project.name = name);

  void setDialect(Dialect d) {
    if (d == _project.dialect) return;
    _edit(() => _project.dialect = d);
  }

  // ---------- ตาราง ----------

  /// ชื่อที่ยังไม่ซ้ำ เช่น table_1, table_2
  String _uniqueTableName(String base) {
    final used = _project.tables.map((t) => t.name.toLowerCase()).toSet();
    var i = 1;
    while (used.contains('${base}_$i')) {
      i++;
    }
    return '${base}_$i';
  }

  TableModel addTable({double x = 40, double y = 40, String? name, bool withId = true}) {
    final t = TableModel(
      id: newId('t'),
      name: name ?? _uniqueTableName('table'),
      x: x,
      y: y,
    );
    if (withId) {
      t.columns.add(ColumnModel(
        id: newId('c'),
        name: 'id',
        type: DataType.integer,
        isPrimaryKey: true,
        notNull: true,
        autoIncrement: true,
      ));
    }
    _edit(() => _project.tables.add(t));
    _selectedTableId = t.id;
    _extra.clear();
    _selectedColumnId = null;
    notifyListeners();
    return t;
  }

  void removeTable(String id) {
    if (_project.tableById(id) == null) return;
    _edit(() {
      _project.tables.removeWhere((t) => t.id == id);
      _project.relations.removeWhere((r) => r.fromTableId == id || r.toTableId == id);
    });
    _fixSelection();
    notifyListeners();
  }

  /// สำเนาตาราง (id ใหม่ทั้งหมด, ไม่คัดลอก FK)
  TableModel? duplicateTable(String id) {
    final src = _project.tableById(id);
    if (src == null) return null;
    final copy = TableModel.fromJson(src.toJson());
    copy.id = newId('t');
    copy.name = _uniqueTableName(src.name);
    copy.x += 30;
    copy.y += 30;
    final idMap = <String, String>{};
    for (final c in copy.columns) {
      idMap[c.id] = c.id = newId('c');
    }
    copy.remapSeedColumns(idMap);
    for (final i in copy.indexes) {
      i.id = newId('i');
      i.columnIds = i.columnIds.map((c) => idMap[c] ?? c).toList();
    }
    _edit(() => _project.tables.add(copy));
    _selectedTableId = copy.id;
    _extra.clear();
    _selectedColumnId = null;
    notifyListeners();
    return copy;
  }

  void renameTable(String id, String name) {
    final t = _project.tableById(id);
    if (t == null || t.name == name) return;
    _edit(() => t.name = name);
  }

  void setTableComment(String id, String comment) {
    final t = _project.tableById(id);
    if (t == null || t.comment == comment) return;
    _edit(() => t.comment = comment);
  }

  /// จัดตำแหน่งตารางอัตโนมัติ (undo ขั้นเดียว) — คืน false ถ้าไม่มีตารางหรือไม่มีอะไรเปลี่ยน
  bool autoLayoutTables() {
    final result = autoLayoutAll(_project);
    final pos = result.tables;
    final moves = [
      for (final t in _project.tables)
        if (pos[t.id] != null && (pos[t.id]!.x != t.x || pos[t.id]!.y != t.y)) t,
    ];

    // กลุ่ม: ตารางสมาชิกถูกจัดภายในกลุ่มแล้ว -> ปรับกรอบกลุ่มให้ครอบพอดี และเลื่อนโน้ตที่อยู่ในกลุ่มตามกลุ่ม
    final groupMoves = <(GroupModel, GroupRect, List<NoteModel>)>[];
    for (final g in _project.groups) {
      final r = result.groups[g.id];
      if (r == null) continue;
      final notes = [
        for (final nid in groupMembers(_project, g).notes) _project.notes.firstWhere((n) => n.id == nid),
      ];
      if (r.x != g.x || r.y != g.y || r.width != g.width || r.height != g.height) {
        groupMoves.add((g, r, notes));
      }
    }
    if (moves.isEmpty && groupMoves.isEmpty) return false;
    _edit(() {
      for (final t in moves) {
        t.x = pos[t.id]!.x;
        t.y = pos[t.id]!.y;
      }
      for (final (g, r, notes) in groupMoves) {
        final dx = r.x - g.x, dy = r.y - g.y;
        for (final n in notes) {
          n.x += dx;
          n.y += dy;
        }
        g.x = r.x;
        g.y = r.y;
        g.width = r.width;
        g.height = r.height;
      }
    });
    return true;
  }

  /// ย้ายแบบ live ระหว่างลาก — ครอบด้วย beginGesture/endGesture
  void moveTable(String id, double x, double y) {
    final t = _project.tableById(id);
    if (t == null) return;
    t.x = x;
    t.y = y;
    notifyListeners();
  }

  // ---------- ปฏิบัติการกับตารางที่เลือกหลายตัว ----------

  /// ตำแหน่งตารางอยู่ในช่วง [kWorldMin]..[kWorldMax] (ติดลบได้ กระดานจะขยายไปทางซ้าย/บน)
  static double _clampXY(double v) => v < kWorldMin ? kWorldMin : (v > kWorldMax ? kWorldMax : v);

  /// ย้ายตารางที่เลือกทั้งหมดแบบ live ระหว่างลาก — ครอบด้วย beginGesture/endGesture
  ///
  /// [grid] != null = ปัดตำแหน่งเข้าช่องตารางขนาดนั้น: คิดจากตำแหน่งตอนเริ่มลาก + ระยะสะสม
  /// ตารางทั้งกลุ่มจึงเลื่อนพร้อมกันและรักษาระยะห่างสัมพัทธ์ของกัน (ตัวที่ไม่ตรงช่องก็เลื่อนเป็นช่องเท่ากัน)
  void moveSelectedBy(double dx, double dy, {double? grid}) {
    if (grid != null) {
      if (!gestureActive || _dragOrigin == null) {
        _attOrigin = _captureAttached();
        _dragOrigin = {
          for (final id in selectedTableIds)
            if (_project.tableById(id) != null) id: (_project.tableById(id)!.x, _project.tableById(id)!.y),
        };
        _rawDx = 0;
        _rawDy = 0;
      }
      _rawDx += dx;
      _rawDy += dy;
      // เลื่อนทั้งกลุ่มด้วยระยะที่ปัดแล้วเท่ากัน (ยึดตารางที่เลือกเป็นหลักเป็นตัวอ้างอิง)
      final ref = _dragOrigin!.values.isEmpty ? (0.0, 0.0) : _dragOrigin!.values.first;
      final sx = snapToGrid(ref.$1 + _rawDx, grid) - ref.$1;
      final sy = snapToGrid(ref.$2 + _rawDy, grid) - ref.$2;
      for (final e in _dragOrigin!.entries) {
        final t = _project.tableById(e.key);
        if (t == null) continue;
        t.x = _clampXY(e.value.$1 + sx);
        t.y = _clampXY(e.value.$2 + sy);
      }
      _applyAttached(sx, sy);
      notifyListeners();
      return;
    }
    for (final id in selectedTableIds) {
      final t = _project.tableById(id);
      if (t == null) continue;
      t.x = _clampXY(t.x + dx);
      t.y = _clampXY(t.y + dy);
    }
    _shiftAttached(dx, dy);
    notifyListeners();
  }

  // --- กลุ่มที่ติดไปกับตารางที่เลือก: เลื่อนพร้อมกัน (พร้อมโน้ตที่อยู่ข้างในกลุ่ม) ---
  Map<String, (double, double)>? _attOrigin;

  /// ตำแหน่งตอนนี้ของกลุ่มที่ติดไป + โน้ตข้างใน ('g:id' / 'n:id')
  Map<String, (double, double)> _captureAttached() {
    final out = <String, (double, double)>{};
    for (final gid in attachedGroupIds) {
      final g = _project.groupById(gid)!;
      out['g:$gid'] = (g.x, g.y);
      for (final nid in groupMembers(_project, g).notes) {
        final n = _project.notes.where((n) => n.id == nid).firstOrNull;
        if (n != null) out['n:$nid'] = (n.x, n.y);
      }
    }
    return out;
  }

  /// เลื่อนกลุ่ม/โน้ตที่จดไว้ตอนเริ่มลากไป (sx, sy) จากตำแหน่งเริ่มลาก
  void _applyAttached(double sx, double sy) {
    final o = _attOrigin;
    if (o == null) return;
    for (final e in o.entries) {
      final x = _clampXY(e.value.$1 + sx), y = _clampXY(e.value.$2 + sy);
      final key = e.key.substring(2);
      if (e.key.startsWith('g:')) {
        final g = _project.groupById(key);
        if (g != null) {
          g.x = x;
          g.y = y;
        }
      } else {
        final n = _project.notes.where((n) => n.id == key).firstOrNull;
        if (n != null) {
          n.x = x;
          n.y = y;
        }
      }
    }
  }

  /// เลื่อนกลุ่ม/โน้ตที่ติดไปด้วยระยะ (dx, dy) จากตำแหน่งปัจจุบัน
  void _shiftAttached(double dx, double dy) {
    final cur = _captureAttached();
    for (final e in cur.entries) {
      final x = _clampXY(e.value.$1 + dx), y = _clampXY(e.value.$2 + dy);
      final key = e.key.substring(2);
      if (e.key.startsWith('g:')) {
        final g = _project.groupById(key);
        if (g != null) {
          g.x = x;
          g.y = y;
        }
      } else {
        final n = _project.notes.where((n) => n.id == key).firstOrNull;
        if (n != null) {
          n.x = x;
          n.y = y;
        }
      }
    }
  }

  /// ขยับตารางที่เลือกด้วยปุ่มลูกศร (undo หนึ่งขั้นต่อหนึ่งการกด) — คืน false ถ้าไม่มีอะไรเลือก/ขยับไม่ได้
  bool nudgeSelected(double dx, double dy) {
    final ts = [for (final id in selectedTableIds) if (_project.tableById(id) != null) _project.tableById(id)!];
    if (ts.isEmpty || ts.every((t) => _clampXY(t.x + dx) == t.x && _clampXY(t.y + dy) == t.y)) return false;
    _edit(() {
      _shiftAttached(dx, dy); // จับตำแหน่งกลุ่ม/โน้ตก่อนขยับตาราง (สมาชิกของกลุ่มคิดจากตำแหน่งเดิม)
      for (final t in ts) {
        t.x = _clampXY(t.x + dx);
        t.y = _clampXY(t.y + dy);
      }
    });
    return true;
  }

  /// ลบตารางที่เลือกทั้งหมดพร้อม FK ที่เกี่ยวข้อง (undo ขั้นเดียว)
  int removeSelectedTables() {
    final ids = selectedTableIds.where((id) => _project.tableById(id) != null).toSet();
    if (ids.isEmpty) return 0;
    _edit(() {
      _project.tables.removeWhere((t) => ids.contains(t.id));
      _project.relations.removeWhere((r) => ids.contains(r.fromTableId) || ids.contains(r.toTableId));
    });
    _selectedTableId = null;
    _selectedColumnId = null;
    _extra.clear();
    notifyListeners();
    return ids.length;
  }

  /// ข้อความสำหรับคลิปบอร์ด (null = ไม่มีอะไรเลือก)
  String? copySelectionText() {
    final ids = selectedTableIds;
    return ids.isEmpty ? null : encodeTableClipboard(_project, ids);
  }

  /// วางตารางจากคลิปบอร์ดของโปรแกรม [offset] = ระยะเลื่อนจากตำแหน่งเดิม
  /// (ชื่อที่ซ้ำกับของเดิมจะต่อท้าย _1, _2…) คืนตารางที่สร้าง — ว่างถ้าข้อความไม่ใช่ข้อมูลของโปรแกรมนี้
  List<TableModel> pasteTableText(String? text, {double offset = 30}) {
    final payload = decodeTableClipboard(text);
    if (payload == null) return const [];
    return _insertCopies(payload.tables, payload.relations, offset);
  }

  /// ทำสำเนาตารางที่เลือก (Ctrl+D) รวม FK ระหว่างกัน
  List<TableModel> duplicateSelected({double offset = 30}) {
    final ids = selectedTableIds;
    if (ids.isEmpty) return const [];
    final payload = decodeTableClipboard(encodeTableClipboard(_project, ids));
    if (payload == null) return const [];
    return _insertCopies(payload.tables, payload.relations, offset);
  }

  List<TableModel> _insertCopies(List<TableModel> tables, List<RelationModel> rels, double offset) {
    final tableMap = <String, String>{};
    final colMap = <String, String>{};
    final used = _project.tables.map((t) => t.name.toLowerCase()).toSet();
    for (final t in tables) {
      tableMap[t.id] = t.id = newId('t');
      // ชื่อยังว่างอยู่ก็ใช้ชื่อเดิม; ไม่ว่างก็ต่อท้าย _1, _2…
      var name = t.name;
      var i = 1;
      while (used.contains(name.toLowerCase())) {
        name = '${t.name}_${i++}';
      }
      t.name = name;
      used.add(name.toLowerCase());
      t.x = _clampXY(t.x + offset);
      t.y = _clampXY(t.y + offset);
      final tColMap = <String, String>{};
      for (final c in t.columns) {
        colMap[c.id] = tColMap[c.id] = c.id = newId('c');
      }
      t.remapSeedColumns(tColMap);
      for (final ix in t.indexes) {
        ix.id = newId('i');
        ix.columnIds = [for (final c in ix.columnIds) colMap[c] ?? c];
      }
    }
    final newRels = <RelationModel>[
      for (final r in rels)
        if (tableMap.containsKey(r.fromTableId) &&
            tableMap.containsKey(r.toTableId) &&
            colMap.containsKey(r.fromColumnId) &&
            colMap.containsKey(r.toColumnId))
          RelationModel(
            id: newId('r'),
            fromTableId: tableMap[r.fromTableId]!,
            fromColumnId: colMap[r.fromColumnId]!,
            toTableId: tableMap[r.toTableId]!,
            toColumnId: colMap[r.toColumnId]!,
            onDelete: r.onDelete,
            onUpdate: r.onUpdate,
            name: null, // ชื่อ constraint เดิมจะชนกัน ให้สร้างใหม่ตอน export
          ),
    ];
    _edit(() {
      _project.tables.addAll(tables);
      _project.relations.addAll(newRels);
    });
    _selectedTableId = tables.last.id;
    _selectedColumnId = null;
    _extra
      ..clear()
      ..addAll(tables.take(tables.length - 1).map((t) => t.id));
    notifyListeners();
    return tables;
  }

  // ---------- คอลัมน์ ----------

  ColumnModel? addColumn(String tableId, {String? name}) {
    final t = _project.tableById(tableId);
    if (t == null) return null;
    final used = t.columns.map((c) => c.name.toLowerCase()).toSet();
    var i = 1;
    while (used.contains('column_$i')) {
      i++;
    }
    final c = ColumnModel(id: newId('c'), name: name ?? 'column_$i');
    _edit(() => t.columns.add(c));
    _selectedColumnId = c.id;
    notifyListeners();
    return c;
  }

  /// แก้คอลัมน์ผ่านฟังก์ชัน เช่น `updateColumn(t, c, (c) => c.notNull = true)`
  void updateColumn(String tableId, String columnId, void Function(ColumnModel c) change) {
    final c = _project.tableById(tableId)?.columnById(columnId);
    if (c == null) return;
    _edit(() => change(c));
  }

  /// เพิ่มหลายคอลัมน์ในครั้งเดียว (เทมเพลต) — undo ขั้นเดียว
  /// ข้ามคอลัมน์ที่ชื่อซ้ำกับของเดิม
  int appendColumns(String tableId, List<ColumnModel> cols) {
    final t = _project.tableById(tableId);
    if (t == null) return 0;
    final used = t.columns.map((c) => c.name.toLowerCase()).toSet();
    final fresh = cols.where((c) => !used.contains(c.name.toLowerCase())).toList();
    if (fresh.isEmpty) return 0;
    _edit(() => t.columns.addAll(fresh));
    return fresh.length;
  }

  /// สร้างตารางใหม่จากรายการคอลัมน์ (เทมเพลต)
  /// เพิ่มตารางที่สร้างเสร็จแล้ว (จากฟอร์มสร้างตาราง) เป็น undo ขั้นเดียว ชื่อซ้ำจะต่อท้ายเลขให้
  TableModel addBuiltTable(TableModel t, {double x = 40, double y = 40}) {
    t
      ..x = x
      ..y = y;
    if (_project.tables.any((e) => e.name.toLowerCase() == t.name.toLowerCase())) {
      t.name = _uniqueTableName(t.name);
    }
    _edit(() => _project.tables.add(t));
    _selectedTableId = t.id;
    _extra.clear();
    _selectedColumnId = null;
    notifyListeners();
    return t;
  }

  TableModel addTableWith(String baseName, List<ColumnModel> cols,
      {double x = 40, double y = 40}) {
    final t = TableModel(id: newId('t'), name: baseName, x: x, y: y, columns: cols);
    if (_project.tables.any((e) => e.name.toLowerCase() == baseName.toLowerCase())) {
      t.name = _uniqueTableName(baseName);
    }
    _edit(() => _project.tables.add(t));
    _selectedTableId = t.id;
    _extra.clear();
    _selectedColumnId = null;
    notifyListeners();
    return t;
  }

  void removeColumn(String tableId, String columnId) {
    final t = _project.tableById(tableId);
    if (t == null || t.columnById(columnId) == null) return;
    _edit(() {
      t.columns.removeWhere((c) => c.id == columnId);
      t.dropSeedColumn(columnId);
      for (final i in t.indexes) {
        i.columnIds.remove(columnId);
      }
      t.indexes.removeWhere((i) => i.columnIds.isEmpty);
      _project.relations.removeWhere((r) =>
          (r.fromTableId == tableId && r.fromColumnId == columnId) ||
          (r.toTableId == tableId && r.toColumnId == columnId));
    });
    _fixSelection();
    notifyListeners();
  }

  /// จำนวนความสัมพันธ์ FK ที่ผูกกับคอลัมน์ [columnId] ของตาราง [tableId]
  int relationCountOfColumn(String tableId, String columnId) => _project.relations
      .where((r) =>
          (r.fromTableId == tableId && r.fromColumnId == columnId) ||
          (r.toTableId == tableId && r.toColumnId == columnId))
      .length;

  /// ใช้ผลจากฟอร์มแก้โครงสร้างตาราง: แทนชื่อ/หมายเหตุ/คอลัมน์/ดัชนีของตาราง [tableId] ด้วย [edited]
  /// (คอลัมน์ที่ id ไม่อยู่ใน [edited] = ถูกลบ → ตัดข้อมูลตั้งต้นและ FK ที่ผูกอยู่) — Undo ขั้นเดียว
  /// ตำแหน่ง/สี/ฟอนต์ของตารางไม่เปลี่ยน
  void applyTableEdit(String tableId, TableModel edited) {
    final t = _project.tableById(tableId);
    if (t == null) return;
    final keep = {for (final c in edited.columns) c.id};
    final dropped = [for (final c in t.columns) if (!keep.contains(c.id)) c.id];
    _edit(() {
      for (final id in dropped) {
        t.dropSeedColumn(id);
        _project.relations.removeWhere((r) =>
            (r.fromTableId == tableId && r.fromColumnId == id) || (r.toTableId == tableId && r.toColumnId == id));
      }
      t
        ..name = edited.name
        ..comment = edited.comment
        ..columns = edited.columns
        ..indexes = edited.indexes;
    });
    _fixSelection();
    notifyListeners();
  }

  void reorderColumn(String tableId, int oldIndex, int newIndex) {
    final t = _project.tableById(tableId);
    if (t == null || oldIndex < 0 || oldIndex >= t.columns.length) return;
    // newIndex = ตำแหน่งสุดท้ายหลังย้าย (ตรงกับ onReorderItem)
    newIndex = newIndex.clamp(0, t.columns.length - 1);
    if (newIndex == oldIndex) return;
    _edit(() => t.columns.insert(newIndex, t.columns.removeAt(oldIndex)));
  }

  // ---------- ความสัมพันธ์ / index / note ----------

  RelationModel? addRelation({
    required String fromTableId,
    required String fromColumnId,
    required String toTableId,
    required String toColumnId,
    RefAction onDelete = RefAction.noAction,
    RefAction onUpdate = RefAction.noAction,
  }) {
    final from = _project.tableById(fromTableId)?.columnById(fromColumnId);
    final to = _project.tableById(toTableId)?.columnById(toColumnId);
    if (from == null || to == null) return null;
    final dup = _project.relations.any((r) =>
        r.fromTableId == fromTableId &&
        r.fromColumnId == fromColumnId &&
        r.toTableId == toTableId &&
        r.toColumnId == toColumnId);
    if (dup) return null;
    final r = RelationModel(
      id: newId('r'),
      fromTableId: fromTableId,
      fromColumnId: fromColumnId,
      toTableId: toTableId,
      toColumnId: toColumnId,
      onDelete: onDelete,
      onUpdate: onUpdate,
    );
    _edit(() {
      // type ของ FK ต้องตรงกับคอลัมน์ที่อ้างถึง
      from.type = to.type;
      from.length = to.length;
      from.scale = to.scale;
      _project.relations.add(r);
    });
    return r;
  }

  void updateRelation(String id, void Function(RelationModel r) change) {
    final r = _project.relations.where((r) => r.id == id).firstOrNull;
    if (r == null) return;
    _edit(() => change(r));
  }

  void removeRelation(String id) {
    if (!_project.relations.any((r) => r.id == id)) return;
    _edit(() => _project.relations.removeWhere((r) => r.id == id));
  }

  IndexModel? addIndex(String tableId, List<String> columnIds, {bool unique = false}) {
    final t = _project.tableById(tableId);
    if (t == null || columnIds.isEmpty) return null;
    if (columnIds.any((c) => t.columnById(c) == null)) return null;
    final names = columnIds.map((c) => t.columnById(c)!.name).join('_');
    final idx = IndexModel(
      id: newId('i'),
      name: 'idx_${t.name}_$names',
      columnIds: List.of(columnIds),
      unique: unique,
    );
    _edit(() => t.indexes.add(idx));
    return idx;
  }

  void removeIndex(String tableId, String indexId) {
    final t = _project.tableById(tableId);
    if (t == null || !t.indexes.any((i) => i.id == indexId)) return;
    _edit(() => t.indexes.removeWhere((i) => i.id == indexId));
  }

  NoteModel addNote({double x = 40, double y = 40, String text = ''}) {
    final n = NoteModel(id: newId('n'), text: text, x: x, y: y);
    _edit(() => _project.notes.add(n));
    return n;
  }

  void updateNote(String id, void Function(NoteModel n) change) {
    final n = _project.notes.where((n) => n.id == id).firstOrNull;
    if (n == null) return;
    _edit(() => change(n));
  }

  /// ย้ายโน้ตแบบ live ระหว่างลาก — ครอบด้วย beginGesture/endGesture
  void moveNote(String id, double x, double y) {
    final n = _project.notes.where((n) => n.id == id).firstOrNull;
    if (n == null) return;
    n.x = x;
    n.y = y;
    notifyListeners();
  }

  void removeNote(String id) {
    if (!_project.notes.any((n) => n.id == id)) return;
    _edit(() => _project.notes.removeWhere((n) => n.id == id));
  }
}
