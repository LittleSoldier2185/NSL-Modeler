import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/diagram_geometry.dart' show kGridSize;
import '../../core/layout/flowchart_geometry.dart';
import '../../core/layout/flowchart_layout.dart';
import '../../core/layout/ortho_route.dart';
import '../../core/models/flowchart_model.dart';
import '../../core/validate/flowchart_validator.dart' show fcShapeLabel;
import '../../state/app_settings.dart';
import '../../state/flowchart_controller.dart';
import '../canvas/context_menu.dart';
import '../canvas/dot_grid_painter.dart';
import '../shortcuts.dart' show Cmd, shortcutText;
import '../theme.dart';
import 'fc_actions.dart';
import 'fc_painter.dart';

/// รูปทรงในแถบเครื่องมือ/คลังสัญลักษณ์ ตามลำดับที่แสดง
const List<FcShape> kFcToolShapes = [
  FcShape.start,
  FcShape.end,
  FcShape.process,
  FcShape.decision,
  FcShape.io,
  FcShape.subroutine,
  FcShape.connector,
  FcShape.note,
  FcShape.rounded,
  FcShape.ellipse,
];

IconData fcShapeIcon(FcShape s) => switch (s) {
      FcShape.start => Icons.play_circle_outline_rounded,
      FcShape.end => Icons.stop_circle_outlined,
      FcShape.process => Icons.crop_square_rounded,
      FcShape.decision => Icons.diamond_outlined,
      FcShape.io => Icons.input_rounded,
      FcShape.subroutine => Icons.view_week_outlined,
      FcShape.connector => Icons.circle_outlined,
      FcShape.note => Icons.sticky_note_2_outlined,
      FcShape.rounded => Icons.rounded_corner_rounded,
      FcShape.ellipse => Icons.panorama_fish_eye_rounded,
    };

/// คีย์ลัดของเครื่องมือวางรูปทรง ("" = ไม่มี)
String fcShapeShortcut(FcShape s) => switch (s) {
      FcShape.start || FcShape.end => shortcutText(Cmd.fcTerminator),
      FcShape.process => 'P',
      FcShape.decision => 'D',
      FcShape.io => shortcutText(Cmd.fcIo),
      FcShape.subroutine => shortcutText(Cmd.fcSubroutine),
      FcShape.connector => shortcutText(Cmd.fcConnector),
      FcShape.note => 'N',
      _ => '',
    };

/// พื้นที่วาดของแท็บ Flowchart: เลื่อน/ซูม, วางสัญลักษณ์ (คลิก หรือลากจากคลังทางซ้าย), ลากย้าย, ปรับขนาด,
/// กรอบเลือก, ต่อเส้น, พิมพ์ข้อความบนแคนวาส, เมนูคลิกขวา
class FlowchartCanvas extends StatefulWidget {
  const FlowchartCanvas({super.key, this.focusNode});

  /// โฟกัสของหน้าหลัก (รับคีย์ลัด) — ขอกลับมาทุกครั้งที่คลิกบนแคนวาส
  final FocusNode? focusNode;

  @override
  State<FlowchartCanvas> createState() => _FlowchartCanvasState();
}

enum _Drag { none, move, marquee, pan, resize }

