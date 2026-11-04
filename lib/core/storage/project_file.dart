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

/// สกุลไฟล์โปรเจกต์ของ NSL Modeler (ไม่มีจุด)
const kProjectExt = 'nslm';

/// สกุลเก่า (ก่อนรุ่นที่เริ่มใช้ `.nslm`) — ยังเปิดอ่านได้ แต่บันทึกเป็น `.nslm` เสมอ
const kLegacyProjectExt = 'erd';

/// สกุลที่เปิดได้ทั้งหมด (ใช้กับ dialog เลือกไฟล์)
const kOpenableExts = [kProjectExt, kLegacyProjectExt];

/// path เป็นไฟล์สกุลเก่า `.erd` หรือไม่
bool isLegacyProjectPath(String path) => path.toLowerCase().endsWith('.$kLegacyProjectExt');

/// ทำให้ path ลงท้าย `.nslm` : `.erd` เก่าถูกเปลี่ยนเป็น `.nslm` , สกุลอื่น/ไม่มีสกุลต่อท้าย `.nslm`
String withProjectExt(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.$kProjectExt')) return path;
  if (isLegacyProjectPath(path)) return '${path.substring(0, path.length - kLegacyProjectExt.length)}$kProjectExt';
  return '$path.$kProjectExt';
}

/// อ่าน/เขียนไฟล์โปรเจกต์ `.nslm` (JSON ; เนื้อในเหมือน `.erd` เดิมทุกประการ จึงอ่านไฟล์เก่าได้)
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
      throw ProjectFormatException(tr('ไม่ใช่ไฟล์โปรเจกต์ NSL Modeler'));
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
