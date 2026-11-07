import '../models/column_model.dart';
import '../models/project.dart';
import '../models/workspace.dart';
import '../validate/issue.dart';
import '../validate/workspace_validator.dart';
import 'workspace_summary.dart';
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

  _tables(b, p, '##');
  return b.toString();
}

/// Data dictionary ของทั้งโปรเจกต์: ภาพรวม (เอกสาร ตัวเลขสรุป ปัญหา) -> ER ทุกอัน -> DFD ทุกอัน
/// โปรเจกต์ที่มี ER ชิ้นเดียวและไม่มีเอกสารอื่น = ผลลัพธ์เดียวกับ [exportDataDictionary] ทุกตัวอักษร
String exportWorkspaceDictionary(Workspace w) {
  if (isSingleErWorkspace(w)) return exportDataDictionary(knownDocs(w).first.er!);
  // ER ทุกอันก่อน แล้ว DFD ทุกอัน (ตามลำดับเอกสารในแต่ละชนิด)
  final docs = [...w.documentsOf(DocType.er), ...w.documentsOf(DocType.dfd)];
  final c = workspaceCounts(w);
  final issues = exportIssues(w);
  final b = StringBuffer();
  b.writeln('# ${_inline(w.name.trim().isEmpty ? 'project' : w.name)} — Data Dictionary');
  b.writeln();
  b.writeln(tr('## ภาพรวมโปรเจกต์'));
  b.writeln();
  b.writeln(tr('- {0} เอกสาร ({1} ER · {2} DFD)', [c.docs, c.ers, c.dfds]));
  b.writeln(tr('- {0} ตาราง · {1} ความสัมพันธ์', [c.tables, c.relations]));
  b.writeln(tr('- {0} วัตถุ DFD · {1} เส้นข้อมูล', [c.objects, c.flows]));
  final ec = issues.where((i) => i.issue.severity == Severity.error).length;
  b.writeln(tr('- {0} ข้อผิดพลาด · {1} คำเตือน', [ec, issues.length - ec]));
  b.writeln();
  b.writeln(tr('**เอกสารในโปรเจกต์**'));
  b.writeln();
  for (final d in docs) {
    if (d.type == DocType.er) {
      final p = d.er!;
      b.writeln('- ER: ${_inline(d.name)} — ${p.dialect.label} · ${tr('{0} ตาราง · {1} ความสัมพันธ์', [p.tables.length, p.relations.length])}');
    } else {
      final g = d.dfd!;
      b.writeln('- DFD: ${_inline(d.name)} — ${tr('{0} วัตถุ DFD · {1} เส้นข้อมูล', [g.nodes.length, g.flows.length])}');
    }
  }
  b.writeln();
  b.writeln(tr('**ปัญหาที่ตรวจพบทั้งโปรเจกต์**'));
  b.writeln();
  if (issues.isEmpty) {
    b.writeln(tr('_ไม่พบปัญหา_'));
  } else {
    for (final i in issues) {
      b.writeln('- ${severityLabel(i.issue.severity)} · ${_inline(i.docName)}: ${_inline(i.issue.title)} — ${_inline(i.issue.message)}');
    }
  }

  for (final d in docs) {
    b.writeln();
    if (d.type == DocType.er) {
      final p = d.er!;
      b.writeln('## ER: ${_inline(d.name)}');
      b.writeln();
      b.writeln('- Dialect: ${p.dialect.label}');
      b.writeln(tr('- {0} ตาราง · {1} ความสัมพันธ์', [p.tables.length, p.relations.length]));
      if (p.tables.isEmpty) {
        b.writeln();
        b.writeln(tr('_ยังไม่มีตาราง_'));
      } else {
        _tables(b, p, '###');
      }
    } else {
      _dfd(b, w, d, [for (final i in issues) if (i.docId == d.id) i]);
    }
  }
  return b.toString();
}

void _dfd(StringBuffer b, Workspace w, ProjectDocument d, List<WorkspaceIssue> issues) {
  final g = d.dfd!;
  b.writeln('## DFD: ${_inline(d.name)}');
  b.writeln();
  b.writeln(tr('- {0} วัตถุ DFD · {1} เส้นข้อมูล', [g.nodes.length, g.flows.length]));
  if (g.nodes.isEmpty) {
    b.writeln();
    b.writeln(tr('_ไม่มีวัตถุ_'));
  } else {
    b.writeln();
    b.writeln('**${tr('วัตถุ')}**');
    b.writeln();
    b.writeln(tr('| ชนิด | เลข/รหัส | ชื่อ | ตาราง ER | แผนภาพย่อย |'));
    b.writeln('|------|----------|------|----------|------------|');
    for (final n in g.nodes) {
      final child = n.childId == null ? null : w.documentById(n.childId!)?.name;
      b.writeln('| ${dfdKindLabel(n.kind)} | ${_cell(n.number)} | ${_cell(n.name)} | '
          '${_cell(dfdStoreTableLabel(w, n) ?? '')} | ${_cell(child ?? '')} |');
    }
    if (g.flows.isNotEmpty) {
      b.writeln();
      b.writeln('**${tr('เส้นข้อมูล')}**');
      b.writeln();
      b.writeln(tr('| จาก | ทิศทาง | ถึง | ป้ายชื่อ |'));
      b.writeln('|-----|:------:|-----|----------|');
      for (final f in g.flows) {
        final from = g.nodeById(f.fromId)?.title ?? '?', to = g.nodeById(f.toId)?.title ?? '?';
        b.writeln('| ${_cell(from)} | ${f.bidirectional ? '↔' : '→'} | ${_cell(to)} | ${_cell(f.label)} |');
      }
    }
  }
  if (issues.isNotEmpty) {
    b.writeln();
    b.writeln(tr('**ปัญหาที่ตรวจพบ**'));
    b.writeln();
    for (final i in issues) {
      b.writeln('- ${severityLabel(i.issue.severity)} · ${_inline(i.issue.title)} — ${_inline(i.issue.message)}');
    }
  }
}

void _tables(StringBuffer b, Project p, String h) {
  for (final t in p.tables) {
    b.writeln();
    b.writeln('$h ${_inline(t.name)}');
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

