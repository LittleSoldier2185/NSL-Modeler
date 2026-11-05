import 'dart:convert';
import 'dart:io';

import '../models/workspace.dart';
import '../l10n/l10n.dart';
import 'project_codec.dart';

export 'project_format_exception.dart';

/// สกุลไฟล์โปรเจกต์ของ NSL Dev (ไม่มีจุด)
const kProjectExt = 'nsld';

/// สกุลเก่า — `.nslm` (NSL Modeler) และ `.erd` : ยังเปิดอ่านได้ แต่บันทึกเป็น `.nsld` เสมอ
const kLegacyProjectExts = ['nslm', 'erd'];

/// สกุลที่เปิดได้ทั้งหมด (ใช้กับ dialog เลือกไฟล์)
const kOpenableExts = [kProjectExt, ...kLegacyProjectExts];

/// path เป็นไฟล์สกุลเก่า (`.nslm` / `.erd`) หรือไม่
bool isLegacyProjectPath(String path) {
  final lower = path.toLowerCase();
  return kLegacyProjectExts.any((e) => lower.endsWith('.$e'));
}

/// ทำให้ path ลงท้าย `.nsld` : สกุลเก่าถูกเปลี่ยนเป็น `.nsld` , สกุลอื่น/ไม่มีสกุลต่อท้าย `.nsld`
String withProjectExt(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.$kProjectExt')) return path;
  for (final e in kLegacyProjectExts) {
    if (lower.endsWith('.$e')) return '${path.substring(0, path.length - e.length)}$kProjectExt';
  }
  return '$path.$kProjectExt';
}

/// อ่าน/เขียนไฟล์โปรเจกต์ `.nsld` (JSON) ผ่าน project_codec : เขียนเป็น v3 เสมอ ; อ่านได้ v1–v3
/// (`.nslm`/`.erd` เดิมเป็น v1/v2 จึงเปิดได้) ; v4 ขึ้นไปถูกปฏิเสธ
class ProjectFile {
  static String encode(Workspace w) =>
      const JsonEncoder.withIndent('  ').convert(encodeProjectMap(w));

  static Workspace decode(String text) {
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException catch (e) {
      throw ProjectFormatException(tr('ไฟล์ไม่ใช่ JSON ที่ถูกต้อง: {0}', [e.message]));
    }
    if (data is! Map<String, dynamic>) {
      throw ProjectFormatException(tr('ไม่ใช่ไฟล์โปรเจกต์ NSL Dev'));
    }
    return decodeProjectMap(data);
  }

  /// เขียนผ่านไฟล์ชั่วคราวแล้วค่อย rename กันไฟล์พังถ้าโปรแกรมค้างกลางคัน
  static Future<void> save(Workspace w, String path) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(encode(w), flush: true);
    await tmp.rename(path);
  }

  static Future<Workspace> load(String path) async =>
      decode(await File(path).readAsString());
}
