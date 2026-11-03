import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/storage/autosave.dart';
import '../state/autosave_coordinator.dart';
import '../state/project_controller.dart';
import 'app_actions.dart';
import 'canvas/canvas_controller.dart';
import 'canvas/canvas_view.dart';
import 'left_panel.dart';
import 'recovery_dialog.dart';
import 'right_panel.dart';
import 'shortcuts.dart';
import 'sql_dock.dart';
import 'top_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.recovery});

  /// งานค้างจาก auto-save ครั้งก่อน — ถ้ามีจะถามกู้คืนตอนเปิดหน้านี้
  final AutosaveInfo? recovery;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _focus = FocusNode(debugLabel: 'home');

  @override
  void initState() {
    super.initState();
    if (widget.recovery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery(widget.recovery!));
    }
  }

  Future<void> _offerRecovery(AutosaveInfo info) async {
    if (!mounted) return;
    final c = context.read<ProjectController>();
    final cv = context.read<CanvasController>();
    final auto = context.read<AutosaveCoordinator?>();
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecoveryDialog(info: info),
    );
    if (restore == true) {
      c.restoreProject(info.project, info.originalPath);
      cv.fit(c.project);
    } else {
      await auto?.discard();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// กำลังพิมพ์ในช่องข้อความอยู่หรือไม่
  bool get _typing =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  /// ดักคีย์ลัดของแอป ขณะพิมพ์ในช่องข้อความจะปล่อยคีย์ที่ช่องข้อความใช้เองผ่านไป
  /// (Ctrl+C/V/A/Z, ตัวอักษรเดี่ยว, ลูกศร, Delete) แต่คีย์ระดับแอป เช่น Ctrl+S ยังทำงาน
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final s = matchShortcut(e, HardwareKeyboard.instance);
    if (s == null || s.cmd == null) return KeyEventResult.ignored;
    if (_typing && !s.global) return KeyEventResult.ignored;
    AppActions(context).run(s.cmd!);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          body: Column(children: [
            const TopBar(),
            Expanded(
              child: Row(children: [
                const LeftPanel(),
                Expanded(
                  child: Column(children: [
                    Expanded(child: CanvasView(focusNode: _focus)),
                    const SqlDock(),
                  ]),
                ),
                const RightPanel(),
              ]),
            ),
          ]),
        ),
      );
}
