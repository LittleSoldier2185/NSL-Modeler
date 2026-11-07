import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/layout/diagram_geometry.dart' show noteHeight;
import '../../core/models/dfd_model.dart';
import '../../core/models/enums.dart';
import '../../core/models/workspace.dart';
import '../../core/validate/dfd_validator.dart';
import '../../state/dfd_controller.dart';
import '../dfd/dfd_panels.dart' show dfdKindName;
import '../../core/search/fuzzy.dart';
import '../../state/project_controller.dart';
import '../canvas/canvas_controller.dart';
import '../export/text_export_dialog.dart';
import '../app_actions.dart';
import '../file_actions.dart';
import '../shortcuts.dart';
import '../whats_new_dialog.dart';
import '../workspace_issues_dialog.dart';
import '../theme.dart';
import '../../core/l10n/l10n.dart';

enum PaletteKind { command, table, column, group, note, dfdNode, dfdFlow, issue }

/// ตัวนำหน้าที่จำกัดชนิดของผลค้น: @ ตาราง/กลุ่ม · # คอลัมน์ · : วัตถุและเส้นของ DFD · ! ปัญหา · > คำสั่ง · ~ โน้ต
const Map<String, Set<PaletteKind>> kPalettePrefixes = {
  '@': {PaletteKind.table, PaletteKind.group},
  '#': {PaletteKind.column},
  ':': {PaletteKind.dfdNode, PaletteKind.dfdFlow},
  '!': {PaletteKind.issue},
  '>': {PaletteKind.command},
  '~': {PaletteKind.note},
};

class PaletteEntry {
  const PaletteEntry({
    required this.kind,
    required this.title,
    required this.search,
    required this.run,
    this.subtitle,
    this.shortcut,
  });

  final PaletteKind kind;
  final String title;
  final String? subtitle;
  final String? shortcut;

  /// ข้อความที่ใช้ค้น (ชื่อไทย + คำอังกฤษที่คนมักพิมพ์ เช่น "export sql")
  final String search;
  final VoidCallback run;
}

