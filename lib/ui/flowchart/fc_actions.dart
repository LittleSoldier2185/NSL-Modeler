import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/flowchart_model.dart';
import '../../state/flowchart_controller.dart';
import '../../state/project_controller.dart';
import '../color_picker_dialog.dart';
import '../file_actions.dart';
import '../shortcuts.dart';
import '../shortcuts_help.dart';
import 'fc_painter.dart';

/// คำสั่งที่ใช้ได้ขณะเปิดแท็บ Flowchart (ใช้ร่วมกันระหว่างคีย์ลัด เมนู เมนูคลิกขวา และแผงข้าง)
class FlowchartActions {
  FlowchartActions(this.context)
      : c = context.read<ProjectController>(),
        f = context.read<FlowchartController>();

  final BuildContext context;
  final ProjectController c;
  final FlowchartController f;

  /// คำสั่งของ Flowchart เอง (แท็บ ER/DFD ไม่ใช้)
  static const flowchartOnly = {Cmd.fcTerminator, Cmd.fcIo, Cmd.fcSubroutine, Cmd.fcConnector};

  /// ทำงานตามคำสั่ง ; คำสั่งที่ไม่เกี่ยวกับ Flowchart (แก้ตาราง/dialect ฯลฯ) ถูกเมินอย่างเงียบ ๆ
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
      case Cmd.groupSelected:
        f.groupSelection();
      case Cmd.ungroupSelected:
        f.ungroupSelection();
      case Cmd.toolSelect:
        f.setTool(FcTool.select);
      case Cmd.toolFk:
        f.setTool(FcTool.edge);
      case Cmd.toolNote:
        f.setShapeTool(FcShape.note);
      case Cmd.dfdProcess: // P
        f.setShapeTool(FcShape.process);
      case Cmd.dfdStore: // D
        f.setShapeTool(FcShape.decision);
      case Cmd.fcTerminator:
        f.setTerminatorTool();
      case Cmd.fcIo:
        f.setShapeTool(FcShape.io);
      case Cmd.fcSubroutine:
        f.setShapeTool(FcShape.subroutine);
      case Cmd.fcConnector:
        f.setShapeTool(FcShape.connector);
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

  /// Ctrl+C : คัดลอกสัญลักษณ์ที่เลือก (+เส้นระหว่างกัน) ลงคลิปบอร์ดของระบบ
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
    if (f.pasteText(text, offset: 30.0 * _pasteCount) == 0) {
      _pasteCount = 0;
      _lastPasted = null;
    }
  }

  /// F2 : พิมพ์ข้อความของสัญลักษณ์/ป้ายเส้นที่เลือกบนแคนวาส
  void rename() {
    final n = f.selectedNode;
    if (n != null) return f.beginEditNode(n.id);
    final e = f.selectedEdge;
    if (e != null) f.beginEditEdge(e.id);
  }

  Future<void> pickNodeColor(Iterable<String> ids, {required bool fill, int? current}) async {
    final r = await showColorPickerDialog(context,
        title: fill ? tr('สีพื้น (กำหนดเอง)') : tr('สีเส้นขอบ (กำหนดเอง)'), initial: current, presets: kFcPalette);
    if (r == null) return;
    f.setNodesStyle(ids, (n) => fill ? n.fill = r.argb : n.stroke = r.argb);
  }

  Future<void> pickTextColor(Iterable<String> ids, {int? current}) async {
    final r = await showColorPickerDialog(context, title: tr('สีตัวอักษร'), initial: current, presets: kFcPalette);
    if (r != null) f.setNodesStyle(ids, (n) => n.textColor = r.argb);
  }

  Future<void> pickEdgeColor(FcEdge e) async {
    final r = await showColorPickerDialog(context, title: tr('สีเส้นเชื่อม'), initial: e.color, presets: kFcPalette);
    if (r != null) f.updateEdge(e.id, (x) => x.color = r.argb);
  }
}
