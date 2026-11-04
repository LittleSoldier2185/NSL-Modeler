import '../l10n/l10n.dart';

/// ชนิดฐานข้อมูลที่เชื่อมต่อได้ (อ่านอย่างเดียวทั้งคู่)
enum DbKind { mysql, sqlite }

/// ข้อมูลที่ใช้เชื่อมต่อฐานข้อมูล — รหัสผ่านอยู่ในหน่วยความจำเท่านั้น ไม่ถูกบันทึกลงไฟล์/ประวัติ/ข้อความผิดพลาด
class DbConfig {
  const DbConfig({
    this.host = 'localhost',
    this.port = 3306,
    this.user = 'root',
    this.password = '',
    this.database = '',
    this.secure = false,
  });

  final String host;
  final int port;
  final String user;
  final String password;
  final String database;

  /// ใช้ SSL/TLS (เซิร์ฟเวอร์ต้องรองรับ — เครื่องตัวเองมักไม่เปิด จึงปิดเป็นค่าเริ่มต้น)
  final bool secure;

  DbConfig copyWith({String? host, int? port, String? user, String? password, String? database, bool? secure}) => DbConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        user: user ?? this.user,
        password: password ?? this.password,
        database: database ?? this.database,
        secure: secure ?? this.secure,
      );

  /// ข้อความอธิบายการเชื่อมต่อที่ปลอดภัยต่อการแสดง (ไม่มีรหัสผ่าน)
  String get label => '$user@$host:$port/$database';

  @override
  String toString() => 'DbConfig($label)';
}

/// การเชื่อมต่อที่เปิดอยู่ — คืนแถวเป็น map ชื่อคอลัมน์ -> ข้อความ
abstract class DbSession {
  Future<List<Map<String, String?>>> query(String sql);
  Future<void> close();
}

/// ตัวสร้างการเชื่อมต่อ (เปลี่ยนได้ในเทสต์)
abstract class DbConnector {
  Future<DbSession> connect(DbConfig config);
}

/// ข้อผิดพลาดที่แสดงให้ผู้ใช้ได้ (ข้อความไม่มีรหัสผ่าน)
class DbException implements Exception {
  DbException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// ครอบ session เพื่อรับประกันว่าเป็น "อ่านอย่างเดียว": ปฏิเสธทุกคำสั่งที่ไม่ใช่ SELECT/SHOW/DESCRIBE/EXPLAIN
/// หรือมีหลายคำสั่งในบรรทัดเดียว (กัน `SELECT 1; DROP TABLE x`) ไม่ว่าโค้ดส่วนไหนจะเรียกมา
class ReadOnlySession implements DbSession {
  ReadOnlySession(this._inner);
  final DbSession _inner;

  static final _allowed = RegExp(r'^\s*(select|show|describe|desc|explain)\b', caseSensitive: false);

  /// true = คำสั่งนี้อ่านอย่างเดียวและมีคำสั่งเดียว
  static bool isSafe(String sql) {
    if (!_allowed.hasMatch(sql)) return false;
    // ตัด string literal / ชื่อในเครื่องหมาย ` ออกก่อน แล้วดูว่ามี ; หรือคอมเมนต์ที่ซ่อนคำสั่งอื่นไหม
    final stripped = sql
        .replaceAll(RegExp(r"'(?:[^'\\]|\\.|'')*'"), "''")
        .replaceAll(RegExp(r'"(?:[^"\\]|\\.|"")*"'), '""')
        .replaceAll(RegExp(r'`(?:[^`]|``)*`'), '``');
    if (stripped.contains(';')) return false;
    if (stripped.contains('--') || stripped.contains('/*') || stripped.contains('#')) return false;
    // SELECT ... INTO OUTFILE/DUMPFILE เขียนไฟล์บนเซิร์ฟเวอร์ได้
    if (RegExp(r'\binto\s+(outfile|dumpfile)\b', caseSensitive: false).hasMatch(stripped)) return false;
    return true;
  }

  @override
  Future<List<Map<String, String?>>> query(String sql) async {
    if (!isSafe(sql)) throw DbException(tr('ปฏิเสธคำสั่งที่ไม่ใช่การอ่านอย่างเดียว'));
    return _inner.query(sql);
  }

  @override
  Future<void> close() => _inner.close();
}
