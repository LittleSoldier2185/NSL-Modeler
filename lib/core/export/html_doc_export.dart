import '../l10n/l10n.dart';
import '../models/column_model.dart';
import '../models/project.dart';
import '../models/workspace.dart';
import '../models/table_model.dart';
import '../types/type_label.dart';
import '../validate/issue.dart';
import '../validate/workspace_validator.dart';
import '../validate/flowchart_validator.dart' show fcShapeLabel;
import 'dfd_svg.dart';
import 'flowchart_svg.dart';
import 'screenflow_svg.dart';
import 'wireframe_svg.dart';
import '../validate/screenflow_validator.dart' show sfKindLabel;
import 'workspace_summary.dart';
import 'svg_export.dart';

/// เอกสารโครงสร้างฐานข้อมูลเป็นไฟล์ HTML ไฟล์เดียว (CSS ฝังในไฟล์ ไม่มี JavaScript ไม่เรียกของภายนอก)
/// - มีสารบัญ ภาพแผนภาพ ER (SVG ฝัง) แผนภาพ DFD และรายละเอียดทุกตาราง
/// - ปรับสีตามโหมดมืด/สว่างของเครื่องผู้อ่าน และมี CSS สำหรับพิมพ์ — เปิดในเบราว์เซอร์แล้วสั่งพิมพ์เป็น PDF ได้
/// ผลลัพธ์คงที่ (ไม่มีวันที่/สุ่ม)
/// - โปรเจกต์ที่มี ER ชิ้นเดียวและไม่มีเอกสารอื่น (หรือไม่มีเอกสารเลย) = รูปแบบเดิม
/// - นอกนั้น = ภาพรวมโปรเจกต์ (เอกสาร ตัวเลขสรุป ปัญหาทั้งโปรเจกต์) -> ER ทุกอัน (ตามลำดับเอกสาร มี dialect ของตัวเอง)
///   -> DFD ทุกอัน (ภาพ + ตารางวัตถุ/เส้นข้อมูล + ปัญหาของ DFD นั้น) ; anchor ของตารางมี id เอกสารนำหน้ากันชนข้าม ER
String exportHtmlDocument(Workspace w, {bool includeDiagrams = true}) {
  final docs = knownDocs(w);
  final legacy = docs.isEmpty || isSingleErWorkspace(w);
  final erDocs = [for (final d in docs) if (d.type == DocType.er) d];
  final dfdDocs = [for (final d in docs) if (d.type == DocType.dfd) d];
  final fcDocs = [for (final d in docs) if (d.type == DocType.flowchart) d];
  final wfDocs = [for (final d in docs) if (d.type == DocType.wireframe) d];
  final sfDocs = [for (final d in docs) if (d.type == DocType.screenflow) d];
  final p0 = erDocs.firstOrNull?.er ?? Project(name: w.name);
  final b = StringBuffer();
  final title = _esc(legacy
      ? (p0.name.trim().isEmpty ? 'schema' : p0.name.trim())
      : (w.name.trim().isEmpty ? 'project' : w.name.trim()));
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
  if (legacy) {
    b.writeln('<p class="meta">${_esc(p0.dialect.label)} · ${_esc(tr('{0} ตาราง · {1} ความสัมพันธ์', [p0.tables.length, p0.relations.length]))}</p>');
  } else {
    final c = workspaceCounts(w);
    b.writeln('<p class="meta">${_esc(docCountLine(c))}</p>');
  }
  b.writeln('</header>');

  final prefixOf = {for (final d in erDocs) d.id: legacy ? '' : '${_safeId(d.id)}-'};
  final erSvgs = {
    for (final d in erDocs) d.id: includeDiagrams ? exportSvg(d.er!, includeNotes: true) : null,
  };
  String erDiagramId(ProjectDocument d) => legacy ? 'er-diagram' : 'er-${_safeId(d.id)}';

  // สารบัญ
  final hasAny = erDocs.any((d) => d.er!.tables.isNotEmpty) ||
      dfdDocs.isNotEmpty ||
      fcDocs.isNotEmpty ||
      wfDocs.isNotEmpty ||
      sfDocs.isNotEmpty;
  if (hasAny || !legacy) {
    b.writeln('<nav aria-label="${_esc(tr('สารบัญ'))}">');
    b.writeln('<h2>${_esc(tr('สารบัญ'))}</h2>');
    b.writeln('<ul>');
    if (!legacy) b.writeln('<li><a href="#overview">${_esc(tr('ภาพรวมโปรเจกต์'))}</a></li>');
    for (final d in erDocs) {
      if (!legacy) b.writeln('<li><a href="#erdoc-${_safeId(d.id)}">ER: ${_esc(d.name)}</a></li>');
      if (erSvgs[d.id] != null) b.writeln('<li><a href="#${erDiagramId(d)}">${_esc(tr('แผนภาพ ER'))}</a></li>');
      for (final t in d.er!.tables) {
        final c = t.comment.trim().isEmpty ? '' : ' <span class="muted">— ${_esc(_oneLine(t.comment))}</span>';
        b.writeln('<li><a href="#${_anchor(t, prefixOf[d.id]!)}">${_esc(t.name)}</a>$c</li>');
      }
    }
    for (final d in dfdDocs) {
      b.writeln('<li><a href="#dfd-${_esc(d.id)}">DFD: ${_esc(d.name)}</a></li>');
    }
    for (final d in fcDocs) {
      b.writeln('<li><a href="#fc-${_safeId(d.id)}">Flowchart: ${_esc(d.name)}</a></li>');
    }
    for (final d in wfDocs) {
      b.writeln('<li><a href="#wf-${_safeId(d.id)}">Wireframe: ${_esc(d.name)}</a></li>');
    }
    for (final d in sfDocs) {
      b.writeln('<li><a href="#sf-${_safeId(d.id)}">Screen Flow: ${_esc(d.name)}</a></li>');
    }
    b.writeln('</ul>');
    b.writeln('</nav>');
  }

  if (!legacy) _overview(b, w, [...erDocs, ...dfdDocs, ...fcDocs, ...wfDocs, ...sfDocs]);

  for (final d in erDocs) {
    final p = d.er!;
    final pre = prefixOf[d.id]!;
    if (!legacy) {
      b.writeln('<section class="group" id="erdoc-${_safeId(d.id)}">');
      b.writeln('<h2>ER: ${_esc(d.name)}</h2>');
      b.writeln('<p class="meta">${_esc(p.dialect.label)} · ${_esc(tr('{0} ตาราง · {1} ความสัมพันธ์', [p.tables.length, p.relations.length]))}</p>');
      b.writeln('</section>');
    }
    final erSvg = erSvgs[d.id];
    if (erSvg != null) {
      b.writeln('<section id="${erDiagramId(d)}">');
      b.writeln('<h2>${_esc(tr('แผนภาพ ER'))}</h2>');
      b.writeln('<div class="diagram">${_inlineSvg(erSvg)}</div>');
      b.writeln('</section>');
    }
    if (p.tables.isEmpty) {
      b.writeln('<p class="muted">${_esc(tr('ยังไม่มีตาราง'))}</p>');
    }
    for (final t in p.tables) {
      _table(b, p, t, pre);
    }
  }
  if (erDocs.isEmpty && legacy) b.writeln('<p class="muted">${_esc(tr('ยังไม่มีตาราง'))}</p>');

  final issues = exportIssues(w);
  for (final d in dfdDocs) {
    _dfd(b, w, d, [for (final i in issues) if (i.docId == d.id) i], includeDiagrams);
  }
  for (final d in fcDocs) {
    _flowchart(b, d, [for (final i in issues) if (i.docId == d.id) i], includeDiagrams);
  }
  for (final d in wfDocs) {
    _wireframe(b, w, d, [for (final i in issues) if (i.docId == d.id) i], includeDiagrams);
  }
  for (final d in sfDocs) {
    _screenflow(b, w, d, [for (final i in issues) if (i.docId == d.id) i], includeDiagrams);
  }
  b.writeln('<footer>${_esc(tr('สร้างโดย NSL Dev'))}</footer>');
  b.writeln('</main>');
  b.writeln('</body>');
  b.writeln('</html>');
  return b.toString();
}

