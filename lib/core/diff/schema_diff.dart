import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/index_model.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';

/// การเปลี่ยนของคอลัมน์หนึ่งตัว (จับคู่ old/new ได้แล้ว)
class ColumnChange {
  ColumnChange(this.old, this.neu);
  final ColumnModel old;
  final ColumnModel neu;

  bool get renamed => old.name != neu.name;
  bool get typeChanged => _typeKey(old) != _typeKey(neu);
  bool get nullChanged => _notNull(old) != _notNull(neu);
  bool get defaultChanged => _def(old) != _def(neu);
  bool get autoIncrementChanged => old.autoIncrement != neu.autoIncrement;
  bool get uniqueChanged => _unique(old) != _unique(neu);
  bool get commentChanged => old.comment != neu.comment;

  /// ต้อง ALTER ตัวคอลัมน์ (ไม่นับชื่อ / unique ซึ่งเป็นคนละคำสั่ง)
  bool get definitionChanged =>
      typeChanged || nullChanged || defaultChanged || autoIncrementChanged || commentChanged;

  bool get any => renamed || definitionChanged || uniqueChanged;

  static bool _notNull(ColumnModel c) => c.notNull || c.isPrimaryKey;
  static bool _unique(ColumnModel c) => c.unique && !c.isPrimaryKey;
  static String _def(ColumnModel c) => (c.defaultValue ?? '').trim();

  /// ชนิดที่มีผลจริง (VARCHAR ไม่ระบุ = 255, DECIMAL ไม่ระบุ = 10,2)
  static String _typeKey(ColumnModel c) => switch (c.type) {
        DataType.varchar => 'varchar(${c.length ?? 255})',
        DataType.decimal => 'decimal(${c.length ?? 10},${c.scale ?? 2})',
        _ => c.type.name,
      };

  /// คำอธิบายชนิดแบบอ่านง่าย เช่น "VARCHAR(255)"
  static String typeText(ColumnModel c) => _typeKey(c).toUpperCase();
}

class TableDiff {
  TableDiff(this.old, this.neu);
  final TableModel old;
  final TableModel neu;

  /// คอลัมน์ที่จับคู่ได้ (old -> new) รวมที่ไม่เปลี่ยนอะไร
  final matched = <ColumnModel, ColumnModel>{};
  final addedColumns = <ColumnModel>[];
  final droppedColumns = <ColumnModel>[];
  final changedColumns = <ColumnChange>[];
  final addedIndexes = <IndexModel>[];
  final droppedIndexes = <IndexModel>[];
  bool pkChanged = false;

  bool get renamed => old.name != neu.name;
  bool get commentChanged => old.comment != neu.comment;

  bool get hasChanges =>
      renamed ||
      commentChanged ||
      pkChanged ||
      addedColumns.isNotEmpty ||
      droppedColumns.isNotEmpty ||
      changedColumns.isNotEmpty ||
      addedIndexes.isNotEmpty ||
      droppedIndexes.isNotEmpty;
}

enum ChangeKind { add, drop, change }

/// บรรทัดสรุปการเปลี่ยนแปลงสำหรับแสดงผู้ใช้
class ChangeLine {
  const ChangeLine(this.kind, this.text, {this.destructive = false});
  final ChangeKind kind;
  final String text;

  /// ทำให้ข้อมูลหายหรือเสี่ยงหาย (ลบตาราง/คอลัมน์, เปลี่ยนชนิด)
  final bool destructive;
}

class SchemaDiff {
  final addedTables = <TableModel>[];
  final droppedTables = <TableModel>[];
  final modified = <TableDiff>[];
  final addedRelations = <RelationModel>[];
  final droppedRelations = <RelationModel>[];

  /// id ตารางเก่า -> id ตารางใหม่ (เฉพาะที่จับคู่ได้)
  final tableMap = <String, String>{};

  bool get isEmpty =>
      addedTables.isEmpty &&
      droppedTables.isEmpty &&
      modified.isEmpty &&
      addedRelations.isEmpty &&
      droppedRelations.isEmpty;

