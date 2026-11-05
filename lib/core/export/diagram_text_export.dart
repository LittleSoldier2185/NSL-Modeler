import '../layout/diagram_geometry.dart';
import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../l10n/l10n.dart';

/// ---------- Mermaid (erDiagram) ----------
///
/// ชื่อที่ Mermaid ไม่รองรับ (ภาษาไทย, ช่องว่าง) จะถูกแปลงเป็น `_` และใส่ชื่อเดิมไว้ในเครื่องหมายคำพูด
/// เพื่อไม่ให้ไดอะแกรมพัง ชนิดข้อมูลไม่ใส่ความยาว (วงเล็บอาจไม่ผ่านบางเวอร์ชัน)
String exportMermaid(Project p) {
  final b = StringBuffer('erDiagram\n');
  final ids = _mermaidIds(p);
  for (final t in p.tables) {
    b.writeln('    ${ids[t.id]} {');
    for (final c in t.columns) {
      final keys = [
        if (c.isPrimaryKey) 'PK',
        if (p.relations.any((r) => r.fromTableId == t.id && r.fromColumnId == c.id)) 'FK',
        if (c.unique && !c.isPrimaryKey) 'UK',
      ];
      final n = _mermaidName(c.name);
      final comment = [
        if (n != c.name) c.name,
        if (c.comment.isNotEmpty) c.comment.replaceAll(RegExp(r'\s+'), ' '),
      ].join(' — ').replaceAll('"', "'");
      b.writeln('        ${_mermaidType(c)} $n${keys.isEmpty ? '' : ' ${keys.join(', ')}'}'
          '${comment.isEmpty ? '' : ' "$comment"'}');
    }
    if (t.columns.isEmpty) b.writeln('        string _empty');
    b.writeln('    }');
  }
  for (final r in p.relations) {
    final child = p.tableById(r.fromTableId), parent = p.tableById(r.toTableId);
    final col = child?.columnById(r.fromColumnId);
    if (child == null || parent == null || col == null) continue;
    // ฝั่งลูก: หลายแถว (หรือ 0..1 ถ้า FK เป็น PK/UNIQUE) · ฝั่งแม่: 1 แถว (หรือ 0..1 ถ้า FK เป็น NULL ได้)
    final left = isUniqueAlone(child, col) ? '|o' : '}o';
    final right = (col.notNull || col.isPrimaryKey) ? '||' : 'o|';
    b.writeln('    ${ids[child.id]} $left--$right ${ids[parent.id]} : "${col.name.replaceAll('"', "'")}"');
  }
  return b.toString();
}

String _mermaidName(String s) {
  var n = s.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  if (n.isEmpty) n = '_';
  if (RegExp(r'^[0-9]').hasMatch(n)) n = '_$n';
  return n;
}

/// ชื่อ entity ที่ไม่ซ้ำกัน (ชื่อไทยหลายตัวจะกลายเป็น `____` เหมือนกัน จึงเติมเลขกันชน)
Map<String, String> _mermaidIds(Project p) {
  final used = <String>{};
  final out = <String, String>{};
  for (final t in p.tables) {
    final base = _mermaidName(t.name);
    var name = base;
    var i = 2;
    while (!used.add(name)) {
      name = '${base}_${i++}';
    }
    out[t.id] = name;
  }
  return out;
}

String _mermaidType(ColumnModel c) => switch (c.type) {
      DataType.integer => 'int',
      DataType.bigint => 'bigint',
      DataType.smallint => 'smallint',
      DataType.varchar => 'varchar',
      DataType.text => 'text',
      DataType.decimal => 'decimal',
      DataType.float => 'float',
      DataType.boolean => 'boolean',
      DataType.date => 'date',
      DataType.datetime => 'datetime',
      DataType.timestamp => 'timestamp',
      DataType.blob => 'blob',
      DataType.uuid => 'uuid',
      DataType.json => 'json',
    };