void _overview(StringBuffer b, Workspace w, List<ProjectDocument> docs) {
  final c = workspaceCounts(w);
  final issues = exportIssues(w);
  final ec = issues.where((i) => i.issue.severity == Severity.error).length;
  b.writeln('<section id="overview">');
  b.writeln('<h2>${_esc(tr('ภาพรวมโปรเจกต์'))}</h2>');
  b.writeln('<ul>');
  b.writeln('<li>${_esc(docCountLine(c))}</li>');
  b.writeln('<li>${_esc(tr('{0} ตาราง · {1} ความสัมพันธ์', [c.tables, c.relations]))}</li>');
  b.writeln('<li>${_esc(tr('{0} วัตถุ DFD · {1} เส้นข้อมูล', [c.objects, c.flows]))}</li>');
  if (c.fcs > 0) b.writeln('<li>${_esc(tr('{0} สัญลักษณ์ Flowchart · {1} เส้นเชื่อม', [c.symbols, c.fcEdges]))}</li>');
  if (c.wfs > 0) b.writeln('<li>${_esc(tr('{0} ชิ้นส่วน Wireframe', [c.components]))}</li>');
  if (c.sfs > 0) b.writeln('<li>${_esc(tr('{0} หน้าจอใน Screen Flow · {1} การเปลี่ยนหน้า', [c.screens, c.navs]))}</li>');
  b.writeln('<li>${_esc(tr('{0} ข้อผิดพลาด · {1} คำเตือน', [ec, issues.length - ec]))}</li>');
  b.writeln('</ul>');
  b.writeln('<h3>${_esc(tr('เอกสารในโปรเจกต์'))}</h3><ul>');
  for (final d in docs) {
    if (d.type == DocType.er) {
      final p = d.er!;
      b.writeln('<li><a href="#erdoc-${_safeId(d.id)}">ER: ${_esc(d.name)}</a> <span class="muted">— ${_esc(p.dialect.label)} · '
          '${_esc(tr('{0} ตาราง · {1} ความสัมพันธ์', [p.tables.length, p.relations.length]))}</span></li>');
    } else if (d.type == DocType.flowchart) {
      final g = d.flowchart!;
      b.writeln('<li><a href="#fc-${_safeId(d.id)}">Flowchart: ${_esc(d.name)}</a> <span class="muted">— '
          '${_esc(tr('{0} สัญลักษณ์ · {1} เส้นเชื่อม', [g.nodes.length, g.edges.length]))}</span></li>');
    } else if (d.type == DocType.wireframe) {
      b.writeln('<li><a href="#wf-${_safeId(d.id)}">Wireframe: ${_esc(d.name)}</a> <span class="muted">— '
          '${_esc(wireframeSummary(d.wireframe!))}</span></li>');
    } else if (d.type == DocType.screenflow) {
      final g = d.screenflow!;
      b.writeln('<li><a href="#sf-${_safeId(d.id)}">Screen Flow: ${_esc(d.name)}</a> <span class="muted">— '
          '${_esc(tr('{0} หน้าจอ · {1} การเปลี่ยนหน้า', [g.nodes.length, g.edges.length]))}</span></li>');
    } else {
      final g = d.dfd!;
      b.writeln('<li><a href="#dfd-${_esc(d.id)}">DFD: ${_esc(d.name)}</a> <span class="muted">— '
          '${_esc(tr('{0} วัตถุ DFD · {1} เส้นข้อมูล', [g.nodes.length, g.flows.length]))}</span></li>');
    }
  }
  b.writeln('</ul>');
  b.writeln('<h3>${_esc(tr('ปัญหาที่ตรวจพบทั้งโปรเจกต์'))}</h3>');
  if (issues.isEmpty) {
    b.writeln('<p class="muted">${_esc(tr('ไม่พบปัญหา'))}</p>');
  } else {
    b.writeln('<table><thead><tr><th>${_esc(tr('ระดับ'))}</th><th>${_esc(tr('เอกสาร'))}</th><th>${_esc(tr('ปัญหา'))}</th></tr></thead><tbody>');
    for (final i in issues) {
      b.writeln('<tr><td>${_sev(i.issue.severity)}</td><td>${_esc(i.docName)}</td>'
          '<td>${_esc(i.issue.title)} <span class="muted">— ${_esc(_oneLine(i.issue.message))}</span></td></tr>');
    }
    b.writeln('</tbody></table>');
  }
  b.writeln('</section>');
}

