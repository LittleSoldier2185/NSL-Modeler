import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/flowchart_layout.dart';
import '../../core/models/flowchart_model.dart';
import '../../core/validate/flowchart_validator.dart';
import '../../core/validate/issue.dart';
import '../../state/flowchart_controller.dart';
import '../../state/workspace_controller.dart';
import '../issue_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'fc_actions.dart';
import 'fc_painter.dart';
import 'fc_view.dart';

/// ข้อความแสดงของสัญลักษณ์ในรายการ (บรรทัดเดียว)
String fcNodeTitle(FcNode n) {
  final t = n.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.isEmpty ? fcShapeLabel(n.shape) : t;
}

/// แผงซ้ายของแท็บ Flowchart: คลังสัญลักษณ์ (ค้นได้ ลากไปวางหรือคลิกเลือกเครื่องมือ) + รายการสัญลักษณ์และเส้น
class FlowchartLeftPanel extends StatefulWidget {
  const FlowchartLeftPanel({super.key});

  @override
  State<FlowchartLeftPanel> createState() => _FlowchartLeftPanelState();
}

class _FlowchartLeftPanelState extends State<FlowchartLeftPanel> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    final w = context.watch<WorkspaceController>();
    final d = f.diagram;
    final q = _q.trim().toLowerCase();
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);
    final shapes = [
      for (final s in kFcToolShapes)
        if (match('${fcShapeLabel(s)} ${s.name}')) s,
    ];
    final nodes = [for (final n in d.nodes) if (match('${n.text} ${fcShapeLabel(n.shape)}')) n];
    String nodeName(String id) {
      final n = d.nodeById(id);
      return n == null ? '?' : fcNodeTitle(n);
    }

    final edges = [for (final e in d.edges) if (match('${e.label} ${nodeName(e.fromId)} ${nodeName(e.toId)}')) e];

    Widget section(String title, int n) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            TextSpan(text: ' ($n)', style: TextStyle(color: C.muted, fontSize: 12.5)),
          ])),
        );

    return Container(
      decoration: BoxDecoration(border: Border(right: BorderSide(color: C.border))),
      child: Material(
        color: C.surface,
        child: ListView(padding: EdgeInsets.zero, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text(w.activeDocument.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: SizedBox(
              height: kFieldHeight,
              child: TextField(
                key: const ValueKey('fc-search'),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('ค้นหาสัญลักษณ์ / ข้อความ'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ),
          section(tr('คลังสัญลักษณ์'), shapes.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
            child: Wrap(spacing: 6, runSpacing: 6, children: [for (final s in shapes) _ShapeTile(shape: s)]),
          ),
          section(tr('สัญลักษณ์'), nodes.length),
          for (final n in nodes)
            ListTile(
              key: ValueKey('fc-item-${n.id}'),
              dense: true,
              visualDensity: VisualDensity.compact,
              selected: f.selectedNodeIds.contains(n.id),
              leading: Icon(fcShapeIcon(n.shape), size: 16, color: Color(fcStrokeColor(n))),
              title: Text(fcNodeTitle(n), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              onTap: () {
                f.selectNode(n.id);
                f.reveal(n.id, f.viewport);
              },
            ),
          section(tr('เส้นเชื่อม'), edges.length),
          for (final e in edges)
            ListTile(
              key: ValueKey('fc-edge-${e.id}'),
              dense: true,
              visualDensity: VisualDensity.compact,
              selected: f.selectedEdgeId == e.id,
              leading: Icon(Icons.arrow_right_alt_rounded, size: 16, color: C.muted),
              title: Text(e.label.isEmpty ? tr('(ไม่มีป้าย)') : e.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              subtitle: Text('${nodeName(e.fromId)} → ${nodeName(e.toId)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: C.muted)),
              onTap: () => f.selectEdge(e.id),
            ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

/// ช่องหนึ่งในคลังสัญลักษณ์: ภาพย่อของรูปทรงจริง — คลิก = เลือกเครื่องมือ, ลากไปวางบนแคนวาสได้
class _ShapeTile extends StatelessWidget {
  const _ShapeTile({required this.shape});
  final FcShape shape;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    final on = f.tool == FcTool.shape && f.toolShape == shape;
    final k = fcShapeShortcut(shape);
    final tile = Container(
      width: 56,
      height: 46,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: on ? C.primaryTint : C.bg,
        border: Border.all(color: on ? C.primary : C.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomPaint(painter: _ShapePreview(shape)),
    );
    return Tooltip(
      message: k.isEmpty ? fcShapeLabel(shape) : '${fcShapeLabel(shape)} ($k)',
      child: Draggable<FcShape>(
        data: shape,
        feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.8, child: tile)),
        child: InkWell(
          key: ValueKey('fc-shape-${shape.name}'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => f.setShapeTool(shape),
          child: tile,
        ),
      ),
    );
  }
}

class _ShapePreview extends CustomPainter {
  _ShapePreview(this.shape);
  final FcShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final (w, h) = fcDefaultSize(shape);
    final s = (size.width / w) < (size.height / h) ? size.width / w : size.height / h;
    canvas.save();
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);
    paintFlowchart(canvas, FlowchartDiagram(nodes: [FcNode(id: 'p', shape: shape)]), shadows: false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapePreview old) => old.shape != shape;
}

/// แผงขวาของแท็บ Flowchart: รูปแบบของสัญลักษณ์/เส้นที่เลือก หรือภาพรวม + ปัญหาของแผนภาพเมื่อไม่ได้เลือกอะไร
class FlowchartRightPanel extends StatelessWidget {
  const FlowchartRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    final node = f.selectedNode;
    final edge = f.selectedEdge;
    final Widget body;
    if (node != null) {
      body = _NodeProps(node: node);
    } else if (edge != null) {
      body = _EdgeProps(edge: edge);
    } else if (f.selectedNodeIds.length > 1) {
      body = _MultiProps(ids: f.selectedNodeIds);
    } else {
      body = _Overview(diagram: f.diagram);
    }
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: C.border))),
      child: Material(
        color: C.surface,
        child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }
}

/// แถวสีสำเร็จรูป + ปุ่มค่าเริ่มต้น + ปุ่มกำหนดเอง
class _Swatches extends StatelessWidget {
  const _Swatches({required this.keyPrefix, required this.current, required this.onPick, required this.onCustom});
  final String keyPrefix;
  final int? current;
  final ValueChanged<int?> onPick;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    Widget sw(Key k, String tip, bool on, VoidCallback tap, Widget child) => Tooltip(
          message: tip,
          child: InkResponse(
            key: k,
            onTap: tap,
            radius: 16,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: on ? C.text : C.border, width: on ? 2 : 1),
              ),
              child: child,
            ),
          ),
        );
    final custom = current != null && !kFcPalette.contains(current);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      sw(ValueKey('$keyPrefix-default'), tr('ค่าเริ่มต้น'), current == null, () => onPick(null),
          Icon(Icons.format_color_reset_outlined, size: 13, color: C.muted)),
      for (var i = 0; i < kFcPalette.length; i++)
        sw(
          ValueKey('$keyPrefix-$i'),
          '#${(kFcPalette[i] & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}',
          current == kFcPalette[i],
          () => onPick(kFcPalette[i]),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Color(kFcPalette[i]), border: Border.all(color: C.border)),
          ),
        ),
      sw(ValueKey('$keyPrefix-custom'), tr('กำหนดสีเอง…'), custom, onCustom,
          custom
              ? Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(current!)))
              : Icon(Icons.colorize_rounded, size: 13, color: C.muted)),
    ]);
  }
}

