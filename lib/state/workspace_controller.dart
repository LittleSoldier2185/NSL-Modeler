import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models/dfd_model.dart';
import '../core/models/diagram.dart';
import '../core/models/doc_ref.dart';
import '../core/models/flowchart_model.dart';
import '../core/models/project.dart';
import '../core/models/workspace.dart';
import 'dfd_controller.dart';
import 'flowchart_controller.dart';
import 'doc_controller.dart';
import 'project_controller.dart';

/// ถือทั้งโปรเจกต์ ([Workspace]) ที่เปิดอยู่: ไฟล์ สถานะยังไม่บันทึก แท็บที่เปิด/แท็บที่ใช้งาน
/// และ controller ของแต่ละเอกสาร (สร้างเมื่อใช้ครั้งแรก, ทิ้งเมื่อเอกสารถูกลบหรือเปิดโปรเจกต์ใหม่)
///
/// การเพิ่ม/ลบ/เปลี่ยนชื่อ/ย้ายเอกสารและโฟลเดอร์ไม่เข้าประวัติ undo (undo เป็นของแต่ละเอกสาร)
/// controller นี้แจ้งผู้ฟังทุกครั้งที่โครงสร้างเปลี่ยน และทุกครั้งที่ controller ของเอกสารใดแจ้ง
class WorkspaceController extends ChangeNotifier {
  WorkspaceController([Workspace? workspace]) : _workspace = workspace ?? Workspace.single(Project()) {
    final er = _ensureEr(_workspace);
    _mainEr = ProjectController.forDoc(er, this);
    _register(_mainEr);
    _resetTabs(er.id);
  }

  Workspace _workspace;
  String? _filePath;
  bool _structureDirty = false;
  int _idCounter = 0;

  /// controller ของเอกสาร ER หลัก — เปิดไฟล์ใหม่ = ผูกตัวเดิมกับเอกสาร ER แรกของไฟล์ใหม่ (ไม่สร้างใหม่)
  /// ลบเอกสาร ER ที่ตัวนี้ผูกอยู่ = controller ของ ER อันถัดไปขึ้นมาเป็นตัวหลักแทน (ตัวเดิมถูกทิ้ง)
  late ProjectController _mainEr;

  /// เอกสาร ER ที่เปิดใช้งานล่าสุด (แท็บที่เปิดไม่ใช่ ER = [currentEr] ยังเป็น ER อันนี้)
  String? _lastErId;

  /// docId -> controller (สร้างเมื่อเรียก [controllerOf] ครั้งแรก)
  final Map<String, DocController> _controllers = {};

  /// แท็บที่เปิดอยู่ (ลำดับแท็บ = ลำดับเอกสารในไฟล์)
  final Set<String> _open = {};
  String _activeId = kErDiagramId;

  /// กำลังแสดงหน้า Project Home แทนแคนวาส (สถานะมุมมองล้วน ไม่ถูกบันทึกในไฟล์ ; เปิดเอกสารใด ๆ = ออกจากหน้านี้)
  bool _homeView = false;

  Workspace get workspace => _workspace;

  bool get homeView => _homeView;

  /// แสดง/ซ่อนหน้า Project Home (ไม่แตะเอกสารหรือสถานะ dirty)
  void showHome([bool show = true]) {
    if (_homeView == show) return;
    _homeView = show;
    notifyListeners();
  }
  String? get filePath => _filePath;

  /// มีการเปลี่ยนโครงสร้าง (เพิ่ม/ลบ/เปลี่ยนชื่อ/ย้ายเอกสาร) ที่ยังไม่บันทึก
  bool get structureDirty => _structureDirty;

  /// มีอะไรยังไม่บันทึก: โครงสร้าง หรือเนื้อหาของเอกสารใดเอกสารหนึ่ง
  bool get dirty => _structureDirty || _controllers.values.any((c) => c.docDirty);

