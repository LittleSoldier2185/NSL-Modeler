import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import 'data_access.dart';
import 'db_session.dart';
import 'mysql_connector.dart';

/// เปิดดู/แก้ข้อมูลของ MySQL / MariaDB จริง
/// - [writable] = false : session ตั้ง `READ ONLY` ที่ฝั่งเซิร์ฟเวอร์ (เซิร์ฟเวอร์ปฏิเสธการเขียนเอง) และ [apply] ถูกปฏิเสธที่ฝั่งโปรแกรมอีกชั้น
/// - [writable] = true : เขียนได้ ทุกคำสั่งใช้ prepared statement (ค่าถูกส่งแยกจากข้อความ SQL) ภายในทรานแซกชันเดียว
///   ก่อนแก้/ลบแต่ละแถวจะล็อกและตรวจว่าแถวนั้นยังอยู่ (`SELECT … FOR UPDATE`) ไม่พึ่งจำนวนแถวที่ถูกกระทบ
///
/// หมายเหตุ : ส่วนนี้ทดสอบกับเซิร์ฟเวอร์จริงไม่ได้ในเครื่องพัฒนา (ทดสอบเฉพาะการสร้างคำสั่ง SQL) — ลองกับฐานข้อมูลทดสอบก่อนใช้กับข้อมูลจริง
class MysqlDataSession implements DataSession {
  MysqlDataSession._(this._conn, this.writable);

  final MySQLConnection _conn;

  @override
  final bool writable;

  @override
  Dialect get dialect => Dialect.mysql;

  static Future<MysqlDataSession> open(DbConfig config, {bool writable = false}) async {
    final conn = await MysqlConnector.openConnection(config, readOnly: !writable);
    return MysqlDataSession._(conn, writable);
  }

  String _q(String n) => quoteIdent(Dialect.mysql, n);

  /// SELECT แบบ prepared : ค่าแยกจากข้อความ SQL
  Future<List<Map<String, String?>>> _select(String sql, [List<dynamic> params = const []]) async {
    final st = await _conn.prepare(sql);
    try {
      final rs = await st.execute(params);
      return [for (final r in rs.rows) r.assoc()];
    } finally {
      try {
        await st.deallocate();
      } catch (_) {}
    }
  }

  Future<List<Map<String, String?>>> _show(String sql) async {
    final rs = await _conn.execute(sql);
    return [for (final r in rs.rows) r.assoc()];
  }

  DbException _wrap(Object e) {
    if (e is DbException) return e;
    if (e is MySQLServerException) return DbException(tr('เซิร์ฟเวอร์ปฏิเสธ: {0}', [e.message]));
    if (e is MySQLClientException) return DbException(tr('คำสั่งผิดพลาด: {0}', [e.message]));
    return DbException(tr('คำสั่งผิดพลาด: {0}', [e]));
  }

  @override
  Future<List<String>> tableNames() async {
    try {
      final rows = await _show("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'");
      return [
        for (final r in rows)
          if (r.values.isNotEmpty && r.values.first != null) r.values.first!,
      ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<DbTable> table(String name) async {
    try {
      final cols = await _show('SHOW FULL COLUMNS FROM ${_q(name)}');
      if (cols.isEmpty) throw DbException(tr('ไม่พบตาราง {0}', [name]));
      final keys = await _show("SHOW KEYS FROM ${_q(name)} WHERE Key_name = 'PRIMARY'");
      keys.sort((a, b) => (int.tryParse(a['Seq_in_index'] ?? '') ?? 0).compareTo(int.tryParse(b['Seq_in_index'] ?? '') ?? 0));
      final pk = [for (final k in keys) k['Column_name']!];
      return DbTable(name, [
        for (final c in cols)
          DbColumn(
            c['Field']!,
            c['Type'] ?? '',
            isPk: pk.contains(c['Field']),
            notNull: c['Null'] == 'NO',
            autoIncrement: (c['Extra'] ?? '').toLowerCase().contains('auto_increment'),
          ),
      ], pk);
    } catch (e) {
      throw _wrap(e);
    }
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
    try {
      final s = buildSearch(Dialect.mysql, table, search);
      final total = int.tryParse((await _select('SELECT count(*) AS n FROM ${_q(table.name)}${s.where}', s.params)).first['n'] ?? '') ?? 0;
      // คอลัมน์ไบนารีไม่ดึงเนื้อมา (ใช้ข้อความสรุปขนาดแทน) กันขยะไบต์ในกริดและกินหน่วยความจำ
      final select = table.columns
          .map((c) => c.isBinary ? "CONCAT('[BLOB ', IFNULL(LENGTH(${_q(c.name)}), 0), ' bytes]') AS ${_q(c.name)}" : _q(c.name))
          .join(', ');
      final order = orderBy != null && table.column(orderBy) != null ? ' ORDER BY ${_q(orderBy)} ${descending ? 'DESC' : 'ASC'}' : '';
      final rows = await _select(
        'SELECT $select FROM ${_q(table.name)}${s.where}$order LIMIT ? OFFSET ?',
        [...s.params, limit.clamp(1, 1000), offset < 0 ? 0 : offset],
      );
      return DbPage([
        for (final r in rows)
          DbRow([for (final c in table.columns) r[c.name]], {for (final k in table.keyColumns) k: r[k]}),
      ], total);
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<ApplyResult> apply(DbTable table, List<RowEdit> edits) async {
    if (!writable) throw DbException(tr('เปิดแบบอ่านอย่างเดียว แก้ข้อมูลไม่ได้'));
    if (edits.isEmpty) return const ApplyResult(0);
    // สร้างคำสั่งทั้งหมดก่อนเริ่มทรานแซกชัน : ไม่ถูกต้องข้อเดียว = ไม่แตะฐานข้อมูล
    final stmts = <SqlStmt>[];
    final checks = <SqlStmt?>[];
    try {
      for (final e in edits) {
        stmts.add(buildEditStatement(Dialect.mysql, table, e));
        checks.add(switch (e) {
          RowUpdate(:final key) || RowDelete(:final key) => buildKeyCheck(Dialect.mysql, table, key),
          RowInsert() => null,
        });
      }
    } on DataSqlException catch (e) {
      throw DbException(e.message);
    }
    try {
      await _conn.execute('START TRANSACTION');
    } catch (e) {
      throw _wrap(e);
    }
    try {
      for (var i = 0; i < stmts.length; i++) {
        final chk = checks[i];
        if (chk != null) {
          final found = await _select('${chk.sql} FOR UPDATE', chk.params);
          if (found.length != 1) {
            throw DbException(tr('คำสั่งที่ {0}: ไม่พบแถวนี้แล้ว (อาจถูกแก้หรือลบที่อื่นไปก่อน) — ยกเลิกทั้งหมด', [i + 1]));
          }
        }
        final st = await _conn.prepare(stmts[i].sql);
        try {
          await st.execute(stmts[i].params);
        } finally {
          try {
            await st.deallocate();
          } catch (_) {}
        }
      }
      await _conn.execute('COMMIT');
    } catch (e) {
      try {
        await _conn.execute('ROLLBACK');
      } catch (_) {}
      final w = _wrap(e);
      throw DbException(tr('บันทึกไม่สำเร็จ (ยกเลิกทั้งหมดแล้ว): {0}', [w.message]));
    }
    return ApplyResult(stmts.length);
  }

  @override
  Future<void> close() async {
    try {
      await _conn.close();
    } catch (_) {}
  }
}
