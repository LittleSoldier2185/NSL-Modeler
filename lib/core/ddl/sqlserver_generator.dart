import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/table_model.dart';
import 'ddl_generator.dart';

class SqlServerGenerator extends DdlGenerator {
  const SqlServerGenerator();

  @override
  Dialect get dialect => Dialect.mssql;

  @override
  String quote(String id) => '[${id.replaceAll(']', ']]')}]';

  @override
  String? identityClause(ColumnModel c) => 'IDENTITY(1,1)';

  @override
  String booleanLiteral(bool v) => v ? '1' : '0';

  /// ข้อความที่มีอักขระนอก ASCII (เช่น ภาษาไทย) ต้องมี N นำหน้า ไม่เช่นนั้นกลายเป็น '?'
  @override
  String stringLiteral(String s) =>
      '${s.codeUnits.any((c) => c > 127) ? 'N' : ''}${super.stringLiteral(s)}';

  @override
  String primaryKeyLine(TableModel t, List<ColumnModel> pk) =>
      'CONSTRAINT ${quote('PK_${t.name}')} PRIMARY KEY (${pk.map((c) => quote(c.name)).join(', ')})';

  @override
  String? get batchSeparator => 'GO';

  String _n(String s) => "N'${s.replaceAll("'", "''")}'";

  @override
  List<String> commentStatements(Project p) => [
        for (final t in p.tables)
          if (t.columns.isNotEmpty) ...[
            if (t.comment.isNotEmpty)
              "EXEC sp_addextendedproperty N'MS_Description', ${_n(t.comment)}, "
                  "N'SCHEMA', N'dbo', N'TABLE', ${_n(t.name)};",
            for (final c in t.columns)
              if (c.comment.isNotEmpty)
                "EXEC sp_addextendedproperty N'MS_Description', ${_n(c.comment)}, "
                    "N'SCHEMA', N'dbo', N'TABLE', ${_n(t.name)}, N'COLUMN', ${_n(c.name)};",
          ],
      ];
}
