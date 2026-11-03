import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';
import '../types/type_map.dart';
import 'issue.dart';
import 'naming.dart';
import 'reserved_words.dart';

/// ตรวจ schema ตาม dialect ที่เลือกในโปรเจกต์ — เรียงผลลัพธ์ error -> warning -> info
List<Issue> validateProject(Project p) => _Validator(p).run();

class _Validator {
  _Validator(this.p) : d = p.dialect;

  final Project p;
  final Dialect d;
  final List<Issue> out = [];

  List<Issue> run() {
    _tables();
    _tableNumberConsistency();
    _relations();
    _indexes();
    if (d == Dialect.mssql) _mssqlCascadePaths();

    // เรียงแบบคงลำดับเดิมภายในระดับเดียวกัน
    final bySeverity = {for (final s in Severity.values) s: <Issue>[]};
    for (final i in out) {
      bySeverity[i.severity]!.add(i);
    }
    return [for (final s in Severity.values) ...bySeverity[s]!];
  }

  void add(Severity s, String code, String title, String message,
      {String? table, String? column, String? relation}) {
    out.add(Issue(
      severity: s,
      code: code,
      title: title,
      message: message,
      tableId: table,
      columnId: column,
      relationId: relation,
    ));
  }

  void err(String code, String title, String msg, {String? table, String? column, String? relation}) =>
      add(Severity.error, code, title, msg, table: table, column: column, relation: relation);
  void warn(String code, String title, String msg, {String? table, String? column, String? relation}) =>
      add(Severity.warning, code, title, msg, table: table, column: column, relation: relation);
  void info(String code, String title, String msg, {String? table, String? column, String? relation}) =>
      add(Severity.info, code, title, msg, table: table, column: column, relation: relation);

  // ---------- ตาราง / คอลัมน์ ----------

  void _tables() {
    final seen = <String, TableModel>{};
    for (final t in p.tables) {
      final label = t.name.isEmpty ? '(ไม่มีชื่อ)' : t.name;
      _checkName(t.name, 'ตาราง', t.id, null, label);

      final key = t.name.toLowerCase();
      if (key.isNotEmpty) {
        if (seen.containsKey(key)) {
          err('dup_table', 'ชื่อตารางซ้ำ', 'มีตารางชื่อ "$label" มากกว่าหนึ่งตาราง', table: t.id);
        }
        seen.putIfAbsent(key, () => t);
      }

      if (t.columns.isEmpty) {
        err('no_columns', 'ตารางไม่มีคอลัมน์', '$label ไม่มีคอลัมน์ จึงไม่ถูกสร้างใน SQL', table: t.id);
        continue;
      }
      if (!t.columns.any((c) => c.isPrimaryKey)) {
        warn('no_pk', 'ไม่มี Primary Key', '$label ยังไม่มีคอลัมน์ที่เป็น PK', table: t.id);
      }

      final names = <String>{};
      var aiCount = 0;
      for (final c in t.columns) {
        final cl = '$label.${c.name.isEmpty ? '(ไม่มีชื่อ)' : c.name}';
        _checkName(c.name, 'คอลัมน์', t.id, c.id, cl);
        if (c.name.isNotEmpty && !names.add(c.name.toLowerCase())) {
          err('dup_column', 'ชื่อคอลัมน์ซ้ำ', '$cl ซ้ำกับคอลัมน์อื่นในตารางเดียวกัน',
              table: t.id, column: c.id);
        }
        _checkType(t, c, cl);
        if (c.autoIncrement) {
          aiCount++;
          _checkAutoIncrement(t, c, cl);
        }
        _checkDefault(t, c, cl);
      }
      if (aiCount > 1 && (d == Dialect.mysql || d == Dialect.mssql || d == Dialect.sqlite)) {
        err('ai_multiple', 'AUTO INCREMENT หลายคอลัมน์',
            '$label มีคอลัมน์ AUTO INCREMENT $aiCount คอลัมน์ แต่ ${d.label} ใช้ได้ตารางละ 1 คอลัมน์',
            table: t.id);
      }
    }
  }