/// รายการทั้งหมดที่ palette ค้นได้: คำสั่ง + ตาราง + คอลัมน์ของโปรเจกต์ปัจจุบัน
List<PaletteEntry> buildPaletteEntries(BuildContext context) {
  final c = context.read<ProjectController>();
  final w = c.workspaceController;
  final cv = context.read<CanvasController>();
  PaletteEntry cmd(String title, String keywords, VoidCallback run, {String? shortcut}) => PaletteEntry(
        kind: PaletteKind.command,
        title: title,
        search: '$title $keywords',
        shortcut: shortcut,
        run: run,
      );

  final actions = AppActions(context);

  /// คำสั่งที่ผูกกับ [Cmd]: ทำงานและแสดงคีย์ลัดจากแหล่งเดียวกับตัวดักปุ่มจริง
  PaletteEntry byCmd(String title, String keywords, Cmd k) =>
      cmd(title, keywords, () => actions.run(k), shortcut: shortcutText(k).isEmpty ? null : shortcutText(k));

  final commands = <PaletteEntry>[
    byCmd(tr('โปรเจกต์ใหม่'), 'new project', Cmd.newProject),
    byCmd(tr('เปิดไฟล์โปรเจกต์…'), 'open nsld nslm erd', Cmd.open),
    byCmd(tr('บันทึก'), 'save', Cmd.save),
    byCmd(tr('บันทึกเป็น…'), 'save as', Cmd.saveAs),
    byCmd('Export .sql', tr('export sql ddl สคริปต์'), Cmd.exportSql),
    byCmd(tr('Export ภาพ PNG / SVG'), tr('export image png svg รูป'), Cmd.exportImage),
    byCmd('Export Data dictionary (Markdown)', tr('export markdown dictionary เอกสาร'), Cmd.exportText),
    cmd('Export Mermaid', 'export mermaid er diagram',
        () => FileActions.exportText(context, c, kind: TextExportKind.mermaid)),
    cmd('Export DBML', 'export dbml dbdiagram',
        () => FileActions.exportText(context, c, kind: TextExportKind.dbml)),
    cmd(tr('สร้างข้อมูลตัวอย่าง (INSERT)'), tr('sample data insert ข้อมูลทดสอบ'),
        () => FileActions.exportText(context, c, kind: TextExportKind.sample)),
    byCmd(tr('นำเข้าจากไฟล์ .sql…'), 'import sql create table', Cmd.importSql),
    byCmd(tr('เปรียบเทียบกับไฟล์เก่า (Migration)…'), tr('diff migration alter compare เทียบ'), Cmd.compare),
    byCmd(tr('เชื่อมต่อฐานข้อมูล…'), 'database connect mysql mariadb sqlite db เชื่อมต่อ ฐานข้อมูล', Cmd.connectDb),
    byCmd(tr('ย้อนกลับ'), 'undo', Cmd.undo),
    byCmd(tr('ทำซ้ำ'), 'redo', Cmd.redo),
    byCmd(tr('คัดลอกตารางที่เลือก'), 'copy', Cmd.copy),
    byCmd(tr('สร้างตารางแบบฟอร์ม (เหมือน phpMyAdmin)'), 'create table form phpmyadmin columns new', Cmd.createTableForm),
    byCmd(tr('แก้โครงสร้างตารางที่เลือก (ฟอร์ม)'), 'edit alter structure table columns phpmyadmin แก้ไข โครงสร้าง', Cmd.editTableStructure),
    byCmd(tr('จัดกลุ่มตารางที่เลือก'), 'group box frame area section', Cmd.groupSelected),
    byCmd(tr('วางตาราง'), 'paste', Cmd.paste),
    byCmd(tr('ทำสำเนาตารางที่เลือก'), 'duplicate clone', Cmd.duplicate),
    byCmd(tr('เลือกทุกตาราง'), 'select all', Cmd.selectAll),
    byCmd(tr('ลบตาราง / คอลัมน์ที่เลือก'), 'delete remove', Cmd.delete),
    byCmd(tr('เปลี่ยนชื่อที่เลือก'), 'rename', Cmd.rename),
    cmd(tr('จัดวางตารางอัตโนมัติ'), tr('auto layout จัดตำแหน่ง'), () {
      c.autoLayoutTables();
      cv.fit(c.project);
    }),
    cmd(tr('จัดวาง DFD อัตโนมัติ'), tr('auto layout dfd จัดตำแหน่ง แผนภาพกระแสข้อมูล'), () {
      final d = context.read<DfdController>();
      if (w.activeDocument.type == DocType.dfd && d.autoLayout()) d.fit(d.viewport);
    }),
    byCmd(tr('พอดีหน้าจอ'), 'fit zoom', Cmd.fit),
    byCmd(tr('ซูม 100%'), 'zoom reset', Cmd.zoom100),
    byCmd(tr('เพิ่มตาราง'), 'add table', Cmd.toolTable),
    byCmd(tr('โหมดเชื่อม FK'), tr('foreign key relation เส้น'), Cmd.toolFk),
    byCmd(tr('โหมดเลือก'), 'select tool pointer cursor', Cmd.toolSelect),
    byCmd(tr('เพิ่มโน้ต'), 'note', Cmd.toolNote),
    byCmd(tr('ใช้ {0}', [Dialect.mysql.label]), tr('dialect mysql สลับ'), Cmd.dialectMysql),
    byCmd(tr('ใช้ {0}', [Dialect.postgres.label]), tr('dialect postgres สลับ'), Cmd.dialectPostgres),
    byCmd(tr('ใช้ {0}', [Dialect.sqlite.label]), tr('dialect sqlite สลับ'), Cmd.dialectSqlite),
    byCmd(tr('ใช้ {0}', [Dialect.mssql.label]), tr('dialect mssql สลับ'), Cmd.dialectMssql),
    cmd(tr('แสดง SQL Preview'), 'sql preview', () => cv.showDock(DockTab.sql)),
    cmd(tr('แสดงปัญหาที่ตรวจพบ'), tr('issues problems validate ตรวจสอบ'), () => cv.showDock(DockTab.issues)),
    cmd(tr('ปัญหาทั้งโปรเจกต์…'), 'workspace project issues problems all documents ทุกเอกสาร ตรวจสอบ', () => showWorkspaceIssues(context)),
    byCmd(tr('ค้นหาตาราง / คอลัมน์'), 'search find', Cmd.find),
    byCmd(tr('ดูคีย์ลัดทั้งหมด'), 'shortcuts help keyboard', Cmd.help),
    cmd(tr('มีอะไรใหม่ (Patch note)'), 'whats new patch note changelog release version อัปเดต รุ่น', () => showWhatsNew(context)),
    cmd(tr('เกี่ยวกับ NSL Dev'), 'about version เวอร์ชัน รุ่น', () => showAbout(context)),
  ];


  /// กระโดดไปแท็บ ER [docId] ก่อน (ถ้าอยู่แท็บอื่น) แล้วทำต่อด้วย controller ของเอกสารนั้น
  void inEr(String docId, void Function(ProjectController er) f) {
    final er = w.erController(docId);
    if (er == null || !w.openDocument(docId)) return;
    f(er);
  }

  // เอกสาร ER ทุกอัน (อันที่ใช้งานอยู่ก่อน) — มีหลายอัน = ต่อท้ายชื่อเอกสารในคำอธิบายและคำค้น
  final ers = [c.doc, for (final d in w.documents) if (d.type == DocType.er && d.id != c.docId) d];
  final multi = ers.length > 1;
  String inDoc(ProjectDocument d) => multi ? ' · ${d.name}' : '';

  final objects = <PaletteEntry>[
    for (final doc in ers)
      for (final g in doc.er!.groups)
        PaletteEntry(
          kind: PaletteKind.group,
          title: g.name.isEmpty ? tr('(กลุ่มไม่มีชื่อ)') : g.name,
          subtitle: '${tr('กลุ่ม')}${inDoc(doc)}',
          search: '${g.name}${inDoc(doc)}',
          run: () => inEr(doc.id, (er) {
            er.selectGroup(g.id);
            cv.centerOn(Offset(g.x + g.width / 2, g.y + g.height / 2), atLeastScale: 0.5);
          }),
        ),
    for (final doc in ers)
      for (final n in doc.er!.notes)
        if (n.text.trim().isNotEmpty)
          PaletteEntry(
            kind: PaletteKind.note,
            title: n.text.trim().split('\n').first,
            subtitle: '${tr('โน้ต')}${inDoc(doc)}',
            search: '${n.text}${inDoc(doc)}',
            run: () => inEr(doc.id, (_) => cv.centerOn(Offset(n.x + n.width / 2, n.y + noteHeight(n) / 2), atLeastScale: 0.6)),
          ),
    for (final i in c.issues)
      PaletteEntry(
        kind: PaletteKind.issue,
        title: i.title,
        subtitle: i.message,
        search: '${i.title} ${i.message} ${i.code}',
        run: () => inEr(c.docId, (_) {
          final t = i.tableId == null ? null : c.project.tableById(i.tableId!);
          if (t == null) {
            cv.showDock(DockTab.issues);
            return;
          }
          c.selectTable(t.id, columnId: i.columnId);
          cv.focusTable(t);
        }),
      ),
    // ---- แผนภาพ DFD ทุกแท็บ: วัตถุ เส้นข้อมูล และปัญหาของแท็บที่เปิดอยู่ ----
    for (final tab in w.documents.where((t) => t.type == DocType.dfd)) ...[
      for (final n in w.dfdOf(tab.id).nodes)
        PaletteEntry(
          kind: PaletteKind.dfdNode,
          title: n.title.isEmpty ? tr('(ไม่มีชื่อ)') : n.title,
          subtitle: '${tab.name} · ${dfdKindName(n.kind)}',
          search: '${n.title} ${tab.name}',
          run: () => gotoDfd(context, tab.id, node: n.id),
        ),
      for (final f in w.dfdOf(tab.id).flows)
        PaletteEntry(
          kind: PaletteKind.dfdFlow,
          title: f.label.isEmpty ? tr('(ไม่มีชื่อ)') : f.label,
          subtitle: '${tab.name} · ${w.dfdOf(tab.id).nodeById(f.fromId)?.title ?? '?'} → ${w.dfdOf(tab.id).nodeById(f.toId)?.title ?? '?'}',
          search: '${f.label} ${tab.name} ${w.dfdOf(tab.id).nodeById(f.fromId)?.title ?? ''} ${w.dfdOf(tab.id).nodeById(f.toId)?.title ?? ''}',
          run: () => gotoDfd(context, tab.id, flow: f.id),
        ),
    ],
    if (w.activeDocument.type == DocType.dfd)
      for (final i in validateDfd(w.dfdOf(w.activeId), workspace: w.workspace, diagramId: w.activeId))
        PaletteEntry(
          kind: PaletteKind.issue,
          title: i.title,
          subtitle: i.message,
          search: '${i.title} ${i.message} ${i.code}',
          run: () => gotoDfd(context, w.activeId, node: i.tableId, flow: i.relationId),
        ),
    for (final doc in ers)
      for (final t in doc.er!.tables) ...[
        PaletteEntry(
          kind: PaletteKind.table,
          title: t.name,
          subtitle: '${tr('ตาราง · {0} คอลัมน์{1}', [t.columns.length, t.comment.isEmpty ? '' : ' · ${t.comment}'])}${inDoc(doc)}',
          search: '${t.name} ${t.comment}${inDoc(doc)}',
          run: () => inEr(doc.id, (er) {
            er.selectTable(t.id);
            cv.focusTable(t);
          }),
        ),
        for (final col in t.columns)
          PaletteEntry(
            kind: PaletteKind.column,
            title: '${t.name}.${col.name}',
            subtitle: '${tr('คอลัมน์ · {0}{1}', [typeLabel(col), col.comment.isEmpty ? '' : ' · ${col.comment}'])}${inDoc(doc)}',
            search: '${t.name}.${col.name} ${col.comment}${inDoc(doc)}',
            run: () => inEr(doc.id, (er) {
              er.selectTable(t.id, columnId: col.id);
              cv.focusTable(t);
            }),
          ),
      ],
  ];
  return [...commands, ...objects];
}

