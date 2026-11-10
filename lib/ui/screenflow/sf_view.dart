import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/box_ops.dart' show BoxAlign;
import '../../core/layout/ortho_route.dart';
import '../../core/layout/screenflow_geometry.dart';
import '../../core/models/screenflow_model.dart';
import '../../core/validate/screenflow_validator.dart';
import '../../state/screenflow_controller.dart';
import '../../state/workspace_controller.dart';
import '../canvas/box_canvas.dart';
import '../canvas/canvas_chrome.dart';
import '../canvas/context_menu.dart';
import '../canvas/inline_text_editor.dart';
import '../shortcuts.dart' show Cmd;
import '../theme.dart';
import 'sf_actions.dart';
import 'sf_painter.dart';

IconData sfKindIcon(SfKind k) => switch (k) {
      SfKind.start => Icons.play_circle_outline_rounded,
      SfKind.screen => Icons.web_outlined,
      SfKind.external => Icons.open_in_new_rounded,
      SfKind.end => Icons.stop_circle_outlined,
    };

/// คีย์ลัดของเครื่องมือวางโหนด
String sfKindShortcut(SfKind k) => switch (k) {
      SfKind.start || SfKind.end => 'O',
      SfKind.screen => 'P',
      SfKind.external => 'E',
    };

/// พื้นที่วาดของแท็บ Screen Flow
class ScreenFlowCanvas extends StatefulWidget {
  const ScreenFlowCanvas({super.key, this.focusNode});
  final FocusNode? focusNode;

  @override
  State<ScreenFlowCanvas> createState() => _ScreenFlowCanvasState();
}

class _ScreenFlowCanvasState extends BoxCanvasState<ScreenFlowCanvas, ScreenFlowController> {
  @override
  FocusNode? get focusNode => widget.focusNode;

  @override
  String get canvasKey => 'sf-canvas';

  @override
  BoxHit hitTest(ScreenFlowController c, Offset world) {
    final d = c.diagram;
    final routes = sfRoutes(d);
    for (final e in d.edges.reversed) {
      final r = routes[e.id];
      final rect = r == null ? null : sfLabelRect(e, r);
      if (rect != null && rect.contains(world)) return (box: null, edge: e.id);
    }
    final edge = sfEdgeAt(d, world.dx, world.dy, tolerance: 6 / c.scale, routes: routes);
    final node = sfNodeAt(d, world.dx, world.dy, tol: 2 / c.scale);
    if (node != null && edge != null) {
      if (distanceToRoute(routes[edge]!, world.dx, world.dy) <= 3 / c.scale) return (box: null, edge: edge);
      return (box: node.id, edge: null);
    }
    return (box: node?.id, edge: edge);
  }

  @override
  bool isSelectTool(ScreenFlowController c) => c.tool == SfTool.select;

  @override
  void resetTool(ScreenFlowController c) => c.setTool(SfTool.select);

  @override
  bool trackCursor(ScreenFlowController c) => c.linkSource != null;

  @override
  void selectEdge(ScreenFlowController c, String id) => c.selectEdge(id);

  @override
  void doubleTap(ScreenFlowController c, BoxHit hit) {
    final n = hit.box == null ? null : c.diagram.nodeById(hit.box!);
    if (n != null && n.kind == SfKind.screen) {
      // ดับเบิลคลิกหน้าจอ = เปิด Wireframe ที่ผูกไว้ (ยังไม่ผูก = พิมพ์ชื่อ)
      if (c.linkedWireframe(n) != null) {
        ScreenFlowActions(context).openWireframe(n.id);
        return;
      }
    }
    if (hit.edge != null) {
      c.beginEditEdge(hit.edge!);
    } else if (hit.box != null) {
      c.beginEdit(hit.box!);
    }
  }

  @override
  void toolTap(ScreenFlowController c, Offset world, BoxHit hit) {
    switch (c.tool) {
      case SfTool.node:
        final n = c.addNode(c.toolKind, world.dx, world.dy, snap: snap);
        if (n != null) c.beginEdit(n.id);
      case SfTool.edge:
        if (hit.box == null) {
          c.escape();
          return;
        }
        final e = c.linkClick(hit.box!);
        if (e != null) c.beginEditEdge(e.id);
      case SfTool.select:
        break;
    }
  }

  @override
  bool acceptsDrop(Object? data) => data is SfKind;

