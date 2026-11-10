import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/wireframe_model.dart';
import '../../core/validate/wireframe_validator.dart';
import '../../state/wireframe_controller.dart';
import '../../state/workspace_controller.dart';
import '../canvas/box_canvas.dart';
import '../canvas/canvas_chrome.dart';
import '../canvas/context_menu.dart';
import '../canvas/inline_text_editor.dart';
import '../../core/layout/box_ops.dart' show BoxAlign;
import '../shortcuts.dart' show Cmd, shortcutText;
import '../theme.dart';
import 'wf_actions.dart';
import 'wf_painter.dart';

/// ชนิดชิ้นส่วนในคลัง ตามลำดับที่แสดง
const List<WfKind> kWfLibraryKinds = WfKind.values;

/// ชิ้นส่วนที่อยู่ในแถบเครื่องมือบนแคนวาส
const List<WfKind> kWfToolbarKinds = [
  WfKind.container,
  WfKind.label,
  WfKind.button,
  WfKind.input,
  WfKind.checkbox,
  WfKind.select,
  WfKind.image,
  WfKind.table,
  WfKind.card,
  WfKind.navbar,
];

IconData wfKindIcon(WfKind k) => switch (k) {
      WfKind.container => Icons.crop_square_rounded,
      WfKind.heading => Icons.title_rounded,
      WfKind.label => Icons.short_text_rounded,
      WfKind.paragraph => Icons.notes_rounded,
      WfKind.button => Icons.smart_button_outlined,
      WfKind.input => Icons.text_fields_rounded,
      WfKind.textarea => Icons.subject_rounded,
      WfKind.checkbox => Icons.check_box_outlined,
      WfKind.radio => Icons.radio_button_checked_rounded,
      WfKind.toggle => Icons.toggle_on_outlined,
      WfKind.select => Icons.arrow_drop_down_circle_outlined,
      WfKind.slider => Icons.linear_scale_rounded,
      WfKind.search => Icons.search_rounded,
      WfKind.image => Icons.image_outlined,
      WfKind.icon => Icons.star_outline_rounded,
      WfKind.avatar => Icons.account_circle_outlined,
      WfKind.table => Icons.table_rows_outlined,
      WfKind.list => Icons.format_list_bulleted_rounded,
      WfKind.card => Icons.credit_card_rounded,
      WfKind.tabs => Icons.tab_outlined,
      WfKind.navbar => Icons.web_asset_rounded,
      WfKind.sidebar => Icons.view_sidebar_outlined,
      WfKind.modal => Icons.picture_in_picture_outlined,
      WfKind.divider => Icons.horizontal_rule_rounded,
      WfKind.badge => Icons.label_outline_rounded,
      WfKind.pagination => Icons.more_horiz_rounded,
      WfKind.breadcrumb => Icons.chevron_right_rounded,
      WfKind.map => Icons.map_outlined,
      WfKind.chart => Icons.bar_chart_rounded,
    };

/// คีย์ลัดของเครื่องมือวางชิ้นส่วน ("" = ไม่มี)
String wfKindShortcut(WfKind k) => switch (k) {
      WfKind.label => 'T',
      WfKind.button => shortcutText(Cmd.wfButton),
      WfKind.container => shortcutText(Cmd.wfContainer),
      WfKind.image => shortcutText(Cmd.wfImage),
      WfKind.input => shortcutText(Cmd.wfInput),
      _ => '',
    };

/// ชิ้นที่พิมพ์หลายบรรทัดได้บนแคนวาส
bool wfMultiline(WfKind k) => const {
      WfKind.paragraph,
      WfKind.textarea,
      WfKind.tabs,
      WfKind.list,
      WfKind.sidebar,
      WfKind.breadcrumb,
      WfKind.table,
    }.contains(k);

/// ชื่อขนาดหน้าจอที่แสดงเหนือกรอบ
String wfFrameLabel(WireframeDiagram d) =>
    d.device == WfDevice.custom ? '${tr('กำหนดเอง')} ${d.width.round()}×${d.height.round()}' : wfDeviceLabel(d.device);

/// พื้นที่วาดของแท็บ Wireframe
class WireframeCanvas extends StatefulWidget {
  const WireframeCanvas({super.key, this.focusNode});
  final FocusNode? focusNode;

  @override
  State<WireframeCanvas> createState() => _WireframeCanvasState();
}

class _WireframeCanvasState extends BoxCanvasState<WireframeCanvas, WireframeController> {
  bool _fitted = false;

  @override
  FocusNode? get focusNode => widget.focusNode;

  @override
  String get canvasKey => 'wf-canvas';

