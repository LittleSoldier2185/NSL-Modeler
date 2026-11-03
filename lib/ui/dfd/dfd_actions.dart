import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/dfd_model.dart';
import '../../state/dfd_controller.dart';
import '../../state/project_controller.dart';
import '../color_picker_dialog.dart';
import '../file_actions.dart';
import '../prompt_dialog.dart';
import '../shortcuts.dart';
import '../shortcuts_help.dart';

/// คำสั่งที่ใช้ได้ขณะเปิดแท็บ DFD (ใช้ร่วมกันระหว่างคีย์ลัด เมนู และเมนูคลิกขวา)
class DfdActions {
  DfdActions(this.context)
      : c = context.read<ProjectController>(),
        d = context.read<DfdController>();

  final BuildContext context;
  final ProjectController c;
  final DfdController d;

  /// คำสั่งของ DFD เอง (ไม่ใช้ตอนเปิดแท็บ ER)
  static const dfdOnly = {Cmd.dfdEntity, Cmd.dfdProcess, Cmd.dfdStore};

  /// ทำงานตามคำสั่ง; คำสั่งที่ไม่เกี่ยวกับ DFD (เช่นแก้ตาราง) ถูกเมินอย่างเงียบ ๆ ไม่แตะเนื้อหา ER
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
      case Cmd.help:
        showShortcutsHelp(context);
      case Cmd.undo:
        c.undo();
      case Cmd.redo:
        c.redo();
      case Cmd.delete:
        d.deleteSelection();
      case Cmd.rename:
        rename();
      case Cmd.escape:
        d.escape();
      case Cmd.selectAll:
        d.selectAll();
      case Cmd.duplicate:
        d.duplicateSelection();
      case Cmd.toolSelect:
        d.setTool(DfdTool.select);
      case Cmd.toolFk:
        d.setTool(DfdTool.flow);
      case Cmd.dfdEntity:
        d.setTool(DfdTool.entity);
      case Cmd.dfdProcess:
        d.setTool(DfdTool.process);
      case Cmd.dfdStore:
        d.setTool(DfdTool.store);
      case Cmd.fit:
        d.fit(d.viewport);
      case Cmd.zoom100:
        d.resetZoom(d.viewport);
      case Cmd.nudgeLeft:
        d.nudge(-10, 0);
      case Cmd.nudgeRight:
        d.nudge(10, 0);
      case Cmd.nudgeUp:
        d.nudge(0, -10);
      case Cmd.nudgeDown:
        d.nudge(0, 10);
      case Cmd.nudgeLeftBig:
        d.nudge(-50, 0);
      case Cmd.nudgeRightBig:
        d.nudge(50, 0);
      case Cmd.nudgeUpBig:
        d.nudge(0, -50);
      case Cmd.nudgeDownBig:
        d.nudge(0, 50);
      default:
        break;
    }
  }

  /// เปลี่ยนชื่อวัตถุที่เลือก / พิมพ์ชื่อเส้นข้อมูลที่เลือก
  Future<void> rename() async {
    final n = d.selectedNode;
    if (n != null) return renameNode(n);
    final f = d.selectedFlow;
    if (f != null) return editFlowLabel(f);
  }

  Future<void> renameNode(DfdNode n) async {
    final r = await showDialog<PromptResult>(
      context: context,
      builder: (_) => TextPromptDialog(title: tr('ชื่อวัตถุ'), initial: n.name, label: tr('ชื่อ')),
    );
    if (r != null) d.renameNode(n.id, r.text);
  }

  Future<void> editFlowLabel(DfdFlow f) async {
    final r = await showDialog<PromptResult>(
      context: context,
      builder: (_) => TextPromptDialog(title: tr('ชื่อเส้นข้อมูล'), initial: f.label, label: tr('ข้อมูลที่ไหล เช่น Order Details')),
    );
    if (r != null) d.setFlowLabel(f.id, r.text);
  }

  /// เลือกสีกำหนดเองให้วัตถุที่เลือก
  Future<void> pickNodesColor(Iterable<String> ids, {int? current}) async {
    final r = await showColorPickerDialog(context, title: tr('สีวัตถุ (กำหนดเอง)'), initial: current, presets: const [
      0xFF3B82F6,
      0xFF9333EA,
      0xFFF59E0B,
      0xFF14B8A6,
      0xFF22C55E,
      0xFFF43F5E,
    ]);
    if (r != null) d.setNodesColor(ids, r.argb);
  }

  Future<void> pickFlowColor(DfdFlow f) async {
    final r = await showColorPickerDialog(context, title: tr('สีเส้นข้อมูล'), initial: f.color);
    if (r != null) d.setFlowColor(f.id, r.argb);
  }
}