class _FlowchartCanvasState extends State<FlowchartCanvas> {
  _Drag _drag = _Drag.none;
  Offset? _marqueeStart, _marqueeEnd;
  final ValueNotifier<Offset?> _cursor = ValueNotifier(null);
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastTapId;
  Set<String> _marqueeBase = const {};
  final _canvasKey = GlobalKey();

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  bool get _ctrlOrShift => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
  bool get _spaceDown => HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space);
  bool get _snap => context.read<AppSettings>().snapToGrid;

  ({FcNode? node, String? edge}) _hit(FlowchartController f, Offset world) {
    final routes = fcRoutes(f.diagram);
    // ป้ายชื่อเส้นอยู่บนสุด คลิกโดนก่อน
    for (final e in f.diagram.edges.reversed) {
      final r = routes[e.id];
      final rect = r == null ? null : fcLabelRect(e, r);
      if (rect != null && rect.contains(world)) return (node: null, edge: e.id);
    }
    final tol = 6 / f.scale;
    final edge = fcEdgeAt(f.diagram, world.dx, world.dy, tolerance: tol, routes: routes);
    final node = fcNodeAt(f.diagram, world.dx, world.dy, tol: 2 / f.scale);
    // เส้นที่วิ่งผ่านบนสัญลักษณ์: ต้องคลิกใกล้เส้นมาก ๆ จึงได้เส้น
    if (node != null && edge != null) {
      final r = routes[edge]!;
      if (distanceToRoute(r, world.dx, world.dy) <= 3 / f.scale) return (node: null, edge: edge);
      return (node: node, edge: null);
    }
    return (node: node, edge: edge);
  }

  Future<void> _tapUp(Offset local) async {
    widget.focusNode?.requestFocus();
    final f = context.read<FlowchartController>();
    // กำลังพิมพ์อยู่: โฟกัสกลับมาที่หน้าหลักแล้ว (บรรทัดบน) ช่องพิมพ์จึงเสียโฟกัสและบันทึกเอง — คลิกนี้ใช้จบการพิมพ์อย่างเดียว
    if (f.editing != null) return;
    final world = f.toWorld(local);
    final hit = _hit(f, world);
    switch (f.tool) {
      case FcTool.select:
        final now = clock.now();
        final id = hit.node?.id ?? hit.edge;
        final doubleTap = id != null && id == _lastTapId && now.difference(_lastTap).inMilliseconds < 400;
        _lastTap = now;
        _lastTapId = id;
        if (hit.node != null) {
          f.selectNode(hit.node!.id, add: _ctrlOrShift && !doubleTap);
          if (doubleTap) f.beginEditNode(hit.node!.id);
        } else if (hit.edge != null) {
          f.selectEdge(hit.edge);
          if (doubleTap) f.beginEditEdge(hit.edge!);
        } else {
          f.clearSelection();
        }
      case FcTool.shape:
        final n = f.addNode(f.toolShape, world.dx, world.dy, snap: _snap);
        if (n != null) f.beginEditNode(n.id);
      case FcTool.edge:
        if (hit.node == null) {
          f.escape();
          return;
        }
        final e = f.linkClick(hit.node!.id);
        // ทางออกของการตัดสินใจต้องมีป้าย: เปิดช่องพิมพ์ให้เลย
        if (e != null && f.diagram.nodeById(e.fromId)?.shape == FcShape.decision) f.beginEditEdge(e.id);
    }
  }

  void _secondaryTap(TapDownDetails t) {
    final f = context.read<FlowchartController>();
    final a = FlowchartActions(context);
    if (f.editing != null) return;
    if (f.tool != FcTool.select) {
      f.setTool(FcTool.select);
      return;
    }
    final world = f.toWorld(t.localPosition);
    final hit = _hit(f, world);
    if (hit.node != null) {
      final n = hit.node!;
      if (!f.selectedNodeIds.contains(n.id)) f.selectNode(n.id);
      final ids = f.selectedNodeIds;
      final many = ids.length > 1;
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ข้อความ'), Icons.edit_outlined, () => f.beginEditNode(n.id), shortcut: 'F2', enabled: !many),
        MenuSpec(tr('ลากเส้นเชื่อมออกจากตัวนี้'), Icons.arrow_right_alt_rounded, () {
          f.setTool(FcTool.edge);
          f.linkClick(n.id);
        }, enabled: !many),
        MenuSpec(tr('คัดลอก'), Icons.copy_rounded, a.copy, shortcut: 'Ctrl+C'),
        MenuSpec(tr('ทำสำเนา'), Icons.file_copy_outlined, f.duplicateSelection, shortcut: 'Ctrl+D'),
        MenuSpec(tr('นำขึ้นบนสุด'), Icons.flip_to_front_rounded, () => f.reorder(front: true)),
        MenuSpec(tr('นำลงล่างสุด'), Icons.flip_to_back_rounded, () => f.reorder(front: false)),
        if (many) ...[
          null,
          MenuSpec(tr('จัดชิดซ้าย'), Icons.align_horizontal_left_rounded, () => f.align(FcAlignKind.left)),
          MenuSpec(tr('จัดกึ่งกลางแนวตั้ง'), Icons.align_horizontal_center_rounded, () => f.align(FcAlignKind.centerH)),
          MenuSpec(tr('จัดชิดบน'), Icons.align_vertical_top_rounded, () => f.align(FcAlignKind.top)),
          MenuSpec(tr('จัดกึ่งกลางแนวนอน'), Icons.align_vertical_center_rounded, () => f.align(FcAlignKind.middle)),
        ],
        null,
        MenuSpec(many ? tr('ลบ {0} สัญลักษณ์', [ids.length]) : tr('ลบสัญลักษณ์'), Icons.delete_outline, f.deleteSelection,
            shortcut: 'Del', danger: true),
      ]);
    } else if (hit.edge != null) {
      final e = f.diagram.edgeById(hit.edge!)!;
      f.selectEdge(e.id);
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ป้ายเส้น'), Icons.edit_outlined, () => f.beginEditEdge(e.id), shortcut: 'F2'),
        MenuSpec(tr('สลับทิศทาง'), Icons.swap_horiz_rounded, () => f.reverseEdge(e.id)),
        MenuSpec(tr('เส้นประ'), Icons.more_horiz_rounded,
            () => f.updateEdge(e.id, (x) => x.dash = x.dash == FcDash.dashed ? FcDash.solid : FcDash.dashed),
            checked: e.dash == FcDash.dashed ? true : null),
        MenuSpec(tr('สีเส้น…'), Icons.colorize_rounded, () => a.pickEdgeColor(e)),
        null,
        MenuSpec(tr('ลบเส้นเชื่อม'), Icons.delete_outline, f.deleteSelection, shortcut: 'Del', danger: true),
      ]);
    } else {
      f.clearSelection();
      void add(FcShape s) {
        final n = f.addNode(s, world.dx, world.dy, snap: _snap);
        if (n != null) f.beginEditNode(n.id);
      }

      showContextMenu(context, t.globalPosition, [
        for (final s in const [FcShape.start, FcShape.end, FcShape.process, FcShape.decision, FcShape.io])
          MenuSpec(tr('วาง{0}ที่นี่', [fcShapeLabel(s)]), fcShapeIcon(s), () => add(s),
              shortcut: fcShapeShortcut(s)),
        null,
        MenuSpec(tr('วาง'), Icons.paste_rounded, a.paste, shortcut: 'Ctrl+V'),
        MenuSpec(tr('เลือกทั้งหมด'), Icons.select_all_rounded, f.selectAll, shortcut: 'Ctrl+A', enabled: f.diagram.nodes.isNotEmpty),
        MenuSpec(tr('จัดวางอัตโนมัติ (บนลงล่าง)'), Icons.account_tree_outlined, () {
          if (f.autoLayout()) f.fit(f.viewport);
        }, enabled: f.diagram.nodes.length > 1),
        MenuSpec(tr('พอดีหน้าจอ'), Icons.fit_screen_outlined, () => f.fit(f.viewport), shortcut: 'Ctrl+0'),
        MenuSpec(tr('Export ภาพ PNG / SVG'), Icons.image_outlined, () => a.run(Cmd.exportImage)),
      ]);
    }
  }

  void _panStart(DragStartDetails s) {
    final f = context.read<FlowchartController>();
    if (f.editing != null) {
      _drag = _Drag.none;
      return;
    }
    if (_spaceDown) {
      _drag = _Drag.pan;
      return;
    }
    if (f.tool != FcTool.select) {
      _drag = _Drag.none;
      return;
    }
    final world = f.toWorld(s.localPosition);
    final handle = f.handleAt(world);
    if (handle != null) {
      f.beginResize(handle);
      _drag = _Drag.resize;
      return;
    }
    final hit = _hit(f, world);
    if (hit.node != null) {
      if (!f.selectedNodeIds.contains(hit.node!.id)) f.selectNode(hit.node!.id, add: _ctrlOrShift);
      f.beginMove();
      _drag = _Drag.move;
    } else {
      _drag = _Drag.marquee;
      _marqueeStart = s.localPosition;
      _marqueeEnd = s.localPosition;
      if (!_ctrlOrShift) f.clearSelection();
    }
  }

  void _panUpdate(DragUpdateDetails u) {
    final f = context.read<FlowchartController>();
    final grid = _snap ? kGridSize : null;
    switch (_drag) {
      case _Drag.pan:
        f.panBy(u.delta);
      case _Drag.move:
        f.moveBy(u.delta.dx / f.scale, u.delta.dy / f.scale, grid: grid);
      case _Drag.resize:
        f.resizeBy(u.delta.dx / f.scale, u.delta.dy / f.scale, grid: grid);
      case _Drag.marquee:
        setState(() => _marqueeEnd = u.localPosition);
        final r = Rect.fromPoints(f.toWorld(_marqueeStart!), f.toWorld(_marqueeEnd!));
        f.setNodeSelection({
          ..._marqueeBase,
          for (final n in f.diagram.nodes)
            if (r.overlaps(Rect.fromLTWH(n.x, n.y, n.w, n.h))) n.id,
        });
      case _Drag.none:
        break;
    }
  }

  void _panEnd() {
    final f = context.read<FlowchartController>();
    if (_drag == _Drag.move) f.endMove();
    if (_drag == _Drag.resize) f.endResize();
    setState(() {
      _drag = _Drag.none;
      _marqueeStart = null;
      _marqueeEnd = null;
    });
  }

  /// วางสัญลักษณ์ที่ลากมาจากคลังทางซ้าย ณ ตำแหน่งที่ปล่อย (พิกัดจอทั้งหน้าต่าง)
  void _drop(FcShape s, Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final f = context.read<FlowchartController>();
    final world = f.toWorld(box.globalToLocal(global));
    final n = f.addNode(s, world.dx, world.dy, snap: _snap);
    if (n != null) f.beginEditNode(n.id);
    widget.focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    final marquee = _marqueeStart == null ? null : Rect.fromPoints(_marqueeStart!, _marqueeEnd ?? _marqueeStart!);
    final editing = f.editing;
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      f.viewport = size;
      return DragTarget<FcShape>(
        onAcceptWithDetails: (d) => _drop(d.data, d.offset + const Offset(28, 20)),
        builder: (context, cand, _) => Listener(
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            if (HardwareKeyboard.instance.isControlPressed) {
              f.zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
            } else {
              f.panBy(-e.scrollDelta);
            }
          },
          onPointerMove: (e) {
            if (e.buttons == kMiddleMouseButton) f.panBy(e.delta);
          },
          onPointerHover: (e) {
            if (f.linkSource != null) _cursor.value = f.toWorld(e.localPosition);
          },
          child: MouseRegion(
            cursor: f.tool == FcTool.select
                ? (_drag == _Drag.pan ? SystemMouseCursors.grabbing : SystemMouseCursors.basic)
                : SystemMouseCursors.precise,
            child: Stack(key: _canvasKey, children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('fc-canvas'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (t) => _tapUp(t.localPosition),
                  onSecondaryTapDown: _secondaryTap,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: (s) {
                    _marqueeBase = _ctrlOrShift ? f.selectedNodeIds : const {};
                    _panStart(s);
                  },
                  onPanUpdate: _panUpdate,
                  onPanEnd: (_) => _panEnd(),
                  onPanCancel: _panEnd,
                  child: CustomPaint(
                    painter: DotGridPainter(f.offset, f.scale),
                    foregroundPainter: FlowchartScreenPainter(
                      diagram: f.diagram,
                      offset: f.offset,
                      scale: f.scale,
                      selectedNodes: f.selectedNodeIds,
                      selectedEdge: f.selectedEdgeId,
                      linkSource: f.linkSource,
                      linkCursor: _cursor.value,
                      marquee: marquee,
                      hideTextOf: editing?.id,
                      repaint: _cursor,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (editing != null)
                _InlineEditor(
                  key: ValueKey('fc-edit-${editing.id}'),
                  target: editing,
                  // จบการพิมพ์ด้วยคีย์: คืนโฟกัสให้หน้าหลัก (ช่องพิมพ์เสียโฟกัส = บันทึก) คีย์ลัดจึงใช้ต่อได้ทันที
                  onDone: () => widget.focusNode?.requestFocus(),
                ),
              if (cand.isNotEmpty)
                IgnorePointer(child: Container(color: C.primary.withValues(alpha: 0.05))),
              Positioned(top: 12, left: 0, right: 0, child: Center(child: _Toolbar(compact: size.width < 900))),
              Positioned(right: 14, bottom: 14, child: _ZoomBar(size: size)),
              if (f.diagram.nodes.isEmpty)
                IgnorePointer(
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.schema_outlined, size: 44, color: C.muted.withValues(alpha: 0.6)),
                      const SizedBox(height: 10),
                      Text(tr('Flowchart ว่างอยู่'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.muted)),
                      const SizedBox(height: 4),
                      Text(tr('ลากสัญลักษณ์จากคลังทางซ้าย หรือเลือกเครื่องมือด้านบน (O / P / D) แล้วคลิกบนพื้นที่ว่าง'),
                          style: TextStyle(color: C.muted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }
}

/// ช่องพิมพ์ข้อความบนแคนวาส (วางทับสัญลักษณ์/ป้ายเส้นที่กำลังแก้) — Ctrl+Enter หรือคลิกที่อื่น = บันทึก, Esc = ยกเลิก
/// สัญลักษณ์พิมพ์หลายบรรทัดได้ (Enter ขึ้นบรรทัดใหม่) ; ป้ายเส้นบรรทัดเดียว (Enter = บันทึก)
class _InlineEditor extends StatefulWidget {
  const _InlineEditor({super.key, required this.target, this.onDone});
  final ({String id, bool isEdge}) target;

  /// เรียกเมื่อผู้ใช้จบการพิมพ์ด้วยคีย์ (Ctrl+Enter / Enter ของป้ายเส้น / Esc)
  final VoidCallback? onDone;

  @override
  State<_InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<_InlineEditor> {
  late final FlowchartController _f = context.read<FlowchartController>();
  late final TextEditingController _ctl = TextEditingController(text: _initial);
  final _focus = FocusNode(debugLabel: 'fc-inline');
  bool _done = false;

  String get _initial => widget.target.isEdge
      ? (_f.diagram.edgeById(widget.target.id)?.label ?? '')
      : (_f.diagram.nodeById(widget.target.id)?.text ?? '');

  @override
  void initState() {
    super.initState();
    _ctl.selection = TextSelection(baseOffset: 0, extentOffset: _ctl.text.length);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _finish() {
    if (widget.onDone == null) {
      _focus.unfocus();
    } else {
      widget.onDone!();
    }
  }

  void _commit() {
    if (_done) return;
    _done = true;
    // ถูกยกเลิก (Esc) หรือเปลี่ยนไปแก้อันอื่นแล้ว = ไม่บันทึก
    if (_f.editing == widget.target) _f.commitEditing(_ctl.text);
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    final t = widget.target;
    Rect rect;
    TextAlign align = TextAlign.center;
    double fontSize = 13;
    if (t.isEdge) {
      final e = f.diagram.edgeById(t.id);
      final r = e == null ? null : fcRoutes(f.diagram)[e.id];
      if (r == null) return const SizedBox.shrink();
      final (ax, ay) = routeLabelAnchor(r);
      rect = Rect.fromCenter(center: Offset(ax, ay), width: 160, height: 26);
      fontSize = kFcLabelSize;
    } else {
      final n = f.diagram.nodeById(t.id);
      if (n == null) return const SizedBox.shrink();
      final b = fcTextBox(n);
      rect = Rect.fromLTWH(b.left, b.top, b.width, b.height);
      if (rect.height < 26) rect = Rect.fromCenter(center: rect.center, width: rect.width, height: 26);
      if (rect.width < 80) rect = Rect.fromCenter(center: rect.center, width: 80, height: rect.height);
      align = switch (n.align) {
        FcAlign.left => TextAlign.left,
        FcAlign.center => TextAlign.center,
        FcAlign.right => TextAlign.right,
      };
      fontSize = n.fontSize;
    }
    final tl = f.toScreen(rect.topLeft);
    return Positioned(
      left: tl.dx,
      top: tl.dy,
      width: rect.width * f.scale,
      height: rect.height * f.scale,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _finish,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _done = true;
            f.cancelEditing();
            widget.onDone?.call();
          },
        },
        child: Material(
          color: C.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(4),
          child: TextField(
            key: const ValueKey('fc-inline-field'),
            controller: _ctl,
            focusNode: _focus,
            textAlign: align,
            textAlignVertical: TextAlignVertical.center,
            maxLines: t.isEdge ? 1 : null,
            expands: !t.isEdge,
            keyboardType: t.isEdge ? TextInputType.text : TextInputType.multiline,
            onSubmitted: t.isEdge ? (_) => _finish() : null,
            style: TextStyle(fontSize: fontSize * f.scale, color: C.text, height: 1.25),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: C.primary)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: C.primary, width: 1.5)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    Widget item(String key, String label, IconData icon, bool on, VoidCallback tap, {bool showLabel = false}) => Tooltip(
          message: label,
          child: InkWell(
            key: ValueKey('fc-tool-$key'),
            borderRadius: BorderRadius.circular(6),
            onTap: tap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: on ? C.primaryTint : Colors.transparent, borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: on ? C.primaryDark : C.muted),
                if (showLabel && !compact) ...[
                  const SizedBox(width: 5),
                  Text(label, style: TextStyle(fontSize: 12.5, color: on ? C.primaryDark : C.text)),
                ],
              ]),
            ),
          ),
        );
    String tip(FcShape s) {
      final k = fcShapeShortcut(s);
      return k.isEmpty ? fcShapeLabel(s) : '${fcShapeLabel(s)} ($k)';
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border),
        boxShadow: [BoxShadow(color: C.palette.shadow.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        item('select', tr('เลือก'), Icons.near_me_outlined, f.tool == FcTool.select, () => f.setTool(FcTool.select), showLabel: true),
        Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4), color: C.border),
        for (final s in kFcToolShapes)
          item(s.name, tip(s), fcShapeIcon(s), f.tool == FcTool.shape && f.toolShape == s, () => f.setShapeTool(s)),
        Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4), color: C.border),
        item('edge', '${tr('เส้นเชื่อม')} (F)', Icons.arrow_right_alt_rounded, f.tool == FcTool.edge, () => f.setTool(FcTool.edge),
            showLabel: true),
      ]),
    );
  }
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar({required this.size});
  final Size size;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    Widget btn(IconData i, String tip, VoidCallback cb, Key k) =>
        IconButton(key: k, tooltip: tip, visualDensity: VisualDensity.compact, iconSize: 18, onPressed: cb, icon: Icon(i));
    return Container(
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove_rounded, tr('ย่อ'), () => f.zoomAt(size.center(Offset.zero), 1 / 1.2), const ValueKey('fc-zoom-out')),
        Text('${(f.scale * 100).round()}%', key: const ValueKey('fc-zoom-label'), style: const TextStyle(fontSize: 12.5)),
        btn(Icons.add_rounded, tr('ขยาย'), () => f.zoomAt(size.center(Offset.zero), 1.2), const ValueKey('fc-zoom-in')),
        btn(Icons.center_focus_strong_outlined, tr('พอดีกับที่เลือก'), () => f.fitSelection(size), const ValueKey('fc-fit-selection')),
        btn(Icons.fit_screen_outlined, tr('พอดีหน้าจอ'), () => f.fit(size), const ValueKey('fc-fit')),
        btn(Icons.account_tree_outlined, tr('จัดวางอัตโนมัติ (บนลงล่าง)'), () {
          if (f.autoLayout(kind: FcLayoutKind.topDown)) f.fit(size);
        }, const ValueKey('fc-autolayout')),
      ]),
    );
  }
}