  /// สรุปเป็นบรรทัด ๆ เรียงตามประเภท
  List<ChangeLine> summary(Project old, Project neu) {
    final out = <ChangeLine>[];
    String fk(Project p, RelationModel r) {
      final c = p.tableById(r.fromTableId), pa = p.tableById(r.toTableId);
      return '${c?.name}.${c?.columnById(r.fromColumnId)?.name} → ${pa?.name}.${pa?.columnById(r.toColumnId)?.name}';
    }

    for (final t in droppedTables) {
      out.add(ChangeLine(ChangeKind.drop, 'ลบตาราง ${t.name}', destructive: true));
    }
    for (final t in addedTables) {
      out.add(ChangeLine(ChangeKind.add, 'เพิ่มตาราง ${t.name} (${t.columns.length} คอลัมน์)'));
    }
    for (final d in modified) {
      final n = d.neu.name;
      if (d.renamed) out.add(ChangeLine(ChangeKind.change, 'เปลี่ยนชื่อตาราง ${d.old.name} → $n'));
      if (d.commentChanged) out.add(ChangeLine(ChangeKind.change, '$n: แก้หมายเหตุตาราง'));
      for (final c in d.droppedColumns) {
        out.add(ChangeLine(ChangeKind.drop, '$n: ลบคอลัมน์ ${c.name}', destructive: true));
      }
      for (final c in d.addedColumns) {
        out.add(ChangeLine(ChangeKind.add, '$n: เพิ่มคอลัมน์ ${c.name} ${ColumnChange.typeText(c)}'));
      }
      for (final c in d.changedColumns) {
        if (c.renamed) out.add(ChangeLine(ChangeKind.change, '$n: เปลี่ยนชื่อคอลัมน์ ${c.old.name} → ${c.neu.name}'));
        final col = '$n.${c.neu.name}';
        if (c.typeChanged) {
          out.add(ChangeLine(ChangeKind.change,
              '$col: ชนิด ${ColumnChange.typeText(c.old)} → ${ColumnChange.typeText(c.neu)}',
              destructive: true));
        }
        if (c.nullChanged) {
          out.add(ChangeLine(ChangeKind.change, '$col: ${c.neu.notNull || c.neu.isPrimaryKey ? 'เป็น NOT NULL' : 'อนุญาต NULL'}'));
        }
        if (c.defaultChanged) {
          out.add(ChangeLine(ChangeKind.change,
              '$col: ค่าเริ่มต้น ${c.old.defaultValue ?? '(ไม่มี)'} → ${c.neu.defaultValue ?? '(ไม่มี)'}'));
        }
        if (c.autoIncrementChanged) {
          out.add(ChangeLine(ChangeKind.change, '$col: ${c.neu.autoIncrement ? 'เปิด' : 'ปิด'} AUTO INCREMENT'));
        }
        if (c.uniqueChanged) {
          out.add(ChangeLine(ChangeKind.change, '$col: ${c.neu.unique ? 'เพิ่ม' : 'เอา'} UNIQUE'));
        }
        if (c.commentChanged) out.add(ChangeLine(ChangeKind.change, '$col: แก้หมายเหตุ'));
      }
      if (d.pkChanged) out.add(ChangeLine(ChangeKind.change, '$n: เปลี่ยน Primary Key'));
      for (final i in d.droppedIndexes) {
        out.add(ChangeLine(ChangeKind.drop, '$n: ลบ INDEX ${i.name}'));
      }
      for (final i in d.addedIndexes) {
        out.add(ChangeLine(ChangeKind.add, '$n: เพิ่ม ${i.unique ? 'UNIQUE ' : ''}INDEX ${i.name}'));
      }
    }
    for (final r in droppedRelations) {
      out.add(ChangeLine(ChangeKind.drop, 'ลบ FK ${fk(old, r)}'));
    }
    for (final r in addedRelations) {
      out.add(ChangeLine(ChangeKind.add, 'เพิ่ม FK ${fk(neu, r)}'));
    }
    return out;
  }
}

