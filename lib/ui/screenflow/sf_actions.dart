import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/screenflow_model.dart';
import '../../state/project_controller.dart';
import '../../state/screenflow_controller.dart';
import '../file_actions.dart';
import '../shortcuts.dart';
import '../shortcuts_help.dart';

/// คำสั่งที่ใช้ได้ขณะเปิดแท็บ Screen Flow (ใช้ร่วมกันระหว่างคีย์ลัด เมนู เมนูคลิกขวา และแผงข้าง)
/// คีย์: O เริ่ม/จบ · P หน้าจอ · E ภายนอก/ป๊อปอัป · F เส้นการเปลี่ยนหน้า · S เลือก (คำสั่งเดียวกับ DFD/Flowchart แต่ทำงานตามแท็บ)
class ScreenFlowActions {
  ScreenFlowActions(this.context)
      : c = context.read<ProjectController>(),
        f = context.read<ScreenFlowController>();

  final BuildContext context;
  final ProjectController c;
  final ScreenFlowController f;

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
        f.setTool(SfTool.select);
      case Cmd.toolFk: // F
        f.setTool(SfTool.edge);
      case Cmd.dfdProcess: // P
        f.setNodeTool(SfKind.screen);
      case Cmd.dfdEntity: // E
        f.setNodeTool(SfKind.external);
      case Cmd.fcTerminator: // O
        f.setTerminatorTool();
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

  Future<void> copy() async {
    final text = f.copySelectionText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    _lastPasted = null;
    _pasteCount = 0;
  }

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

  /// F2 : พิมพ์ชื่อหน้าจอ/ป้ายเส้นที่เลือกบนแคนวาส
  void rename() {
    final n = f.selectedNode;
    if (n != null) return f.beginEdit(n.id);
    final e = f.selectedEdge;
    if (e != null) f.beginEditEdge(e.id);
  }

  /// เปิด Wireframe ที่หน้าจอ [nodeId] ผูกไว้ — ยังไม่ผูก/เอกสารหายไป = สร้างใหม่แล้วผูก
  void openWireframe(String nodeId) {
    final n = f.diagram.nodeById(nodeId);
    if (n == null || n.kind != SfKind.screen) return;
    final wf = n.wireframeId;
    if (wf != null && f.workspace.documentById(wf)?.wireframe != null) {
      f.workspace.openDocument(wf);
    } else {
      f.createWireframeFor(nodeId);
    }
  }
}
