import '../export/seed_data.dart';
import '../models/project.dart';
import '../models/table_model.dart';

/// ความต่างของข้อมูลตั้งต้นหนึ่งตารางระหว่างโปรเจกต์เก่ากับใหม่
///
/// หลักความปลอดภัยของ migration: เพิ่มได้เฉพาะ "แถวใหม่" ([added]) แบบรันซ้ำได้ ไม่แตะแถวเดิมในฐานข้อมูล
/// แถวที่แก้ค่า ([changed]) หรือถูกลบ ([removed]) จะไม่ถูกสร้างเป็น UPDATE/DELETE ให้ — แจ้งเตือนให้ทำเอง
class SeedTableDelta {
  const SeedTableDelta(this.table, this.added, this.changed, this.removed);
  final TableModel table;
  final List<Map<String, String?>> added;
  final int changed;
  final int removed;

  bool get any => added.isNotEmpty || changed > 0 || removed > 0;
}

/// เทียบข้อมูลตั้งต้นของตารางที่จับคู่กันแล้ว ([tableMap]: id ตารางเก่า -> id ตารางใหม่)
/// จับคู่แถวด้วยค่า Primary Key (ตามชื่อคอลัมน์ ไม่ใช่ id จึงใช้ได้แม้ไฟล์เก่ามาจากการ import); ไม่มี PK = เทียบทั้งแถว
List<SeedTableDelta> computeSeedDelta(Project old, Project neu, Map<String, String> tableMap) {
  final rev = {for (final e in tableMap.entries) e.value: e.key};
  final out = <SeedTableDelta>[];

  for (final t in neu.tables) {
    final o = rev[t.id] == null ? null : old.tableById(rev[t.id]!);
    if (o == null) {
      // ตารางใหม่: ทุกแถวเป็นแถวใหม่
      if (t.seedRows.isNotEmpty) out.add(SeedTableDelta(t, [for (final r in t.seedRows) Map.of(r)], 0, 0));
      continue;
    }
    if (t.seedRows.isEmpty && o.seedRows.isEmpty) continue;

    final pkNames = [for (final c in t.columns) if (c.isPrimaryKey) c.name.toLowerCase()]..sort();
    final keyNames = pkNames.isNotEmpty ? pkNames : ([for (final c in t.columns) c.name.toLowerCase()]..sort());

    /// ค่ามาตรฐานของแถวตามชื่อคอลัมน์ (ชื่อพิมพ์เล็ก)
    Map<String, String?> byName(TableModel tb, Map<String, String?> row) => {
          for (final c in tb.columns)
            if (row.containsKey(c.id)) c.name.toLowerCase(): seedNormalized(c, row[c.id]),
        };
    String? keyOf(Map<String, String?> named) {
      final parts = <String>[];
      for (final k in keyNames) {
        if (!named.containsKey(k) || named[k] == null) return null;
        parts.add(named[k]!);
      }
      return parts.join('\u0001');
    }

    final oldRows = <String, Map<String, String?>>{};
    for (final r in o.seedRows) {
      final named = byName(o, r);
      final k = keyOf(named);
      if (k != null) oldRows[k] = named;
    }

    final added = <Map<String, String?>>[];
    var changed = 0;
    final seen = <String>{};
    for (final r in t.seedRows) {
      final named = byName(t, r);
      final k = keyOf(named);
      if (k == null) {
        // ไม่ระบุค่า key (เช่น PK เป็น AUTO INCREMENT ที่ไม่ได้ใส่ค่า): ระบุตัวตนของแถวไม่ได้ จึงถือเป็นแถวใหม่เสมอ
        // (seedInsertSql โหมดรันซ้ำได้จะข้ามแถวแบบนี้พร้อมคอมเมนต์เตือน ไม่ปล่อยให้เกิดแถวซ้ำ)
        added.add(Map.of(r));
        continue;
      }
      seen.add(k);
      final before = oldRows[k];
      if (before == null) {
        added.add(Map.of(r));
      } else if (named.entries.any((e) => !before.containsKey(e.key) || before[e.key] != e.value)) {
        changed++;
      }
    }
    final removed = oldRows.keys.where((k) => !seen.contains(k)).length;
    final d = SeedTableDelta(t, added, changed, removed);
    if (d.any) out.add(d);
  }
  return out;
}
