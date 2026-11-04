import 'dart:async';
import 'dart:io';

import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';

import '../l10n/l10n.dart';
import 'db_session.dart';

/// เชื่อมต่อ MySQL/MariaDB จริงด้วย mysql_client (รองรับ mysql_native_password และ caching_sha2_password)
/// ทุก session ที่คืนออกไปถูกครอบด้วย [ReadOnlySession] และตั้ง `SET SESSION TRANSACTION READ ONLY` ที่ฝั่งเซิร์ฟเวอร์ด้วย
class MysqlConnector implements DbConnector {
  const MysqlConnector();

  static const connectTimeout = Duration(seconds: 10);

  @override
  Future<DbSession> connect(DbConfig config) async => ReadOnlySession(_MysqlSession(await openConnection(config, readOnly: true)));

  /// เปิดการเชื่อมต่อ MySQL พร้อมแปลข้อผิดพลาดเป็นข้อความที่อ่านเข้าใจ (ไม่มีรหัสผ่าน)
  /// [readOnly] = true ตั้ง `SET SESSION TRANSACTION READ ONLY` ให้เซิร์ฟเวอร์ปฏิเสธการเขียนเอง ; false = เขียนได้ (ใช้กับโหมดแก้ข้อมูลเท่านั้น)
  static Future<MySQLConnection> openConnection(DbConfig config, {required bool readOnly}) async {
    try {
      return await _open(config, readOnly: readOnly);
    } on DbException catch (e) {
      // MySQL 8+ ใช้รหัสผ่านแบบ caching_sha2_password ซึ่งส่งได้เฉพาะผ่านการเข้ารหัส : ถ้าผู้ใช้ไม่ได้ติ๊ก SSL/TLS ไว้
      // ลองใหม่โดยเปิด TLS ให้เอง (ปลอดภัยกว่าเดิม ไม่ต้องให้ผู้ใช้รู้เรื่องปลั๊กอินยืนยันตัวตน)
      if (!config.secure && e.message.contains('caching_sha2_password')) {
        return _open(config.copyWith(secure: true), readOnly: readOnly);
      }
      rethrow;
    }
  }

  static Future<MySQLConnection> _open(DbConfig config, {required bool readOnly}) async {
    MySQLConnection? conn;
    try {
      conn = await MySQLConnection.createConnection(
        host: config.host,
        port: config.port,
        userName: config.user,
        password: config.password,
        databaseName: config.database.isEmpty ? null : config.database,
        secure: config.secure,
      ).timeout(connectTimeout);
      await conn.connect(timeoutMs: connectTimeout.inMilliseconds);
      // ชั้นที่สองของความปลอดภัย: ให้เซิร์ฟเวอร์ปฏิเสธการเขียนเองด้วย (ชั้นแรกคือ ReadOnlySession)
      if (readOnly) await conn.execute('SET SESSION TRANSACTION READ ONLY');
      return conn;
    } on SocketException catch (e) {
      await _closeQuietly(conn);
      throw DbException(tr('เชื่อมต่อ {0}:{1} ไม่ได้ ({2}) — ตรวจชื่อเครื่อง พอร์ต และว่าเซิร์ฟเวอร์เปิดอยู่', [config.host, config.port, e.message]));
    } on TimeoutException {
      await _closeQuietly(conn);
      throw DbException(tr('เชื่อมต่อ {0}:{1} หมดเวลา', [config.host, config.port]));
    } on MySQLServerException catch (e) {
      await _closeQuietly(conn);
      throw DbException(tr('เซิร์ฟเวอร์ปฏิเสธ: {0}', [e.message]));
    } on MySQLClientException catch (e) {
      await _closeQuietly(conn);
      throw DbException(tr('เชื่อมต่อไม่สำเร็จ: {0}', [e.message]));
    } catch (e) {
      await _closeQuietly(conn);
      // ข้อความของไลบรารีไม่มีรหัสผ่าน แต่กันไว้ถ้าบังเอิญมี
      final safe = config.password.isEmpty ? e.toString() : e.toString().replaceAll(config.password, '***');
      throw DbException(tr('เชื่อมต่อไม่สำเร็จ: {0}', [safe]));
    }
  }

  static Future<void> _closeQuietly(MySQLConnection? c) async {
    try {
      await c?.close();
    } catch (_) {}
  }
}

class _MysqlSession implements DbSession {
  _MysqlSession(this._conn);
  final MySQLConnection _conn;

  @override
  Future<List<Map<String, String?>>> query(String sql) async {
    final r = await _conn.execute(sql);
    return [for (final row in r.rows) row.assoc()];
  }

  @override
  Future<void> close() => _conn.close();
}
