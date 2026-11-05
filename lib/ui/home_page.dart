import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../core/storage/autosave.dart';
import '../state/app_settings.dart';
import '../state/autosave_coordinator.dart';
import '../state/project_controller.dart';
import '../state/workspace_controller.dart';
import 'app_actions.dart';
import 'canvas/canvas_controller.dart';
import 'canvas/canvas_view.dart';
import 'dfd/dfd_panels.dart';
import 'dfd/dfd_view.dart';
import 'diagram_tabs.dart';
import 'status_bar.dart';
import 'language_dialog.dart';
import 'panel_splitter.dart';
import 'left_panel.dart';
import 'recovery_dialog.dart';
import 'right_panel.dart';
import 'shortcuts.dart';
import 'sql_dock.dart';
import 'file_actions.dart';
import 'theme.dart';
import 'window_chrome.dart';
import 'top_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.recovery, this.onRecoveryOffered});

  /// เรียกเมื่อเริ่มถามกู้คืนแล้ว (ตัวแอปจะไม่ส่ง recovery มาซ้ำเมื่อสลับธีม/ภาษา)
  final VoidCallback? onRecoveryOffered;

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
    // ปิดหน้าต่างด้วยปุ่มบนแถบบน: ถามบันทึกก่อนถ้ามีการแก้ค้างอยู่
    WindowChrome.closeHandler = () async {
      if (!mounted) return;
      if (await FileActions.confirmDiscard(context, context.read<ProjectController>())) {
        await WindowChrome.backend?.destroy();
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  /// เปิดครั้งแรก: ถามภาษาก่อน (เลือกแล้วแอปจะสร้างหน้าใหม่ แล้วหน้าใหม่ค่อยถามกู้คืนต่อ)
  Future<void> _startup() async {
    if (!mounted) return;
    final settings = context.read<AppSettings>();
    if (settings.needsLanguagePrompt) {
      final lang = await showDialog<Lang>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LanguageDialog(),
      );
      if (lang != null) settings.setLang(lang);
      return;
    }
    final rec = widget.recovery;
    if (rec != null) {
      widget.onRecoveryOffered?.call();
      await _offerRecovery(rec);
    }
  }

  Future<void> _offerRecovery(AutosaveInfo info) async {
    if (!mounted) return;
    final w = context.read<WorkspaceController>();
    final cv = context.read<CanvasController>();
    final auto = context.read<AutosaveCoordinator?>();
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecoveryDialog(info: info),
    );
    if (restore == true) {
      w.restoreWorkspace(info.workspace, info.originalPath);
      cv.fit(w.currentEr.project);
    } else {
      await auto?.discard();
    }
  }

  @override
  void dispose() {
    WindowChrome.closeHandler = null;
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
    // คำสั่งถูกส่งต่อให้ AppActions: แท็บ DFD ใช้ชุดคำสั่งของ DFD (คำสั่งแก้ตารางไม่แตะ ER ที่ซ่อนอยู่)
    AppActions(context).run(s.cmd!);
    return KeyEventResult.handled;
  }

  // เนื้อหาของแต่ละส่วนสร้างครั้งเดียว: ระหว่างลากขอบ ListenableBuilder แค่สร้างกล่องขนาดใหม่
  // (Flutter ข้ามการสร้างลูกที่เป็นวิดเจ็ตตัวเดิม) จึงไม่ต้องสร้าง canvas / ข้อความ SQL ใหม่ทุกเฟรม
  static const _leftPanel = LeftPanel();
  static const _rightPanel = RightPanel();
  static const _sqlDock = SqlDock();
  late final Widget _canvas = CanvasView(focusNode: _focus);
  static const _dfdLeft = DfdLeftPanel();
  static const _dfdRight = DfdRightPanel();
  late final Widget _dfdCanvas = DfdCanvas(focusNode: _focus);

  // ขนาดแผง ณ ตอนเริ่มลากขอบ (ลากแบบสัมบูรณ์: ขนาด = ขนาดเริ่ม + ระยะเมาส์ที่เคลื่อน)
  double _startLeft = 0, _startRight = 0, _startDock = 0;

  /// พื้นที่ใต้แถบบน: แผงซ้าย | canvas + แผง SQL | แผงขวา พร้อมแถบลากขอบ (วางทับรอยต่อ ไม่กินพื้นที่)
  Widget _body(BuildContext context) {
    final settings = context.read<AppSettings>();
    final layout = settings.layout;
    return LayoutBuilder(
      builder: (context, box) => ListenableBuilder(
        listenable: layout,
        builder: (context, _) {
          final (leftW, rightW) = layout.effectiveWidths(box.maxWidth);
          final dockH = layout.effectiveDock(box.maxHeight);
          final collapsed = context.select<CanvasController, bool>((cv) => cv.dockCollapsed);
          // แท็บ DFD: แผงซ้าย/ขวาและพื้นที่วาดของแผนภาพนั้น (ไม่มีแผง SQL)
          final isEr = context.select<WorkspaceController, DocType?>((w) => w.activeDocument.type) == DocType.er;
          // แคนวาสผูกกับเอกสาร: สลับเอกสาร = สร้าง State ใหม่ (ตัวฟัง/ตัวแปรที่จับ controller ของเอกสารเดิมไว้ไม่ค้าง)
          final docId = context.select<WorkspaceController, String>((w) => isEr ? w.currentEr.docId : w.activeId);
          return Stack(children: [
            Row(children: [
              SizedBox(width: leftW, child: isEr ? _leftPanel : _dfdLeft),
              Expanded(
                child: CustomPaint(
                  foregroundPainter: const _EdgeShadow(),
                  child: isEr
                      ? Column(children: [
                          Expanded(child: KeyedSubtree(key: ValueKey('er-canvas-$docId'), child: _canvas)),
                          SizedBox(height: collapsed ? 44 : dockH, child: _sqlDock),
                        ])
                      : KeyedSubtree(key: ValueKey('dfd-canvas-$docId'), child: _dfdCanvas),
                ),
              ),
              SizedBox(width: rightW, child: isEr ? _rightPanel : _dfdRight),
            ]),
            Positioned(
              left: leftW - 4,
              top: 0,
              bottom: 0,
              width: 8,
              child: PanelSplitter(
                key: const ValueKey('splitter-left'),
                vertical: true,
                onStart: () => _startLeft = leftW,
                onUpdate: (total) => layout.setLeft(_startLeft + total),
                onEnd: settings.commitLayout,
                onReset: () {
                  layout.resetLeft();
                  settings.commitLayout();
                },
              ),
            ),
            Positioned(
              right: rightW - 4,
              top: 0,
              bottom: 0,
              width: 8,
              child: PanelSplitter(
                key: const ValueKey('splitter-right'),
                vertical: true,
                onStart: () => _startRight = rightW,
                onUpdate: (total) => layout.setRight(_startRight - total),
                onEnd: settings.commitLayout,
                onReset: () {
                  layout.resetRight();
                  settings.commitLayout();
                },
              ),
            ),
            if (!collapsed && isEr)
              Positioned(
                left: leftW,
                right: rightW,
                bottom: dockH - 4,
                height: 8,
                child: PanelSplitter(
                  key: const ValueKey('splitter-dock'),
                  vertical: false,
                  onStart: () => _startDock = dockH,
                  onUpdate: (total) => layout.setDock(_startDock - total),
                  onEnd: settings.commitLayout,
                  onReset: () {
                    layout.resetDock();
                    settings.commitLayout();
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          body: Column(children: [
            const TopBar(),
            const DiagramTabBar(),
            Expanded(child: _body(context)),
            const StatusBar(),
          ]),
        ),
      );
}

/// เงาขอบด้านในของพื้นที่ canvas: ตกจากแถบบนและแผงซ้าย/ขวา ทำให้แผงดูลอยเหนือพื้นงาน
/// (วาดเป็น foreground เพราะแผงข้างเคียงถูกวาดก่อน canvas เงาของมันเองจึงถูกบัง; ไม่รับ pointer)
class _EdgeShadow extends CustomPainter {
  const _EdgeShadow();

  static const _depth = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final a = C.isDark ? 0.34 : 0.10;
    final c0 = C.palette.shadow.withValues(alpha: a);
    final c1 = C.palette.shadow.withValues(alpha: 0);
    Paint strip(Offset from, Offset to) => Paint()
      ..shader = LinearGradient(colors: [c0, c1]).createShader(Rect.fromPoints(from, to));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, _depth), strip(Offset.zero, const Offset(0, _depth)));
    canvas.drawRect(Rect.fromLTWH(0, 0, _depth, size.height), strip(Offset.zero, const Offset(_depth, 0)));
    canvas.drawRect(Rect.fromLTWH(size.width - _depth, 0, _depth, size.height),
        Paint()..shader = LinearGradient(colors: [c1, c0]).createShader(Rect.fromLTWH(size.width - _depth, 0, _depth, 0)));
  }

  @override
  bool shouldRepaint(_EdgeShadow old) => true;
}
