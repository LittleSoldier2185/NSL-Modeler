import '../models/enums.dart';

/// คอลัมน์ของตารางในฐานข้อมูลจริง
class DbColumn {
  const DbColumn(this.name, this.type, {this.isPk = false, this.notNull = false, this.autoIncrement = false});
  final String name;
  final String type;
  final bool isPk;
  final bool notNull;
  final bool autoIncrement;

  /// ชนิดไบนารี : แสดงเป็น [BLOB] และแก้จากกริดไม่ได้
  bool get isBinary {
    final t = type.toLowerCase();
    return t.contains('blob') || t.contains('binary');
  }
}

/// โครงสร้างตารางที่ใช้เปิดดู/แก้ข้อมูล
class DbTable {
  const DbTable(this.name, this.columns, this.keyColumns, {this.usesRowid = false});
  final String name;
  final List<DbColumn> columns;

  /// คอลัมน์ที่ใช้ระบุแถวตอนแก้/ลบ : คีย์หลัก ; ไม่มีคีย์หลักใน SQLite ใช้ `rowid` ([usesRowid]) ; ว่าง = แก้/ลบไม่ได้ (ดูอย่างเดียว)
  final List<String> keyColumns;
  final bool usesRowid;

  /// แก้/ลบแถวได้ (มีวิธีระบุแถวได้แน่นอน)
  bool get canEditRows => keyColumns.isNotEmpty;
  DbColumn? column(String name) => columns.where((c) => c.name == name).firstOrNull;
}

/// หนึ่งแถวที่อ่านมา : [cells] ตามลำดับ [DbTable.columns] , [key] = ค่าที่ระบุแถวนี้ (ว่างถ้าแก้ไม่ได้) ; null = NULL
class DbRow {
  const DbRow(this.cells, this.key);
  final List<String?> cells;
  final Map<String, String?> key;
}

class DbPage {
  const DbPage(this.rows, this.total);
  final List<DbRow> rows;

  /// จำนวนแถวทั้งหมดที่ตรงเงื่อนไขค้นหา (ไม่ใช่เฉพาะหน้านี้)
  final int total;
}

/// การแก้ไขแถวที่ผู้ใช้ "เตรียมไว้" ก่อนกดบันทึก (ค่า null = NULL)
sealed class RowEdit {
  const RowEdit();
}

class RowInsert extends RowEdit {
  const RowInsert(this.values);

  /// คอลัมน์ที่ไม่ระบุ = ให้ฐานข้อมูลใส่ค่าเริ่มต้น/AUTO INCREMENT เอง
  final Map<String, String?> values;
}

class RowUpdate extends RowEdit {
  const RowUpdate(this.key, this.changes);
  final Map<String, String?> key;
  final Map<String, String?> changes;
}

class RowDelete extends RowEdit {
  const RowDelete(this.key);
  final Map<String, String?> key;
}

/// ผลการบันทึกการแก้ไข
class ApplyResult {
  const ApplyResult(this.statements, {this.backupPath});
  final int statements;

  /// ไฟล์สำรองที่สร้างก่อนเขียน (SQLite) ; null = ไม่มี
  final String? backupPath;
}

/// เซสชันเปิดดู/แก้ข้อมูลของฐานข้อมูลจริง (ต่างจาก DbSession ที่อ่านโครงสร้างอย่างเดียว)
abstract class DataSession {
  Dialect get dialect;

  /// เปิดให้เขียนได้ ; false = อ่านอย่างเดียวจริง (ตัวเชื่อมต่อปฏิเสธการเขียนเอง ไม่ใช่แค่ซ่อนปุ่ม)
  bool get writable;

  Future<List<String>> tableNames();
  Future<DbTable> table(String name);

  Future<DbPage> fetch(
    DbTable table, {
    int offset = 0,
    int limit = 100,
    String? orderBy,
    bool descending = false,
    String search = '',
  });

  /// บันทึกทั้งชุดในทรานแซกชันเดียว : ผิดพลาดข้อเดียว = ยกเลิกทั้งหมด ; แต่ละคำสั่งแก้/ลบต้องกระทบ 1 แถวพอดี
  Future<ApplyResult> apply(DbTable table, List<RowEdit> edits);

  Future<void> close();
}

/// คำสั่ง SQL พร้อมค่า (ใช้ ? เป็นตัวแทนค่า ไม่เอาค่าไปต่อในข้อความ SQL)
class SqlStmt {
  const SqlStmt(this.sql, this.params);
  final String sql;
  final List<String?> params;

  /// ข้อความสำหรับแสดงให้ผู้ใช้ดูก่อนบันทึก (แทนค่าเข้าไป ใช้แสดงเท่านั้น ไม่ใช้รัน)
  String preview() {
    var i = 0;
    return sql.replaceAllMapped(RegExp(r'\?'), (_) {
      if (i >= params.length) return '?';
      final v = params[i++];
      return v == null ? 'NULL' : "'${v.replaceAll("'", "''")}'";
    });
  }
}