/// ส่วนรูปแบบ (สีพื้น/เส้นขอบ/ตัวอักษร ขนาด ตัวหนา/เอียง แนวข้อความ เส้นขอบ) — ใช้ทั้งชิ้นเดียวและหลายชิ้น
class _StyleSection extends StatelessWidget {
  const _StyleSection({required this.ids, required this.sample});
  final Set<String> ids;
  final FcNode sample;

  @override
  Widget build(BuildContext context) {
    final f = context.read<FlowchartController>();
    final a = FlowchartActions(context);
    Widget toggle(String key, IconData icon, String tip, bool on, VoidCallback tap) => IconButton(
          key: ValueKey(key),
          tooltip: tip,
          isSelected: on,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(backgroundColor: on ? C.primaryTint : null),
          icon: Icon(icon, size: 18, color: on ? C.primaryDark : C.muted),
          onPressed: tap,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledField(
        label: tr('สีพื้น'),
        child: _Swatches(
          keyPrefix: 'fc-fill',
          current: sample.fill,
          onPick: (c) => f.setNodesStyle(ids, (n) => n.fill = c),
          onCustom: () => a.pickNodeColor(ids, fill: true, current: sample.fill),
        ),
      ),
      const SizedBox(height: 12),
      LabeledField(
        label: tr('สีเส้นขอบ'),
        child: _Swatches(
          keyPrefix: 'fc-stroke',
          current: sample.stroke,
          onPick: (c) => f.setNodesStyle(ids, (n) => n.stroke = c),
          onCustom: () => a.pickNodeColor(ids, fill: false, current: sample.stroke ?? fcStrokeColor(sample)),
        ),
      ),
      const SizedBox(height: 12),
      LabeledField(
        label: tr('สีตัวอักษร'),
        child: _Swatches(
          keyPrefix: 'fc-text',
          current: sample.textColor,
          onPick: (c) => f.setNodesStyle(ids, (n) => n.textColor = c),
          onCustom: () => a.pickTextColor(ids, current: sample.textColor),
        ),
      ),
      const SizedBox(height: 12),
      LabeledField(
        label: tr('ตัวอักษร'),
        child: Row(children: [
          SizedBox(
            width: 76,
            child: KeyedSubtree(
              key: const ValueKey('fc-font-size'),
              child: Dropdown<double>(
                value: const [10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0].contains(sample.fontSize)
                    ? sample.fontSize
                    : 13.0,
                items: const [10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0],
                labelOf: (v) => v.toStringAsFixed(0),
                onChanged: (v) => f.setNodesStyle(ids, (n) => n.fontSize = v),
              ),
            ),
          ),
          const SizedBox(width: 6),
          toggle('fc-bold', Icons.format_bold_rounded, tr('ตัวหนา'), sample.bold,
              () => f.setNodesStyle(ids, (n) => n.bold = !sample.bold)),
          toggle('fc-italic', Icons.format_italic_rounded, tr('ตัวเอียง'), sample.italic,
              () => f.setNodesStyle(ids, (n) => n.italic = !sample.italic)),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        toggle('fc-align-left', Icons.format_align_left_rounded, tr('ชิดซ้าย'), sample.align == FcAlign.left,
            () => f.setNodesStyle(ids, (n) => n.align = FcAlign.left)),
        toggle('fc-align-center', Icons.format_align_center_rounded, tr('กึ่งกลาง'), sample.align == FcAlign.center,
            () => f.setNodesStyle(ids, (n) => n.align = FcAlign.center)),
        toggle('fc-align-right', Icons.format_align_right_rounded, tr('ชิดขวา'), sample.align == FcAlign.right,
            () => f.setNodesStyle(ids, (n) => n.align = FcAlign.right)),
      ]),
      const SizedBox(height: 8),
      LabeledField(
        label: tr('เส้นขอบ'),
        child: KeyedSubtree(
          key: const ValueKey('fc-node-dash'),
          child: Dropdown<FcDash>(
            value: sample.dash,
            items: FcDash.values,
            labelOf: fcDashLabel,
            onChanged: (v) => f.setNodesStyle(ids, (n) => n.dash = v),
          ),
        ),
      ),
    ]);
  }
}