String _sev(Severity s) => '<span class="tag sev-${s.name}">${_esc(severityLabel(s))}</span>';

void _dfd(StringBuffer b, Workspace w, ProjectDocument d, List<WorkspaceIssue> issues, bool includeDiagrams) {
  final g = d.dfd!;
  b.writeln('<section id="dfd-${_esc(d.id)}">');
  b.writeln('<h2>DFD: ${_esc(d.name)}</h2>');
  b.writeln('<p class="meta">${_esc(tr('{0} วัตถุ DFD · {1} เส้นข้อมูล', [g.nodes.length, g.flows.length]))}</p>');
  if (g.nodes.isEmpty) {
    b.writeln('<p class="muted">${_esc(tr('ไม่มีวัตถุ'))}</p>');
  } else {
    final svg = includeDiagrams ? exportDfdSvg(g, title: d.name) : null; // ธีมสว่างเสมอ
    if (svg != null) b.writeln('<div class="diagram">${_inlineSvg(svg)}</div>');
    b.writeln('<h3>${_esc(tr('วัตถุ'))}</h3>');
    b.writeln('<table><thead><tr><th>${_esc(tr('ชนิด'))}</th><th>${_esc(tr('เลข/รหัส'))}</th><th>${_esc(tr('ชื่อ'))}</th>'
        '<th>${_esc(tr('ตาราง ER'))}</th><th>${_esc(tr('แผนภาพย่อย'))}</th></tr></thead><tbody>');
    for (final n in g.nodes) {
      final childId = n.childId;
      final child = childId == null ? null : w.documentById(childId);
      final childCell = child == null ? '' : '<a href="#dfd-${_esc(child.id)}">${_esc(child.name)}</a>';
      b.writeln('<tr><td>${_esc(dfdKindLabel(n.kind))}</td><td>${_esc(n.number)}</td><td>${_esc(n.name)}</td>'
          '<td>${_esc(dfdStoreTableLabel(w, n) ?? '')}</td><td>$childCell</td></tr>');
    }
    b.writeln('</tbody></table>');
    if (g.flows.isNotEmpty) {
      b.writeln('<h3>${_esc(tr('เส้นข้อมูล'))}</h3>');
      b.writeln('<table><thead><tr><th>${_esc(tr('จาก'))}</th><th class="c">${_esc(tr('ทิศทาง'))}</th><th>${_esc(tr('ถึง'))}</th>'
          '<th>${_esc(tr('ป้ายชื่อ'))}</th></tr></thead><tbody>');
      for (final f in g.flows) {
        b.writeln('<tr><td>${_esc(g.nodeById(f.fromId)?.title ?? '?')}</td><td class="c">${f.bidirectional ? '↔' : '→'}</td>'
            '<td>${_esc(g.nodeById(f.toId)?.title ?? '?')}</td><td>${_esc(f.label)}</td></tr>');
      }
      b.writeln('</tbody></table>');
    }
  }
  if (issues.isNotEmpty) {
    b.writeln('<h3>${_esc(tr('ปัญหาที่ตรวจพบ'))}</h3><ul>');
    for (final i in issues) {
      b.writeln('<li>${_sev(i.issue.severity)} ${_esc(i.issue.title)} <span class="muted">— ${_esc(_oneLine(i.issue.message))}</span></li>');
    }
    b.writeln('</ul>');
  }
  b.writeln('</section>');
}

