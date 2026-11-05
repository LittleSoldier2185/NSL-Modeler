import '../l10n/l10n.dart';
import '../models/column_model.dart';
import '../models/diagram.dart';
import '../models/project.dart';
import '../models/table_model.dart';
import '../types/type_label.dart';
import 'dfd_svg.dart';
import 'svg_export.dart';

/// เอกสารโครงสร้างฐานข้อมูลเป็นไฟล์ HTML ไฟล์เดียว (CSS ฝังในไฟล์ ไม่มี JavaScript ไม่เรียกของภายนอก)
/// - มีสารบัญ ภาพแผนภาพ ER (SVG ฝัง) แผนภาพ DFD และรายละเอียดทุกตาราง
/// - ปรับสีตามโหมดมืด/สว่างของเครื่องผู้อ่าน และมี CSS สำหรับพิมพ์ — เปิดในเบราว์เซอร์แล้วสั่งพิมพ์เป็น PDF ได้
/// ผลลัพธ์คงที่ (ไม่มีวันที่/สุ่ม)
String exportHtmlDocument(Project p, {bool includeDiagrams = true}) {
  final b = StringBuffer();
  final title = _esc(p.name.trim().isEmpty ? 'schema' : p.name.trim());
  b.writeln('<!DOCTYPE html>');
  b.writeln('<html lang="${currentLang.code}">');
  b.writeln('<head>');
  b.writeln('<meta charset="utf-8">');
  b.writeln('<meta name="viewport" content="width=device-width, initial-scale=1">');
  b.writeln('<title>$title — Data Dictionary</title>');
  b.writeln('<style>$_css</style>');
  b.writeln('</head>');
  b.writeln('<body>');
  b.writeln('<main>');
  b.writeln('<header>');
  b.writeln('<h1>$title</h1>');
  b.writeln('<p class="meta">${_esc(p.dialect.label)} · ${_esc(tr('{0} ตาราง · {1} ความสัมพันธ์', [p.tables.length, p.relations.length]))}</p>');
  b.writeln('</header>');

  // สารบัญ
  final dfdTabs = [for (final d in p.diagrams) if (d.kind == DiagramKind.dfd && p.dfdOf(d.id).nodes.isNotEmpty) d];
  final erSvg = includeDiagrams ? exportSvg(p, includeNotes: true) : null;
  if (p.tables.isNotEmpty || dfdTabs.isNotEmpty) {
    b.writeln('<nav aria-label="${_esc(tr('สารบัญ'))}">');
    b.writeln('<h2>${_esc(tr('สารบัญ'))}</h2>');
    b.writeln('<ul>');
    if (erSvg != null) b.writeln('<li><a href="#er-diagram">${_esc(tr('แผนภาพ ER'))}</a></li>');
    for (final d in includeDiagrams ? dfdTabs : const <DiagramTab>[]) {
      b.writeln('<li><a href="#dfd-${_esc(d.id)}">DFD: ${_esc(d.name)}</a></li>');
    }
    for (final t in p.tables) {
      final c = t.comment.trim().isEmpty ? '' : ' <span class="muted">— ${_esc(_oneLine(t.comment))}</span>';
      b.writeln('<li><a href="#${_anchor(t)}">${_esc(t.name)}</a>$c</li>');
    }
    b.writeln('</ul>');
    b.writeln('</nav>');
  }

  if (erSvg != null) {
    b.writeln('<section id="er-diagram">');
    b.writeln('<h2>${_esc(tr('แผนภาพ ER'))}</h2>');
    b.writeln('<div class="diagram">${_inlineSvg(erSvg)}</div>');
    b.writeln('</section>');
  }
  if (includeDiagrams) {
    for (final d in dfdTabs) {
      final svg = exportDfdSvg(p.dfdOf(d.id), title: d.name);
      if (svg == null) continue;
      b.writeln('<section id="dfd-${_esc(d.id)}">');
      b.writeln('<h2>DFD: ${_esc(d.name)}</h2>');
      b.writeln('<div class="diagram">${_inlineSvg(svg)}</div>');
      b.writeln('</section>');
    }
  }

  if (p.tables.isEmpty) {
    b.writeln('<p class="muted">${_esc(tr('ยังไม่มีตาราง'))}</p>');
  }
  for (final t in p.tables) {
    _table(b, p, t);
  }
  b.writeln('<footer>${_esc(tr('สร้างโดย NSL Dev'))}</footer>');
  b.writeln('</main>');
  b.writeln('</body>');
  b.writeln('</html>');
  return b.toString();
}

