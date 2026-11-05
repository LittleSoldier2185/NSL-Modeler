import 'dart:convert';
import 'dart:io';

import '../models/project.dart';
import '../l10n/l10n.dart';

class ProjectFormatException implements Exception {
  ProjectFormatException(this.message);
  final String message;
  @override
  String toString() => 'ProjectFormatException: $message';
}

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

/// อ่าน/เขียนไฟล์โปรเจกต์ `.nsld` (JSON ; เนื้อในเหมือน `.nslm`/`.erd` เดิมทุกประการ จึงอ่านไฟล์เก่าได้)
class ProjectFile {
  static String encode(Project p) =>
      const JsonEncoder.withIndent('  ').convert(p.toJson());

  static Project decode(String text) {
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException catch (e) {
      throw ProjectFormatException(tr('ไฟล์ไม่ใช่ JSON ที่ถูกต้อง: {0}', [e.message]));
    }
    if (data is! Map<String, dynamic> || data['format'] != 'nsl-erd') {
      throw ProjectFormatException(tr('ไม่ใช่ไฟล์โปรเจกต์ NSL Dev'));
    }
    final v = data['version'];
    if (v is! int || v > Project.formatVersion) {
      throw ProjectFormatException(tr('ไฟล์เวอร์ชันใหม่กว่าที่โปรแกรมรองรับ'));
    }
    try {
      return Project.fromJson(data);
    } catch (e) {
      throw ProjectFormatException(tr('โครงสร้างไฟล์ไม่ถูกต้อง: {0}', [e]));
    }
  }

  /// เขียนผ่านไฟล์ชั่วคราวแล้วค่อย rename กันไฟล์พังถ้าโปรแกรมค้างกลางคัน
  static Future<void> save(Project p, String path) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(encode(p), flush: true);
    await tmp.rename(path);
  }

  static Future<Project> load(String path) async =>
      decode(await File(path).readAsString());
}
