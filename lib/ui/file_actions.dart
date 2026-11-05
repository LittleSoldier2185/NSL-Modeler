import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/export/dfd_svg.dart';
import '../core/export/seed_data.dart';
import '../core/models/diagram.dart';
import '../core/export/selection_crop.dart';
import '../core/export/sql_export.dart';
import '../core/layout/diagram_geometry.dart';
import '../core/parser/sql_decode.dart';
import '../core/parser/sql_importer.dart';
import '../core/models/project.dart';
import '../core/export/svg_export.dart';
import '../state/app_settings.dart';
import 'board_size_dialog.dart';
import 'export/dfd_png.dart';
import '../core/db/db_session.dart' show DbKind;
import '../core/db/mysql_data.dart';
import '../core/db/sqlite_data.dart';
import 'data_browser_dialog.dart';
import 'db_connect_dialog.dart';
import 'export/diagram_png.dart';
import 'export/export_image_dialog.dart';
import 'export/text_export_dialog.dart';
import 'import_dialog.dart';
import 'migration_dialog.dart';
import '../core/models/enums.dart';
import '../core/storage/project_file.dart';
import '../core/validate/issue.dart';
import 'canvas/canvas_controller.dart';
import '../state/project_controller.dart';
import '../core/l10n/l10n.dart';

/// เปิด/บันทึก/โปรเจกต์ใหม่ พร้อมถามก่อนทิ้งงานที่ยังไม่บันทึก
class FileActions {
  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  /// true = ไปต่อได้ (บันทึกแล้ว / ไม่บันทึก / ไม่มีอะไรค้าง)
  static Future<bool> confirmDiscard(BuildContext context, ProjectController c) async {
    if (!c.dirty) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('มีการแก้ไขที่ยังไม่ได้บันทึก')),
        content: Text(tr('ต้องการบันทึกก่อนหรือไม่')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text(tr('ยกเลิก'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(tr('ไม่บันทึก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    if (r == 'save') {
      if (!context.mounted) return false;
      return save(context, c);
    }
    return r == 'discard';
  }

  static Future<void> newProject(BuildContext context, ProjectController c) async {
    if (!await confirmDiscard(context, c)) return;
    if (!context.mounted) return;
    final size = await showBoardSizeDialog(context, title: tr('โปรเจกต์ใหม่'), confirmLabel: tr('สร้าง'));
    if (size == null) return;
    c.newProject(boardWidth: size.width, boardHeight: size.height);
  }

  /// เปลี่ยนขนาดกระดานของโปรเจกต์ที่เปิดอยู่ (undo ได้)
  static Future<void> changeBoardSize(BuildContext context, ProjectController c) async {
    final size = await showBoardSizeDialog(
      context,
      title: tr('ขนาดกระดาน'),
      confirmLabel: tr('ตกลง'),
      width: c.project.boardWidth,
      height: c.project.boardHeight,
    );
    if (size != null) c.setBoardSize(size.width, size.height);
  }

  static Future<void> open(BuildContext context, ProjectController c) async {
    if (!await confirmDiscard(context, c)) return;
    final f = await FilePicker.pickFile(
      dialogTitle: tr('เปิดโปรเจกต์'),
      type: FileType.custom,
      allowedExtensions: kOpenableExts,
    );
    final path = f?.path;
    if (path == null) return;
    try {
      c.loadProject(await ProjectFile.load(path), path);
    } on ProjectFormatException catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, tr('เปิดไฟล์ไม่ได้: {0}', [e]));
    }
  }

  /// นำเข้าจากไฟล์ .sql (CREATE TABLE ฯลฯ) -> แทนที่โปรเจกต์ หลังพรีวิวและยืนยัน
  static Future<void> importSqlFile(BuildContext context, ProjectController c) async {
    if (!await confirmDiscard(context, c)) return;
    final f = await FilePicker.pickFile(
      dialogTitle: tr('นำเข้าจากไฟล์ .sql'),
      type: FileType.custom,
      allowedExtensions: ['sql', 'ddl', 'txt'],
    );
    final path = f?.path;
    if (path == null) return;
    try {
      final sql = decodeSqlBytes(await File(path).readAsBytes());
      final fileName = path.split(RegExp(r'[\\/]')).last;
      final name = fileName.replaceFirst(RegExp(r'\.[^.]*$'), '');
      final result = importSql(sql, name: name);
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => ImportPreviewDialog(result: result, fileName: fileName),
      );
      if (ok != true) return;
      c.loadImported(result.project);
      if (!context.mounted) return;
      final cv = context.read<CanvasController>();
      cv.fit(c.project);
      if (result.notes.any((n) => n.warning)) cv.showDock(DockTab.issues);
    } catch (e) {
      if (context.mounted) _toast(context, tr('นำเข้าไม่ได้: {0}', [e]));
    }
  }