  String newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}w${_idCounter++}';

  // ---------- controller ของเอกสาร ----------

  /// controller ของเอกสาร ER หลัก (ตอนเปิดไฟล์คือเอกสาร ER แรก — ถ้าถูกลบ ER อันถัดไปเป็นตัวหลักแทน)
  ProjectController get mainEr => _mainEr;

  /// controller ของเอกสาร [id] (สร้างเมื่อใช้ครั้งแรก) ; null = ไม่มีเอกสารนี้หรือเป็นชนิดที่ไม่รู้จัก
  DocController? controllerOf(String id) {
    final existing = _controllers[id];
    if (existing != null) return existing;
    final doc = _workspace.documentById(id);
    if (doc == null) return null;
    final DocController? c = switch (doc.type) {
      DocType.er => ProjectController.forDoc(doc, this),
      DocType.dfd => DfdController.forDoc(doc, this),
      DocType.flowchart => FlowchartController.forDoc(doc, this),
      null => null,
    };
    if (c != null) _register(c);
    return c;
  }

  /// controller ของเอกสาร DFD [id] (null = ไม่ใช่เอกสาร DFD)
  DfdController? dfdController(String id) {
    final c = controllerOf(id);
    return c is DfdController ? c : null;
  }

  /// controller ของเอกสาร Flowchart [id] (null = ไม่ใช่เอกสาร Flowchart)
  FlowchartController? flowchartController(String id) {
    final c = controllerOf(id);
    return c is FlowchartController ? c : null;
  }

  ProjectController? erController(String id) {
    final c = controllerOf(id);
    return c is ProjectController ? c : null;
  }

  /// controller ที่ถูกสร้างไว้แล้ว (ไม่สร้างใหม่) — ใช้ในเทสต์
  bool hasController(String id) => _controllers.containsKey(id);

  void _register(DocController c) {
    _controllers[c.docId] = c;
    c.addListener(_onDocChanged);
  }

  void _unregister(String id) {
    final c = _controllers.remove(id);
    if (c == null) return;
    c.removeListener(_onDocChanged);
    if (!identical(c, _mainEr)) c.dispose();
  }

  void _onDocChanged() => notifyListeners();

  // ---------- เปิด / ใหม่ / กู้คืน / บันทึก ----------

  void newProject({double boardWidth = kDefaultBoardWidth, double boardHeight = kDefaultBoardHeight}) =>
      _replace(Workspace.single(Project(boardWidth: boardWidth, boardHeight: boardHeight)), null, dirty: false);

  /// เปิดโปรเจกต์ (เช่น จากไฟล์) — [w] ถูกใช้เป็นข้อมูลจริง (ไม่คัดลอก)
  void loadWorkspace(Workspace w, String? path) => _replace(w, path, dirty: false);

  /// เปิดโปรเจกต์ที่มีแต่ ER
  void loadProject(Project p, String? path) => _replace(Workspace.single(p), path, dirty: false);

  /// กู้คืนงานที่ auto-save ไว้ — ยังไม่ได้บันทึกลงไฟล์จริง จึงถือว่ายังมีการแก้ค้างอยู่
  void restoreWorkspace(Workspace w, String? originalPath) => _replace(w, originalPath, dirty: true);

  /// โปรเจกต์ที่ได้จากการ import .sql — ยังไม่มีไฟล์โปรเจกต์ จึงถือว่ายังไม่ได้บันทึก
  void loadImported(Project p) => _replace(Workspace.single(p), null, dirty: true);

  void markSaved(String path) {
    _filePath = path;
    _structureDirty = false;
    for (final c in _controllers.values) {
      c.markClean();
    }
    notifyListeners();
  }

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
    for (final id in List.of(_controllers.keys)) {
      _unregister(id);
    }
    _workspace = w;
    final er = _ensureEr(w);
    _mainEr.attach(er);
    _register(_mainEr);
    _filePath = path;
    _structureDirty = dirty;
    _resetTabs(er.id);
    notifyListeners();
  }

  void _resetTabs(String activeId) {
    _open
      ..clear()
      ..addAll([for (final d in _workspace.documents) if (d.type != null) d.id]);
    _lastErId = null;
    _setActive(activeId);
  }

  /// ตั้งแท็บที่ใช้งาน (จำ ER ล่าสุดไว้ให้ [currentEr])
  void _setActive(String id) {
    _activeId = id;
    _homeView = false;
    if (_workspace.documentById(id)?.type == DocType.er) _lastErId = id;
  }

  void _structureChanged() {
    _structureDirty = true;
    notifyListeners();
  }


  // ---------- เอกสาร ----------

  /// เอกสารทั้งหมดตามลำดับในไฟล์ (รวมชนิดที่โปรแกรมรุ่นนี้ไม่รู้จัก)
  List<ProjectDocument> get documents => _workspace.documents;

  ProjectDocument? documentById(String id) => _workspace.documentById(id);

  /// เนื้อหา DFD ของเอกสาร [id] — ไม่ใช่เอกสาร DFD/ไม่มีอยู่ = แผนภาพว่างชั่วคราว (ไม่ถูกเก็บในโปรเจกต์)
  DfdDiagram dfdOf(String id) => _workspace.documentById(id)?.dfd ?? DfdDiagram();

  /// เนื้อหา Flowchart ของเอกสาร [id] — ไม่ใช่ Flowchart/ไม่มีอยู่ = แผนภาพว่างชั่วคราว
  FlowchartDiagram flowchartOf(String id) => _workspace.documentById(id)?.flowchart ?? FlowchartDiagram();

  /// เพิ่มเอกสารใหม่ต่อท้าย (ER, DFD หรือ Flowchart) แล้วเปิดเป็นแท็บที่ใช้งาน — ชื่อซ้ำจะต่อเลขให้
  ///
  /// ER ใหม่: [er] = เนื้อหาตั้งต้น (null = ว่าง ใช้ dialect และขนาดกระดานเดียวกับ ER ที่ใช้งานอยู่)
  ProjectDocument? addDocument(DocType type, {String? name, String? folderId, Project? er}) {
    final base = cleanDiagramName(name ?? '');
    final folder = folderId != null && _workspace.folderById(folderId) != null ? folderId : null;
    final ProjectDocument doc;
    switch (type) {
      case DocType.er:
        final cur = currentEr.project;
        doc = ProjectDocument.er(
          id: newId('e'),
          name: _workspace.uniqueDocumentName(base.isEmpty ? 'ER' : base),
          content: er ??
              Project(
                name: _workspace.name,
                dialect: cur.dialect,
                boardWidth: cur.boardWidth,
                boardHeight: cur.boardHeight,
              ),
          folderId: folder,
        );
      case DocType.dfd:
        doc = ProjectDocument.dfd(
          id: newId('d'),
          name: _workspace.uniqueDocumentName(base.isEmpty ? 'DFD' : base),
          content: DfdDiagram(),
          folderId: folder,
        );
      case DocType.flowchart:
        doc = ProjectDocument.flowchart(
          id: newId('c'),
          name: _workspace.uniqueDocumentName(base.isEmpty ? 'Flowchart' : base),
          content: FlowchartDiagram(),
          folderId: folder,
        );
    }
    _workspace.documents.add(doc);
    _open.add(doc.id);
    _setActive(doc.id);
    _structureChanged();
    return doc;
  }

  /// เปลี่ยนชื่อเอกสาร — คืน false ถ้าชื่อว่าง/ซ้ำกับเอกสารอื่น (ไม่สนตัวพิมพ์)
  bool renameDocument(String id, String name) {
    final t = _workspace.documentById(id);
    final n = cleanDiagramName(name);
    if (t == null || n.isEmpty) return false;
    if (_workspace.documents.any((d) => d.id != id && d.name.toLowerCase() == n.toLowerCase())) return false;
    if (t.name == n) return true;
    t.name = n;
    _structureChanged();
    return true;
  }

  /// ทำสำเนาเอกสาร [id] (ER, DFD หรือ Flowchart: เนื้อหาเดียวกัน ชื่อใหม่ไม่ซ้ำ ประวัติ undo เริ่มใหม่) วางต่อจากต้นฉบับแล้วเปิด
  /// สำเนา ER ใช้ id ตาราง/คอลัมน์เดิม (id มีความหมายภายในเอกสารเท่านั้น) — ที่เก็บข้อมูลใน DFD ยังผูกกับต้นฉบับ
  ProjectDocument? duplicateDocument(String id) {
    final src = _workspace.documentById(id);
    if (src == null) return null;
    // เนื้อหาที่ยังไม่ได้ commit (ลากค้าง) ก็ติดไปด้วย — สำเนาผ่าน JSON ให้แยกขาดจากต้นฉบับ
    final ProjectDocument copy;
    switch (src.type) {
      case DocType.er:
        copy = ProjectDocument.er(
          id: newId('e'),
          name: _workspace.uniqueDocumentName(src.name),
          content: Project.fromContentJson(jsonDecode(jsonEncode(src.er!.toContentJson())) as Map<String, dynamic>),
          folderId: src.folderId,
        );
      case DocType.dfd:
        copy = ProjectDocument.dfd(
          id: newId('d'),
          name: _workspace.uniqueDocumentName(src.name),
          content: DfdDiagram.fromJson(jsonDecode(jsonEncode(src.dfd!.toJson())) as Map<String, dynamic>),
          folderId: src.folderId,
        );
      case DocType.flowchart:
        copy = ProjectDocument.flowchart(
          id: newId('c'),
          name: _workspace.uniqueDocumentName(src.name),
          content: FlowchartDiagram.fromJson(jsonDecode(jsonEncode(src.flowchart!.toJson()))),
          folderId: src.folderId,
        );
      case null:
        return null;
    }
    _workspace.documents.insert(_workspace.documents.indexOf(src) + 1, copy);
    _open.add(copy.id);
    _setActive(copy.id);
    _structureChanged();
    return copy;
  }

  /// การอ้างอิงจากเอกสารอื่นที่ชี้มาที่ [id] (จะใช้ไม่ได้ถ้าลบเอกสารนี้)
  List<(String fromDoc, String fromElement, DocRef ref)> backlinksOf(String id) => WorkspaceIndex(_workspace).backlinks(id);

  /// ลบเอกสาร [id] ได้หรือไม่ — โปรเจกต์ต้องเหลือเอกสาร ER อย่างน้อยหนึ่งอันเสมอ (ER อันสุดท้ายลบไม่ได้)
  bool canDeleteDocument(String id) {
    final doc = _workspace.documentById(id);
    if (doc == null) return false;
    return doc.type != DocType.er || _workspace.documentsOf(DocType.er).length > 1;
  }

  /// ลบเอกสาร (ไม่มีถังขยะ ย้อนด้วย undo ไม่ได้) — คืนรายการอ้างอิงจากเอกสารอื่นที่ใช้ไม่ได้แล้ว ; null = ลบไม่ได้
  /// (ดู [canDeleteDocument]) ; ถ้าเป็นแท็บที่เปิดอยู่ จะย้ายไปแท็บข้างเคียง ; controller ของเอกสารถูกทิ้ง
  /// ลิงก์ที่ขาด (เช่น ที่เก็บข้อมูลใน DFD ที่ผูกตารางของ ER นี้) ไม่ถูกลบ — ตัวตรวจจะแจ้งเป็นปัญหาให้แก้เอง
  List<(String fromDoc, String fromElement, DocRef ref)>? deleteDocument(String id) {
    if (!canDeleteDocument(id)) return null;
    final doc = _workspace.documentById(id)!;
    final broken = backlinksOf(id);
    final tabs = openTabIds;
    final i = tabs.indexOf(id);
    if (identical(doc, _mainEr.doc)) {
      // ER หลักถูกลบ: ER อันแรกที่เหลือขึ้นมาเป็นตัวหลัก (controller เดิมถูกทิ้งตอน _unregister)
      final next = _workspace.documentsOf(DocType.er).firstWhere((d) => d.id != id);
      _mainEr = erController(next.id)!;
    }
    _workspace.documents.remove(doc);
    _open.remove(id);
    _unregister(id);
    if (_lastErId == id) _lastErId = null;
    if (_activeId == id) {
      final rest = openTabIds;
      _setActive(rest.isEmpty ? _mainEr.docId : rest[(i > 0 ? i - 1 : 0).clamp(0, rest.length - 1)]);
    }
    _structureChanged();
    return broken;
  }

  /// ย้ายเอกสารไปตำแหน่ง [index] ในรายการเอกสารทั้งหมด และ/หรือเข้าโฟลเดอร์ ([changeFolder] = true ใช้ค่า [folderId] — null = ราก)
  bool moveDocument(String id, {int? index, String? folderId, bool changeFolder = false}) {
    final doc = _workspace.documentById(id);
    if (doc == null) return false;
    if (changeFolder && folderId != null && _workspace.folderById(folderId) == null) return false;
    var changed = false;
    if (changeFolder && doc.folderId != folderId) {
      doc.folderId = folderId;
      changed = true;
    }
    if (index != null) {
      final docs = _workspace.documents;
      final from = docs.indexOf(doc);
      final to = index.clamp(0, docs.length - 1);
      if (to != from) {
        docs.insert(to, docs.removeAt(from));
        changed = true;
      }
    }
    if (changed) _structureChanged();
    return true;
  }

  // ---------- โฟลเดอร์ ----------

  DocFolder addFolder(String name, {String? parentId}) {
    final f = DocFolder(
      id: newId('f'),
      name: cleanDiagramName(name),
      parentId: parentId != null && _workspace.folderById(parentId) != null ? parentId : null,
    );
    _workspace.folders.add(f);
    _structureChanged();
    return f;
  }

  bool renameFolder(String id, String name) {
    final f = _workspace.folderById(id);
    final n = cleanDiagramName(name);
    if (f == null || n.isEmpty) return false;
    if (f.name != n) {
      f.name = n;
      _structureChanged();
    }
    return true;
  }

  /// ลบโฟลเดอร์: เอกสารและโฟลเดอร์ย่อยข้างในย้ายขึ้นไปอยู่ที่โฟลเดอร์แม่ (ไม่ลบเอกสาร)
  bool deleteFolder(String id) {
    final f = _workspace.folderById(id);
    if (f == null) return false;
    for (final d in _workspace.documents) {
      if (d.folderId == id) d.folderId = f.parentId;
    }
    for (final sub in _workspace.folders) {
      if (sub.parentId == id) sub.parentId = f.parentId;
    }
    _workspace.folders.remove(f);
    _structureChanged();
    return true;
  }

  // ---------- แท็บ ----------

  /// id ของแท็บที่เปิดอยู่ตามลำดับ
  List<String> get openTabIds => [for (final d in tabDocuments) d.id];

  /// เอกสารที่แสดงเป็นแท็บ (เปิดอยู่และเป็นชนิดที่รู้จัก) ตามลำดับเอกสาร
  List<ProjectDocument> get tabDocuments =>
      [for (final d in _workspace.documents) if (d.type != null && _open.contains(d.id)) d];

  /// เอกสารที่ใช้งานอยู่ (ถ้าเอกสารนั้นหายไปจะกลับเป็น ER หลัก)
  ProjectDocument get activeDocument {
    final d = _workspace.documentById(_activeId);
    return d != null && d.type != null ? d : _mainEr.doc;
  }

  String get activeId => activeDocument.id;

  /// เปิดเอกสาร [id] เป็นแท็บที่ใช้งาน — คืน false ถ้าไม่มี/ชนิดที่ไม่รู้จัก
  bool openDocument(String id) {
    final d = _workspace.documentById(id);
    if (d == null || d.type == null) return false;
    if (_open.contains(id) && activeId == id) {
      showHome(false); // คลิกเอกสารที่ใช้งานอยู่แล้ว = กลับจากหน้า Project Home
      return true;
    }
    _open.add(id);
    _setActive(id);
    notifyListeners();
    return true;
  }

  /// ปิดแท็บ (เอกสารยังอยู่ในโปรเจกต์) — ถ้าเป็นแท็บที่ใช้งาน จะย้ายไปแท็บข้างเคียง
  void closeTab(String id) {
    final tabs = openTabIds;
    final i = tabs.indexOf(id);
    if (i < 0) return;
    final wasActive = activeId == id;
    _open.remove(id);
    if (wasActive) {
      final rest = openTabIds;
      _setActive(rest.isEmpty ? _mainEr.docId : rest[(i > 0 ? i - 1 : 0).clamp(0, rest.length - 1)]);
    }
    notifyListeners();
  }

  /// ย้ายแท็บไปตำแหน่ง [toIndex] (ตำแหน่งในรายการแท็บหลังเอาแท็บนั้นออกแล้ว) — ลำดับเอกสารในไฟล์เปลี่ยนตาม
  /// เอกสารที่ไม่มีแท็บคงตำแหน่งสัมพัทธ์เดิมในไฟล์
  void reorderTab(String id, int toIndex) {
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
    _structureChanged();
  }

  // ---------- เอกสารที่ใช้งานอยู่ ----------

  /// controller ของ ER ที่ใช้งานอยู่ (แท็บที่เปิดไม่ใช่ ER = ER ที่เปิดล่าสุด ; ไม่เคยเปิด = ER หลัก)
  ProjectController get currentEr {
    final d = activeDocument;
    final id = d.type == DocType.er ? d.id : _lastErId;
    return (id == null ? null : erController(id)) ?? _mainEr;
  }

  /// เอกสาร ER ที่มีตาราง [tableId] — ระบุ [docId] = ดูเฉพาะเอกสารนั้น ;
  /// ไม่ระบุ (ข้อมูลเก่าที่ไม่รู้เอกสาร) = ดู ER ที่ใช้งานอยู่ก่อน แล้วไล่ ER ทุกอันตามลำดับ
  ProjectDocument? erDocumentWithTable(String? docId, String tableId) {
    if (docId != null) {
      final d = _workspace.documentById(docId);
      return d?.er?.tableById(tableId) != null ? d : null;
    }
    final cur = currentEr.doc;
    if (cur.er?.tableById(tableId) != null) return cur;
    return _workspace.documentsOf(DocType.er).where((d) => d.er!.tableById(tableId) != null).firstOrNull;
  }

  /// ตัวแทนตอนเอกสารที่ใช้งานไม่ใช่ DFD (แผนภาพว่าง แก้ไขไม่ได้)
  late final DfdController _noDfd = DfdController.detached(this);

  /// controller ของ DFD ที่ใช้งานอยู่ (แท็บที่เปิดไม่ใช่ DFD = ตัวแทนที่ว่างและแก้ไขไม่ได้)
  DfdController get currentDfd {
    final d = activeDocument;
    return (d.type == DocType.dfd ? dfdController(d.id) : null) ?? _noDfd;
  }

  /// ตัวแทนตอนเอกสารที่ใช้งานไม่ใช่ Flowchart (แผนภาพว่าง แก้ไขไม่ได้)
  late final FlowchartController _noFlowchart = FlowchartController.detached(this);

  /// controller ของ Flowchart ที่ใช้งานอยู่ (แท็บที่เปิดไม่ใช่ Flowchart = ตัวแทนที่ว่างและแก้ไขไม่ได้)
  FlowchartController get currentFlowchart {
    final d = activeDocument;
    return (d.type == DocType.flowchart ? flowchartController(d.id) : null) ?? _noFlowchart;
  }

  /// controller ของเอกสารที่ใช้งานอยู่
  DocController get activeController => controllerOf(activeId) ?? _mainEr;

  bool get canUndo => activeController.canUndo;
  bool get canRedo => activeController.canRedo;
  void undo() => activeController.undo();
  void redo() => activeController.redo();

  @override
  void dispose() {
    for (final id in List.of(_controllers.keys)) {
      _unregister(id);
    }
    _mainEr.dispose();
    _noDfd.dispose();
    _noFlowchart.dispose();
    super.dispose();
  }
}