void _table(StringBuffer b, Project p, TableModel t) {
  b.writeln('<section class="table" id="${_anchor(t)}">');
  b.writeln('<h2>${_esc(t.name)}</h2>');
  if (t.comment.trim().isNotEmpty) b.writeln('<p class="comment">${_esc(t.comment.trim()).replaceAll('\n', '<br>')}</p>');
  if (t.columns.isEmpty) {
    b.writeln('<p class="muted">${_esc(tr('ไม่มีคอลัมน์'))}</p>');
    b.writeln('</section>');
    return;
  }
  final fkCols = {for (final r in p.relations) if (r.fromTableId == t.id) r.fromColumnId};
  b.writeln('<table>');
  b.writeln('<thead><tr><th class="num">#</th><th>${_esc(tr('คอลัมน์'))}</th><th>${_esc(tr('ชนิด'))}</th>'
      '<th>Key</th><th class="c">Null</th><th>${_esc(tr('ค่าเริ่มต้น'))}</th><th>${_esc(tr('หมายเหตุ'))}</th></tr></thead>');
  b.writeln('<tbody>');
  for (var i = 0; i < t.columns.length; i++) {
    final c = t.columns[i];
    final keys = <String>[
      if (c.isPrimaryKey) '<span class="tag pk">PK</span>',
      if (fkCols.contains(c.id)) '<span class="tag fk">FK</span>',
      if (c.unique && !c.isPrimaryKey) '<span class="tag">UQ</span>',
      if (c.autoIncrement) '<span class="tag">AI</span>',
    ];
    final nullable = !(c.notNull || c.isPrimaryKey);
    b.writeln('<tr><td class="num">${i + 1}</td><td><code>${_esc(c.name)}</code></td><td>${_esc(typeLabel(c))}</td>'
        '<td>${keys.join(' ')}</td><td class="c">${nullable ? '✓' : ''}</td><td>${_esc(_def(c))}</td>'
        '<td>${_esc(c.comment.trim()).replaceAll('\n', '<br>')}</td></tr>');
  }
  b.writeln('</tbody></table>');

  final out = [for (final r in p.relations) if (r.fromTableId == t.id) r];
  if (out.isNotEmpty) {
    b.writeln('<h3>${_esc(tr('อ้างถึง (FK)'))}</h3><ul>');
    for (final r in out) {
      final to = p.tableById(r.toTableId);
      final target = to == null ? '?' : to.name;
      final link = to == null ? _esc(target) : '<a href="#${_anchor(to)}">${_esc(target)}</a>';
      final actions = [
        if (r.onDelete.sql != 'NO ACTION') 'ON DELETE ${r.onDelete.sql}',
        if (r.onUpdate.sql != 'NO ACTION') 'ON UPDATE ${r.onUpdate.sql}',
      ];
      b.writeln('<li><code>${_esc(t.columnById(r.fromColumnId)?.name ?? '?')}</code> → $link.'
          '<code>${_esc(to?.columnById(r.toColumnId)?.name ?? '?')}</code>'
          '${actions.isEmpty ? '' : ' <span class="muted">(${actions.join(', ')})</span>'}</li>');
    }
    b.writeln('</ul>');
  }
  final incoming = [for (final r in p.relations) if (r.toTableId == t.id && r.fromTableId != t.id) r];
  if (incoming.isNotEmpty) {
    b.writeln('<h3>${_esc(tr('ถูกอ้างถึงโดย'))}</h3><ul>');
    for (final r in incoming) {
      final from = p.tableById(r.fromTableId);
      final link = from == null ? '?' : '<a href="#${_anchor(from)}">${_esc(from.name)}</a>';
      b.writeln('<li>$link.<code>${_esc(from?.columnById(r.fromColumnId)?.name ?? '?')}</code></li>');
    }
    b.writeln('</ul>');
  }
  if (t.indexes.isNotEmpty) {
    b.writeln('<h3>INDEX</h3><ul>');
    for (final i in t.indexes) {
      final cols = i.columnIds.map((id) => t.columnById(id)?.name ?? '?').join(', ');
      b.writeln('<li><code>${_esc(i.name)}</code> (${_esc(cols)})${i.unique ? ' <span class="tag">UNIQUE</span>' : ''}</li>');
    }
    b.writeln('</ul>');
  }
  b.writeln('</section>');
}