/// เปรียบเทียบ [old] กับ [neu] — จับคู่ด้วย id ก่อน แล้วค่อยจับคู่ด้วยชื่อสำหรับที่เหลือ
/// (id ไม่ตรงเมื่อเทียบกับโปรเจกต์ที่ import มา)
SchemaDiff diffProjects(Project old, Project neu) {
  final diff = SchemaDiff();

  // ---- จับคู่ตาราง ----
  final pairs = <TableModel, TableModel>{}; // old -> new
  final usedNew = <TableModel>{};
  for (final o in old.tables) {
    final n = neu.tableById(o.id);
    if (n != null) {
      pairs[o] = n;
      usedNew.add(n);
    }
  }
  for (final o in old.tables.where((t) => !pairs.containsKey(t))) {
    final n = neu.tables.where((t) => !usedNew.contains(t) && t.name.toLowerCase() == o.name.toLowerCase());
    if (n.isNotEmpty) {
      pairs[o] = n.first;
      usedNew.add(n.first);
    }
  }
  diff.droppedTables.addAll(old.tables.where((t) => !pairs.containsKey(t)));
  diff.addedTables.addAll(neu.tables.where((t) => !usedNew.contains(t)));
  for (final e in pairs.entries) {
    diff.tableMap[e.key.id] = e.value.id;
  }

  // ---- คอลัมน์ / index ต่อตาราง ----
  final colMap = <String, String>{}; // old col id -> new col id (ทุกตาราง)
  for (final e in pairs.entries) {
    final td = TableDiff(e.key, e.value);
    final cp = _matchColumns(e.key, e.value);
    td.matched.addAll(cp);
    for (final c in cp.entries) {
      colMap[c.key.id] = c.value.id;
    }
    td.droppedColumns.addAll(e.key.columns.where((c) => !cp.containsKey(c)));
    td.addedColumns.addAll(e.value.columns.where((c) => !cp.containsValue(c)));
    for (final c in cp.entries) {
      final ch = ColumnChange(c.key, c.value);
      if (ch.any) td.changedColumns.add(ch);
    }
    td.pkChanged = _pkKey(e.key, (id) => colMap[id] ?? id) != _pkKey(e.value, (id) => id);
    _diffIndexes(td, colMap);
    if (td.hasChanges) diff.modified.add(td);
  }

  // ---- ความสัมพันธ์ FK ----
  String key(RelationModel r, {required bool isOld}) {
    String t(String id) => isOld ? (diff.tableMap[id] ?? 'x:$id') : id;
    String c(String id) => isOld ? (colMap[id] ?? 'x:$id') : id;
    return '${t(r.fromTableId)}.${c(r.fromColumnId)}>${t(r.toTableId)}.${c(r.toColumnId)}';
  }

  final newByKey = {for (final r in neu.relations) key(r, isOld: false): r};
  final seen = <String>{};
  for (final r in old.relations) {
    final k = key(r, isOld: true);
    final n = newByKey[k];
    seen.add(k);
    if (n == null) {
      diff.droppedRelations.add(r);
    } else if (n.onDelete != r.onDelete || n.onUpdate != r.onUpdate) {
      // action เปลี่ยน = ลบแล้วสร้างใหม่
      diff.droppedRelations.add(r);
      diff.addedRelations.add(n);
    }
  }
  for (final e in newByKey.entries) {
    if (!seen.contains(e.key)) diff.addedRelations.add(e.value);
  }
  return diff;
}

Map<ColumnModel, ColumnModel> _matchColumns(TableModel o, TableModel n) {
  final out = <ColumnModel, ColumnModel>{};
  final used = <ColumnModel>{};
  for (final c in o.columns) {
    final m = n.columnById(c.id);
    if (m != null) {
      out[c] = m;
      used.add(m);
    }
  }
  for (final c in o.columns.where((c) => !out.containsKey(c))) {
    final m = n.columns.where((x) => !used.contains(x) && x.name.toLowerCase() == c.name.toLowerCase());
    if (m.isNotEmpty) {
      out[c] = m.first;
      used.add(m.first);
    }
  }
  return out;
}

String _pkKey(TableModel t, String Function(String) mapId) =>
    t.columns.where((c) => c.isPrimaryKey).map((c) => mapId(c.id)).join(',');

void _diffIndexes(TableDiff td, Map<String, String> colMap) {
  String sig(IndexModel i, {required bool isOld}) {
    final cols = i.columnIds.map((id) => isOld ? (colMap[id] ?? 'x:$id') : id).join(',');
    return '${i.name.toLowerCase()}|$cols|${i.unique}';
  }

  final newSigs = {for (final i in td.neu.indexes) sig(i, isOld: false): i};
  final oldSigs = {for (final i in td.old.indexes) sig(i, isOld: true): i};
  for (final e in oldSigs.entries) {
    if (!newSigs.containsKey(e.key)) td.droppedIndexes.add(e.value);
  }
  for (final e in newSigs.entries) {
    if (!oldSigs.containsKey(e.key)) td.addedIndexes.add(e.value);
  }
}