  void _checkName(String name, String kind, String tableId, String? columnId, String label) {
    if (name.trim().isEmpty) {
      err('empty_name', 'ชื่อ$kindว่าง', 'มี$kindที่ยังไม่ได้ตั้งชื่อ', table: tableId, column: columnId);
      return;
    }
    final max = maxIdentifierLength(d);
    if (max != null && name.length > max) {
      err('name_too_long', 'ชื่อ$kindยาวเกินไป',
          '$label ยาว ${name.length} ตัวอักษร (${d.label} จำกัด $max)',
          table: tableId, column: columnId);
    }
    if (isReservedWord(name, d)) {
      warn('reserved_word', 'ชื่อชนกับ reserved word',
          '"$name" เป็นคำสงวนของ SQL — ระบบ quote ให้แล้ว แต่ควรเลี่ยงเพื่อกันปัญหาตอนเขียนคำสั่งเอง',
          table: tableId, column: columnId);
    }
    // รูปแบบการตั้งชื่อ: แนะนำ snake_case (ข้ามชื่อภาษาไทย/อักขระนอก ASCII ซึ่งแปลงไม่ได้)
    if (!hasNonAscii(name) && styleOf(name) != NameStyle.snake) {
      final fix = toSnakeCase(name);
      info('naming_style', 'ชื่อไม่เป็น snake_case',
          '$label${fix.isEmpty || fix == name ? '' : ' → แนะนำ "$fix"'} (รูปแบบ ${_styleLabel(styleOf(name))})',
          table: tableId, column: columnId);
    }
  }

  static String _styleLabel(NameStyle s) => switch (s) {
        NameStyle.upperSnake => 'ตัวพิมพ์ใหญ่',
        NameStyle.camel => 'camelCase',
        NameStyle.pascal => 'PascalCase',
        NameStyle.kebab => 'มีขีดกลาง',
        NameStyle.spaced => 'มีช่องว่าง',
        _ => 'อื่น ๆ',
      };

  /// ตารางส่วนใหญ่ใช้พหูพจน์ (users) หรือเอกพจน์ (user) แต่บางตารางไม่ตรง
  void _tableNumberConsistency() {
    final named = p.tables.where((t) => t.name.isNotEmpty && !hasNonAscii(t.name)).toList();
    if (named.length < 3) return;
    final plural = named.where((t) => looksPlural(t.name)).toList();
    final singular = named.where((t) => !looksPlural(t.name)).toList();
    final minority = plural.length >= singular.length ? singular : plural;
    final majorityIsPlural = plural.length >= singular.length;
    // เสียงข้างมากต้องชัด (>= 2/3) จึงจะเตือน เพื่อไม่ให้รบกวนกรณีที่ครึ่งต่อครึ่ง
    final majority = majorityIsPlural ? plural.length : singular.length;
    if (majority * 3 < named.length * 2 || minority.isEmpty) return;
    for (final t in minority) {
      info('naming_number', 'ชื่อตารางไม่สม่ำเสมอ',
          '${t.name} เป็น${majorityIsPlural ? 'เอกพจน์' : 'พหูพจน์'} แต่ตารางอื่นส่วนใหญ่ใช้${majorityIsPlural ? 'พหูพจน์' : 'เอกพจน์'}',
          table: t.id);
    }
  }

