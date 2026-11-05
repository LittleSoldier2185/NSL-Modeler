import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models/dfd_model.dart';
import '../core/models/diagram.dart';
import '../core/models/doc_ref.dart';
import '../core/models/project.dart';
import '../core/models/workspace.dart';
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

  /// controller ของเอกสาร ER หลัก — เป็น object เดิมตลอดอายุของ workspace controller
  /// (เปิดไฟล์ใหม่ = ผูกกับเอกสาร ER แรกของไฟล์ใหม่ ไม่สร้างใหม่)
  late final ProjectController _mainEr;

  /// docId -> controller (สร้างเมื่อเรียก [controllerOf] ครั้งแรก)
  final Map<String, DocController> _controllers = {};

  /// แท็บที่เปิดอยู่ (ลำดับแท็บ = ลำดับเอกสารในไฟล์)
  final Set<String> _open = {};
  String _activeId = kErDiagramId;

  Workspace get workspace => _workspace;
  String? get filePath => _filePath;

  /// มีการเปลี่ยนโครงสร้าง (เพิ่ม/ลบ/เปลี่ยนชื่อ/ย้ายเอกสาร) ที่ยังไม่บันทึก
  bool get structureDirty => _structureDirty;

  /// มีอะไรยังไม่บันทึก: โครงสร้าง หรือเนื้อหาของเอกสารใดเอกสารหนึ่ง
  bool get dirty => _structureDirty || _controllers.values.any((c) => c.docDirty);

  String newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}w${_idCounter++}';

  // ---------- controller ของเอกสาร ----------

  /// controller ของเอกสาร ER หลัก (เอกสาร ER แรกของโปรเจกต์ — ลบไม่ได้)
  ProjectController get mainEr => _mainEr;

  /// controller ของเอกสาร [id] (สร้างเมื่อใช้ครั้งแรก) ; null = ไม่มีเอกสารนี้หรือเป็นชนิดที่ไม่รู้จัก
  DocController? controllerOf(String id) {
    final existing = _controllers[id];
    if (existing != null) return existing;
    final doc = _workspace.documentById(id);
    if (doc == null) return null;
    final DocController? c = switch (doc.type) {
      DocType.er => ProjectController.forDoc(doc, this),
      DocType.dfd => null,
      null => null,
    };
    if (c != null) _register(c);
    return c;
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
    _activeId = activeId;
  }

  void _structureChanged() {
    _structureDirty = true;
    notifyListeners();
  }

  /// นับว่าโปรเจกต์มีการแก้ที่ยังไม่บันทึก (ไม่ได้ผ่าน controller ของเอกสาร)
  void markDirty() => _structureDirty = true;

  // ---------- เอกสาร ----------

  /// เอกสารทั้งหมดตามลำดับในไฟล์ (รวมชนิดที่โปรแกรมรุ่นนี้ไม่รู้จัก)
  List<ProjectDocument> get documents => _workspace.documents;

  ProjectDocument? documentById(String id) => _workspace.documentById(id);

  /// เนื้อหา DFD ของเอกสาร [id] — ไม่ใช่เอกสาร DFD/ไม่มีอยู่ = แผนภาพว่างชั่วคราว (ไม่ถูกเก็บในโปรเจกต์)
  DfdDiagram dfdOf(String id) => _workspace.documentById(id)?.dfd ?? DfdDiagram();

  /// เพิ่มเอกสารใหม่ต่อท้าย (ตอนนี้เพิ่มได้เฉพาะ DFD) แล้วเปิดเป็นแท็บที่ใช้งาน — ชื่อซ้ำจะต่อเลขให้
  ProjectDocument? addDocument(DocType type, {String? name, String? folderId}) {
    if (type != DocType.dfd) return null;
    final base = cleanDiagramName(name ?? '');
    final doc = ProjectDocument.dfd(
      id: newId('d'),
      name: _workspace.uniqueDocumentName(base.isEmpty ? 'DFD' : base),
      content: DfdDiagram(),
      folderId: folderId != null && _workspace.folderById(folderId) != null ? folderId : null,
    );
    _workspace.documents.add(doc);
    _open.add(doc.id);
    _activeId = doc.id;
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

  /// ทำสำเนาเอกสาร [id] (เนื้อหาเดียวกัน ชื่อใหม่ไม่ซ้ำ) วางต่อจากต้นฉบับแล้วเปิด — เอกสาร ER ทำสำเนาไม่ได้ (มีได้อันเดียว)
  ProjectDocument? duplicateDocument(String id) {
    final src = _workspace.documentById(id);
    if (src == null || src.type != DocType.dfd) return null;
    // เนื้อหาที่ยังไม่ได้ commit (ลากค้าง) ก็ติดไปด้วย — สำเนาผ่าน JSON ให้แยกขาดจากต้นฉบับ
    final content = DfdDiagram.fromJson(jsonDecode(jsonEncode(src.dfd!.toJson())) as Map<String, dynamic>);
    final copy = ProjectDocument.dfd(
      id: newId('d'),
      name: _workspace.uniqueDocumentName(src.name),
      content: content,
      folderId: src.folderId,
    );
    _workspace.documents.insert(_workspace.documents.indexOf(src) + 1, copy);
    _open.add(copy.id);
    _activeId = copy.id;
    _structureChanged();
    return copy;
  }

  /// การอ้างอิงจากเอกสารอื่นที่ชี้มาที่ [id] (จะใช้ไม่ได้ถ้าลบเอกสารนี้)
  List<(String fromDoc, String fromElement, DocRef ref)> backlinksOf(String id) => WorkspaceIndex(_workspace).backlinks(id);

  /// ลบเอกสาร (ลบเอกสาร ER หลักไม่ได้) — คืนรายการอ้างอิงจากเอกสารอื่นที่ใช้ไม่ได้แล้ว ; null = ลบไม่ได้
  /// ถ้าเป็นแท็บที่เปิดอยู่ จะย้ายไปแท็บข้างเคียง ; controller ของเอกสารถูกทิ้ง
  List<(String fromDoc, String fromElement, DocRef ref)>? deleteDocument(String id) {
    final doc = _workspace.documentById(id);
    if (doc == null || identical(doc, _mainEr.doc) || doc.type == DocType.er) return null;
    final broken = backlinksOf(id);
    final tabs = openTabIds;
    final i = tabs.indexOf(id);
    _workspace.documents.remove(doc);
    _open.remove(id);
    _unregister(id);
    if (_activeId == id) {
      final rest = openTabIds;
      _activeId = rest.isEmpty ? _mainEr.docId : rest[(i > 0 ? i - 1 : 0).clamp(0, rest.length - 1)];
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
    if (_open.contains(id) && activeId == id) return true;
    _open.add(id);
    _activeId = id;
    notifyListeners();
    return true;
  }

  /// ปิดแท็บ (เอกสารยังอยู่ในโปรเจกต์) — ถ้าเป็นแท็บที่ใช้งาน จะย้ายไปแท็บข้างเคียง
  void closeTab(String id) {
    final tabs = openTabIds;
    final i = tabs.indexOf(id);
    if (i < 0) return;
    _open.remove(id);
    if (activeId == id) {
      final rest = openTabIds;
      _activeId = rest.isEmpty ? _mainEr.docId : rest[(i > 0 ? i - 1 : 0).clamp(0, rest.length - 1)];
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

  /// controller ของ ER ที่ใช้งานอยู่ (แท็บที่เปิดไม่ใช่ ER = ER หลัก)
  ProjectController get currentEr {
    final d = activeDocument;
    return (d.type == DocType.er ? erController(d.id) : null) ?? _mainEr;
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
    super.dispose();
  }
}