/// ---------- DBML (dbdiagram.io) ----------
String exportDbml(Project p) {
  final b = StringBuffer();
  b.writeln(tr('// {0} — สร้างโดย NSL Dev', [p.name.replaceAll(RegExp(r'\s+'), ' ')]));
  for (final t in p.tables) {
    b.writeln();
    b.writeln('Table ${_dbmlId(t.name)} {');
    final pk = t.columns.where((c) => c.isPrimaryKey).toList();
    for (final c in t.columns) {
      final attrs = <String>[
        if (c.isPrimaryKey && pk.length == 1) 'pk',
        if (c.autoIncrement) 'increment',
        if (c.notNull && !c.isPrimaryKey) 'not null',
        if (c.unique && !c.isPrimaryKey) 'unique',
        if ((c.defaultValue ?? '').trim().isNotEmpty) 'default: ${_dbmlDefault(c)}',
        if (c.comment.isNotEmpty) 'note: ${_dbmlStr(c.comment)}',
      ];
      b.writeln('  ${_dbmlId(c.name)} ${_dbmlType(c)}${attrs.isEmpty ? '' : ' [${attrs.join(', ')}]'}');
    }
    if (t.comment.isNotEmpty) {
      b.writeln();
      b.writeln('  Note: ${_dbmlStr(t.comment)}');
    }
    final idx = <String>[
      if (pk.length > 1) '(${pk.map((c) => _dbmlId(c.name)).join(', ')}) [pk]',
      for (final i in t.indexes)
        if (i.columnIds.every((id) => t.columnById(id) != null))
          '${i.columnIds.length == 1 ? _dbmlId(t.columnById(i.columnIds.first)!.name) : '(${i.columnIds.map((id) => _dbmlId(t.columnById(id)!.name)).join(', ')})'}'
              ' [name: ${_dbmlStr(i.name)}${i.unique ? ', unique' : ''}]',
    ];
    if (idx.isNotEmpty) {
      b.writeln();
      b.writeln('  indexes {');
      for (final i in idx) {
        b.writeln('    $i');
      }
      b.writeln('  }');
    }
    b.writeln('}');
  }

  final refs = <String>[];
  for (final r in p.relations) {
    final line = _dbmlRef(p, r);
    if (line != null) refs.add(line);
  }
  if (refs.isNotEmpty) {
    b.writeln();
    refs.forEach(b.writeln);
  }
  return b.toString();
}

String? _dbmlRef(Project p, RelationModel r) {
  final child = p.tableById(r.fromTableId), parent = p.tableById(r.toTableId);
  final cc = child?.columnById(r.fromColumnId), pc = parent?.columnById(r.toColumnId);
  if (child == null || parent == null || cc == null || pc == null) return null;
  final op = isUniqueAlone(child, cc) ? '-' : '>'; // 1:1 หรือ หลาย:1
  final opts = [
    if (r.onDelete != RefAction.noAction) 'delete: ${r.onDelete.sql.toLowerCase()}',
    if (r.onUpdate != RefAction.noAction) 'update: ${r.onUpdate.sql.toLowerCase()}',
  ];
  return 'Ref: ${_dbmlId(child.name)}.${_dbmlId(cc.name)} $op ${_dbmlId(parent.name)}.${_dbmlId(pc.name)}'
      '${opts.isEmpty ? '' : ' [${opts.join(', ')}]'}';
}

/// ชื่อปกติใช้ตรง ๆ ได้; ชื่อที่มีอักขระพิเศษ/ขึ้นต้นด้วยตัวเลข/ภาษาไทยใส่ "..."
String _dbmlId(String s) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(s) ? s : '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

String _dbmlStr(String s) => "'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll(RegExp(r'\r?\n'), '\\n')}'";

String _dbmlType(ColumnModel c) => switch (c.type) {
      DataType.integer => 'int',
      DataType.bigint => 'bigint',
      DataType.smallint => 'smallint',
      DataType.varchar => 'varchar(${c.length ?? 255})',
      DataType.text => 'text',
      DataType.decimal => 'decimal(${c.length ?? 10},${c.scale ?? 2})',
      DataType.float => 'float',
      DataType.boolean => 'boolean',
      DataType.date => 'date',
      DataType.datetime => 'datetime',
      DataType.timestamp => 'timestamp',
      DataType.blob => 'blob',
      DataType.uuid => 'uuid',
      DataType.json => 'json',
    };

/// DBML: ตัวเลข/true/false/null ตรง ๆ, นิพจน์/ฟังก์ชันใน backtick, ข้อความใน '...'
String _dbmlDefault(ColumnModel c) {
  final v = c.defaultValue!.trim();
  final up = v.toUpperCase();
  if (RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(v) && c.type != DataType.varchar && c.type != DataType.text) return v;
  if (up == 'TRUE' || up == 'FALSE' || up == 'NULL') return up.toLowerCase();
  if (up.startsWith('CURRENT_') || up == 'NOW()' || RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\(.*\)$').hasMatch(v)) {
    return '`${v.replaceAll('`', '')}`';
  }
  return _dbmlStr(v);
}