  void _checkType(TableModel t, ColumnModel c, String label) {
    if (c.type == DataType.varchar) {
      final n = c.length ?? 255;
      if (n <= 0) {
        err('bad_length', 'ความยาวไม่ถูกต้อง', '$label: VARCHAR ต้องยาวอย่างน้อย 1',
            table: t.id, column: c.id);
      } else if (d == Dialect.mssql && n > 4000) {
        err('bad_length', 'ความยาวเกินขีดจำกัด',
            '$label: NVARCHAR($n) เกิน 4000 — ใช้ชนิด TEXT (NVARCHAR(MAX)) แทน',
            table: t.id, column: c.id);
      } else if (d == Dialect.mysql && n > 16383) {
        err('bad_length', 'ความยาวเกินขีดจำกัด',
            '$label: VARCHAR($n) เกิน 16383 (utf8mb4) — ใช้ชนิด TEXT แทน',
            table: t.id, column: c.id);
      }
    }
    if (c.type == DataType.decimal) {
      final prec = c.length ?? 10;
      final scale = c.scale ?? 2;
      final maxPrec = switch (d) {
        Dialect.mysql => 65,
        Dialect.postgres => 1000,
        Dialect.mssql => 38,
        Dialect.sqlite => 1000,
      };
      if (prec < 1 || prec > maxPrec) {
        err('bad_precision', 'Precision ไม่ถูกต้อง',
            '$label: DECIMAL($prec,$scale) — ${d.label} รองรับ precision 1–$maxPrec',
            table: t.id, column: c.id);
      } else if (scale < 0 || scale > prec) {
        err('bad_precision', 'Scale ไม่ถูกต้อง',
            '$label: DECIMAL($prec,$scale) — scale ต้องอยู่ระหว่าง 0 ถึง precision',
            table: t.id, column: c.id);
      }
    }
  }

  void _checkAutoIncrement(TableModel t, ColumnModel c, String label) {
    if (!isIntegerType(c.type)) {
      err('ai_type', 'AUTO INCREMENT ใช้กับชนิดนี้ไม่ได้',
          '$label ต้องเป็นชนิดจำนวนเต็ม (INT/BIGINT/SMALLINT)',
          table: t.id, column: c.id);
      return;
    }
    if (c.defaultValue != null && c.defaultValue!.trim().isNotEmpty) {
      warn('ai_default', 'ค่าเริ่มต้นจะถูกข้าม', '$label เป็น AUTO INCREMENT จึงไม่ใส่ DEFAULT ใน SQL',
          table: t.id, column: c.id);
    }
    if (d == Dialect.mysql && !_isKeyColumn(t, c)) {
      err('ai_key', 'AUTO INCREMENT ต้องเป็น key',
          '$label: MySQL บังคับให้คอลัมน์ AUTO_INCREMENT เป็น PK, UNIQUE หรืออยู่ใน INDEX',
          table: t.id, column: c.id);
    }
    if (d == Dialect.sqlite) {
      final pk = t.columns.where((x) => x.isPrimaryKey).toList();
      if (!(pk.length == 1 && pk.first.id == c.id)) {
        warn('ai_ignored', 'AUTOINCREMENT จะถูกข้าม',
            '$label: SQLite ใช้ AUTOINCREMENT ได้เฉพาะ PK คอลัมน์เดียวเท่านั้น',
            table: t.id, column: c.id);
      }
    }
  }

  void _checkDefault(TableModel t, ColumnModel c, String label) {
    final v = c.defaultValue?.trim();
    if (v == null || v.isEmpty || c.autoIncrement) return;
    final isFunc = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\(.*\)$').hasMatch(v) ||
        v.toUpperCase().startsWith('CURRENT_');
    final numeric = isIntegerType(c.type) || c.type == DataType.decimal || c.type == DataType.float;
    if (numeric &&
        !isFunc &&
        v.toUpperCase() != 'NULL' &&
        !RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(v)) {
      err('bad_default', 'ค่าเริ่มต้นไม่ตรงกับชนิด', '$label: "$v" ไม่ใช่ตัวเลข',
          table: t.id, column: c.id);
    }
    if (c.type == DataType.boolean &&
        !const {'TRUE', 'FALSE', '0', '1', 'NULL'}.contains(v.toUpperCase())) {
      err('bad_default', 'ค่าเริ่มต้นไม่ตรงกับชนิด', '$label: BOOLEAN ใช้ได้เฉพาะ true / false / 0 / 1',
          table: t.id, column: c.id);
    }
    if (d == Dialect.mysql &&
        (c.type == DataType.text || c.type == DataType.blob || c.type == DataType.json) &&
        !isFunc &&
        v.toUpperCase() != 'NULL') {
      err('mysql_blob_default', 'ค่าเริ่มต้นใช้ไม่ได้',
          '$label: MySQL ไม่ให้ DEFAULT ค่าคงที่กับ TEXT/BLOB/JSON',
          table: t.id, column: c.id);
    }
  }