void _flowchart(StringBuffer b, ProjectDocument d, List<WorkspaceIssue> issues, bool includeDiagrams) {
  final g = d.flowchart!;
  b.writeln('<section id="fc-${_safeId(d.id)}">');
  b.writeln('<h2>Flowchart: ${_esc(d.name)}</h2>');
  b.writeln('<p class="meta">${_esc(tr('{0} สัญลักษณ์ · {1} เส้นเชื่อม', [g.nodes.length, g.edges.length]))}</p>');
  if (g.nodes.isEmpty) {
    b.writeln('<p class="muted">${_esc(tr('ไม่มีสัญลักษณ์'))}</p>');
  } else {
    final svg = includeDiagrams ? exportFlowchartSvg(g, title: d.name) : null; // ธีมสว่างเสมอ
    if (svg != null) b.writeln('<div class="diagram">${_inlineSvg(svg)}</div>');
    b.writeln('<h3>${_esc(tr('สัญลักษณ์'))}</h3>');
    b.writeln('<table><thead><tr><th>${_esc(tr('ชนิด'))}</th><th>${_esc(tr('ข้อความ'))}</th></tr></thead><tbody>');
    for (final n in g.nodes) {
      b.writeln('<tr><td>${_esc(fcShapeLabel(n.shape))}</td><td>${_esc(n.text).replaceAll('\n', '<br>')}</td></tr>');
    }
    b.writeln('</tbody></table>');
    if (g.edges.isNotEmpty) {
      b.writeln('<h3>${_esc(tr('เส้นเชื่อม'))}</h3>');
      b.writeln('<table><thead><tr><th>${_esc(tr('จาก'))}</th><th>${_esc(tr('ถึง'))}</th><th>${_esc(tr('ป้าย'))}</th></tr></thead><tbody>');
      for (final e in g.edges) {
        b.writeln('<tr><td>${_esc(fcNodeText(g, e.fromId))}</td><td>${_esc(fcNodeText(g, e.toId))}</td><td>${_esc(e.label)}</td></tr>');
      }
      b.writeln('</tbody></table>');
    }
  }
  if (issues.isNotEmpty) {
    b.writeln('<h3>${_esc(tr('ปัญหาที่ตรวจพบ'))}</h3><ul>');
    for (final i in issues) {
      b.writeln('<li>${_sev(i.issue.severity)} ${_esc(i.issue.title)} <span class="muted">— ${_esc(_oneLine(i.issue.message))}</span></li>');
    }
    b.writeln('</ul>');
  }
  b.writeln('</section>');
}

