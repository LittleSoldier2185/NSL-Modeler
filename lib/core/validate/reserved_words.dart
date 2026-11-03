import '../models/enums.dart';

/// คำที่ชนกับ keyword ของ SQL (ชุดที่พบบ่อย ไม่ใช่รายการครบทุกคำ)
/// ตัวสร้าง SQL quote ชื่อให้อยู่แล้ว จึงเป็นแค่คำเตือน
const _common = {
  'add', 'all', 'alter', 'and', 'as', 'asc', 'between', 'by', 'case', 'check', 'column',
  'constraint', 'create', 'cross', 'database', 'default', 'delete', 'desc', 'distinct', 'drop',
  'else', 'end', 'exists', 'foreign', 'from', 'full', 'group', 'having', 'in', 'index', 'inner',
  'insert', 'into', 'is', 'join', 'key', 'left', 'like', 'not', 'null', 'on', 'or', 'order',
  'outer', 'primary', 'references', 'right', 'select', 'set', 'table', 'then', 'to', 'union',
  'unique', 'update', 'values', 'view', 'when', 'where', //
};

const _extra = <Dialect, Set<String>>{
  Dialect.mysql: {
    'describe', 'explain', 'keys', 'limit', 'range', 'rank', 'rename', 'replace', 'show', 'rows',
    'usage', 'condition', 'interval', 'leave', 'lock', 'match', 'option', 'schema', 'trigger', //
  },
  Dialect.postgres: {
    'analyse', 'analyze', 'authorization', 'both', 'collation', 'current_user', 'do', 'limit',
    'offset', 'only', 'returning', 'user', 'window', 'with', 'grant', 'symmetric', 'trailing',
    'verbose', 'variadic', //
  },
  Dialect.sqlite: {
    'abort', 'autoincrement', 'glob', 'indexed', 'limit', 'offset', 'pragma', 'replace',
    'rowid', 'vacuum', 'virtual', 'without', 'transaction', 'trigger', //
  },
  Dialect.mssql: {
    'user', 'identity', 'top', 'merge', 'percent', 'plan', 'proc', 'procedure', 'public',
    'tran', 'transaction', 'waitfor', 'rowcount', 'grant', 'file', 'schema', 'trigger', 'with', //
  },
};

bool isReservedWord(String name, Dialect d) {
  final n = name.toLowerCase();
  return _common.contains(n) || (_extra[d]?.contains(n) ?? false);
}

/// ความยาวสูงสุดของชื่อ (null = ไม่จำกัด)
int? maxIdentifierLength(Dialect d) => switch (d) {
      Dialect.mysql => 64,
      Dialect.postgres => 63,
      Dialect.mssql => 128,
      Dialect.sqlite => null,
    };
