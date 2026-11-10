import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/wireframe_model.dart';
import '../../state/project_controller.dart';
import '../../state/wireframe_controller.dart';
import '../color_picker_dialog.dart';
import '../file_actions.dart';
import '../shortcuts.dart';
import '../shortcuts_help.dart';
import 'er_ref_dialog.dart';
import 'wf_painter.dart';

/// คำสั่งที่ใช้ได้ขณะเปิดแท็บ Wireframe (ใช้ร่วมกันระหว่างคีย์ลัด เมนู เมนูคลิกขวา และแผงข้าง)
class WireframeActions {
  WireframeActions(this.context)
      : c = context.read<ProjectController>(),
        f = context.read<WireframeController>();

  final BuildContext context;
  final ProjectController c;
  final WireframeController f;

  /// คำสั่งของ Wireframe เอง (แท็บอื่นไม่ใช้)
  static const wireframeOnly = {Cmd.wfButton, Cmd.wfContainer, Cmd.wfImage, Cmd.wfInput};

  /// ทำงานตามคำสั่ง ; คำสั่งที่ไม่เกี่ยวกับ Wireframe ถูกเมินอย่างเงียบ ๆ
  void run(Cmd cmd) {
    switch (cmd) {
      case Cmd.newProject:
        FileActions.newProject(context, c);
      case Cmd.open:
        FileActions.open(context, c);
      case Cmd.save:
        FileActions.save(context, c);
      case Cmd.saveAs:
        FileActions.saveAs(context, c);
      case Cmd.exportImage:
        FileActions.exportImage(context, c);
      case Cmd.exportText:
        FileActions.exportText(context, c);
      case Cmd.help:
        showShortcutsHelp(context);
      case Cmd.undo:
        f.undo();
      case Cmd.redo:
        f.redo();
      case Cmd.delete:
        f.deleteSelection();
      case Cmd.rename:
        rename();
      case Cmd.escape:
        f.escape();
      case Cmd.selectAll:
        f.selectAll();
      case Cmd.duplicate:
        f.duplicateSelection();
      case Cmd.copy:
        copy();
      case Cmd.paste:
        paste();
      case Cmd.toolSelect:
        f.setTool(WfTool.select);
      case Cmd.toolTable: // T
        f.setPlaceTool(WfKind.label);
      case Cmd.wfButton:
        f.setPlaceTool(WfKind.button);
      case Cmd.wfContainer:
        f.setPlaceTool(WfKind.container);
      case Cmd.wfImage:
        f.setPlaceTool(WfKind.image);
      case Cmd.wfInput:
        f.setPlaceTool(WfKind.input);
      case Cmd.fit:
        f.fit(f.viewport);
      case Cmd.zoom100:
        f.resetZoom(f.viewport);
      case Cmd.nudgeLeft:
        f.nudge(-10, 0);
      case Cmd.nudgeRight:
        f.nudge(10, 0);
      case Cmd.nudgeUp:
        f.nudge(0, -10);
      case Cmd.nudgeDown:
        f.nudge(0, 10);
      case Cmd.nudgeLeftBig:
        f.nudge(-50, 0);
      case Cmd.nudgeRightBig:
        f.nudge(50, 0);
      case Cmd.nudgeUpBig:
        f.nudge(0, -50);
      case Cmd.nudgeDownBig:
        f.nudge(0, 50);
      default:
        break;
    }
  }

  static String? _lastPasted;
  static int _pasteCount = 0;

  /// Ctrl+C : คัดลอกชิ้นที่เลือก (และลูกในภาชนะ) ลงคลิปบอร์ดของระบบ
  Future<void> copy() async {
    final text = f.copySelectionText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    _lastPasted = null;
    _pasteCount = 0;
  }

  /// Ctrl+V : วางจากคลิปบอร์ด (วางซ้ำจะเลื่อนทีละขั้น) ข้ามแท็บ/ข้ามโปรเจกต์ได้
  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    _pasteCount = text == _lastPasted ? _pasteCount + 1 : 1;
    _lastPasted = text;
    if (f.pasteText(text, offset: 20.0 * _pasteCount) == 0) {
      _pasteCount = 0;
      _lastPasted = null;
    }
  }

  /// F2 : พิมพ์ข้อความของชิ้นที่เลือกบนแคนวาส
  void rename() {
    final s = f.selectedBox;
    if (s != null) f.beginEdit(s.id);
  }

  Future<void> pickColor(Iterable<String> ids, {required String which, int? current}) async {
    final title = switch (which) {
      'fill' => tr('สีพื้น (กำหนดเอง)'),
      'stroke' => tr('สีเส้นขอบ (กำหนดเอง)'),
      _ => tr('สีตัวอักษร'),
    };
    final r = await showColorPickerDialog(context, title: title, initial: current, presets: kWfPalette);
    if (r == null) return;
    f.updateComponents(ids, (c) {
      switch (which) {
        case 'fill':
          c.fill = r.argb;
        case 'stroke':
          c.stroke = r.argb;
        default:
          c.textColor = r.argb;
      }
    });
  }

  Future<void> pickAccent() async {
    final r = await showColorPickerDialog(context, title: tr('สีเน้น (accent)'), initial: f.diagram.accent, presets: kWfPalette);
    final v = r?.argb;
    if (v != null) f.setAccent(v);
  }

  /// เลือก ER › ตาราง › คอลัมน์ ให้ชิ้น [id] (หรือเลิกผูก)
  Future<void> bindData(String id) async {
    final comp = f.diagram.componentById(id);
    if (comp == null) return;
    final r = await showErRefDialog(context, f.workspace.workspace, current: comp.ref);
    if (r != null) f.setRef(id, r.ref);
  }
}
