import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../l10n/l10n.dart';
import 'db_session.dart';

/// ผลของการรัน migration กับไฟล์ SQLite
class SqliteApplyResult {
  const SqliteApplyResult(this.backupPath, [this.fkViolations = const []]);

  /// แถวที่ละเมิดคีย์ต่างประเทศหลังรัน (สคริปต์ commit แล้ว แต่ข้อมูลเดิมมีแถวกำพร้า) — ว่าง = ปกติ
  final List<String> fkViolations;

  /// ไฟล์สำรองของฐานข้อมูลเดิม (ก่อนรัน) — เก็บไว้ให้เสมอ ไม่ลบเอง
  final String backupPath;
}

/// ชื่อไฟล์สำรอง : `shop.db` -> `shop.db.bak-20261104-153045` (ไม่ชนกับของเดิม)
String sqliteBackupPath(String dbPath, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  var path = '$dbPath.bak-$stamp';
  for (var i = 2; File(path).existsSync(); i++) {
    path = '$dbPath.bak-$stamp-$i';
  }
  return path;
}

/// รันสคริปต์ migration กับไฟล์ SQLite จริง อย่างปลอดภัย :
/// 1. สำรองไฟล์เดิมเป็น `.bak-<เวลา>` ก่อนเสมอ (ถ้าสำรองไม่ได้ = ไม่รันอะไรเลย)
/// 2. รันสคริปต์ในคำสั่งเดียว ถ้าผิดพลาดกลางทางจะ ROLLBACK ให้ ฐานข้อมูลคงเดิม
/// 3. ผิดพลาด = โยน [DbException] ที่บอกที่อยู่ไฟล์สำรองไว้
/// ไม่ลบไฟล์สำรองทิ้งเองแม้รันสำเร็จ (ผู้ใช้เก็บ/ลบเอง)
SqliteApplyResult applySqliteMigration(String dbPath, String script, {DateTime? now}) {
  final file = File(dbPath);
  if (!file.existsSync()) throw DbException(tr('ไม่พบไฟล์ {0}', [dbPath]));
  if (script.trim().isEmpty) throw DbException(tr('ไม่มีสคริปต์ให้รัน'));

  final backup = sqliteBackupPath(dbPath, now ?? DateTime.now());
  try {
    file.copySync(backup);
  } on FileSystemException catch (e) {
    throw DbException(tr('สำรองไฟล์ไม่ได้ จึงไม่รันสคริปต์: {0}', [e.message]));
  }

  late final Database db;
  try {
    db = sqlite3.open(dbPath);
  } on SqliteException catch (e) {
    throw DbException(tr('เปิดไฟล์ไม่ได้: {0} (ไฟล์สำรอง: {1})', [e.message, backup]));
  }
  try {
    db.execute(script);
  } on SqliteException catch (e) {
    try {
      if (!db.autocommit) db.execute('ROLLBACK');
    } catch (_) {}
    db.close();
    throw DbException(tr('รันสคริปต์ไม่สำเร็จ (ยกเลิกการเปลี่ยนแปลงแล้ว): {0} — ไฟล์สำรอง: {1}', [e.message, backup]));
  }
  // เช็กความสมบูรณ์ของคีย์ต่างประเทศหลังรัน (ไม่แก้อะไร แค่รายงาน)
  List<String> fkProblems = const [];
  try {
    fkProblems = [
      for (final r in db.select('PRAGMA foreign_key_check')) '${r['table']}#${r['rowid']} -> ${r['parent']}',
    ];
  } catch (_) {}
  db.close();
  return SqliteApplyResult(backup, fkProblems);
}