String fcDashLabel(FcDash d) => switch (d) {
      FcDash.solid => tr('เส้นทึบ'),
      FcDash.dashed => tr('เส้นประ'),
      FcDash.dotted => tr('เส้นจุด'),
    };

String fcArrowLabel(FcArrow a) => switch (a) {
      FcArrow.none => tr('ไม่มี'),
      FcArrow.arrow => tr('ลูกศรทึบ'),
      FcArrow.open => tr('ลูกศรโปร่ง'),
    };

class _NodeProps extends StatelessWidget {
  const _NodeProps({required this.node});
  final FcNode node;

  @override
  Widget build(BuildContext context) {
    final f = context.read<FlowchartController>();
    final d = f.diagram;
    final outs = [for (final e in d.edges) if (e.fromId == node.id) e];
    final ins = [for (final e in d.edges) if (e.toId == node.id) e];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(fcShapeIcon(node.shape), size: 18, color: Color(fcStrokeColor(node))),
        const SizedBox(width: 8),
        Expanded(child: Text(fcShapeLabel(node.shape), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        IconButton(
          key: const ValueKey('fc-delete'),
          tooltip: tr('ลบสัญลักษณ์'),
          icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
          onPressed: f.deleteSelection,
        ),
      ]),
      const SizedBox(height: 10),
      LabeledField(
        label: tr('รูปทรง'),
        child: KeyedSubtree(
          key: const ValueKey('fc-shape'),
          child: Dropdown<FcShape>(
            value: node.shape,
            items: kFcToolShapes,
            labelOf: fcShapeLabel,
            onChanged: (s) => f.setShape([node.id], s),
          ),
        ),
      ),
      const SizedBox(height: 12),
      CommitField(
        key: ValueKey('fc-text-${node.id}-${node.text}'),
        label: tr('ข้อความ'),
        value: node.text,
        minLines: 2,
        maxLines: 6,
        onCommit: (v) => f.setText(node.id, v),
      ),
      const SizedBox(height: 14),
      _StyleSection(ids: {node.id}, sample: node),
      const SizedBox(height: 14),
      Text(tr('เส้นออก {0} · เส้นเข้า {1}', [outs.length, ins.length]), style: TextStyle(fontSize: 12, color: C.muted)),
      for (final e in outs)
        InkWell(
          onTap: () => f.selectEdge(e.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '→ ${d.nodeById(e.toId) == null ? '?' : fcNodeTitle(d.nodeById(e.toId)!)}${e.label.isEmpty ? '' : '  ·  ${e.label}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
    ]);
  }
}