void _issueList(StringBuffer b, List<WorkspaceIssue> issues) {
  if (issues.isEmpty) return;
  b.writeln('<h3>${_esc(tr('ปัญหาที่ตรวจพบ'))}</h3><ul>');
  for (final i in issues) {
    b.writeln('<li>${_sev(i.issue.severity)} ${_esc(i.issue.title)} <span class="muted">— ${_esc(_oneLine(i.issue.message))}</span></li>');
  }
  b.writeln('</ul>');
}

void _wireframe(StringBuffer b, Workspace w, ProjectDocument d, List<WorkspaceIssue> issues, bool includeDiagrams) {
  final g = d.wireframe!;
  b.writeln('<section id="wf-${_safeId(d.id)}">');
  b.writeln('<h2>Wireframe: ${_esc(d.name)}</h2>');
  b.writeln('<p class="meta">${_esc(wireframeSummary(g))}</p>');
  final linked = screensLinkingTo(w, d.id);
  if (linked.isNotEmpty) b.writeln('<p class="meta">${_esc(tr('ใช้ใน Screen Flow: {0}', [linked.join(', ')]))}</p>');
  // ภาพตามรูปแบบการแสดงผลของเอกสาร (แสดงแม้ยังไม่มีชิ้นส่วน = กรอบหน้าจอเปล่า)
  if (includeDiagrams) b.writeln('<div class="diagram">${_inlineSvg(exportWireframeSvg(g, title: d.name))}</div>');
  if (g.components.isEmpty) {
    b.writeln('<p class="muted">${_esc(tr('ไม่มีชิ้นส่วน'))}</p>');
  } else {
    b.writeln('<h3>${_esc(tr('ชิ้นส่วน'))}</h3>');
    b.writeln('<table><thead><tr><th>${_esc(tr('ชนิด'))}</th><th>${_esc(tr('ข้อความ'))}</th><th>${_esc(tr('ตำแหน่ง / ขนาด'))}</th>'
        '<th>${_esc(tr('สถานะ'))}</th><th>${_esc(tr('ข้อมูล ER'))}</th></tr></thead><tbody>');
    for (final r in wireframeRows(w, g)) {
      b.writeln('<tr><td style="padding-left:${10 + r.depth * 16}px">${_esc(r.kind)}</td><td>${_esc(r.text).replaceAll('\n', '<br>')}</td>'
          '<td>${_esc(r.geometry)}</td><td>${_esc(r.state)}</td><td>${_esc(r.binding)}</td></tr>');
    }
    b.writeln('</tbody></table>');
  }
  _issueList(b, issues);
  b.writeln('</section>');
}

