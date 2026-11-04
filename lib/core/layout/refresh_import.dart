import 'dart:math' as math;

import '../models/column_model.dart';
import '../models/index_model.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';

/// อัปเดตแผนภาพ [current] ให้ตรงกับโครงสร้างที่อ่านมาใหม่ [imported] (จากฐานข้อมูลหรือไฟล์ .sql)
/// โดย "คงงานจัดวางของผู้ใช้ไว้":
/// - จับคู่ตาราง/คอลัมน์ด้วยชื่อ (ไม่สนตัวพิมพ์) → ตารางเดิมคง id ตำแหน่ง ขนาด สี ฟอนต์ ข้อมูลตั้งต้น ; คอลัมน์เดิมคง id
/// - ตัวคอลัมน์ ชนิด คีย์ INDEX ใช้ตามฐานข้อมูลทั้งหมด
/// - ตารางใหม่ในฐานข้อมูลถูกวางต่อจากแผนภาพเดิม (ไม่ทับของเดิม)
/// - ตารางที่แผนภาพมีแต่ฐานข้อมูลไม่มี : เก็บไว้ (ถือเป็นตารางที่ออกแบบไว้แต่ยังไม่ได้สร้าง) เว้นแต่ [removeMissing]
/// - FK: ที่ตรงกับฐานข้อมูลคงสี/ชื่อเดิม ที่ไม่มีในฐานข้อมูลถูกตัด (เฉพาะระหว่างตารางที่ฐานข้อมูลมี) ที่ใหม่ถูกเพิ่ม
/// - โน้ต กลุ่ม แท็บ DFD ขนาดกระดาน คงเดิม ; [current] ไม่ถูกแก้ (คืนโปรเจกต์ใหม่)
/// [newId] สร้าง id ใหม่ที่ไม่ซ้ำ (ใช้ `ProjectController.newId`)
Project refreshFromImport(
  Project current,
  Project imported, {
  required String Function(String prefix) newId,
  bool removeMissing = false,
}) {
  final cur = Project.fromJson(current.toJson()); // สำเนา ไม่แตะของเดิม
  String k(String s) => s.toLowerCase();

  final curByName = {for (final t in cur.tables) k(t.name): t};
  final impByName = {for (final t in imported.tables) k(t.name): t};

  // id (ในฝั่ง imported) -> id ในผลลัพธ์ ; ระดับตารางและคอลัมน์
  final tableMap = <String, String>{};
  final colMap = <String, String>{}; // key = importedTableId/importedColId
  String ck(String tableId, String colId) => '$tableId/$colId';

  final usedIds = <String>{for (final t in cur.tables) t.id};
  String fresh(String prefix) {
    var id = newId(prefix);
    while (!usedIds.add(id)) {
      id = newId(prefix);
    }
    return id;
  }

  final newTables = <TableModel>[];
  for (final it in imported.tables) {
    final old = curByName[k(it.name)];
    if (old == null) {
      final t = TableModel.fromJson(it.toJson());
      final id = fresh('t');
      tableMap[it.id] = id;
      t.id = id;
      for (final c in t.columns) {
        final nid = fresh('c');
        colMap[ck(it.id, c.id)] = nid;
        c.id = nid;
      }
      newTables.add(t);
      continue;
    }
    tableMap[it.id] = old.id;
    final oldCols = {for (final c in old.columns) k(c.name): c};
    final cols = <ColumnModel>[];
    for (final ic in it.columns) {
      final oc = oldCols[k(ic.name)];
      final c = ColumnModel.fromJson(ic.toJson());
      if (oc != null) {
        c.id = oc.id;
      } else {
        c.id = fresh('c');
      }
      colMap[ck(it.id, ic.id)] = c.id;
      cols.add(c);
    }
    // ข้อมูลตั้งต้นของคอลัมน์ที่ยังอยู่ ไม่หาย
    final keepIds = {for (final c in cols) c.id};
    final seed = [
      for (final r in old.seedRows)
        {for (final e in r.entries) if (keepIds.contains(e.key)) e.key: e.value},
    ]..removeWhere((r) => r.isEmpty);
    final indexes = [
      for (final ix in it.indexes)
        IndexModel(
          id: fresh('i'),
          name: ix.name,
          columnIds: [for (final cid in ix.columnIds) if (colMap[ck(it.id, cid)] != null) colMap[ck(it.id, cid)]!],
          unique: ix.unique,
        ),
    ]..removeWhere((ix) => ix.columnIds.isEmpty);
    old
      ..name = it.name
      ..columns = cols
      ..indexes = indexes
      ..comment = it.comment
      ..seedRows = seed;
  }

  // คงลำดับตารางเดิม (ลำดับมีผลต่อ SQL ที่สร้าง) ; ตารางที่มีแต่ในแผนภาพเก็บไว้เว้นแต่สั่งลบ
  final result = [
    for (final t in cur.tables)
      if (impByName.containsKey(k(t.name)) || !removeMissing) t,
  ];

  // ตำแหน่งตารางใหม่ : ต่อจากขอบขวาของของเดิม จัดเป็นแถวห่อบรรทัด โดยคงการจัดวางสัมพัทธ์ที่ตัวนำเข้าคำนวณไว้
  if (newTables.isNotEmpty) {
    final existing = result;
    var right = 0.0, top = double.infinity;
    for (final t in existing) {
      right = math.max(right, t.x + t.width);
      top = math.min(top, t.y);
    }
    final hasExisting = existing.isNotEmpty;
    final minX = newTables.map((t) => t.x).reduce(math.min);
    final minY = newTables.map((t) => t.y).reduce(math.min);
    final dx = hasExisting ? right + 120 - minX : 0.0;
    final dy = hasExisting ? top - minY : 0.0;
    for (final t in newTables) {
      t.x += dx;
      t.y += dy;
    }
    result.addAll(newTables);
  }
  cur.tables = result;

  // ---- FK ----
  final inDb = {for (final t in imported.tables) k(t.name)}; // ชื่อตารางที่ฐานข้อมูลมี
  bool dbKnows(String tableId) {
    final t = cur.tableById(tableId);
    return t != null && inDb.contains(k(t.name));
  }

  String keyOf(String f, String fc, String t, String tc) => '$f/$fc>$t/$tc';
  final impKeys = <String>{};
  final impByKey = <String, RelationModel>{};
  for (final r in imported.relations) {
    final f = tableMap[r.fromTableId], fc = colMap[ck(r.fromTableId, r.fromColumnId)];
    final t = tableMap[r.toTableId], tc = colMap[ck(r.toTableId, r.toColumnId)];
    if (f == null || fc == null || t == null || tc == null) continue;
    final key = keyOf(f, fc, t, tc);
    impKeys.add(key);
    impByKey[key] = r;
  }
  final kept = <RelationModel>[];
  final seen = <String>{};
  for (final r in cur.relations) {
    final key = keyOf(r.fromTableId, r.fromColumnId, r.toTableId, r.toColumnId);
    final from = cur.tableById(r.fromTableId), to = cur.tableById(r.toTableId);
    final colsOk = from?.columnById(r.fromColumnId) != null && to?.columnById(r.toColumnId) != null;
    if (!colsOk) continue; // คอลัมน์ที่อ้างถึงหายไปจากฐานข้อมูล
    if (impKeys.contains(key)) {
      final db = impByKey[key]!;
      // ค่าตามฐานข้อมูล (การกระทำ ON DELETE/UPDATE) แต่คงสี/ชื่อที่ผู้ใช้ตั้งไว้
      r
        ..onDelete = db.onDelete
        ..onUpdate = db.onUpdate;
      kept.add(r);
      seen.add(key);
    } else if (!(dbKnows(r.fromTableId) && dbKnows(r.toTableId))) {
      kept.add(r); // เกี่ยวกับตารางที่ฐานข้อมูลไม่มี → ของที่ออกแบบไว้ล่วงหน้า
    }
    // อีกกรณี : ทั้งสองตารางมีในฐานข้อมูลแต่ฐานข้อมูลไม่มี FK นี้ → ตัดทิ้งให้ตรงความจริง
  }
  for (final r in imported.relations) {
    final f = tableMap[r.fromTableId], fc = colMap[ck(r.fromTableId, r.fromColumnId)];
    final t = tableMap[r.toTableId], tc = colMap[ck(r.toTableId, r.toColumnId)];
    if (f == null || fc == null || t == null || tc == null) continue;
    final key = keyOf(f, fc, t, tc);
    if (seen.contains(key)) continue;
    seen.add(key);
    kept.add(RelationModel(
      id: fresh('r'),
      fromTableId: f,
      fromColumnId: fc,
      toTableId: t,
      toColumnId: tc,
      onDelete: r.onDelete,
      onUpdate: r.onUpdate,
      name: r.name,
    ));
  }
  cur.relations = kept;
  return cur;
}
