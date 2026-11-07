import '../ddl/ddl_generator.dart';
import '../l10n/l10n.dart';
import '../models/project.dart';
import '../models/workspace.dart';
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

/// ไฟล์ `.sql` เดียวที่รวมทุก ER ของโปรเจกต์ ตามลำดับเอกสาร — แต่ละ ER มีหัวคอมเมนต์ (ชื่อเอกสาร + dialect)
/// และสร้างด้วย dialect ของ ER นั้นเอง (ไม่รวมข้อมูลตั้งต้น) ; ไม่มี ER = สตริงว่าง
String buildWorkspaceSql(Workspace w) {
  final ers = w.documentsOf(DocType.er).toList();
  final b = StringBuffer();
  for (var i = 0; i < ers.length; i++) {
    final d = ers[i];
    final p = d.er!;
    if (i > 0) b.writeln();
    final name = d.name.replaceAll(RegExp(r'\s+'), ' ');
    b.writeln('-- ===== ${tr('ER {0}/{1}: {2} ({3})', [i + 1, ers.length, name, p.dialect.label])} =====');
    b.write(buildExportSql(p));
  }
  return b.toString();
}