void _screenflow(StringBuffer b, Workspace w, ProjectDocument d, List<WorkspaceIssue> issues, bool includeDiagrams) {
  final g = d.screenflow!;
  b.writeln('<section id="sf-${_safeId(d.id)}">');
  b.writeln('<h2>Screen Flow: ${_esc(d.name)}</h2>');
  b.writeln('<p class="meta">${_esc(tr('{0} หน้าจอ · {1} การเปลี่ยนหน้า', [g.nodes.length, g.edges.length]))}</p>');
  if (g.nodes.isEmpty) {
    b.writeln('<p class="muted">${_esc(tr('ไม่มีหน้าจอ'))}</p>');
  } else {
    final svg = includeDiagrams
        ? exportScreenFlowSvg(g, title: d.name, wireframeOf: (id) => w.documentById(id)?.wireframe)
        : null; // ธีมสว่างเสมอ
    if (svg != null) b.writeln('<div class="diagram">${_inlineSvg(svg)}</div>');
    b.writeln('<h3>${_esc(tr('หน้าจอ'))}</h3>');
    b.writeln('<table><thead><tr><th>${_esc(tr('ชนิด'))}</th><th>${_esc(tr('ชื่อ'))}</th><th>Wireframe</th></tr></thead><tbody>');
    for (final n in g.nodes) {
      final wf = n.wireframeId == null ? null : w.documentById(n.wireframeId!);
      final cell = wf?.wireframe != null ? '<a href="#wf-${_safeId(wf!.id)}">${_esc(wf.name)}</a>' : _esc(sfWireframeLabel(w, n));
      b.writeln('<tr><td>${_esc(sfKindLabel(n.kind))}</td><td>${_esc(n.title)}</td><td>$cell</td></tr>');
    }
    b.writeln('</tbody></table>');
    if (g.edges.isNotEmpty) {
      b.writeln('<h3>${_esc(tr('การเปลี่ยนหน้า'))}</h3>');
      b.writeln('<table><thead><tr><th>${_esc(tr('จาก'))}</th><th>${_esc(tr('ถึง'))}</th><th>${_esc(tr('เมื่อ (trigger)'))}</th>'
          '<th>${_esc(tr('เงื่อนไข'))}</th></tr></thead><tbody>');
      for (final e in g.edges) {
        b.writeln('<tr><td>${_esc(sfNodeText(g, e.fromId))}</td><td>${_esc(sfNodeText(g, e.toId))}</td>'
            '<td>${_esc(e.label)}</td><td>${_esc(e.condition)}</td></tr>');
      }
      b.writeln('</tbody></table>');
    }
  }
  _issueList(b, issues);
  b.writeln('</section>');
}

String _safeId(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

void _table(StringBuffer b, Project p, TableModel t, String pre) {
  b.writeln('<section class="table" id="${_anchor(t, pre)}">');
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
      final link = to == null ? _esc(target) : '<a href="#${_anchor(to, pre)}">${_esc(target)}</a>';
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
      final link = from == null ? '?' : '<a href="#${_anchor(from, pre)}">${_esc(from.name)}</a>';
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
String _anchor(TableModel t, String pre) => 't-$pre${t.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

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
.tag.sev-error{background:#fee2e2;color:#991b1b}.tag.sev-warning{background:var(--pk);color:var(--pkfg)}
.group h2{font-size:24px;margin:0}
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
