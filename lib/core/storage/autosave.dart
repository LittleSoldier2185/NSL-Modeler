import 'dart:convert';
import 'dart:io';

import '../models/workspace.dart';
import '../l10n/l10n.dart';
import 'project_codec.dart';

/// งานที่ auto-save ไว้ เพื่อกู้คืนหลังโปรแกรมปิดผิดปกติ
class AutosaveInfo {
  const AutosaveInfo(this.workspace, this.savedAt, this.originalPath);
  final Workspace workspace;
  final DateTime savedAt;

  /// ไฟล์โปรเจกต์ที่เปิดอยู่ตอนนั้น (null = โปรเจกต์ยังไม่เคยบันทึก)
  final String? originalPath;
}

abstract class AutosaveStore {
  Future<void> write(Workspace w, {String? originalPath, DateTime? now});

  /// null = ไม่มีงานให้กู้ (ไม่มีไฟล์ / ไฟล์เสีย / ล้าสมัยกว่าไฟล์ที่บันทึกแล้ว)
  Future<AutosaveInfo?> readRecoverable();
  Future<void> clear();
}

/// เก็บเป็นไฟล์เดียวในโฟลเดอร์ [dir] — เขียนผ่านไฟล์ชั่วคราวแล้ว rename เพื่อไม่ให้ไฟล์พังถ้าปิดกลางคัน
/// ตัวโปรเจกต์ข้างในเป็น JSON รูปแบบเดียวกับไฟล์ (เขียน v3 ; อ่านได้ v1–v3 ผ่าน project_codec)
class FileAutosaveStore implements AutosaveStore {
  FileAutosaveStore(this.dir, {this.fileName = 'autosave.json'});
  final Directory dir;
  final String fileName;

  File get file => File('${dir.path}${Platform.pathSeparator}$fileName');

  @override
  Future<void> write(Workspace w, {String? originalPath, DateTime? now}) async {
    await dir.create(recursive: true);
    final body = jsonEncode({
      'format': 'nsl-autosave',
      'savedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'originalPath': originalPath,
      'project': encodeProjectMap(w),
    });
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<AutosaveInfo?> readRecoverable() async {
    final f = file;
    if (!await f.exists()) return null;
    AutosaveInfo info;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['format'] != 'nsl-autosave') throw FormatException(tr('ไม่ใช่ไฟล์ autosave'));
      info = AutosaveInfo(
        decodeProjectMap(j['project'] as Map<String, dynamic>),
        DateTime.parse(j['savedAt'] as String).toLocal(),
        j['originalPath'] as String?,
      );
    } catch (_) {
      // ไฟล์เสีย (หรือมาจากโปรแกรมรุ่นใหม่กว่า): เก็บไว้ดูทีหลังแต่ไม่ถามซ้ำทุกครั้งที่เปิดโปรแกรม
      try {
        await f.rename('${f.path}.corrupt');
      } catch (_) {}
      return null;
    }
    // ผู้ใช้บันทึกไฟล์เดิมไปแล้วหลัง auto-save (เช่น โปรแกรมค้างก่อนลบ autosave) -> ไม่ต้องกู้
    final orig = info.originalPath;
    if (orig != null) {
      final of = File(orig);
      if (await of.exists() && !(await of.lastModified()).isBefore(info.savedAt)) {
        await clear();
        return null;
      }
    }
    return info;
  }

  @override
  Future<void> clear() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
