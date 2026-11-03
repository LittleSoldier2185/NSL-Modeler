import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/table_model.dart';
import 'ddl_generator.dart';

class MySqlGenerator extends DdlGenerator {
  const MySqlGenerator();

  @override
  Dialect get dialect => Dialect.mysql;

  @override
  String quote(String id) => '`${id.replaceAll('`', '``')}`';

  // MySQL ถือ \ เป็นตัว escape ในสตริง
  @override
  String stringLiteral(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", "''")}'";

  @override
  String? autoIncrementClause(ColumnModel c) => 'AUTO_INCREMENT';

  @override
  String? columnTrailer(ColumnModel c) =>
      c.comment.isEmpty ? null : 'COMMENT ${stringLiteral(c.comment)}';

  // utf8mb4 เพื่อให้เก็บภาษาไทย/อีโมจิได้ครบ
  @override
  String tableSuffix(TableModel t) =>
      ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
      '${t.comment.isEmpty ? '' : ' COMMENT=${stringLiteral(t.comment)}'}';
}