  // ---------- ความสัมพันธ์ ----------

  void _relations() {
    for (final r in p.relations) {
      final child = p.tableById(r.fromTableId);
      final parent = p.tableById(r.toTableId);
      final cc = child?.columnById(r.fromColumnId);
      final pc = parent?.columnById(r.toColumnId);
      if (child == null || parent == null || cc == null || pc == null) {
        err('fk_dangling', 'FK ชี้ไปที่ไม่มีอยู่',
            'ความสัมพันธ์นี้อ้างถึงตารางหรือคอลัมน์ที่ถูกลบไปแล้ว — จะถูกข้ามตอน Export',
            table: child?.id ?? parent?.id, relation: r.id);
        continue;
      }
      final from = '${child.name}.${cc.name}';
      final to = '${parent.name}.${pc.name}';

      if (cc.type != pc.type) {
        warn('fk_type_mismatch', 'ชนิดข้อมูลไม่ตรงกัน',
            '$from (${cc.type.name.toUpperCase()}) ≠ $to (${pc.type.name.toUpperCase()})',
            table: child.id, column: cc.id, relation: r.id);
      }

      if (!_isUniqueColumn(parent, pc)) {
        final msg = '$to ไม่ใช่ PK/UNIQUE จึงถูกอ้างถึงด้วย FK ไม่ได้';
        if (d == Dialect.mysql) {
          warn('fk_target_not_unique', 'FK ชี้คอลัมน์ที่ไม่ unique',
              '$msg (MySQL ยอมถ้ามี INDEX แต่ไม่แนะนำ)',
              table: child.id, column: cc.id, relation: r.id);
        } else {
          err('fk_target_not_unique', 'FK ชี้คอลัมน์ที่ไม่ unique', msg,
              table: child.id, column: cc.id, relation: r.id);
        }
      }

      if ((r.onDelete == RefAction.setNull || r.onUpdate == RefAction.setNull) &&
          (cc.notNull || cc.isPrimaryKey)) {
        err('fk_set_null_notnull', 'SET NULL กับคอลัมน์ NOT NULL',
            '$from เป็น NOT NULL/PK แต่ตั้ง ON DELETE/UPDATE เป็น SET NULL',
            table: child.id, column: cc.id, relation: r.id);
      }

      if (!_isIndexedFirst(child, cc)) {
        info('fk_no_index', 'คำแนะนำ', '$from ยังไม่มี INDEX — การ JOIN และลบแถวแม่จะช้าเมื่อข้อมูลเยอะ',
            table: child.id, column: cc.id, relation: r.id);
      }
    }
  }

  // ---------- index ----------

  void _indexes() {
    final global = <String, TableModel>{};
    for (final t in p.tables) {
      final local = <String>{};
      for (final i in t.indexes) {
        if (i.name.trim().isEmpty) {
          err('empty_name', 'ชื่อ INDEX ว่าง', 'ตาราง ${t.name} มี INDEX ที่ยังไม่ได้ตั้งชื่อ', table: t.id);
          continue;
        }
        if (i.columnIds.isEmpty || i.columnIds.any((id) => t.columnById(id) == null)) {
          err('index_missing_column', 'INDEX อ้างคอลัมน์ที่ไม่มี',
              '${i.name} บนตาราง ${t.name} ไม่มีคอลัมน์ที่ใช้ได้ — จะถูกข้ามตอน Export',
              table: t.id);
        }
        final key = i.name.toLowerCase();
        final perSchema = d == Dialect.postgres || d == Dialect.sqlite;
        final dup = perSchema ? global.containsKey(key) : !local.add(key);
        if (dup) {
          err('dup_index', 'ชื่อ INDEX ซ้ำ',
              perSchema
                  ? '"${i.name}" ซ้ำกับ INDEX อื่น (${d.label} บังคับชื่อไม่ซ้ำทั้งฐานข้อมูล)'
                  : '"${i.name}" ซ้ำในตาราง ${t.name}',
              table: t.id);
        }
        global.putIfAbsent(key, () => t);
        final max = maxIdentifierLength(d);
        if (max != null && i.name.length > max) {
          err('name_too_long', 'ชื่อ INDEX ยาวเกินไป', '${i.name} ยาวเกิน $max ตัวอักษร', table: t.id);
        }
      }
    }
  }