class _MultiProps extends StatelessWidget {
  const _MultiProps({required this.ids});
  final Set<String> ids;

  @override
  Widget build(BuildContext context) {
    final f = context.read<FlowchartController>();
    final sample = f.diagram.nodeById(ids.first) ?? FcNode(id: '', shape: FcShape.process);
    Widget btn(String key, IconData icon, String tip, VoidCallback tap) => IconButton(
          key: ValueKey(key),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 18, color: C.muted),
          onPressed: tap,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(tr('เลือก {0} สัญลักษณ์', [ids.length]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        IconButton(
          key: const ValueKey('fc-delete'),
          tooltip: tr('ลบสัญลักษณ์'),
          icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
          onPressed: f.deleteSelection,
        ),
      ]),
      const SizedBox(height: 8),
      LabeledField(
        label: tr('จัดแนว'),
        child: Wrap(children: [
          btn('fc-al-left', Icons.align_horizontal_left_rounded, tr('จัดชิดซ้าย'), () => f.align(FcAlignKind.left)),
          btn('fc-al-center', Icons.align_horizontal_center_rounded, tr('จัดกึ่งกลางแนวตั้ง'), () => f.align(FcAlignKind.centerH)),
          btn('fc-al-right', Icons.align_horizontal_right_rounded, tr('จัดชิดขวา'), () => f.align(FcAlignKind.right)),
          btn('fc-al-top', Icons.align_vertical_top_rounded, tr('จัดชิดบน'), () => f.align(FcAlignKind.top)),
          btn('fc-al-middle', Icons.align_vertical_center_rounded, tr('จัดกึ่งกลางแนวนอน'), () => f.align(FcAlignKind.middle)),
          btn('fc-al-bottom', Icons.align_vertical_bottom_rounded, tr('จัดชิดล่าง'), () => f.align(FcAlignKind.bottom)),
        ]),
      ),
      const SizedBox(height: 6),
      LabeledField(
        label: tr('กระจาย / ขนาด'),
        child: Wrap(children: [
          btn('fc-dist-h', Icons.horizontal_distribute_rounded, tr('กระจายแนวนอน (3 ชิ้นขึ้นไป)'),
              () => f.distribute(horizontal: true)),
          btn('fc-dist-v', Icons.vertical_distribute_rounded, tr('กระจายแนวตั้ง (3 ชิ้นขึ้นไป)'),
              () => f.distribute(horizontal: false)),
          btn('fc-same-size', Icons.photo_size_select_small_rounded, tr('ขนาดเท่ากับชิ้นแรกที่เลือก'), f.sameSize),
        ]),
      ),
      const SizedBox(height: 10),
      _StyleSection(ids: ids, sample: sample),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('fc-duplicate'),
        onPressed: f.duplicateSelection,
        icon: const Icon(Icons.file_copy_outlined, size: 16),
        label: Text(tr('ทำสำเนา')),
      ),
    ]);
  }
}