/// เปิดแท็บ DFD [tabId] แล้วเลือกวัตถุ/เส้นที่ต้องการและเลื่อนไปให้เห็น (รอเฟรมถัดไปเพื่อให้แคนวาสของแท็บนั้นสร้างเสร็จและรู้ขนาด)
void gotoDfd(BuildContext context, String tabId, {String? node, String? flow}) {
  final w = context.read<ProjectController>().workspaceController;
  final d = w.dfdController(tabId);
  if (d == null || !w.openDocument(tabId)) return;
  void apply() {
    if (node != null) {
      d.selectNode(node);
      d.reveal(node, d.viewport);
    } else if (flow != null) {
      d.selectFlow(flow);
      final f = d.diagram.flowById(flow);
      final r = f == null ? null : dfdRoutes(d.diagram)[flow];
      if (r != null) {
        final (x, y) = dfdLabelAnchor(r);
        d.revealPoint(Offset(x, y), d.viewport);
      }
    }
  }

  apply();
  WidgetsBinding.instance.addPostFrameCallback((_) => apply());
}

/// แยกตัวนำหน้า (@ # : ! > ~) ออกจากคำค้น — คืนชุดชนิดที่จำกัด (null = ไม่จำกัด) และคำค้นที่เหลือ
({Set<PaletteKind>? kinds, String query}) parsePaletteQuery(String raw) {
  final t = raw.trimLeft();
  if (t.isNotEmpty && kPalettePrefixes.containsKey(t[0])) {
    return (kinds: kPalettePrefixes[t[0]], query: t.substring(1).trim());
  }
  return (kinds: null, query: raw);
}

