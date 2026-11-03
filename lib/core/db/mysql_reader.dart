import '../l10n/l10n.dart';
import '../models/enums.dart';
import '../parser/sql_importer.dart';
import 'db_session.dart';

/// ผลการอ่านโครงสร้างจากฐานข้อมูล: DDL ที่ได้ + ผลนำเข้า (ผ่าน parser เดียวกับการนำเข้าไฟล์ .sql)
class DbReadResult {
  const DbReadResult(this.ddl, this.tableCount, this.import);
  final String ddl;
  final int tableCount;
  final ImportResult import;
}

/// ใส่ชื่อในเครื่องหมาย ` สำหรับ MySQL (` ในชื่อเขียนซ้ำ)
String quoteMysqlIdent(String name) => '`${name.replaceAll('`', '``')}`';

/// อ่านโครงสร้างของฐานข้อมูล MySQL/MariaDB เป็น DDL: รายชื่อตารางจริง (ไม่รวม VIEW) แล้ว SHOW CREATE TABLE ทีละตาราง
/// จากนั้นนำเข้าด้วย [importSql] จึงได้คอลัมน์/ชนิด/คีย์/FK/ดัชนี/คอมเมนต์เหมือนนำเข้าไฟล์ dump
/// ใช้เฉพาะคำสั่งอ่านอย่างเดียว (ดู [ReadOnlySession])
Future<DbReadResult> readMysqlSchema(DbSession session, {required String database, void Function(int done, int total)? onProgress}) async {
  final s = session is ReadOnlySession ? session : ReadOnlySession(session);
  final rows = await s.query("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'");
  final names = <String>[
    for (final r in rows)
      if (r.values.isNotEmpty && r.values.first != null) r.values.first!,
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final ddl = StringBuffer();
  for (var i = 0; i < names.length; i++) {
    final created = await s.query('SHOW CREATE TABLE ${quoteMysqlIdent(names[i])}');
    final text = created.isEmpty ? null : (created.first['Create Table'] ?? created.first.values.skip(1).firstOrNull);
    if (text == null) throw DbException(tr('อ่านโครงสร้างตาราง {0} ไม่ได้', [names[i]]));
    ddl
      ..write(text.trimRight())
      ..writeln(';')
      ..writeln();
    onProgress?.call(i + 1, names.length);
  }
  final text = ddl.toString();
  return DbReadResult(text, names.length, importSql(text, name: database.isEmpty ? 'database' : database, dialect: Dialect.mysql));
}