class _EdgeProps extends StatelessWidget {
  const _EdgeProps({required this.edge});
  final FcEdge edge;

  @override
  Widget build(BuildContext context) {
    final f = context.read<FlowchartController>();
    final a = FlowchartActions(context);
    final d = f.diagram;
    final from = d.nodeById(edge.fromId), to = d.nodeById(edge.toId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.arrow_right_alt_rounded, size: 20, color: C.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('เส้นเชื่อม'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        IconButton(
          key: const ValueKey('fc-delete'),
          tooltip: tr('ลบเส้นเชื่อม'),
          icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
          onPressed: f.deleteSelection,
        ),
      ]),
      const SizedBox(height: 6),
      Text('${from == null ? '?' : fcNodeTitle(from)}  →  ${to == null ? '?' : fcNodeTitle(to)}',
          style: TextStyle(fontSize: 12.5, color: C.muted)),
      const SizedBox(height: 12),
      CommitField(
        key: ValueKey('fc-label-${edge.id}-${edge.label}'),
        label: tr('ป้ายเส้น (เช่น ใช่ / ไม่ใช่)'),
        value: edge.label,
        onCommit: (v) => f.setEdgeLabel(edge.id, v.trim()),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: LabeledField(
            label: tr('หัวต้นเส้น'),
            child: KeyedSubtree(
              key: const ValueKey('fc-start-arrow'),
              child: Dropdown<FcArrow>(
                value: edge.startArrow,
                items: FcArrow.values,
                labelOf: fcArrowLabel,
                onChanged: (v) => f.updateEdge(edge.id, (e) => e.startArrow = v),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LabeledField(
            label: tr('หัวปลายเส้น'),
            child: KeyedSubtree(
              key: const ValueKey('fc-end-arrow'),
              child: Dropdown<FcArrow>(
                value: edge.endArrow,
                items: FcArrow.values,
                labelOf: fcArrowLabel,
                onChanged: (v) => f.updateEdge(edge.id, (e) => e.endArrow = v),
              ),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: LabeledField(
            label: tr('ลักษณะเส้น'),
            child: KeyedSubtree(
              key: const ValueKey('fc-edge-dash'),
              child: Dropdown<FcDash>(
                value: edge.dash,
                items: FcDash.values,
                labelOf: fcDashLabel,
                onChanged: (v) => f.updateEdge(edge.id, (e) => e.dash = v),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LabeledField(
            label: tr('ความหนา'),
            child: KeyedSubtree(
              key: const ValueKey('fc-edge-width'),
              child: Dropdown<double>(
                value: const [1.0, 1.8, 2.5, 3.5, 5.0].contains(edge.width) ? edge.width : 1.8,
                items: const [1.0, 1.8, 2.5, 3.5, 5.0],
                labelOf: (v) => '$v px',
                onChanged: (v) => f.updateEdge(edge.id, (e) => e.width = v),
              ),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      LabeledField(
        label: tr('สีเส้น'),
        child: _Swatches(
          keyPrefix: 'fc-edge-color',
          current: edge.color,
          onPick: (c) => f.updateEdge(edge.id, (e) => e.color = c),
          onCustom: () => a.pickEdgeColor(edge),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('fc-reverse'),
        onPressed: () => f.reverseEdge(edge.id),
        icon: const Icon(Icons.swap_horiz_rounded, size: 16),
        label: Text(tr('สลับทิศทาง')),
      ),
    ]);
  }
}

/// ภาพรวมของแผนภาพ + จัดวางอัตโนมัติ + ผลตรวจ (คลิกรายการเพื่อไปที่สัญลักษณ์/เส้น)
class _Overview extends StatelessWidget {
  const _Overview({required this.diagram});
  final FlowchartDiagram diagram;

  @override
  Widget build(BuildContext context) {
    final f = context.read<FlowchartController>();
    final issues = validateFlowchart(diagram);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Flowchart', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 4),
      Text(tr('{0} สัญลักษณ์ · {1} เส้นเชื่อม', [diagram.nodes.length, diagram.edges.length]),
          style: TextStyle(fontSize: 12.5, color: C.muted)),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        OutlinedButton.icon(
          key: const ValueKey('fc-layout-td'),
          onPressed: diagram.nodes.length < 2
              ? null
              : () {
                  if (f.autoLayout(kind: FcLayoutKind.topDown)) f.fit(f.viewport);
                },
          icon: const Icon(Icons.south_rounded, size: 16),
          label: Text(tr('จัดวางบนลงล่าง')),
        ),
        OutlinedButton.icon(
          key: const ValueKey('fc-layout-lr'),
          onPressed: diagram.nodes.length < 2
              ? null
              : () {
                  if (f.autoLayout(kind: FcLayoutKind.leftRight)) f.fit(f.viewport);
                },
          icon: const Icon(Icons.east_rounded, size: 16),
          label: Text(tr('จัดวางซ้ายไปขวา')),
        ),
      ]),
      const SizedBox(height: 14),
      Text.rich(TextSpan(children: [
        TextSpan(text: tr('ตรวจสอบแผนภาพ'), style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: ' (${issues.length})', style: TextStyle(color: C.muted)),
      ])),
      const SizedBox(height: 8),
      if (diagram.nodes.isEmpty)
        Text(tr('วางสัญลักษณ์แล้วต่อเส้น ระบบจะตรวจกฎของผังงานให้'), style: TextStyle(fontSize: 12.5, color: C.muted))
      else if (issues.isEmpty)
        Text(tr('✓ ไม่พบปัญหา'), key: const ValueKey('fc-no-issues'), style: TextStyle(fontSize: 12.5, color: C.primaryDark))
      else
        for (final i in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: IssueCard(
              key: ValueKey('fc-issue-${i.code}-${i.tableId ?? i.relationId}'),
              issue: i,
              onTap: () {
                if (i.tableId != null) {
                  f.selectNode(i.tableId!);
                  f.reveal(i.tableId!, f.viewport);
                } else if (i.relationId != null) {
                  f.selectEdge(i.relationId);
                }
              },
            ),
          ),
      if (issues.any((i) => i.severity == Severity.error)) const SizedBox(height: 2),
    ]);
  }
}
