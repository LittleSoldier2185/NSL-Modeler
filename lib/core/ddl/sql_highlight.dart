enum SqlTokenKind { plain, space, comment, identifier, string, keyword, type, number, punct }

class SqlToken {
  const SqlToken(this.text, this.kind);
  final String text;
  final SqlTokenKind kind;

  @override
  String toString() => '$kind($text)';
}

const _keywords = {
  'CREATE', 'TABLE', 'NOT', 'NULL', 'AUTO_INCREMENT', 'AUTOINCREMENT', 'DEFAULT', 'PRIMARY',
  'KEY', 'ENGINE', 'CHARSET', 'ALTER', 'ADD', 'FOREIGN', 'REFERENCES', 'IDENTITY', 'CONSTRAINT',
  'GO', 'ON', 'DELETE', 'UPDATE', 'CASCADE', 'RESTRICT', 'SET', 'NO', 'ACTION', 'UNIQUE',
  'INDEX', 'COMMENT', 'PRAGMA', 'EXEC', 'IS', 'TRUE', 'FALSE', 'CURRENT_TIMESTAMP',
  'CURRENT_DATE', 'CURRENT_TIME', //
};

const _types = {
  'INT', 'INTEGER', 'BIGINT', 'SMALLINT', 'VARCHAR', 'NVARCHAR', 'CHAR', 'TEXT', 'DECIMAL',
  'NUMERIC', 'FLOAT', 'DOUBLE', 'PRECISION', 'REAL', 'BOOLEAN', 'BIT', 'DATE', 'DATETIME',
  'DATETIME2', 'TIMESTAMP', 'TIMESTAMPTZ', 'BLOB', 'BYTEA', 'VARBINARY', 'UUID',
  'UNIQUEIDENTIFIER', 'JSON', 'SERIAL', 'BIGSERIAL', 'SMALLSERIAL', 'MAX', 'INNODB', //
};

// ลำดับสำคัญ: คอมเมนต์ก่อน, แล้วสตริง/ชื่อที่ quote (กลืนตัวอักษร -- ที่อยู่ข้างในไว้)
final _re = RegExp(
  r'''--.*|`[^`]*`|"[^"]*"|\[[^\]]*\]|'(?:[^']|'')*'|[A-Za-z_][A-Za-z0-9_]*|\d+(?:\.\d+)?|\s+|.''',
);

/// แยกบรรทัด SQL เป็น token สำหรับไฮไลต์ — ต่อ token ทั้งหมดต้องได้ข้อความเดิมเป๊ะ
List<SqlToken> tokenizeSqlLine(String line) {
  final out = <SqlToken>[];
  for (final m in _re.allMatches(line)) {
    final t = m.group(0)!;
    final c = t[0];
    SqlTokenKind k;
    if (t.startsWith('--')) {
      k = SqlTokenKind.comment;
    } else if (c == '`' || c == '"' || c == '[') {
      k = SqlTokenKind.identifier;
    } else if (c == "'") {
      k = SqlTokenKind.string;
    } else if (RegExp(r'^\s+$').hasMatch(t)) {
      k = SqlTokenKind.space;
    } else if (RegExp(r'^\d').hasMatch(t)) {
      k = SqlTokenKind.number;
    } else if (RegExp(r'^[A-Za-z_]').hasMatch(t)) {
      final u = t.toUpperCase();
      k = _keywords.contains(u)
          ? SqlTokenKind.keyword
          : _types.contains(u)
              ? SqlTokenKind.type
              : SqlTokenKind.plain;
    } else if ('(),;=.'.contains(c)) {
      k = SqlTokenKind.punct;
    } else {
      k = SqlTokenKind.plain;
    }
    out.add(SqlToken(t, k));
  }
  return out;
}
