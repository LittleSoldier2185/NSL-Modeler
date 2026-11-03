import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/table_model.dart';
import '../types/type_map.dart';
import 'ddl_generator.dart';

/// SQLite: เพิ่ม FK ด้วย ALTER ไม่ได้ จึงใส่ใน CREATE TABLE
/// ไม่มี COMMENT จึงแปลงความเห็นเป็นคอมเมนต์ `--`
class SqliteGenerator extends DdlGenerator {
  const SqliteGenerator();

  @override
  Dialect get dialect => Dialect.sqlite;

  @override
  String quote(String id) => '"${id.replaceAll('"', '""')}"';

  @override
  bool get fksInline => true;

  // SQLite ไม่ตรวจ FK จนกว่าจะเปิด
  @override
  String? get preamble => 'PRAGMA foreign_keys = ON;';

  @override
  String booleanLiteral(bool v) => v ? '1' : '0';

  /// AUTOINCREMENT ใช้ได้เฉพาะ PK คอลัมน์เดียวชนิด INTEGER
  @override
  String primaryKeyLine(TableModel t, List<ColumnModel> pk) {
    if (pk.length == 1 && pk.first.autoIncrement && isIntegerType(pk.first.type)) {
      return 'PRIMARY KEY (${quote(pk.first.name)} AUTOINCREMENT)';
    }
    return super.primaryKeyLine(t, pk);
  }

  @override
  String tablePrefix(TableModel t) =>
      t.comment.isEmpty ? '' : '-- ${DdlGenerator.flat(t.comment)}\n';

  @override
  String columnDef(TableModel t, ColumnModel c, List<ColumnModel> pk) {
    final def = super.columnDef(t, c, pk);
    return c.comment.isEmpty ? def : '-- ${DdlGenerator.flat(c.comment)}\n  $def';
  }
}