String _def(ColumnModel c) => (c.defaultValue ?? '').trim();

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// id ของ anchor ต่อตาราง — ใช้ id ภายในไม่ใช่ชื่อ (ชื่อซ้ำ/มีอักขระพิเศษก็ไม่ชน)
String _anchor(TableModel t) => 't-${t.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

/// ตัดส่วนหัว `<?xml ...?>` ออก และให้ภาพย่อลงตามความกว้างหน้า
String _inlineSvg(String svg) {
  var s = svg.replaceFirst(RegExp(r'^\s*<\?xml[^>]*\?>\s*'), '');
  // width/height ตายตัวทำให้ล้นจอ : เก็บ viewBox ไว้แล้วให้ CSS คุมขนาด (ER ไม่มี viewBox ใน attribute → เติมให้)
  final m = RegExp(r'<svg\b[^>]*>').firstMatch(s);
  if (m == null) return s;
  var tag = m.group(0)!;
  final w = RegExp(r'\swidth="([\d.]+)"').firstMatch(tag)?.group(1);
  final h = RegExp(r'\sheight="([\d.]+)"').firstMatch(tag)?.group(1);
  if (!tag.contains('viewBox') && w != null && h != null) {
    tag = tag.replaceFirst('<svg', '<svg viewBox="0 0 $w $h"');
  }
  tag = tag.replaceAll(RegExp(r'\s(width|height)="[\d.]+"'), '');
  return s.replaceRange(m.start, m.end, tag);
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const _css = '''
:root{--bg:#fff;--fg:#1e293b;--muted:#64748b;--line:#e2e8f0;--head:#f1f5f9;--accent:#0f766e;--tag:#e2e8f0;--tagfg:#334155;--pk:#fef3c7;--pkfg:#92400e;--fk:#dbeafe;--fkfg:#1e40af}
@media (prefers-color-scheme:dark){:root{--bg:#0f172a;--fg:#e2e8f0;--muted:#94a3b8;--line:#334155;--head:#1e293b;--accent:#5eead4;--tag:#334155;--tagfg:#e2e8f0;--pk:#78350f;--pkfg:#fde68a;--fk:#1e3a8a;--fkfg:#bfdbfe}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 "Noto Sans Thai","Segoe UI",system-ui,sans-serif}
main{max-width:1040px;margin:0 auto;padding:32px 20px 48px}
h1{font-size:28px;margin:0 0 4px}
h2{font-size:20px;margin:0 0 10px;padding-top:4px}
h3{font-size:14px;margin:16px 0 6px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
.meta,.muted{color:var(--muted)}
nav{margin:20px 0;padding:14px 18px;background:var(--head);border-radius:10px}
nav h2{font-size:15px;margin:0 0 6px}
nav ul{margin:0;padding-left:20px;columns:2}
section{margin:28px 0;padding-top:12px;border-top:1px solid var(--line)}
.diagram{overflow:auto;border:1px solid var(--line);border-radius:10px;padding:8px}
.diagram svg{max-width:100%;height:auto;display:block}
.comment{margin:0 0 10px;color:var(--muted)}
table{width:100%;border-collapse:collapse;font-size:13.5px}
th,td{padding:6px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{background:var(--head);font-weight:600}
.num{width:36px;text-align:right;color:var(--muted)}
.c{text-align:center}
code{font:13px/1.4 Consolas,"Cascadia Mono",monospace}
.tag{display:inline-block;padding:0 6px;border-radius:4px;background:var(--tag);color:var(--tagfg);font-size:11.5px;font-weight:600}
.tag.pk{background:var(--pk);color:var(--pkfg)}.tag.fk{background:var(--fk);color:var(--fkfg)}
ul{margin:4px 0;padding-left:22px}
footer{margin-top:40px;color:var(--muted);font-size:12px;text-align:center}
@media print{
:root{--bg:#fff;--fg:#000;--muted:#475569;--line:#cbd5e1;--head:#f1f5f9}
body{font-size:12px}main{max-width:none;padding:0}
section.table{break-inside:avoid}
nav ul{columns:3}.diagram{overflow:visible;break-inside:avoid}
a{color:inherit}
}
''';
