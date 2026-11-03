import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/ddl/ddl_generator.dart';
import '../core/parser/sql_decode.dart';
import '../core/parser/sql_importer.dart';
import '../core/models/project.dart';
import '../core/export/svg_export.dart';
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

/// เปิด/บันทึก/โปรเจกต์ใหม่ พร้อมถามก่อนทิ้งงานที่ยังไม่บันทึก
class FileActions {
  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  /// true = ไปต่อได้ (บันทึกแล้ว / ไม่บันทึก / ไม่มีอะไรค้าง)
  static Future<bool> _confirmDiscard(BuildContext context, ProjectController c) async {
    if (!c.dirty) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('มีการแก้ไขที่ยังไม่ได้บันทึก'),
        content: const Text('ต้องการบันทึกก่อนหรือไม่'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('ไม่บันทึก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('บันทึก')),
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
    if (await _confirmDiscard(context, c)) c.newProject();
  }

  static Future<void> open(BuildContext context, ProjectController c) async {
    if (!await _confirmDiscard(context, c)) return;
    final f = await FilePicker.pickFile(
      dialogTitle: 'เปิดโปรเจกต์',
      type: FileType.custom,
      allowedExtensions: ['erd'],
    );
    final path = f?.path;
    if (path == null) return;
    try {
      c.loadProject(await ProjectFile.load(path), path);
    } on ProjectFormatException catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, 'เปิดไฟล์ไม่ได้: $e');
    }
  }

  /// นำเข้าจากไฟล์ .sql (CREATE TABLE ฯลฯ) -> แทนที่โปรเจกต์ หลังพรีวิวและยืนยัน
  static Future<void> importSqlFile(BuildContext context, ProjectController c) async {
    if (!await _confirmDiscard(context, c)) return;
    final f = await FilePicker.pickFile(
      dialogTitle: 'นำเข้าจากไฟล์ .sql',
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
      if (context.mounted) _toast(context, 'นำเข้าไม่ได้: $e');
    }
  }

  /// เลือกไฟล์ .erd เก่ามาเทียบกับโปรเจกต์ปัจจุบัน -> หน้าต่างรายการเปลี่ยนแปลง + สคริปต์ migration
  static Future<void> compareWithFile(BuildContext context, ProjectController c) async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'เลือกไฟล์โปรเจกต์เวอร์ชันเก่าเพื่อเปรียบเทียบ',
      type: FileType.custom,
      allowedExtensions: ['erd'],
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
      if (context.mounted) _toast(context, 'เปิดไฟล์ไม่ได้: $e');
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
      _toast(context, 'ยังไม่มีตารางให้ Export');
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
      if (context.mounted) _toast(context, 'บันทึกแล้ว: $path');
    } catch (e) {
      if (context.mounted) _toast(context, 'บันทึกไม่ได้: $e');
    }
  }

  /// Export แผนภาพเป็น PNG หรือ SVG (ทั้งแผนภาพ ไม่ขึ้นกับว่าตอนนี้ซูม/เลื่อนอยู่ตรงไหน)
  static Future<void> exportImage(BuildContext context, ProjectController c) async {
    final p = c.project;
    if (p.tables.isEmpty && p.notes.isEmpty) {
      _toast(context, 'ยังไม่มีตารางให้ Export เป็นภาพ');
      return;
    }
    final opts = await showDialog<ImageExportOptions>(
      context: context,
      builder: (_) => ExportImageDialog(hasNotes: p.notes.isNotEmpty),
    );
    if (opts == null || !context.mounted) return;
    try {
      late final Uint8List bytes;
      var note = '';
      if (opts.format == ImageFormat.svg) {
        bytes = Uint8List.fromList(utf8.encode(exportSvg(p, includeNotes: opts.includeNotes)!));
      } else {
        final png = await exportPng(p, scale: opts.scale, includeNotes: opts.includeNotes);
        if (png == null) return;
        bytes = png.bytes;
        if (png.scale < opts.scale) note = ' (ลดสเกลเหลือ ${png.scale.toStringAsFixed(1)}x เพราะภาพใหญ่เกินไป)';
      }
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export ภาพ ${opts.format.name.toUpperCase()}',
        fileName: imageFileName(p.name, opts.format),
        bytes: bytes,
      );
      if (uri == null) return;
      var path = uri.toFilePath();
      if (!path.toLowerCase().endsWith('.${opts.format.name}')) path = '$path.${opts.format.name}';
      await File(path).writeAsBytes(bytes);
      if (context.mounted) _toast(context, 'Export แล้ว: $path$note');
    } catch (e) {
      if (context.mounted) _toast(context, 'Export ภาพไม่ได้: $e');
    }
  }

  /// บันทึกสคริปต์ migration เป็น `ชื่อโปรเจกต์_migration_dialect.sql`
  static Future<void> saveMigration(BuildContext context, String sql, Project neu) async {
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'บันทึกสคริปต์ migration',
        fileName: sqlFileName('${neu.name}_migration', neu.dialect),
        bytes: utf8.encode(sql),
      );
      if (uri == null) return;
      var path = uri.toFilePath();
      if (!path.toLowerCase().endsWith('.sql')) path = '$path.sql';
      await File(path).writeAsString(sql);
      if (context.mounted) _toast(context, 'บันทึกแล้ว: $path');
    } catch (e) {
      if (context.mounted) _toast(context, 'บันทึกไม่ได้: $e');
    }
  }

  /// คืน true ถ้าบันทึกสำเร็จ
  static Future<bool> save(BuildContext context, ProjectController c) async {
    final path = c.filePath;
    if (path == null) return saveAs(context, c);
    return _write(context, c, path);
  }

  static Future<bool> saveAs(BuildContext context, ProjectController c) async {
    final name = c.project.name.trim().isEmpty ? 'untitled' : c.project.name.trim();
    final uri = await FilePicker.saveFile(
      dialogTitle: 'บันทึกเป็น',
      fileName: '$name.erd',
      bytes: utf8.encode(ProjectFile.encode(c.project)),
    );
    if (uri == null) return false;
    var path = uri.toFilePath();
    if (!path.toLowerCase().endsWith('.erd')) path = '$path.erd';
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
          title: Text('พบข้อผิดพลาด $errors รายการ'),
          content: Text('SQL ที่ได้อาจ import เข้า ${dialect.label} ไม่ผ่าน '
              'ต้องการดูปัญหาก่อน หรือ Export ต่อเลย?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('ยกเลิก')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'export'), child: const Text('Export ต่อ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'view'), child: const Text('ดูปัญหา')),
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
    final sql = DdlGenerator.forDialect(dialect).generate(c.project);
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
      if (context.mounted) _toast(context, 'Export แล้ว: $path');
    } catch (e) {
      if (context.mounted) _toast(context, 'Export ไม่ได้: $e');
    }
  }

  static Future<bool> _write(BuildContext context, ProjectController c, String path) async {
    try {
      await ProjectFile.save(c.project, path);
      c.markSaved(path);
      return true;
    } catch (e) {
      if (context.mounted) _toast(context, 'บันทึกไม่ได้: $e');
      return false;
    }
  }
}
