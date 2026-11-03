import '../ddl/ddl_generator.dart';
import '../models/project.dart';
import 'seed_data.dart';

/// ข้อความ `.sql` ที่ Export: โครงสร้างตาราง + (ถ้า [includeSeed]) ข้อมูลตั้งต้นต่อท้าย
/// ข้อมูลตั้งต้นที่ไม่ถูกต้องโยน [SeedException] — ไม่ปล่อย SQL ที่ใส่ข้อมูลผิดออกไป
String buildExportSql(Project p, {bool includeSeed = false}) {
  final ddl = DdlGenerator.forDialect(p.dialect).generate(p);
  if (!includeSeed) return ddl;
  final seed = generateSeedSql(p);
  return seed.isEmpty ? ddl : '$ddl\n$seed';
}

/// จำนวนแถวข้อมูลตั้งต้นทั้งหมดและจำนวนตารางที่มี
({int rows, int tables}) seedSummary(Project p) {
  final ts = tablesWithSeed(p);
  return (rows: ts.fold<int>(0, (s, t) => s + t.seedRows.length), tables: ts.length);
}
