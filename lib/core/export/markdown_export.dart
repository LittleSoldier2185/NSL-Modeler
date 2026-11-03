import '../models/column_model.dart';
import '../models/project.dart';
import '../types/type_label.dart';
import '../l10n/l10n.dart';

/// Data dictionary เป็น Markdown: ตาราง -> คอลัมน์ / FK ขาออก / FK ขาเข้า / INDEX
/// ใช้ส่งงานหรือแปะใน README — ผลลัพธ์คงที่ ไม่มีวันที่
String exportDataDictionary(Project p) {
  final b = StringBuffer();
  b.writeln('# ${_inline(p.name)} — Data Dictionary');
  b.writeln();
  b.writeln('- Dialect: ${p.dialect.label}');
  b.writeln(tr('- {0} ตาราง · {1} ความสัมพันธ์', [p.tables.length, p.relations.length]));
  if (p.tables.isEmpty) {
    b.writeln();
    b.writeln(tr('_ยังไม่มีตาราง_'));
    return b.toString();
  }

  b.writeln();
  b.writeln(tr('## สารบัญ'));
  b.writeln();
  for (final t in p.tables) {
    b.writeln('- [${_inline(t.name)}](#${_anchor(t.name)})${t.comment.isEmpty ? '' : ' — ${_inline(t.comment)}'}');
  }

  for (final t in p.tables) {
    b.writeln();
    b.writeln('## ${_inline(t.name)}');
    if (t.comment.isNotEmpty) {
      b.writeln();
      b.writeln(_inline(t.comment));
    }
    b.writeln();
    if (t.columns.isEmpty) {
      b.writeln(tr('_ไม่มีคอลัมน์_'));
      continue;
    }
    final fkCols = {
      for (final r in p.relations)
        if (r.fromTableId == t.id) r.fromColumnId: r
    };
    b.writeln(tr('| # | คอลัมน์ | ชนิด | Key | Null | ค่าเริ่มต้น | หมายเหตุ |'));
    b.writeln('|--:|---------|------|-----|:----:|-------------|----------|');
    for (var i = 0; i < t.columns.length; i++) {
      final c = t.columns[i];
      final keys = [
        if (c.isPrimaryKey) 'PK',
        if (fkCols.containsKey(c.id)) 'FK',
        if (c.unique && !c.isPrimaryKey) 'UQ',
        if (c.autoIncrement) 'AI',
      ].join(' ');
      final nullable = !(c.notNull || c.isPrimaryKey);
      b.writeln('| ${i + 1} | ${_cell(c.name)} | ${_cell(typeLabel(c))} | $keys | ${nullable ? '✓' : ''} | '
          '${_cell(_def(c))} | ${_cell(c.comment)} |');
    }

    final out = [
      for (final r in p.relations)
        if (r.fromTableId == t.id) r
    ];
    if (out.isNotEmpty) {
      b.writeln();
      b.writeln(tr('**อ้างถึง (FK)**'));
      b.writeln();
      for (final r in out) {
        b.writeln('- ${_cell(_ref(p, r.fromTableId, r.fromColumnId))} → ${_cell(_ref(p, r.toTableId, r.toColumnId))}'
            '${_actions(r.onDelete.sql, r.onUpdate.sql)}');
      }
    }
    final incoming = [
      for (final r in p.relations)
        if (r.toTableId == t.id && r.fromTableId != t.id) r
    ];
    if (incoming.isNotEmpty) {
      b.writeln();
      b.writeln(tr('**ถูกอ้างถึงโดย**'));
      b.writeln();
      for (final r in incoming) {
        b.writeln('- ${_cell(_ref(p, r.fromTableId, r.fromColumnId))}');
      }
    }
    if (t.indexes.isNotEmpty) {
      b.writeln();
      b.writeln('**INDEX**');
      b.writeln();
      for (final i in t.indexes) {
        final cols = i.columnIds.map((id) => t.columnById(id)?.name ?? '?').join(', ');
        b.writeln('- `${i.name}` ($cols)${i.unique ? ' — UNIQUE' : ''}');
      }
    }
  }
  return b.toString();
}

String _def(ColumnModel c) {
  final v = (c.defaultValue ?? '').trim();
  return v.isEmpty ? '' : v;
}

String _ref(Project p, String tableId, String columnId) {
  final t = p.tableById(tableId);
  return '${t?.name ?? '?'}.${t?.columnById(columnId)?.name ?? '?'}';
}

String _actions(String del, String upd) {
  final parts = [
    if (del != 'NO ACTION') 'ON DELETE $del',
    if (upd != 'NO ACTION') 'ON UPDATE $upd',
  ];
  return parts.isEmpty ? '' : ' (${parts.join(', ')})';
}

/// ข้อความในบรรทัดเดียว (หัวข้อ/รายการ)
String _inline(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// ข้อความในช่องตาราง: escape `|` และแปลงขึ้นบรรทัดใหม่
String _cell(String s) => s.replaceAll('\\', '\\\\').replaceAll('|', '\\|').replaceAll(RegExp(r'\r?\n'), '<br>');

/// anchor แบบ GitHub: ตัวพิมพ์เล็ก ช่องว่างเป็น - ตัดอักขระพิเศษ (คงตัวอักษรไทย/ตัวเลข/_/-)
String _anchor(String s) => _inline(s)
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}_\- ]', unicode: true), '')
    .replaceAll(' ', '-');

