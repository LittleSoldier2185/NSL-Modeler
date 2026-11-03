import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/group_model.dart';
import '../core/models/table_model.dart';
import '../state/project_controller.dart';
import 'color_picker_dialog.dart';
import 'font_picker_dialog.dart';

/// การกำหนดสี/ฟอนต์อิสระ ใช้ร่วมกันระหว่างแผงขวา เมนูคลิกขวา และเมนูมุมมอง
class StyleActions {
  StyleActions._();

  static Future<void> tableColor(BuildContext context, ProjectController c, Iterable<String> ids, {int? current}) async {
    final r = await showColorPickerDialog(context, title: tr('สีตาราง (กำหนดเอง)'), initial: current, presets: kTableColors);
    if (r == null) return;
    r.argb == null ? c.setTablesColor(ids, null) : c.setTablesCustomColor(ids, r.argb);
  }

  static Future<void> tableFont(BuildContext context, ProjectController c, Iterable<String> ids, {String? current}) async {
    final r = await showFontPickerDialog(context, current: current);
    if (r != null) c.setTablesFont(ids, r.family);
  }

  static Future<void> groupColor(BuildContext context, ProjectController c, String id, {int? current}) async {
    final r = await showColorPickerDialog(context, title: tr('สีกลุ่ม (กำหนดเอง)'), initial: current, presets: kGroupColors);
    if (r == null) return;
    r.argb == null ? c.setGroupCustomColor(id, null) : c.setGroupCustomColor(id, r.argb);
  }

  static Future<void> relationColor(BuildContext context, ProjectController c, String id, {int? current}) async {
    final r = await showColorPickerDialog(context, title: tr('สีเส้น FK'), initial: current ?? c.project.lineColor);
    if (r != null) c.setRelationColor(id, r.argb);
  }

  static Future<void> lineColor(BuildContext context, ProjectController c) async {
    final r = await showColorPickerDialog(context, title: tr('สีเส้นความสัมพันธ์ทั้งหมด'), initial: c.project.lineColor);
    if (r != null) c.setLineColor(r.argb);
  }
}