  @override
  BoxHit hitTest(WireframeController c, Offset world) {
    final tol = 2 / c.scale;
    for (final x in c.diagram.components.reversed) {
      if (world.dx >= x.x - tol && world.dx <= x.right + tol && world.dy >= x.y - tol && world.dy <= x.bottom + tol) {
        return (box: x.id, edge: null);
      }
    }
    return (box: null, edge: null);
  }

  @override
  bool isSelectTool(WireframeController c) => c.tool == WfTool.select;

  @override
  void resetTool(WireframeController c) => c.setTool(WfTool.select);

  void _place(WireframeController c, WfKind k, Offset world) {
    final n = c.addComponent(k, world.dx, world.dy, snap: snap);
    if (n != null && _editable(k)) c.beginEdit(n.id);
  }

  bool _editable(WfKind k) => !const {
        WfKind.container,
        WfKind.image,
        WfKind.icon,
        WfKind.avatar,
        WfKind.divider,
        WfKind.slider,
        WfKind.map,
        WfKind.chart,
        WfKind.pagination,
      }.contains(k);

  @override
  void toolTap(WireframeController c, Offset world, BoxHit hit) => _place(c, c.toolKind, world);

  @override
  bool acceptsDrop(Object? data) => data is WfKind;

  @override
  void drop(WireframeController c, Object data, Offset world) {
    if (data is WfKind) _place(c, data, world);
  }

