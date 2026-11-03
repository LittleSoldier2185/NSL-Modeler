import '../models/column_model.dart';
import '../models/enums.dart';

/// ชนิดข้อมูลกลาง -> ชนิดจริงของแต่ละ dialect
///
/// หมายเหตุ:
/// - PostgreSQL: คอลัมน์ AUTO INCREMENT จะใช้ SERIAL/BIGSERIAL/SMALLSERIAL แทนชนิดปกติ
/// - SQL Server: TIMESTAMP ของ MSSQL คือ rowversion จึงแมป TIMESTAMP -> DATETIME2
/// - SQLite: เก็บวันที่เป็น TEXT, boolean เป็น INTEGER
String sqlType(ColumnModel c, Dialect d) {
  final len = c.length;
  final prec = len ?? 10;
  final scale = c.scale ?? 2;
  final n = len ?? 255;

  switch (d) {
    case Dialect.mysql:
      return switch (c.type) {
        DataType.integer => 'INT',
        DataType.bigint => 'BIGINT',
        DataType.smallint => 'SMALLINT',
        DataType.varchar => 'VARCHAR($n)',
        DataType.text => 'TEXT',
        DataType.decimal => 'DECIMAL($prec,$scale)',
        DataType.float => 'FLOAT',
        DataType.boolean => 'BOOLEAN',
        DataType.date => 'DATE',
        DataType.datetime => 'DATETIME',
        DataType.timestamp => 'TIMESTAMP',
        DataType.blob => 'BLOB',
        DataType.uuid => 'CHAR(36)',
        DataType.json => 'JSON',
      };
    case Dialect.postgres:
      if (c.autoIncrement) {
        switch (c.type) {
          case DataType.integer:
            return 'SERIAL';
          case DataType.bigint:
            return 'BIGSERIAL';
          case DataType.smallint:
            return 'SMALLSERIAL';
          default:
            break;
        }
      }
      return switch (c.type) {
        DataType.integer => 'INTEGER',
        DataType.bigint => 'BIGINT',
        DataType.smallint => 'SMALLINT',
        DataType.varchar => 'VARCHAR($n)',
        DataType.text => 'TEXT',
        DataType.decimal => 'NUMERIC($prec,$scale)',
        DataType.float => 'DOUBLE PRECISION',
        DataType.boolean => 'BOOLEAN',
        DataType.date => 'DATE',
        DataType.datetime => 'TIMESTAMP',
        DataType.timestamp => 'TIMESTAMPTZ',
        DataType.blob => 'BYTEA',
        DataType.uuid => 'UUID',
        DataType.json => 'JSON',
      };
    case Dialect.sqlite:
      return switch (c.type) {
        DataType.integer || DataType.bigint || DataType.smallint || DataType.boolean => 'INTEGER',
        DataType.varchar ||
        DataType.text ||
        DataType.date ||
        DataType.datetime ||
        DataType.timestamp ||
        DataType.uuid ||
        DataType.json =>
          'TEXT',
        DataType.decimal => 'NUMERIC',
        DataType.float => 'REAL',
        DataType.blob => 'BLOB',
      };
    case Dialect.mssql:
      return switch (c.type) {
        DataType.integer => 'INT',
        DataType.bigint => 'BIGINT',
        DataType.smallint => 'SMALLINT',
        DataType.varchar => 'NVARCHAR($n)',
        DataType.text => 'NVARCHAR(MAX)',
        DataType.decimal => 'DECIMAL($prec,$scale)',
        DataType.float => 'FLOAT',
        DataType.boolean => 'BIT',
        DataType.date => 'DATE',
        DataType.datetime => 'DATETIME2',
        DataType.timestamp => 'DATETIME2',
        DataType.blob => 'VARBINARY(MAX)',
        DataType.uuid => 'UNIQUEIDENTIFIER',
        DataType.json => 'NVARCHAR(MAX)',
      };
  }
}

/// ชนิดที่ใช้ AUTO INCREMENT ได้
bool isIntegerType(DataType t) =>
    t == DataType.integer || t == DataType.bigint || t == DataType.smallint;