String quoteIdent(Dialect d, String name) =>
    d == Dialect.mysql ? '`${name.replaceAll('`', '``')}`' : '"${name.replaceAll('"', '""')}"';

class DataSqlException implements Exception {
  DataSqlException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// สร้างคำสั่งของการแก้ไขหนึ่งรายการ : ตรวจว่าชื่อคอลัมน์มีอยู่จริงในตาราง , แก้/ลบต้องมีคีย์ครบ , ไม่แก้ชนิดไบนารี
SqlStmt buildEditStatement(Dialect d, DbTable t, RowEdit e) {
  String q(String n) => quoteIdent(d, n);
  void need(String col, {bool forWrite = true}) {
    final c = t.column(col);
    if (c == null) throw DataSqlException('ไม่พบคอลัมน์ $col');
    if (forWrite && c.isBinary) throw DataSqlException('คอลัมน์ $col เป็นข้อมูลไบนารี แก้จากตารางนี้ไม่ได้');
  }

  String where(Map<String, String?> key) => _keyWhere(d, t, key);
  List<String?> keyParams(Map<String, String?> key) => _keyParams(t, key);

  switch (e) {
    case RowInsert(:final values):
      for (final c in values.keys) {
        need(c);
      }
      if (values.isEmpty) {
        return SqlStmt(d == Dialect.mysql ? 'INSERT INTO ${q(t.name)} () VALUES ()' : 'INSERT INTO ${q(t.name)} DEFAULT VALUES', const []);
      }
      final cols = values.keys.toList();
      return SqlStmt(
        'INSERT INTO ${q(t.name)} (${cols.map(q).join(', ')}) VALUES (${cols.map((_) => '?').join(', ')})',
        [for (final c in cols) values[c]],
      );
    case RowUpdate(:final key, :final changes):
      if (changes.isEmpty) throw DataSqlException('ไม่มีค่าที่เปลี่ยน');
      for (final c in changes.keys) {
        need(c);
      }
      final cols = changes.keys.toList();
      return SqlStmt(
        'UPDATE ${q(t.name)} SET ${cols.map((c) => '${q(c)} = ?').join(', ')} WHERE ${where(key)}',
        [for (final c in cols) changes[c], ...keyParams(key)],
      );
    case RowDelete(:final key):
      return SqlStmt('DELETE FROM ${q(t.name)} WHERE ${where(key)}', keyParams(key));
  }
}

String _keyWhere(Dialect d, DbTable t, Map<String, String?> key) {
  if (!t.canEditRows) throw DataSqlException('ตาราง ${t.name} ไม่มีคีย์หลัก จึงแก้/ลบแถวไม่ได้');
  final cols = t.keyColumns.toSet();
  if (key.length != cols.length || !key.keys.every(cols.contains)) {
    throw DataSqlException('ต้องระบุคีย์ให้ครบ: ${t.keyColumns.join(', ')}');
  }
  return t.keyColumns.map((k) => key[k] == null ? '${quoteIdent(d, k)} IS NULL' : '${quoteIdent(d, k)} = ?').join(' AND ');
}

List<String?> _keyParams(DbTable t, Map<String, String?> key) => [for (final k in t.keyColumns) if (key[k] != null) key[k]];

/// คำสั่งตรวจว่าแถวตามคีย์ยังมีอยู่ (ใช้ก่อนแก้/ลบ เพื่อไม่พึ่งจำนวนแถวที่ถูกกระทบ ซึ่งบางไดรเวอร์รายงานไม่ตรง)
SqlStmt buildKeyCheck(Dialect d, DbTable t, Map<String, String?> key) =>
    SqlStmt('SELECT 1 FROM ${quoteIdent(d, t.name)} WHERE ${_keyWhere(d, t, key)}', _keyParams(t, key));

/// เงื่อนไขค้นหา "มีข้อความนี้ในคอลัมน์ใดคอลัมน์หนึ่ง" : คืน (ข้อความ WHERE, ค่า) ; ค้นหาว่าง = ไม่มีเงื่อนไข
({String where, List<String> params}) buildSearch(Dialect d, DbTable t, String search) {
  final s = search.trim();
  if (s.isEmpty) return (where: '', params: const []);
  final esc = s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  final cols = t.columns.where((c) => !c.isBinary).toList();
  if (cols.isEmpty) return (where: '', params: const []);
  final escape = d == Dialect.mysql ? r"ESCAPE '\\'" : r"ESCAPE '\'";
  final cast = d == Dialect.mysql ? 'CHAR' : 'TEXT';
  return (
    where: ' WHERE ${cols.map((c) => 'CAST(${quoteIdent(d, c.name)} AS $cast) LIKE ? $escape').join(' OR ')}',
    params: [for (final _ in cols) '%$esc%'],
  );
}
