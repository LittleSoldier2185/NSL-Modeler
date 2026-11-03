import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/enums.dart';
import '../../core/search/fuzzy.dart';
import '../../state/project_controller.dart';
import '../canvas/canvas_controller.dart';
import '../export/text_export_dialog.dart';
import '../app_actions.dart';
import '../file_actions.dart';
import '../shortcuts.dart';
import '../theme.dart';
import '../../core/l10n/l10n.dart';

enum PaletteKind { command, table, column }

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
    byCmd(tr('เปิดไฟล์โปรเจกต์…'), 'open erd', Cmd.open),
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
    byCmd(tr('ย้อนกลับ'), 'undo', Cmd.undo),
    byCmd(tr('ทำซ้ำ'), 'redo', Cmd.redo),
    byCmd(tr('คัดลอกตารางที่เลือก'), 'copy', Cmd.copy),
    byCmd(tr('สร้างตารางแบบฟอร์ม (เหมือน phpMyAdmin)'), 'create table form phpmyadmin columns new', Cmd.createTableForm),
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
    byCmd(tr('ค้นหาตาราง / คอลัมน์'), 'search find', Cmd.find),
    byCmd(tr('ดูคีย์ลัดทั้งหมด'), 'shortcuts help keyboard', Cmd.help),
  ];

  final objects = <PaletteEntry>[
    for (final t in c.project.tables) ...[
      PaletteEntry(
        kind: PaletteKind.table,
        title: t.name,
        subtitle: tr('ตาราง · {0} คอลัมน์{1}', [t.columns.length, t.comment.isEmpty ? '' : ' · ${t.comment}']),
        search: '${t.name} ${t.comment}',
        run: () {
          c.selectTable(t.id);
          cv.focusTable(t);
        },
      ),
      for (final col in t.columns)
        PaletteEntry(
          kind: PaletteKind.column,
          title: '${t.name}.${col.name}',
          subtitle: tr('คอลัมน์ · {0}{1}', [typeLabel(col), col.comment.isEmpty ? '' : ' · ${col.comment}']),
          search: '${t.name}.${col.name} ${col.comment}',
          run: () {
            c.selectTable(t.id, columnId: col.id);
            cv.focusTable(t);
          },
        ),
    ],
  ];
  return [...commands, ...objects];
}

/// คำที่ค้นไว้ → รายการที่แสดง (ค้นว่าง: คำสั่งก่อน แล้วตาราง ไม่แสดงคอลัมน์ทั้งหมดเพื่อไม่ให้ยาวเกิน)
List<PaletteEntry> paletteResults(List<PaletteEntry> all, String query, {int limit = 60}) {
  if (query.trim().isEmpty) {
    return all.where((e) => e.kind != PaletteKind.column).take(limit).toList();
  }
  return fuzzyRank(all, query, (e) => e.search).take(limit).toList();
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
                    hintText: tr('พิมพ์คำสั่ง หรือชื่อตาราง / คอลัมน์…'),
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
                    style: (e.kind == PaletteKind.command ? const TextStyle() : monoStyle)
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
