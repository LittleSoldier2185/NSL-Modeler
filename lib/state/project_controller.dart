import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/clipboard/table_clipboard.dart';
import '../core/layout/auto_layout.dart';
import '../core/models/column_model.dart';
import '../core/models/enums.dart';
import '../core/models/index_model.dart';
import '../core/models/note_model.dart';
import '../core/models/project.dart';
import '../core/models/relation_model.dart';
import '../core/models/table_model.dart';
import '../core/validate/issue.dart';
import '../core/validate/validator.dart';

/// ถือโปรเจกต์ปัจจุบัน + selection + undo/redo (แบบ snapshot)
class ProjectController extends ChangeNotifier {
  ProjectController([Project? project]) : _project = project ?? Project();

  static const _maxHistory = 100;

  Project _project;
  String? _filePath;
  bool _dirty = false;
  String? _selectedTableId;
  String? _selectedColumnId;

  /// ตารางที่เลือกเพิ่มจากตัวหลัก [_selectedTableId] (เลือกหลายตารางด้วย Ctrl/Shift+คลิก หรือ Ctrl+A)
  final Set<String> _extra = {};

  final List<String> _undo = [];
  final List<String> _redo = [];
  String? _gestureBefore;
  int _idCounter = 0;

  Project get project => _project;
  String? get filePath => _filePath;
  bool get dirty => _dirty;
  String? get selectedTableId => _selectedTableId;
  String? get selectedColumnId => _selectedColumnId;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

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

  String _snapshot() => jsonEncode(_project.toJson());

  void _push(String snap) {
    _undo.add(snap);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  /// แก้ข้อมูลแบบมีประวัติ
  void _edit(void Function() change) {
    _push(_snapshot());
    change();
    _dirty = true;
    _issues = null;
    notifyListeners();
  }

  void _fixSelection() {
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

  void newProject() => _replace(Project(), null, dirty: false);

  void loadProject(Project p, String? path) => _replace(p, path, dirty: false);

  /// กู้คืนงานที่ auto-save ไว้ — ยังไม่ได้บันทึกลงไฟล์จริง จึงถือว่ายังมีการแก้ค้างอยู่
  void restoreProject(Project p, String? originalPath) => _replace(p, originalPath, dirty: true);

  /// โปรเจกต์ที่ได้จากการ import .sql — ยังไม่มีไฟล์ .erd จึงถือว่ายังไม่ได้บันทึก
  void loadImported(Project p) => _replace(p, null, dirty: true);

  void _replace(Project p, String? path, {required bool dirty}) {
    _project = p;
    _filePath = path;
    _dirty = dirty;
    _issues = null;
    _selectedTableId = null;
    _extra.clear();
    _selectedColumnId = null;
    _undo.clear();
    _redo.clear();
    _gestureBefore = null;
    notifyListeners();
  }

  void markSaved(String path) {
    _filePath = path;
    _dirty = false;
    notifyListeners();
  }

  // ---------- undo / redo ----------

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _project = Project.fromJson(jsonDecode(_undo.removeLast()) as Map<String, dynamic>);
    _dirty = true;
    _issues = null;
    _fixSelection();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _project = Project.fromJson(jsonDecode(_redo.removeLast()) as Map<String, dynamic>);
    _dirty = true;
    _issues = null;
    _fixSelection();
    notifyListeners();
  }

  // ---------- gesture (ลาก) : นับเป็น 1 ขั้น undo ----------

  void beginGesture() => _gestureBefore ??= _snapshot();

  void endGesture() {
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before != null && before != _snapshot()) {
      _push(before);
      _dirty = true;
      _issues = null;
      notifyListeners();
    }
  }

  // ---------- selection ----------

  void selectTable(String? id, {String? columnId}) {
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

  /// Ctrl+A
  void selectAllTables() {
    if (_project.tables.isEmpty) return;
    final keepPrimary = _selectedTableId != null && _project.tableById(_selectedTableId!) != null;
    _selectedTableId = keepPrimary ? _selectedTableId : _project.tables.first.id;
    _extra
      ..clear()
      ..addAll(_project.tables.map((t) => t.id).where((id) => id != _selectedTableId));
    if (!keepPrimary) _selectedColumnId = null;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedTableId == null && _extra.isEmpty) return;
    _selectedTableId = null;
    _selectedColumnId = null;
    _extra.clear();
    notifyListeners();
  }

  // ---------- โปรเจกต์ ----------

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
    final pos = autoLayout(_project);
    final moves = [
      for (final t in _project.tables)
        if (pos[t.id] != null && (pos[t.id]!.x != t.x || pos[t.id]!.y != t.y)) t,
    ];
    if (moves.isEmpty) return false;
    _edit(() {
      for (final t in moves) {
        t.x = pos[t.id]!.x;
        t.y = pos[t.id]!.y;
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

  /// ตำแหน่งตารางอยู่ในช่วง 0..19600 (world ของ canvas กว้าง 20000)
  static double _clampXY(double v) => v < 0 ? 0 : (v > 19600 ? 19600 : v);

  /// ย้ายตารางที่เลือกทั้งหมดแบบ live ระหว่างลาก — ครอบด้วย beginGesture/endGesture
  void moveSelectedBy(double dx, double dy) {
    for (final id in selectedTableIds) {
      final t = _project.tableById(id);
      if (t == null) continue;
      t.x = _clampXY(t.x + dx);
      t.y = _clampXY(t.y + dy);
    }
    notifyListeners();
  }

  /// ขยับตารางที่เลือกด้วยปุ่มลูกศร (undo หนึ่งขั้นต่อหนึ่งการกด) — คืน false ถ้าไม่มีอะไรเลือก/ขยับไม่ได้
  bool nudgeSelected(double dx, double dy) {
    final ts = [for (final id in selectedTableIds) if (_project.tableById(id) != null) _project.tableById(id)!];
    if (ts.isEmpty || ts.every((t) => _clampXY(t.x + dx) == t.x && _clampXY(t.y + dy) == t.y)) return false;
    _edit(() {
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
      for (final c in t.columns) {
        colMap[c.id] = c.id = newId('c');
      }
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
