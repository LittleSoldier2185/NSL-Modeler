/// Dialect ที่รองรับ
enum Dialect {
  mysql('MySQL / MariaDB'),
  postgres('PostgreSQL'),
  sqlite('SQLite'),
  mssql('SQL Server');

  const Dialect(this.label);
  final String label;
}

/// ชนิดข้อมูลกลาง (แมปเป็นชนิดจริงของแต่ละ dialect ในเฟส 2)
enum DataType {
  integer,
  bigint,
  smallint,
  varchar,
  text,
  decimal,
  float,
  boolean,
  date,
  datetime,
  timestamp,
  blob,
  uuid,
  json,
}

enum RefAction {
  noAction('NO ACTION'),
  cascade('CASCADE'),
  restrict('RESTRICT'),
  setNull('SET NULL');

  const RefAction(this.sql);
  final String sql;
}
