import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import 'data_access.dart';
import 'db_session.dart';
import 'sqlite_apply.dart' show sqliteBackupPath;

/// เปิดดู/แก้ข้อมูลในไฟล์ SQLite จริง
/// - [writable] = false : เปิดด้วยโหมด read-only ของไลบรารี + `PRAGMA query_only` (เขียนไม่ได้จริง)
/// - [writable] = true : เขียนได้ แต่ [apply] สำรองไฟล์เป็น `.bak-วันเวลา` ก่อนเขียนครั้งแรกของเซสชัน และรันในทรานแซกชันเสมอ
class SqliteDataSession implements DataSession {
  SqliteDataSession._(this._db, this.path, this.writable);

  final Database _db;
  final String path;

  @override
  final bool writable;

  String? _backup;

  @override
  Dialect get dialect => Dialect.sqlite;

  static SqliteDataSession open(String path, {bool writable = false}) {
    if (path.trim().isEmpty) throw DbException(tr('กรอกที่อยู่ไฟล์ SQLite'));
    if (!File(path).existsSync()) throw DbException(tr('ไม่พบไฟล์ {0}', [path]));
    late final Database db;
    try {
      db = sqlite3.open(path, mode: writable ? OpenMode.readWrite : OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw DbException(tr('เปิดไฟล์ไม่ได้: {0}', [e.message]));
    }
    try {
      if (!writable) db.execute('PRAGMA query_only = ON');
      db.execute('PRAGMA foreign_keys = ON'); // ให้ฐานข้อมูลปฏิเสธการแก้ที่ผิดกฎ FK แทนที่จะปล่อยผ่านเงียบ ๆ
      db.select('SELECT count(*) FROM sqlite_master');
    } on SqliteException catch (e) {
      db.close();
      throw DbException(tr('ไม่ใช่ไฟล์ฐานข้อมูล SQLite: {0}', [e.message]));
    }
    return SqliteDataSession._(db, path, writable);
  }

  String _q(String n) => quoteIdent(Dialect.sqlite, n);

  String? _text(Object? v) => switch (v) {
        null => null,
        Uint8List b => '[BLOB ${b.length} bytes]',
        _ => v.toString(),
      };

  @override
  Future<List<String>> tableNames() async => [
        for (final r in _db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND substr(name, 1, 7) <> 'sqlite_' ORDER BY lower(name)",
        ))
          r['name'] as String,
      ];

  @override
  Future<DbTable> table(String name) async {
    final info = _db.select('PRAGMA table_info(${_q(name)})');
    if (info.isEmpty) throw DbException(tr('ไม่พบตาราง {0}', [name]));
    final sql = _db.select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [name]).firstOrNull?['sql'] as String? ?? '';
    final withoutRowid = RegExp(r'\)\s*WITHOUT\s+ROWID\s*;?\s*$', caseSensitive: false).hasMatch(sql.trim());
    final pks = [
      for (final r in info)
        if ((r['pk'] as int) > 0) (r['pk'] as int, r['name'] as String),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final autoInc = sql.toUpperCase().contains('AUTOINCREMENT');
    final cols = [
      for (final r in info)
        DbColumn(
          r['name'] as String,
          (r['type'] as String?) ?? '',
          isPk: (r['pk'] as int) > 0,
          notNull: (r['notnull'] as int) == 1,
          autoIncrement: autoInc && (r['pk'] as int) == 1 && pks.length == 1,
        ),
    ];
    if (pks.isNotEmpty) return DbTable(name, cols, [for (final p in pks) p.$2]);
    // ไม่มีคีย์หลัก : ใช้ rowid ระบุแถว (ตาราง WITHOUT ROWID ต้องมีคีย์หลักอยู่แล้ว)
    return withoutRowid ? DbTable(name, cols, const []) : DbTable(name, cols, const ['rowid'], usesRowid: true);
  }

  @override
  Future<DbPage> fetch(
    DbTable table, {
    int offset = 0,
    int limit = 100,
    String? orderBy,
    bool descending = false,
    String search = '',
  }) async {
    final s = buildSearch(Dialect.sqlite, table, search);
    final total = _db.select('SELECT count(*) AS n FROM ${_q(table.name)}${s.where}', s.params).first['n'] as int;
    final order = orderBy != null && table.column(orderBy) != null ? ' ORDER BY ${_q(orderBy)} ${descending ? 'DESC' : 'ASC'}' : '';
    final keySelect = table.usesRowid ? ', rowid AS "__nsl_rowid__"' : '';
    final rs = _db.select(
      'SELECT *$keySelect FROM ${_q(table.name)}${s.where}$order LIMIT ? OFFSET ?',
      [...s.params, limit.clamp(1, 1000), offset < 0 ? 0 : offset],
    );
    final rows = <DbRow>[];
    for (final r in rs) {
      final cells = [for (final c in table.columns) _text(r[c.name])];
      final key = <String, String?>{};
      if (table.usesRowid) {
        key['rowid'] = _text(r['__nsl_rowid__']);
      } else {
        for (final k in table.keyColumns) {
          key[k] = _text(r[k]);
        }
      }
      rows.add(DbRow(cells, key));
    }
    return DbPage(rows, total);
  }

  @override
  Future<ApplyResult> apply(DbTable table, List<RowEdit> edits) async {
    if (!writable) throw DbException(tr('เปิดแบบอ่านอย่างเดียว แก้ข้อมูลไม่ได้'));
    if (edits.isEmpty) return const ApplyResult(0);
    // สร้างคำสั่งทั้งหมดก่อนแตะไฟล์ : ถ้าคำสั่งไหนไม่ถูกต้องจะไม่สำรอง/ไม่เขียนอะไรเลย
    final stmts = <SqlStmt>[];
    try {
      for (final e in edits) {
        stmts.add(buildEditStatement(Dialect.sqlite, table, e));
      }
    } on DataSqlException catch (e) {
      throw DbException(e.message);
    }
    if (_backup == null) {
      final b = sqliteBackupPath(path, DateTime.now());
      try {
        File(path).copySync(b);
      } on FileSystemException catch (e) {
        throw DbException(tr('สำรองไฟล์ไม่ได้ จึงไม่บันทึก: {0}', [e.message]));
      }
      _backup = b;
    }
    try {
      _db.execute('BEGIN IMMEDIATE');
      for (var i = 0; i < stmts.length; i++) {
        _db.execute(stmts[i].sql, stmts[i].params);
        final isInsert = edits[i] is RowInsert;
        if (!isInsert && _db.updatedRows != 1) {
          throw DbException(tr('คำสั่งที่ {0} กระทบ {1} แถว (ควรเป็น 1) — ข้อมูลอาจถูกแก้โดยที่อื่นไปแล้ว', [i + 1, _db.updatedRows]));
        }
      }
      _db.execute('COMMIT');
    } on SqliteException catch (e) {
      _rollback();
      throw DbException(tr('บันทึกไม่สำเร็จ (ยกเลิกทั้งหมดแล้ว): {0}', [e.message]));
    } on DbException {
      _rollback();
      rethrow;
    }
    return ApplyResult(stmts.length, backupPath: _backup);
  }

  void _rollback() {
    try {
      if (!_db.autocommit) _db.execute('ROLLBACK');
    } catch (_) {}
  }

  @override
  Future<void> close() async => _db.close();
}
