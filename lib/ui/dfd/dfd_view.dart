import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/diagram_geometry.dart' show kGridSize;
import '../../core/models/dfd_model.dart';
import '../../state/app_settings.dart';
import '../../state/dfd_controller.dart';
import '../../state/project_controller.dart';
import '../canvas/context_menu.dart';
import '../canvas/dot_grid_painter.dart';
import '../shortcuts.dart' show Cmd;
import '../theme.dart';
import 'dfd_actions.dart';
import 'dfd_painter.dart';

/// พื้นที่วาดของแท็บ DFD: เลื่อน/ซูม, วางวัตถุ, ลากย้าย, กรอบเลือก, ต่อเส้นข้อมูล, เมนูคลิกขวา
class DfdCanvas extends StatefulWidget {
  const DfdCanvas({super.key, this.focusNode});

  /// โฟกัสของหน้าหลัก (รับคีย์ลัด) — ขอกลับมาทุกครั้งที่คลิกบนแคนวาส
  final FocusNode? focusNode;

  @override
  State<DfdCanvas> createState() => _DfdCanvasState();
}

enum _Drag { none, move, marquee, pan, resize, boundary }

class _DfdCanvasState extends State<DfdCanvas> {
  _Drag _drag = _Drag.none;
  Offset? _marqueeStart, _marqueeEnd; // พิกัดจอ (ในพื้นที่แคนวาส)
  final ValueNotifier<Offset?> _cursor = ValueNotifier(null); // พิกัดแผนภาพ ใช้ทำเส้นพรีวิวตอนต่อ flow
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastTapId;

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  bool get _ctrlOrShift => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
  bool get _spaceDown => HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space);

  /// ชนิดที่คลิกโดน: วัตถุก่อน แล้วค่อยเส้น/ป้ายชื่อ
  ({DfdNode? node, String? flow, DfdBoundary? boundary}) _hit(DfdController d, Offset world) {
    final n = dfdNodeAt(d.diagram, world.dx, world.dy);
    if (n != null) return (node: n, flow: null, boundary: null);
    final tol = 7 / d.scale;
    var flow = dfdFlowAt(d.diagram, world.dx, world.dy, tolerance: tol);
    if (flow == null) {
      // ป้ายชื่อที่ยื่นออกนอกเส้นก็คลิกโดนได้
      final routes = dfdRoutes(d.diagram);
      for (final f in d.diagram.flows) {
        final r = routes[f.id];
        if (r != null && f.label.trim().isNotEmpty && dfdLabelRect(f, r).contains(world)) {
          flow = f.id;
          break;
        }
      }
    }
    if (flow != null) return (node: null, flow: flow, boundary: null);
    return (node: null, flow: null, boundary: dfdBoundaryAt(d.diagram, world.dx, world.dy, tol: tol));
  }

  Future<void> _tapUp(Offset local) async {
    widget.focusNode?.requestFocus();
    final d = context.read<DfdController>();
    final actions = DfdActions(context);
    final world = d.toWorld(local);
    final snap = context.read<AppSettings>().snapToGrid;
    final hit = _hit(d, world);

    switch (d.tool) {
      case DfdTool.select:
        final now = clock.now();
        final id = hit.node?.id ?? hit.flow ?? hit.boundary?.id;
        final doubleTap = id != null && id == _lastTapId && now.difference(_lastTap).inMilliseconds < 400;
        _lastTap = now;
        _lastTapId = id;
        if (hit.node != null) {
          d.selectNode(hit.node!.id, add: _ctrlOrShift);
          if (doubleTap) await actions.renameNode(hit.node!);
        } else if (hit.flow != null) {
          d.selectFlow(hit.flow);
          if (doubleTap) await actions.editFlowLabel(d.diagram.flowById(hit.flow!)!);
        } else if (hit.boundary != null) {
          d.selectBoundary(hit.boundary!.id);
          if (doubleTap) await actions.renameBoundary(hit.boundary!);
        } else {
          d.clearSelection();
        }
      case DfdTool.entity || DfdTool.process || DfdTool.store:
        final kind = switch (d.tool) {
          DfdTool.entity => DfdKind.entity,
          DfdTool.process => DfdKind.process,
          _ => DfdKind.store,
        };
        final n = d.addNode(kind, world.dx, world.dy, snap: snap);
        if (n != null) await actions.renameNode(n);
      case DfdTool.flow:
        if (hit.node == null) {
          d.escape();
          return;
        }
        final f = d.linkClick(hit.node!.id);
        if (f != null) await actions.editFlowLabel(f);
    }
  }

  void _secondaryTap(TapDownDetails t) {
    final d = context.read<DfdController>();
    final actions = DfdActions(context);
    if (d.tool != DfdTool.select) {
      d.setTool(DfdTool.select);
      return;
    }
    final world = d.toWorld(t.localPosition);
    final hit = _hit(d, world);
    final snap = context.read<AppSettings>().snapToGrid;
    if (hit.node != null) {
      final n = hit.node!;
      if (!d.selectedNodeIds.contains(n.id)) d.selectNode(n.id);
      final ids = d.selectedNodeIds;
      final many = ids.length > 1;
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('เปลี่ยนชื่อ'), Icons.drive_file_rename_outline, () => actions.renameNode(n), shortcut: 'F2', enabled: !many),
        MenuSpec(tr('ลากเส้นข้อมูลออกจากตัวนี้'), Icons.arrow_right_alt_rounded, () {
          d.setTool(DfdTool.flow);
          d.linkClick(n.id);
        }, enabled: !many),
        MenuSpec(tr('สีวัตถุ…'), Icons.palette_outlined, () => actions.pickNodesColor(ids, current: n.color)),
        MenuSpec(tr('ใช้สีตามชนิด'), Icons.format_color_reset_outlined, () => d.setNodesColor(ids, null),
            enabled: ids.any((i) => d.diagram.nodeById(i)?.color != null)),
        MenuSpec(tr('คัดลอก'), Icons.copy_rounded, actions.copy, shortcut: 'Ctrl+C'),
        MenuSpec(tr('ทำสำเนา'), Icons.file_copy_outlined, d.duplicateSelection, shortcut: 'Ctrl+D'),
        MenuSpec(tr('ครอบด้วยขอบเขตระบบ'), Icons.crop_free_rounded, d.addBoundaryAround),
        null,
        MenuSpec(many ? tr('ลบ {0} วัตถุ', [ids.length]) : tr('ลบวัตถุ'), Icons.delete_outline, d.deleteSelection,
            shortcut: 'Del', danger: true),
      ]);
    } else if (hit.boundary != null) {
      final b = hit.boundary!;
      d.selectBoundary(b.id);
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('เปลี่ยนชื่อ'), Icons.drive_file_rename_outline, () => actions.renameBoundary(b), shortcut: 'F2'),
        MenuSpec(tr('สีขอบเขต…'), Icons.palette_outlined, () => actions.pickBoundaryColor(b)),
        MenuSpec(tr('ใช้สีเริ่มต้น'), Icons.format_color_reset_outlined, () => d.setBoundaryColor(b.id, null),
            enabled: b.color != null),
        null,
        MenuSpec(tr('ลบขอบเขต (ไม่ลบวัตถุข้างใน)'), Icons.delete_outline, d.deleteSelection, shortcut: 'Del', danger: true),
      ]);
    } else if (hit.flow != null) {
      final f = d.diagram.flowById(hit.flow!)!;
      d.selectFlow(f.id);
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ชื่อเส้นข้อมูล'), Icons.edit_outlined, () => actions.editFlowLabel(f), shortcut: 'F2'),
        MenuSpec(tr('สลับทิศทาง'), Icons.swap_horiz_rounded, () => d.reverseFlow(f.id)),
        MenuSpec(tr('ข้อมูลไหลสองทาง'), Icons.sync_alt_rounded, () => d.setFlowBidirectional(f.id, !f.bidirectional),
            checked: f.bidirectional ? true : null),
        MenuSpec(tr('สีเส้น…'), Icons.colorize_rounded, () => actions.pickFlowColor(f)),
        null,
        MenuSpec(tr('ลบเส้นข้อมูล'), Icons.delete_outline, d.deleteSelection, shortcut: 'Del', danger: true),
      ]);
    } else {
      d.clearSelection();
      Future<void> add(DfdKind k) async {
        final n = d.addNode(k, world.dx, world.dy, snap: snap);
        if (n != null) await actions.renameNode(n);
      }

      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('วางผู้ใช้ภายนอกที่นี่'), Icons.crop_square_rounded, () => add(DfdKind.entity), shortcut: 'E'),
        MenuSpec(tr('วางกระบวนการที่นี่'), Icons.rounded_corner_rounded, () => add(DfdKind.process), shortcut: 'P'),
        MenuSpec(tr('วางที่เก็บข้อมูลที่นี่'), Icons.storage_rounded, () => add(DfdKind.store), shortcut: 'D'),
        MenuSpec(tr('วางขอบเขตระบบที่นี่'), Icons.crop_free_rounded, () {
          final b = d.addBoundaryAt(world.dx, world.dy, snap: snap);
          if (b != null) actions.renameBoundary(b);
        }),
        null,
        MenuSpec(tr('วาง'), Icons.paste_rounded, actions.paste, shortcut: 'Ctrl+V'),
        MenuSpec(tr('เลือกทั้งหมด'), Icons.select_all_rounded, d.selectAll, shortcut: 'Ctrl+A', enabled: d.diagram.nodes.isNotEmpty),
        MenuSpec(tr('จัดวางอัตโนมัติ'), Icons.grid_view_rounded, () {
          if (d.autoLayout()) d.fit(d.viewport);
        }, enabled: d.diagram.nodes.length > 1),
        MenuSpec(tr('พอดีหน้าจอ'), Icons.fit_screen_outlined, () => d.fit(d.viewport), shortcut: 'Ctrl+0'),
        MenuSpec(tr('Export ภาพ PNG / SVG'), Icons.image_outlined, () => actions.run(Cmd.exportImage)),
      ]);
    }
  }

  void _panStart(DragStartDetails s) {
    final d = context.read<DfdController>();
    if (d.tool != DfdTool.select) {
      _drag = _Drag.none;
      return;
    }
    if (_spaceDown) {
      _drag = _Drag.pan;
      return;
    }
    final world = d.toWorld(s.localPosition);
    final handle = d.handleAt(world);
    if (handle != null) {
      d.beginResize(handle);
      _drag = _Drag.resize;
      return;
    }
    final hit = _hit(d, world);
    if (hit.node == null && hit.flow == null && hit.boundary != null) {
      d.selectBoundary(hit.boundary!.id);
      d.beginBoundaryMove();
      _drag = _Drag.boundary;
      return;
    }
    if (hit.node != null) {
      if (!d.selectedNodeIds.contains(hit.node!.id)) d.selectNode(hit.node!.id, add: _ctrlOrShift);
      d.beginMove();
      _drag = _Drag.move;
    } else {
      _drag = _Drag.marquee;
      _marqueeStart = s.localPosition;
      _marqueeEnd = s.localPosition;
      if (!_ctrlOrShift) d.clearSelection();
    }
  }

  Set<String> _marqueeBase = const {};

  void _panUpdate(DragUpdateDetails u) {
    final d = context.read<DfdController>();
    switch (_drag) {
      case _Drag.pan:
        d.panBy(u.delta);
      case _Drag.move:
        d.moveBy(u.delta.dx / d.scale, u.delta.dy / d.scale, grid: context.read<AppSettings>().snapToGrid ? kGridSize : null);
      case _Drag.boundary:
        d.moveBoundaryBy(u.delta.dx / d.scale, u.delta.dy / d.scale, grid: context.read<AppSettings>().snapToGrid ? kGridSize : null);
      case _Drag.resize:
        d.resizeBy(u.delta.dx / d.scale, u.delta.dy / d.scale, grid: context.read<AppSettings>().snapToGrid ? kGridSize : null);
      case _Drag.marquee:
        setState(() => _marqueeEnd = u.localPosition);
        final a = d.toWorld(_marqueeStart!), b = d.toWorld(_marqueeEnd!);
        final r = Rect.fromPoints(a, b);
        final inside = {
          for (final n in d.diagram.nodes)
            if (r.overlaps(Rect.fromLTWH(n.x, n.y, n.w, n.h))) n.id,
        };
        d.setNodeSelection({..._marqueeBase, ...inside});
      case _Drag.none:
        break;
    }
  }

  void _panEnd() {
    final d = context.read<DfdController>();
    if (_drag == _Drag.move) d.endMove();
    if (_drag == _Drag.resize) d.endResize();
    if (_drag == _Drag.boundary) d.endBoundaryMove();
    setState(() {
      _drag = _Drag.none;
      _marqueeStart = null;
      _marqueeEnd = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    context.watch<ProjectController>(); // เนื้อหา/ชื่อเปลี่ยน -> วาดใหม่
    final marquee = _marqueeStart == null ? null : Rect.fromPoints(_marqueeStart!, _marqueeEnd ?? _marqueeStart!);
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      d.viewport = size;
      return Listener(
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent) return;
          if (HardwareKeyboard.instance.isControlPressed) {
            d.zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
          } else {
            d.panBy(-e.scrollDelta);
          }
        },
        onPointerMove: (e) {
          // ปุ่มกลางลาก = เลื่อนมุมมอง
          if (e.buttons == kMiddleMouseButton) d.panBy(e.delta);
        },
        onPointerHover: (e) {
          if (d.linkSource != null) _cursor.value = d.toWorld(e.localPosition);
        },
        child: MouseRegion(
          cursor: switch (d.tool) {
            DfdTool.select => _drag == _Drag.pan ? SystemMouseCursors.grabbing : SystemMouseCursors.basic,
            DfdTool.flow => SystemMouseCursors.precise,
            _ => SystemMouseCursors.precise,
          },
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('dfd-canvas'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (t) => _tapUp(t.localPosition),
                onSecondaryTapDown: _secondaryTap,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (s) {
                  _marqueeBase = _ctrlOrShift ? d.selectedNodeIds : const {};
                  _panStart(s);
                },
                onPanUpdate: _panUpdate,
                onPanEnd: (_) => _panEnd(),
                onPanCancel: _panEnd,
                child: CustomPaint(
                  painter: DotGridPainter(d.offset, d.scale),
                  foregroundPainter: DfdScreenPainter(
                    diagram: d.diagram,
                    offset: d.offset,
                    scale: d.scale,
                    selectedNodes: d.selectedNodeIds,
                    selectedFlow: d.selectedFlowId,
                    selectedBoundary: d.selectedBoundaryId,
                    linkSource: d.linkSource,
                    linkCursor: _cursor.value,
                    marquee: marquee,
                    repaint: _cursor,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // แคนวาสแคบ: แถบเครื่องมือแสดงเฉพาะไอคอน (ชื่ออยู่ในทูลทิป) ไม่ให้ล้น
            Positioned(top: 12, left: 0, right: 0, child: Center(child: _Toolbar(compact: size.width < 760))),
            Positioned(right: 14, bottom: 14, child: _ZoomBar(size: size)),
            if (d.diagram.nodes.isEmpty)
              IgnorePointer(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.account_tree_outlined, size: 44, color: C.muted.withValues(alpha: 0.6)),
                    const SizedBox(height: 10),
                    Text(tr('แผนภาพ DFD ว่างอยู่'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.muted)),
                    const SizedBox(height: 4),
                    Text(tr('เลือกเครื่องมือด้านบน (E / P / D) แล้วคลิกบนพื้นที่ว่างเพื่อวางวัตถุ'), style: TextStyle(color: C.muted)),
                  ]),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({this.compact = false});

  /// true = ไอคอนอย่างเดียว
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    Widget item(DfdTool t, String label, IconData icon, String key) {
      final on = d.tool == t;
      return Tooltip(
        message: label,
        child: InkWell(
          key: ValueKey('dfd-tool-$key'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => d.setTool(t),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 10, vertical: 6),
            decoration: BoxDecoration(color: on ? C.primaryTint : Colors.transparent, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: compact ? 17 : 15, color: on ? C.primaryDark : C.muted),
              if (!compact) ...[
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 12.5, color: on ? C.primaryDark : C.text, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
              ],
            ]),
          ),
        ),
      );
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
        item(DfdTool.select, tr('เลือก'), Icons.near_me_outlined, 'select'),
        item(DfdTool.entity, tr('ผู้ใช้ภายนอก'), Icons.crop_square_rounded, 'entity'),
        item(DfdTool.process, tr('กระบวนการ'), Icons.rounded_corner_rounded, 'process'),
        item(DfdTool.store, tr('ที่เก็บข้อมูล'), Icons.storage_rounded, 'store'),
        item(DfdTool.flow, tr('เส้นข้อมูล'), Icons.arrow_right_alt_rounded, 'flow'),
      ]),
    );
  }
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar({required this.size});
  final Size size;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    Widget btn(IconData i, String tip, VoidCallback f, Key k) => IconButton(
          key: k,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: f,
          icon: Icon(i),
        );
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove_rounded, tr('ย่อ'), () => d.zoomAt(size.center(Offset.zero), 1 / 1.2), const ValueKey('dfd-zoom-out')),
        Text('${(d.scale * 100).round()}%', key: const ValueKey('dfd-zoom-label'), style: const TextStyle(fontSize: 12.5)),
        btn(Icons.add_rounded, tr('ขยาย'), () => d.zoomAt(size.center(Offset.zero), 1.2), const ValueKey('dfd-zoom-in')),
        btn(Icons.fit_screen_outlined, tr('พอดีหน้าจอ'), () => d.fit(size), const ValueKey('dfd-fit')),
      ]),
    );
  }
}
