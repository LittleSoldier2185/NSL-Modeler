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

/// อ่าน/เขียนไฟล์ `.erd` (JSON)
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
