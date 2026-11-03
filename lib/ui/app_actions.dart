import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/enums.dart';
import '../state/project_controller.dart';
import '../core/layout/diagram_geometry.dart';
import 'canvas/canvas_controller.dart';
import 'create_table_dialog.dart';
import 'file_actions.dart';
import 'palette/command_palette.dart';
import 'prompt_dialog.dart';
import 'shortcuts.dart';
import 'shortcuts_help.dart';
import '../core/l10n/l10n.dart';

/// การทำงานจริงของคำสั่งทั้งหมดใน [Cmd] — ใช้ร่วมกันระหว่างคีย์ลัด เมนู และ command palette
class AppActions {
  AppActions(this.context)
      : c = context.read<ProjectController>(),
        cv = context.read<CanvasController>();

  final BuildContext context;
  final ProjectController c;
  final CanvasController cv;

  /// นับการวางซ้ำข้อความเดิม เพื่อเลื่อนตำแหน่งทีละขั้นไม่ให้วางทับกัน
  static String? _lastPasted;
  static int _pasteCount = 0;

  static const nudgeStep = 10.0;
  static const nudgeBigStep = 50.0;

  /// คำสั่งทุกตัวต้องมีการทำงาน (เทสต์ตรวจว่าคีย์ไม่ถูกผูกกับคำสั่งที่ไม่มีอะไรทำ)
  Map<Cmd, VoidCallback> get map => {
        Cmd.newProject: () => FileActions.newProject(context, c),
        Cmd.open: () => FileActions.open(context, c),
        Cmd.save: () => FileActions.save(context, c),
        Cmd.saveAs: () => FileActions.saveAs(context, c),
        Cmd.exportSql: () => FileActions.exportSql(context, c),
        Cmd.exportImage: () => FileActions.exportImage(context, c),
        Cmd.exportText: () => FileActions.exportText(context, c),
        Cmd.importSql: () => FileActions.importSqlFile(context, c),
        Cmd.compare: () => FileActions.compareWithFile(context, c),
        Cmd.undo: c.undo,
        Cmd.redo: c.redo,
        Cmd.copy: copy,
        Cmd.paste: paste,
        Cmd.duplicate: duplicate,
        Cmd.selectAll: c.selectAllTables,
        Cmd.delete: deleteSelection,
        Cmd.rename: rename,
        Cmd.toolSelect: () => cv.setTool(CanvasTool.select),
        Cmd.toolTable: () => cv.setTool(CanvasTool.table),
        Cmd.toolFk: () => cv.setTool(CanvasTool.fk),
        Cmd.toolNote: () => cv.setTool(CanvasTool.note),
        Cmd.createTableForm: createTableFromForm,
        Cmd.groupSelected: groupSelected,
        Cmd.escape: escape,
        Cmd.fit: () => cv.fit(c.project),
        Cmd.zoom100: cv.resetZoom,
        Cmd.nudgeLeft: () => c.nudgeSelected(-nudgeStep, 0),
        Cmd.nudgeRight: () => c.nudgeSelected(nudgeStep, 0),
        Cmd.nudgeUp: () => c.nudgeSelected(0, -nudgeStep),
        Cmd.nudgeDown: () => c.nudgeSelected(0, nudgeStep),
        Cmd.nudgeLeftBig: () => c.nudgeSelected(-nudgeBigStep, 0),
        Cmd.nudgeRightBig: () => c.nudgeSelected(nudgeBigStep, 0),
        Cmd.nudgeUpBig: () => c.nudgeSelected(0, -nudgeBigStep),
        Cmd.nudgeDownBig: () => c.nudgeSelected(0, nudgeBigStep),
        Cmd.find: cv.searchFocus.requestFocus,
        Cmd.palette: () => showCommandPalette(context),
        Cmd.dialectMysql: () => c.setDialect(Dialect.mysql),
        Cmd.dialectPostgres: () => c.setDialect(Dialect.postgres),
        Cmd.dialectSqlite: () => c.setDialect(Dialect.sqlite),
        Cmd.dialectMssql: () => c.setDialect(Dialect.mssql),
        Cmd.help: () => showShortcutsHelp(context),
      };