  /// เชื่อมต่อ MySQL/MariaDB (อ่านอย่างเดียว) แล้วนำโครงสร้างเข้ามาเป็นแผนภาพ หรือเทียบกับแผนภาพปัจจุบันเพื่อสร้าง migration
  static Future<void> connectDatabase(BuildContext context, ProjectController c) async {
    final out = await showDialog<DbConnectOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DbConnectDialog(projectDialect: c.project.dialect),
    );
    if (out == null || !context.mounted) return;
    if (out.action == DbAction.browse) {
      final cfg = out.config!;
      await showDataBrowser(
        context,
        title: out.label,
        opener: (writable) async => out.kind == DbKind.sqlite
            ? SqliteDataSession.open(cfg.database, writable: writable)
            : await MysqlDataSession.open(cfg, writable: writable),
      );
      return;
    }
    final read = out.read!;
    if (out.action == DbAction.compare) {
      // ฝั่งฐานข้อมูลคือ "ของเก่า" แผนภาพปัจจุบันคือ "ของใหม่": สคริปต์ที่ได้ทำให้ฐานข้อมูลตรงกับแผนภาพ
      await showDialog<void>(
        context: context,
        builder: (_) => MigrationDialog(old: read.import.project, neu: c.project, oldLabel: out.label, sqlitePath: out.sqlitePath),
      );
      return;
    }
    if (!await confirmDiscard(context, c) || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ImportPreviewDialog(result: read.import, fileName: out.label),
    );
    if (ok != true) return;
    c.loadImported(read.import.project);
    if (!context.mounted) return;
    final cv = context.read<CanvasController>();
    cv.fit(c.project);
    if (read.import.notes.any((n) => n.warning)) cv.showDock(DockTab.issues);
  }

  /// เลือกไฟล์โปรเจกต์เก่า (.nsld / .nslm / .erd) มาเทียบกับโปรเจกต์ปัจจุบัน -> หน้าต่างรายการเปลี่ยนแปลง + สคริปต์ migration
  static Future<void> compareWithFile(BuildContext context, ProjectController c) async {
    final f = await FilePicker.pickFile(
      dialogTitle: tr('เลือกไฟล์โปรเจกต์เวอร์ชันเก่าเพื่อเปรียบเทียบ'),
      type: FileType.custom,
      allowedExtensions: kOpenableExts,
    );
    final path = f?.path;
    if (path == null) return;
    try {
      final old = await ProjectFile.load(path);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => MigrationDialog(
          old: old,
          neu: c.project,
          oldLabel: path.split(RegExp(r'[\\/]')).last,
        ),
      );
    } on ProjectFormatException catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, tr('เปิดไฟล์ไม่ได้: {0}', [e]));
    }
  }

  /// ชื่อไฟล์ภาพ `ชื่อโปรเจกต์_diagram.png|svg` (ตัดอักขระที่ Windows ห้ามใช้)
  static String imageFileName(String projectName, ImageFormat f) =>
      '${safeName(projectName)}_diagram.${f.name}';

  /// ชื่อโปรเจกต์ที่ใช้เป็นส่วนของชื่อไฟล์ได้ (ตัดอักขระที่ Windows ห้าม; ว่าง = schema)
  static String safeName(String projectName) {
    final base = projectName.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    return base.isEmpty ? 'schema' : base;
  }

  /// เปิดหน้าต่าง Export เอกสาร/ข้อมูล (Data dictionary, Mermaid, DBML, ข้อมูลตัวอย่าง)
  static Future<void> exportText(BuildContext context, ProjectController c,
      {TextExportKind kind = TextExportKind.dictionary}) async {
    if (c.project.tables.isEmpty) {
      _toast(context, tr('ยังไม่มีตารางให้ Export'));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => TextExportDialog(project: c.project, initial: kind),
    );
  }

  /// บันทึกข้อความ (UTF-8 ไม่มี BOM) ลงไฟล์ที่ผู้ใช้เลือก
  static Future<void> saveText(BuildContext context, String text, String fileName, String title) async {
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: title,
        fileName: fileName,
        bytes: utf8.encode(text),
      );
      if (uri == null) return;
      var path = uri.toFilePath();
      final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.')) : '';
      if (ext.isNotEmpty && !path.toLowerCase().endsWith(ext)) path = '$path$ext';
      await File(path).writeAsString(text);
      if (context.mounted) _toast(context, tr('บันทึกแล้ว: {0}', [path]));
    } catch (e) {
      if (context.mounted) _toast(context, tr('บันทึกไม่ได้: {0}', [e]));
    }
  }

  /// Export แผนภาพเป็น PNG หรือ SVG (ทั้งแผนภาพ ไม่ขึ้นกับว่าตอนนี้ซูม/เลื่อนอยู่ตรงไหน)
  static Future<void> exportImage(BuildContext context, ProjectController c, {ImageArea? initialArea}) async {
    if (c.activeDiagram.kind == DiagramKind.dfd) return _exportDfdImage(context, c);
    final p = c.project;
    if (p.tables.isEmpty && p.notes.isEmpty) {
      _toast(context, tr('ยังไม่มีตารางให้ Export เป็นภาพ'));
      return;
    }
    // ตารางที่ถือว่าเลือกอยู่: ที่เลือกเอง + ตารางในกลุ่มที่เลือกอยู่ (เลือกกลุ่ม = export กลุ่มทั้งก้อน)
    final gid = c.selectedGroupId;
    final selGroup = gid == null ? null : p.groupById(gid);
    final selected = {...c.selectedTableIds, if (selGroup != null) ...groupMembers(p, selGroup).tables};
    final showFlow = context.read<AppSettings>().showFlow;
    final opts = await showDialog<ImageExportOptions>(
      context: context,
      builder: (_) =>
          ExportImageDialog(hasNotes: p.notes.isNotEmpty, hasSelection: selected.isNotEmpty, initialArea: initialArea),
    );
    if (opts == null || !context.mounted) return;

    // เลือกพื้นที่: เฉพาะตารางที่เลือก (ทำโปรเจกต์ย่อย) / ทั้งกระดาน / เฉพาะส่วนที่มีตาราง (ค่าเริ่มต้น)
    var src = p;
    var includeNotes = opts.includeNotes;
    DiagramBounds? bounds;
    switch (opts.area) {
      case ImageArea.selection:
        // กรอบกลุ่มที่เกี่ยวข้องติดไปด้วย (ดู cropToSelection)
        src = cropToSelection(p, selected, groupId: gid, groupIds: c.attachedGroupIds);
        includeNotes = false;
      case ImageArea.board:
        bounds = boardBounds(p);
      case ImageArea.content:
        break;
    }
    try {
      late final Uint8List bytes;
      var note = '';
      if (opts.format == ImageFormat.svg) {
        bytes = Uint8List.fromList(utf8.encode(exportSvg(src, includeNotes: includeNotes, bounds: bounds, dark: opts.dark, flowMarkers: showFlow)!));
      } else {
        final png = await exportPng(src, scale: opts.scale, includeNotes: includeNotes, bounds: bounds, dark: opts.dark, flowMarkers: showFlow);
        if (png == null) return;
        bytes = png.bytes;
        if (png.scale < opts.scale) note = tr(' (ลดสเกลเหลือ {0}x เพราะภาพใหญ่เกินไป)', [png.scale.toStringAsFixed(1)]);
      }
      final uri = await FilePicker.saveFile(
        dialogTitle: tr('Export ภาพ {0}', [opts.format.name.toUpperCase()]),
        fileName: imageFileName(p.name, opts.format),
        bytes: bytes,
      );
      if (uri == null) return;
      var path = uri.toFilePath();
      if (!path.toLowerCase().endsWith('.${opts.format.name}')) path = '$path.${opts.format.name}';
      await File(path).writeAsBytes(bytes);
      if (context.mounted) _toast(context, tr('Export แล้ว: {0}{1}', [path, note]));
    } catch (e) {
      if (context.mounted) _toast(context, tr('Export ภาพไม่ได้: {0}', [e]));
    }
  }

  /// Export แผนภาพ DFD ที่เปิดอยู่เป็น PNG/SVG (ตัดเฉพาะส่วนที่มีวัตถุ)
  static Future<void> _exportDfdImage(BuildContext context, ProjectController c) async {
    final tab = c.activeDiagram;
    final d = c.project.dfdOf(tab.id);
    if (d.nodes.isEmpty) {
      _toast(context, tr('ยังไม่มีวัตถุให้ Export เป็นภาพ'));
      return;
    }
    final opts = await showDialog<ImageExportOptions>(
      context: context,
      builder: (_) => const ExportImageDialog(hasNotes: false, showArea: false),
    );
    if (opts == null || !context.mounted) return;
    try {
      late final Uint8List bytes;
      var note = '';
      if (opts.format == ImageFormat.svg) {
        bytes = Uint8List.fromList(utf8.encode(exportDfdSvg(d, dark: opts.dark, title: tab.name)!));
      } else {
        final png = await exportDfdPng(d, scale: opts.scale, dark: opts.dark);
        if (png == null) return;
        bytes = png.bytes;
        if (png.scale < opts.scale) note = tr(' (ลดสเกลเหลือ {0}x เพราะภาพใหญ่เกินไป)', [png.scale.toStringAsFixed(1)]);
      }
      final uri = await FilePicker.saveFile(
        dialogTitle: tr('Export ภาพ {0}', [opts.format.name.toUpperCase()]),
        fileName: '${safeName(tab.name)}_dfd.${opts.format.name}',
        bytes: bytes,
      );
      if (uri == null) return;
      var path = uri.toFilePath();
      if (!path.toLowerCase().endsWith('.${opts.format.name}')) path = '$path.${opts.format.name}';
      await File(path).writeAsBytes(bytes);
      if (context.mounted) _toast(context, tr('Export แล้ว: {0}{1}', [path, note]));
    } catch (e) {
      if (context.mounted) _toast(context, tr('Export ภาพไม่ได้: {0}', [e]));
    }
  }

  /// บันทึกสคริปต์ migration เป็น `ชื่อโปรเจกต์_migration_dialect.sql`
  static Future<void> saveMigration(BuildContext context, String sql, Project neu) async {
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: tr('บันทึกสคริปต์ migration'),
        fileName: sqlFileName('${neu.name}_migration', neu.dialect),
        bytes: utf8.encode(sql),
      );
      if (uri == null) return;
      var path = uri.toFilePath();
      if (!path.toLowerCase().endsWith('.sql')) path = '$path.sql';
      await File(path).writeAsString(sql);
      if (context.mounted) _toast(context, tr('บันทึกแล้ว: {0}', [path]));
    } catch (e) {
      if (context.mounted) _toast(context, tr('บันทึกไม่ได้: {0}', [e]));
    }
  }

  /// คืน true ถ้าบันทึกสำเร็จ
  static Future<bool> save(BuildContext context, ProjectController c) async {
    final path = c.filePath;
    // ไฟล์ .erd/.nslm เก่า: ไม่เขียนทับ ให้บันทึกเป็น .nsld ใหม่ (ไฟล์เดิมคงอยู่)
    if (path == null || isLegacyProjectPath(path)) return saveAs(context, c);
    return _write(context, c, path);
  }

  static Future<bool> saveAs(BuildContext context, ProjectController c) async {
    final name = c.project.name.trim().isEmpty ? 'untitled' : c.project.name.trim();
    final uri = await FilePicker.saveFile(
      dialogTitle: tr('บันทึกเป็น'),
      fileName: '$name.$kProjectExt',
      bytes: utf8.encode(ProjectFile.encode(c.project)),
    );
    if (uri == null) return false;
    final path = withProjectExt(uri.toFilePath());
    if (!context.mounted) return false;
    return _write(context, c, path);
  }

  /// ชื่อไฟล์ .sql จากชื่อโปรเจกต์ + dialect (ตัดอักขระที่ Windows ห้ามใช้ในชื่อไฟล์)
  static String sqlFileName(String projectName, Dialect dialect) =>
      '${safeName(projectName)}_${dialect.name}.sql';

  /// สร้างไฟล์ .sql ตาม dialect ปัจจุบันแล้วให้เลือกที่บันทึก
  static Future<void> exportSql(BuildContext context, ProjectController c) async {
    final dialect = c.project.dialect;
    final errors = c.issues.where((i) => i.severity == Severity.error).length;
    if (errors > 0) {
      final go = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('พบข้อผิดพลาด {0} รายการ', [errors])),
          content: Text(tr('SQL ที่ได้อาจ import เข้า {0} ไม่ผ่าน ต้องการดูปัญหาก่อน หรือ Export ต่อเลย?', [dialect.label])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text(tr('ยกเลิก'))),
            TextButton(onPressed: () => Navigator.pop(ctx, 'export'), child: Text(tr('Export ต่อ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'view'), child: Text(tr('ดูปัญหา'))),
          ],
        ),
      );
      if (!context.mounted) return;
      if (go == 'view') {
        context.read<CanvasController>().showDock(DockTab.issues);
        return;
      }
      if (go != 'export') return;
    }
    // ข้อมูลตั้งต้น: ตรวจก่อน แล้วถามว่าจะรวมหรือไม่ (ข้อมูลที่ไม่ถูกต้องไม่ถูกใส่ลง SQL)
    var includeSeed = false;
    final seed = seedSummary(c.project);
    if (seed.rows > 0) {
      final problems = validateSeed(c.project);
      if (!context.mounted) return;
      if (problems.isNotEmpty) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('ข้อมูลตั้งต้นมีปัญหา {0} รายการ', [problems.length])),
            content: SizedBox(
              width: 460,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('จะไม่รวมข้อมูลตั้งต้นใน SQL จนกว่าจะแก้ให้ถูกต้อง'), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                for (final pr in problems.take(6))
                  Text('• ${c.project.tableById(pr.tableId)?.name ?? '?'}'
                      '${pr.row == null ? '' : ' #${pr.row! + 1}'}: ${pr.message}',
                      style: const TextStyle(fontSize: 12.5)),
                if (problems.length > 6) Text(tr('…และอีก {0} รายการ', [problems.length - 6])),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Export โดยไม่รวมข้อมูลตั้งต้น'))),
            ],
          ),
        );
        if (go != true) return;
      } else {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('รวมข้อมูลตั้งต้นใน SQL หรือไม่')),
            content: Text(tr('มีข้อมูลตั้งต้น {0} แถวใน {1} ตาราง จะสร้างเป็น INSERT ต่อท้ายไฟล์', [seed.rows, seed.tables])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text(tr('ยกเลิก'))),
              TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: Text(tr('ไม่รวม'))),
              FilledButton(key: const ValueKey('seed-include'), onPressed: () => Navigator.pop(ctx, 'include'), child: Text(tr('รวมข้อมูลตั้งต้น'))),
            ],
          ),
        );
        if (choice == null || choice == 'cancel') return;
        includeSeed = choice == 'include';
      }
    }
    if (!context.mounted) return;
    final sql = buildExportSql(c.project, includeSeed: includeSeed);
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export .sql (${dialect.label})',
        fileName: sqlFileName(c.project.name, dialect),
        bytes: utf8.encode(sql),
      );
      if (uri == null) return;
      var path = uri.toFilePath();
      if (!path.toLowerCase().endsWith('.sql')) path = '$path.sql';
      await File(path).writeAsString(sql); // UTF-8 ไม่มี BOM
      if (context.mounted) _toast(context, tr('Export แล้ว: {0}', [path]));
    } catch (e) {
      if (context.mounted) _toast(context, tr('Export ไม่ได้: {0}', [e]));
    }
  }

  static Future<bool> _write(BuildContext context, ProjectController c, String path) async {
    try {
      await ProjectFile.save(c.project, path);
      c.markSaved(path);
      return true;
    } catch (e) {
      if (context.mounted) _toast(context, tr('บันทึกไม่ได้: {0}', [e]));
      return false;
    }
  }
}
