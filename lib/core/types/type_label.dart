import '../models/column_model.dart';
import '../models/enums.dart';

/// ชื่อชนิดข้อมูลแบบที่แสดงบน UI (กลาง ไม่ผูก dialect)
String typeLabel(ColumnModel c) {
  switch (c.type) {
    case DataType.integer:
      return 'INT';
    case DataType.bigint:
      return 'BIGINT';
    case DataType.smallint:
      return 'SMALLINT';
    case DataType.varchar:
      return 'VARCHAR(${c.length ?? 255})';
    case DataType.text:
      return 'TEXT';
    case DataType.decimal:
      return 'DECIMAL(${c.length ?? 10},${c.scale ?? 2})';
    case DataType.float:
      return 'FLOAT';
    case DataType.boolean:
      return 'BOOLEAN';
    case DataType.date:
      return 'DATE';
    case DataType.datetime:
      return 'DATETIME';
    case DataType.timestamp:
      return 'TIMESTAMP';
    case DataType.blob:
      return 'BLOB';
    case DataType.uuid:
      return 'UUID';
    case DataType.json:
      return 'JSON';
  }
}