  void run(Cmd cmd) => map[cmd]!();

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  /// สร้างตารางแบบฟอร์มคอลัมน์ทั้งหมดในหน้าเดียว (เหมือน phpMyAdmin) แล้ววางกลางจอ
  Future<void> createTableFromForm() async {
    final t = await showCreateTableDialog(context, newId: c.newId);
    if (t == null) return;
    final center = cv.toWorld(cv.viewport.center(Offset.zero));
    final at = Offset(snapToGrid(center.dx - t.width / 2), snapToGrid(center.dy - tableHeight(t) / 2));
    final added = c.addBuiltTable(t, x: at.dx < 0 ? 40 : at.dx, y: at.dy < 0 ? 60 : at.dy);
    if (context.mounted) cv.focusTable(added);
  }

  /// Ctrl+G: จัดตารางที่เลือกเป็นกลุ่ม (สร้างกรอบครอบ แล้วเข้าโหมดพิมพ์ชื่อทันที)
  void groupSelected() {
    final g = c.groupSelectedTables();
    if (g == null) {
      _toast(tr('เลือกตารางก่อน จึงจะจัดกลุ่มได้'));
      return;
    }
    cv.requestGroupEdit(g.id);
  }

  /// Ctrl+C: คัดลอกตารางที่เลือก (+ FK ระหว่างกัน) ลงคลิปบอร์ดของระบบ
  Future<void> copy() async {
    final text = c.copySelectionText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    _lastPasted = null;
    _pasteCount = 0;
    if (context.mounted) _toast(tr('คัดลอก {0} ตาราง', [c.selectionCount]));
  }

  /// Ctrl+V: วางตารางจากคลิปบอร์ด (วางซ้ำจะเลื่อนทีละขั้น)
  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    _pasteCount = text == _lastPasted ? _pasteCount + 1 : 1;
    _lastPasted = text;
    final pasted = c.pasteTableText(text, offset: 30.0 * _pasteCount);
    if (pasted.isEmpty) {
      _pasteCount = 0;
      _lastPasted = null;
      if (context.mounted) _toast(tr('ไม่มีตารางของ NSL Modeler ในคลิปบอร์ด'));
      return;
    }
    if (context.mounted) cv.focusTable(pasted.last);
  }

  /// Ctrl+D: ทำสำเนาตารางที่เลือก
  void duplicate() {
    final copies = c.duplicateSelected();
    if (copies.isNotEmpty) cv.focusTable(copies.last);
  }

  /// Delete: ลบคอลัมน์ที่เลือก (ถ้าเลือกตารางเดียวและมีคอลัมน์ที่เลือก) ไม่เช่นนั้นลบตารางที่เลือกทั้งหมด
  void deleteSelection() {
    // เลือกกลุ่มอยู่ = ลบกลุ่ม (ตารางข้างในไม่ถูกลบ)
    final g = c.selectedGroup;
    if (g != null) {
      c.removeGroup(g.id);
      return;
    }
    final t = c.selectedTable;
    final col = c.selectedColumn;
    if (t != null && col != null && c.selectionCount == 1) {
      c.removeColumn(t.id, col.id);
    } else {
      c.removeSelectedTables();
    }
  }

  /// Esc: ยกเลิกเครื่องมือที่ค้างอยู่ก่อน ถ้าอยู่โหมดเลือกแล้วจึงล้างการเลือก
  void escape() {
    if (cv.tool != CanvasTool.select || cv.fkSource != null) {
      cv.setTool(CanvasTool.select);
    } else {
      c.clearSelection();
    }
  }

  /// F2: เปลี่ยนชื่อคอลัมน์ที่เลือก (ถ้ามี) หรือตารางที่เลือก
  Future<void> rename() async {
    final g = c.selectedGroup;
    if (g != null) {
      cv.requestGroupEdit(g.id); // F2 บนกลุ่ม = พิมพ์ชื่อบนแถบชื่อ
      return;
    }
    final t = c.selectedTable;
    if (t == null) return;
    final col = c.selectedColumn;
    final current = col?.name ?? t.name;
    final name = await promptText(
      context,
      title: col != null ? tr('เปลี่ยนชื่อคอลัมน์') : tr('เปลี่ยนชื่อตาราง'),
      initial: current,
      label: col != null ? '${t.name}.' : tr('ชื่อตาราง'),
    );
    if (name == null || name.isEmpty || name == current) return;
    if (col != null) {
      c.updateColumn(t.id, col.id, (x) => x.name = name);
    } else {
      c.renameTable(t.id, name);
    }
  }
}
