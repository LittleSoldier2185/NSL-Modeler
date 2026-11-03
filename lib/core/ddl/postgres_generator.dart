import '../models/enums.dart';
import '../models/project.dart';
import 'ddl_generator.dart';

class PostgresGenerator extends DdlGenerator {
  const PostgresGenerator();

  @override
  Dialect get dialect => Dialect.postgres;

  @override
  String quote(String id) => '"${id.replaceAll('"', '""')}"';

  @override
  List<String> commentStatements(Project p) => [
        for (final t in p.tables) ...[
          if (t.comment.isNotEmpty && t.columns.isNotEmpty)
            'COMMENT ON TABLE ${quote(t.name)} IS ${stringLiteral(t.comment)};',
          if (t.columns.isNotEmpty)
            for (final c in t.columns)
              if (c.comment.isNotEmpty)
                'COMMENT ON COLUMN ${quote(t.name)}.${quote(c.name)} IS ${stringLiteral(c.comment)};',
        ],
      ];
}