  @override
  void contextMenu(WireframeController c, TapDownDetails t, Offset world, BoxHit hit) {
    final a = WireframeActions(context);
    if (hit.box != null) {
      final id = hit.box!;
      if (!c.selectedIds.contains(id)) c.selectBox(id);
      final ids = c.selectedIds;
      final many = ids.length > 1;
      final comp = c.diagram.componentById(id)!;
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ข้อความ'), Icons.edit_outlined, () => c.beginEdit(id), shortcut: 'F2', enabled: !many),
        if (!many && kWfBindableKinds.contains(comp.kind))
          MenuSpec(tr('ผูกกับข้อมูลใน ER…'), Icons.storage_rounded, () => a.bindData(id)),
        MenuSpec(tr('คัดลอก'), Icons.copy_rounded, a.copy, shortcut: 'Ctrl+C'),
        MenuSpec(tr('ทำสำเนา'), Icons.file_copy_outlined, c.duplicateSelection, shortcut: 'Ctrl+D'),
        MenuSpec(tr('นำขึ้นบนสุด'), Icons.flip_to_front_rounded, () => c.reorder(front: true)),
        MenuSpec(tr('นำลงล่างสุด'), Icons.flip_to_back_rounded, () => c.reorder(front: false)),
        if (many) ...[
          null,
          MenuSpec(tr('จัดชิดซ้าย'), Icons.align_horizontal_left_rounded, () => c.align(BoxAlign.left)),
          MenuSpec(tr('จัดกึ่งกลางแนวตั้ง'), Icons.align_horizontal_center_rounded, () => c.align(BoxAlign.centerH)),
          MenuSpec(tr('จัดชิดบน'), Icons.align_vertical_top_rounded, () => c.align(BoxAlign.top)),
          MenuSpec(tr('จัดกึ่งกลางแนวนอน'), Icons.align_vertical_center_rounded, () => c.align(BoxAlign.middle)),
        ],
        null,
        MenuSpec(many ? tr('ลบ {0} ชิ้นส่วน', [ids.length]) : tr('ลบชิ้นส่วน'), Icons.delete_outline, c.deleteSelection,
            shortcut: 'Del', danger: true),
      ]);
      return;
    }
    c.clearSelection();
    showContextMenu(context, t.globalPosition, [
      for (final k in const [WfKind.label, WfKind.button, WfKind.input, WfKind.image, WfKind.container])
        MenuSpec(tr('วาง{0}ที่นี่', [wfKindLabel(k)]), wfKindIcon(k), () => _place(c, k, world), shortcut: wfKindShortcut(k)),
      null,
      MenuSpec(tr('วาง'), Icons.paste_rounded, a.paste, shortcut: 'Ctrl+V'),
      MenuSpec(tr('เลือกทั้งหมด'), Icons.select_all_rounded, c.selectAll, shortcut: 'Ctrl+A', enabled: c.diagram.components.isNotEmpty),
      MenuSpec(
          c.diagram.style == WfStyle.sketch ? tr('เปลี่ยนเป็นแบบเรียบร้อย') : tr('เปลี่ยนเป็นแบบร่าง'),
          Icons.style_outlined,
          () => c.setStyle(c.diagram.style == WfStyle.sketch ? WfStyle.clean : WfStyle.sketch)),
      MenuSpec(tr('พอดีหน้าจอ'), Icons.fit_screen_outlined, () => c.fit(c.viewport), shortcut: 'Ctrl+0'),
      MenuSpec(tr('Export ภาพ PNG / SVG'), Icons.image_outlined, () => a.run(Cmd.exportImage)),
    ]);
  }

  @override
  CustomPainter foregroundPainter(WireframeController c, Rect? marquee) {
    final w = context.read<WorkspaceController>().workspace;
    final sel = c.selectedIds;
    return WireframeScreenPainter(
      diagram: c.diagram,
      offset: c.offset,
      scale: c.scale,
      frameLabel: wfFrameLabel(c.diagram),
      selected: sel,
      children: sel.isEmpty ? const {} : c.moveSet(sel).difference(sel),
      chips: {
        for (final x in c.diagram.components)
          if (x.ref != null) x.id: (wfRefLabel(w, x.ref!), wfRefProblem(w, x.ref!) != null),
      },
      marquee: marquee,
      hideTextOf: c.editing?.id,
    );
  }

  @override
  List<Widget> overlays(WireframeController c, Size size) {
    // เปิดแท็บครั้งแรก: ให้เห็นกรอบหน้าจอทั้งกรอบ
    if (!_fitted && !size.isEmpty) {
      _fitted = true;
      if (c.offset == const Offset(120, 90) && c.scale == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) c.fit(size);
        });
      }
    }
    final editing = c.editing;
    final comp = editing == null ? null : c.diagram.componentById(editing.id);
    return [
      if (editing != null && comp != null)
        InlineTextEditor(
          key: ValueKey('wf-edit-${editing.id}'),
          fieldKey: const ValueKey('wf-inline-field'),
          rect: _editorRect(c, comp),
          initial: c.inlineText(comp),
          multiline: wfMultiline(comp.kind),
          fontSize: comp.effectiveFontSize * c.scale,
          align: switch (comp.align) { WfAlign.left => TextAlign.left, WfAlign.center => TextAlign.center, WfAlign.right => TextAlign.right },
          onCommit: (text) {
            if (c.editing == editing) c.commitEditing(text);
          },
          onCancel: c.cancelEditing,
          onDone: () => widget.focusNode?.requestFocus(),
        ),
      Positioned(top: 12, left: 0, right: 0, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: _Toolbar(compact: size.width < 1000)))),
      Positioned(right: 14, bottom: 14, child: CanvasZoomBar(controller: c, size: size, keyPrefix: 'wf')),
      if (c.diagram.components.isEmpty)
        Positioned(
          left: 0,
          right: 0,
          bottom: 60,
          child: IgnorePointer(
            child: Center(
              child: Text(tr('ลากชิ้นส่วนจากคลังทางซ้ายมาวางในกรอบหน้าจอ หรือเลือกเครื่องมือด้านบน (T / B / L / R / G) แล้วคลิก'),
                  style: TextStyle(color: C.muted)),
            ),
          ),
        ),
    ];
  }

  Rect _editorRect(WireframeController c, WfComponent comp) {
    var r = toScreenRect(c, Rect.fromLTWH(comp.x, comp.y, comp.w, comp.h));
    final minH = wfMultiline(comp.kind) ? 80.0 : 28.0;
    if (r.height < minH) r = Rect.fromLTWH(r.left, r.top, r.width, minH);
    if (r.width < 120) r = Rect.fromLTWH(r.left, r.top, 120, r.height);
    return r;
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<WireframeController>();
    String tip(WfKind k) {
      final s = wfKindShortcut(k);
      return s.isEmpty ? wfKindLabel(k) : '${wfKindLabel(k)} ($s)';
    }

    final style = f.diagram.style;
    return CanvasToolbarBox(children: [
      canvasToolItem(
          key: const ValueKey('wf-tool-select'),
          label: tr('เลือก'),
          icon: Icons.near_me_outlined,
          on: f.tool == WfTool.select,
          onTap: () => f.setTool(WfTool.select),
          showLabel: !compact),
      canvasToolDivider(),
      for (final k in compact ? kWfToolbarKinds.take(6) : kWfToolbarKinds)
        canvasToolItem(
            key: ValueKey('wf-tool-${k.name}'),
            label: tip(k),
            icon: wfKindIcon(k),
            on: f.tool == WfTool.place && f.toolKind == k,
            onTap: () => f.setPlaceTool(k)),
      canvasToolDivider(),
      canvasToolItem(
          key: const ValueKey('wf-style-sketch'),
          label: wfStyleLabel(WfStyle.sketch),
          icon: Icons.gesture_rounded,
          on: style == WfStyle.sketch,
          onTap: () => f.setStyle(WfStyle.sketch)),
      canvasToolItem(
          key: const ValueKey('wf-style-clean'),
          label: wfStyleLabel(WfStyle.clean),
          icon: Icons.auto_awesome_mosaic_outlined,
          on: style == WfStyle.clean,
          onTap: () => f.setStyle(WfStyle.clean)),
    ]);
  }
}