  @override
  void drop(ScreenFlowController c, Object data, Offset world) {
    if (data is! SfKind) return;
    final n = c.addNode(data, world.dx, world.dy, snap: snap);
    if (n != null) c.beginEdit(n.id);
  }

  @override
  void contextMenu(ScreenFlowController c, TapDownDetails t, Offset world, BoxHit hit) {
    final a = ScreenFlowActions(context);
    if (hit.box != null) {
      final n = c.diagram.nodeById(hit.box!)!;
      if (!c.selectedIds.contains(n.id)) c.selectBox(n.id);
      final ids = c.selectedIds;
      final many = ids.length > 1;
      final linked = c.linkedWireframe(n) != null;
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ชื่อ'), Icons.edit_outlined, () => c.beginEdit(n.id), shortcut: 'F2', enabled: !many),
        if (n.kind == SfKind.screen && !many)
          linked
              ? MenuSpec(tr('เปิด Wireframe ของหน้าจอนี้'), Icons.web_outlined, () => a.openWireframe(n.id))
              : MenuSpec(tr('สร้าง Wireframe สำหรับหน้าจอนี้'), Icons.add_box_outlined, () => c.createWireframeFor(n.id)),
        MenuSpec(tr('ลากเส้นการเปลี่ยนหน้าออกจากตัวนี้'), Icons.arrow_right_alt_rounded, () {
          c.setTool(SfTool.edge);
          c.linkClick(n.id);
        }, enabled: !many),
        MenuSpec(tr('คัดลอก'), Icons.copy_rounded, a.copy, shortcut: 'Ctrl+C'),
        MenuSpec(tr('ทำสำเนา'), Icons.file_copy_outlined, c.duplicateSelection, shortcut: 'Ctrl+D'),
        if (many) ...[
          null,
          MenuSpec(tr('จัดชิดบน'), Icons.align_vertical_top_rounded, () => c.align(BoxAlign.top)),
          MenuSpec(tr('จัดชิดซ้าย'), Icons.align_horizontal_left_rounded, () => c.align(BoxAlign.left)),
        ],
        null,
        MenuSpec(many ? tr('ลบ {0} หน้าจอ', [ids.length]) : tr('ลบหน้าจอ'), Icons.delete_outline, c.deleteSelection,
            shortcut: 'Del', danger: true),
      ]);
      return;
    }
    if (hit.edge != null) {
      final e = c.diagram.edgeById(hit.edge!)!;
      c.selectEdge(e.id);
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ป้ายเส้น'), Icons.edit_outlined, () => c.beginEditEdge(e.id), shortcut: 'F2'),
        MenuSpec(tr('สลับทิศทาง'), Icons.swap_horiz_rounded, () => c.reverseEdge(e.id)),
        null,
        MenuSpec(tr('ลบเส้นการเปลี่ยนหน้า'), Icons.delete_outline, c.deleteSelection, shortcut: 'Del', danger: true),
      ]);
      return;
    }
    c.clearSelection();
    void add(SfKind k) {
      final n = c.addNode(k, world.dx, world.dy, snap: snap);
      if (n != null) c.beginEdit(n.id);
    }

    showContextMenu(context, t.globalPosition, [
      for (final k in SfKind.values) MenuSpec(tr('วาง{0}ที่นี่', [sfKindLabel(k)]), sfKindIcon(k), () => add(k), shortcut: sfKindShortcut(k)),
      null,
      MenuSpec(tr('วาง'), Icons.paste_rounded, a.paste, shortcut: 'Ctrl+V'),
      MenuSpec(tr('เลือกทั้งหมด'), Icons.select_all_rounded, c.selectAll, shortcut: 'Ctrl+A', enabled: c.diagram.nodes.isNotEmpty),
      MenuSpec(tr('จัดวางอัตโนมัติ (ซ้ายไปขวา)'), Icons.account_tree_outlined, () {
        if (c.autoLayout()) c.fit(c.viewport);
      }, enabled: c.diagram.nodes.length > 1),
      MenuSpec(tr('พอดีหน้าจอ'), Icons.fit_screen_outlined, () => c.fit(c.viewport), shortcut: 'Ctrl+0'),
      MenuSpec(tr('Export ภาพ PNG / SVG'), Icons.image_outlined, () => a.run(Cmd.exportImage)),
    ]);
  }

  @override
  CustomPainter foregroundPainter(ScreenFlowController c, Rect? marquee) {
    final w = context.read<WorkspaceController>();
    return ScreenFlowScreenPainter(
      diagram: c.diagram,
      offset: c.offset,
      scale: c.scale,
      wireframeOf: (id) => w.documentById(id)?.wireframe,
      selectedNodes: c.selectedIds,
      selectedEdge: c.selectedEdgeId,
      linkSource: c.linkSource,
      linkCursor: cursor,
      marquee: marquee,
      hideTextOf: c.editing?.id,
      repaint: cursor,
    );
  }

  @override
  List<Widget> overlays(ScreenFlowController c, Size size) {
    final editing = c.editing;
    Widget? editor;
    if (editing != null) {
      Rect? world;
      String initial = '';
      if (editing.isEdge) {
        final e = c.diagram.edgeById(editing.id);
        final r = e == null ? null : sfRoutes(c.diagram)[e.id];
        if (r != null) {
          final (ax, ay) = routeLabelAnchor(r);
          world = Rect.fromCenter(center: Offset(ax, ay), width: 180, height: 26);
          initial = e!.label;
        }
      } else {
        final n = c.diagram.nodeById(editing.id);
        if (n != null) {
          world = n.kind == SfKind.screen
              ? Rect.fromLTWH(n.x, n.y, n.w, kSfTitleBar)
              : Rect.fromLTWH(n.x, n.y, n.w, n.h);
          initial = n.title;
        }
      }
      if (world != null) {
        var r = toScreenRect(c, world);
        if (r.height < 28) r = Rect.fromLTWH(r.left, r.top, r.width, 28);
        if (r.width < 120) r = Rect.fromCenter(center: r.center, width: 120, height: r.height);
        editor = InlineTextEditor(
          key: ValueKey('sf-edit-${editing.id}'),
          fieldKey: const ValueKey('sf-inline-field'),
          rect: r,
          initial: initial,
          multiline: false,
          fontSize: 13 * c.scale,
          onCommit: (text) {
            if (c.editing == editing) c.commitEditing(text);
          },
          onCancel: c.cancelEditing,
          onDone: () => widget.focusNode?.requestFocus(),
        );
      }
    }
    return [
      ?editor,
      Positioned(top: 12, left: 0, right: 0, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: _Toolbar(compact: size.width < 760)))),
      Positioned(
        right: 14,
        bottom: 14,
        child: CanvasZoomBar(controller: c, size: size, keyPrefix: 'sf', extra: [
          IconButton(
            key: const ValueKey('sf-autolayout'),
            tooltip: tr('จัดวางอัตโนมัติ (ซ้ายไปขวา)'),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () {
              if (c.autoLayout()) c.fit(size);
            },
            icon: const Icon(Icons.account_tree_outlined),
          ),
        ]),
      ),
      if (c.diagram.nodes.isEmpty)
        IgnorePointer(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.alt_route_rounded, size: 44, color: C.muted.withValues(alpha: 0.6)),
              const SizedBox(height: 10),
              Text(tr('Screen Flow ว่างอยู่'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.muted)),
              const SizedBox(height: 4),
              Text(tr('วางจุดเริ่มและหน้าจอจากแถบด้านบน (O / P / E) แล้วลากเส้นการเปลี่ยนหน้า (F)'), style: TextStyle(color: C.muted)),
            ]),
          ),
        ),
    ];
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<ScreenFlowController>();
    return CanvasToolbarBox(children: [
      canvasToolItem(
          key: const ValueKey('sf-tool-select'),
          label: tr('เลือก'),
          icon: Icons.near_me_outlined,
          on: f.tool == SfTool.select,
          onTap: () => f.setTool(SfTool.select),
          showLabel: !compact),
      canvasToolDivider(),
      for (final k in SfKind.values)
        canvasToolItem(
            key: ValueKey('sf-tool-${k.name}'),
            label: '${sfKindLabel(k)} (${sfKindShortcut(k)})',
            icon: sfKindIcon(k),
            on: f.tool == SfTool.node && f.toolKind == k,
            onTap: () => f.setNodeTool(k)),
      canvasToolDivider(),
      canvasToolItem(
          key: const ValueKey('sf-tool-edge'),
          label: '${tr('เส้นการเปลี่ยนหน้า')} (F)',
          icon: Icons.arrow_right_alt_rounded,
          on: f.tool == SfTool.edge,
          onTap: () => f.setTool(SfTool.edge),
          showLabel: !compact),
    ]);
  }
}
