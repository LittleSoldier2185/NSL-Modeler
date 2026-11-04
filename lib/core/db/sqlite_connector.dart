import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import '../parser/sql_importer.dart';
import 'db_session.dart';
import 'mysql_reader.dart' show DbReadResult;

/// เปิดไฟล์ SQLite แบบ "อ่านอย่างเดียว" : เปิดด้วยโหมด read-only ของไลบรารี (ไฟล์ไม่ถูกแก้แม้โปรแกรมพลาด)
/// + `PRAGMA query_only = ON` + ครอบด้วย [ReadOnlySession] ที่ปฏิเสธทุกคำสั่งที่ไม่ใช่ SELECT/EXPLAIN
/// ชื่อไฟล์เก็บใน [DbConfig.database]
class SqliteConnector implements DbConnector {
  const SqliteConnector();

  @override
  Future<DbSession> connect(DbConfig config) async {
    final path = config.database;
    if (path.trim().isEmpty) throw DbException(tr('กรอกที่อยู่ไฟล์ SQLite'));
    if (!File(path).existsSync()) throw DbException(tr('ไม่พบไฟล์ {0}', [path]));
    late final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw DbException(tr('เปิดไฟล์ไม่ได้: {0}', [e.message]));
    }
    try {
      db.execute('PRAGMA query_only = ON');
      db.select('SELECT count(*) FROM sqlite_master'); // ไม่ใช่ไฟล์ฐานข้อมูล -> error ตรงนี้
    } on SqliteException catch (e) {
      db.close();
      throw DbException(tr('ไม่ใช่ไฟล์ฐานข้อมูล SQLite: {0}', [e.message]));
    }
    return ReadOnlySession(_SqliteSession(db));
  }
}

class _SqliteSession implements DbSession {
  _SqliteSession(this._db);
  final Database _db;

  @override
  Future<List<Map<String, String?>>> query(String sql) async {
    try {
      final rs = _db.select(sql);
      return [
        for (final row in rs) {for (final c in rs.columnNames) c: row[c]?.toString()},
      ];
    } on SqliteException catch (e) {
      throw DbException(tr('คำสั่งผิดพลาด: {0}', [e.message]));
    }
  }

  @override
  Future<void> close() async => _db.close();
}

/// อ่านโครงสร้างจากไฟล์ SQLite : CREATE TABLE / CREATE INDEX ที่เก็บไว้ใน `sqlite_master` (ไม่รวม VIEW/TRIGGER และตารางภายใน)
/// แล้วนำเข้าด้วย [importSql] เหมือนนำเข้าไฟล์ .sql จึงได้คอลัมน์/ชนิด/คีย์/FK/ดัชนีเดียวกัน
Future<DbReadResult> readSqliteSchema(DbSession session, {required String name, void Function(int done, int total)? onProgress}) async {
  final s = session is ReadOnlySession ? session : ReadOnlySession(session);
  final rows = await s.query(
    "SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL AND substr(name, 1, 7) <> 'sqlite_' "
    "AND type IN ('table', 'index') ORDER BY type DESC, lower(name)",
  );
  final ddl = StringBuffer();
  var tables = 0;
  for (var i = 0; i < rows.length; i++) {
    final sql = rows[i]['sql'];
    if (sql == null || sql.trim().isEmpty) continue;
    if (rows[i]['type'] == 'table') tables++;
    ddl
      ..write(sql.trimRight())
      ..writeln(';')
      ..writeln();
    onProgress?.call(i + 1, rows.length);
  }
  final text = ddl.toString();
  return DbReadResult(text, tables, importSql(text, name: name.isEmpty ? 'database' : name, dialect: Dialect.sqlite));
}