  // ---------- SQL Server: multiple cascade paths ----------

  /// SQL Server ปฏิเสธ FK แบบ CASCADE/SET NULL ที่ทำให้ลบแล้วลามถึงตารางเดียวกันได้หลายทาง หรือวนเป็นวง
  void _mssqlCascadePaths() {
    final edges = <String, List<RelationModel>>{}; // parent -> relations ที่ลามลงไป
    for (final r in p.relations) {
      if (r.onDelete == RefAction.noAction && r.onUpdate == RefAction.noAction) continue;
      if (p.tableById(r.fromTableId) == null || p.tableById(r.toTableId) == null) continue;
      edges.putIfAbsent(r.toTableId, () => []).add(r);
    }
    final flagged = <String>{};
    var budget = 20000; // กันกราฟหนาแน่นจนช้า

    void walk(String node, Set<String> stack, Map<String, int> arrivals) {
      for (final r in edges[node] ?? const <RelationModel>[]) {
        if (--budget < 0) return;
        final next = r.fromTableId;
        if (stack.contains(next)) {
          flagged.add(r.id); // วนกลับมาที่ตารางที่อยู่ในเส้นทางเดียวกัน
          continue;
        }
        final n = (arrivals[next] = (arrivals[next] ?? 0) + 1);
        if (n > 1) flagged.add(r.id);
        stack.add(next);
        walk(next, stack, arrivals);
        stack.remove(next);
      }
    }

    for (final start in edges.keys) {
      walk(start, {start}, {});
    }
    for (final id in flagged) {
      final r = p.relations.firstWhere((x) => x.id == id);
      final child = p.tableById(r.fromTableId)!;
      final parent = p.tableById(r.toTableId)!;
      err('mssql_cascade_paths', 'Multiple cascade paths',
          'FK ${child.name} → ${parent.name} อาจทำให้ลบ/แก้แล้วลามถึงตารางเดียวกันหลายทางหรือวนเป็นวง '
          '— SQL Server จะ error ให้เปลี่ยน ON DELETE/UPDATE เป็น NO ACTION อย่างน้อยหนึ่งเส้น',
          table: child.id, column: r.fromColumnId, relation: r.id);
    }
  }

  // ---------- ตัวช่วย ----------

  /// คอลัมน์เดี่ยวที่ถูกการันตีว่าไม่ซ้ำ (PK เดี่ยว / UNIQUE / unique index คอลัมน์เดียว)
  bool _isUniqueColumn(TableModel t, ColumnModel c) {
    final pk = t.columns.where((x) => x.isPrimaryKey).toList();
    if (pk.length == 1 && pk.first.id == c.id) return true;
    if (c.unique) return true;
    return t.indexes.any((i) => i.unique && i.columnIds.length == 1 && i.columnIds.first == c.id);
  }

  /// เป็น PK / UNIQUE / อยู่ใน INDEX ใด ๆ (ใช้กับกฎ AUTO_INCREMENT ของ MySQL)
  bool _isKeyColumn(TableModel t, ColumnModel c) =>
      c.isPrimaryKey || c.unique || t.indexes.any((i) => i.columnIds.contains(c.id));

  /// ค้นหาด้วยคอลัมน์นี้ได้เร็ว: เป็นคอลัมน์แรกของ PK/index หรือ UNIQUE
  bool _isIndexedFirst(TableModel t, ColumnModel c) {
    if (c.unique) return true;
    final pk = t.columns.where((x) => x.isPrimaryKey).toList();
    if (pk.isNotEmpty && pk.first.id == c.id) return true;
    return t.indexes.any((i) => i.columnIds.isNotEmpty && i.columnIds.first == c.id);
  }
}