/// คำที่ค้นไว้ → รายการที่แสดง
/// ค้นว่าง: คำสั่ง ตาราง กลุ่ม (ไม่แสดงคอลัมน์/วัตถุ DFD/ปัญหาทั้งหมดเพื่อไม่ให้ยาวเกิน)
/// ขึ้นต้นด้วย @ # : ! > ~ = ค้นเฉพาะชนิดนั้น (ตัวนำหน้าอย่างเดียว = แสดงทั้งหมดของชนิดนั้น)
List<PaletteEntry> paletteResults(List<PaletteEntry> all, String query, {int limit = 60}) {
  final p = parsePaletteQuery(query);
  final pool = p.kinds == null ? all : all.where((e) => p.kinds!.contains(e.kind)).toList();
  if (p.query.trim().isEmpty) {
    if (p.kinds != null) return pool.take(limit).toList();
    const hiddenWhenEmpty = {PaletteKind.column, PaletteKind.dfdNode, PaletteKind.dfdFlow, PaletteKind.issue, PaletteKind.note};
    return pool.where((e) => !hiddenWhenEmpty.contains(e.kind)).take(limit).toList();
  }
  return fuzzyRank(pool, p.query, (e) => e.search).take(limit).toList();
}

Future<void> showCommandPalette(BuildContext context) async {
  final entries = buildPaletteEntries(context);
  final picked = await showDialog<PaletteEntry>(
    context: context,
    barrierColor: Colors.black38,
    builder: (_) => CommandPalette(entries: entries),
  );
  // รันหลังปิด palette แล้ว เพื่อให้คำสั่งที่เปิด dialog ต่อทำงานได้ตามปกติ
  picked?.run();
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.entries});
  final List<PaletteEntry> entries;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  static const _rowHeight = 46.0;
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  int _index = 0;

  late List<PaletteEntry> _results = paletteResults(widget.entries, '');

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String q) => setState(() {
        _query = q;
        _results = paletteResults(widget.entries, q);
        _index = 0;
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });

  void _move(int d) {
    if (_results.isEmpty) return;
    setState(() => _index = (_index + d).clamp(0, _results.length - 1));
    if (!_scroll.hasClients) return;
    final top = _index * _rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(top + _rowHeight - view);
    }
  }

  void _pick(int i) {
    if (i >= 0 && i < _results.length) Navigator.pop(context, _results[i]);
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: const Alignment(0, -0.6),
        child: Material(
          color: C.surface,
          borderRadius: BorderRadius.circular(12),
          elevation: 12,
          child: SizedBox(
            width: 580,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Focus(
                onKeyEvent: (node, e) {
                  if (e is KeyUpEvent) return KeyEventResult.ignored;
                  if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _move(1);
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _move(-1);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _ctl,
                  autofocus: true,
                  onChanged: _onQuery,
                  onSubmitted: (_) => _pick(_index),
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: tr('พิมพ์คำสั่ง ชื่อตาราง คอลัมน์ วัตถุ DFD…'),
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr('ไม่พบ "{0}"', [_query]), style: TextStyle(color: C.muted)),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _rowHeight,
                        itemCount: _results.length,
                        itemBuilder: (_, i) => _row(i),
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  Text(tr('↑↓ เลือก'), style: TextStyle(fontSize: 11.5, color: C.muted)),
                  SizedBox(width: 14),
                  Text(tr('Enter ทำงาน'), style: TextStyle(fontSize: 11.5, color: C.muted)),
                  SizedBox(width: 14),
                  Text(tr('Esc ปิด'), style: TextStyle(fontSize: 11.5, color: C.muted)),
                  const Spacer(),
                  Flexible(
                    child: Text(tr('@ ตาราง · # คอลัมน์ · : DFD · ! ปัญหา · > คำสั่ง · ~ โน้ต'),
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: C.muted)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _row(int i) {
    final e = _results[i];
    final on = i == _index;
    final icon = switch (e.kind) {
      PaletteKind.command => Icons.bolt_outlined,
      PaletteKind.table => Icons.table_rows_outlined,
      PaletteKind.column => Icons.view_column_outlined,
      PaletteKind.group => Icons.dashboard_customize_outlined,
      PaletteKind.note => Icons.sticky_note_2_outlined,
      PaletteKind.dfdNode => Icons.account_tree_outlined,
      PaletteKind.dfdFlow => Icons.arrow_right_alt_rounded,
      PaletteKind.issue => Icons.warning_amber_rounded,
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _index = i),
      child: InkWell(
        onTap: () => _pick(i),
        child: Container(
          color: on ? C.primaryTint : null,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Icon(icon, size: 18, color: on ? C.primaryDark : C.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title,
                    overflow: TextOverflow.ellipsis,
                    style: (const {PaletteKind.table, PaletteKind.column}.contains(e.kind) ? monoStyle : const TextStyle())
                        .copyWith(fontSize: 13.5, fontWeight: FontWeight.w500)),
                if (e.subtitle != null)
                  Text(e.subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: C.muted)),
              ]),
            ),
            if (e.shortcut != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(5)),
                child: Text(e.shortcut!, style: monoStyle.copyWith(fontSize: 11, color: C.muted)),
              ),
          ]),
        ),
      ),
    );
  }
}
