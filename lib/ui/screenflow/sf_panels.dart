import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/box_ops.dart';
import '../../core/layout/screenflow_geometry.dart' show sfNodeColor;
import '../../core/models/screenflow_model.dart';
import '../../core/models/workspace.dart';
import '../../core/validate/screenflow_validator.dart';
import '../../state/screenflow_controller.dart';
import '../../state/workspace_controller.dart';
import '../canvas/canvas_chrome.dart';
import '../color_picker_dialog.dart';
import '../issue_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import '../wireframe/wf_painter.dart' show kWfPalette;
import '../wireframe/wf_panels.dart' show WireframeThumbnail;
import 'sf_actions.dart';
import 'sf_view.dart';

/// แผงซ้ายของแท็บ Screen Flow: ชนิดโหนด (คลิก = เครื่องมือ / ลากไปวาง) + รายการหน้าจอและการเปลี่ยนหน้า
class ScreenFlowLeftPanel extends StatefulWidget {
  const ScreenFlowLeftPanel({super.key});

  @override
  State<ScreenFlowLeftPanel> createState() => _ScreenFlowLeftPanelState();
}

class _ScreenFlowLeftPanelState extends State<ScreenFlowLeftPanel> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final f = context.watch<ScreenFlowController>();
    final w = context.watch<WorkspaceController>();
    final d = f.diagram;
    final q = _q.trim().toLowerCase();
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);
    String name(String id) => d.nodeById(id) == null ? '?' : sfNodeTitle(d.nodeById(id)!);
    final nodes = [for (final n in d.nodes) if (match('${n.title} ${sfKindLabel(n.kind)}')) n];
    final edges = [for (final e in d.edges) if (match('${e.label} ${e.condition} ${name(e.fromId)} ${name(e.toId)}')) e];

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
                key: const ValueKey('sf-search'),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('ค้นหาหน้าจอ / การเปลี่ยนหน้า'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ),
          section(tr('ชนิดโหนด'), SfKind.values.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
            child: Wrap(spacing: 6, runSpacing: 6, children: [for (final k in SfKind.values) _KindTile(kind: k)]),
          ),
          section(tr('หน้าจอ'), nodes.length),
          for (final n in nodes)
            ListTile(
              key: ValueKey('sf-item-${n.id}'),
              dense: true,
              visualDensity: VisualDensity.compact,
              selected: f.selectedIds.contains(n.id),
              leading: Icon(sfKindIcon(n.kind), size: 16, color: Color(sfNodeColor(n))),
              title: Text(sfNodeTitle(n), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              trailing: n.wireframeId == null ? null : Icon(Icons.web_outlined, size: 14, color: C.muted),
              onTap: () {
                f.selectBox(n.id);
                f.reveal(n.id, f.viewport);
              },
            ),
          section(tr('การเปลี่ยนหน้า'), edges.length),
          for (final e in edges)
            ListTile(
              key: ValueKey('sf-edge-${e.id}'),
              dense: true,
              visualDensity: VisualDensity.compact,
              selected: f.selectedEdgeId == e.id,
              leading: Icon(Icons.arrow_right_alt_rounded, size: 16, color: C.muted),
              title: Text(e.caption.isEmpty ? tr('(ไม่มีป้าย)') : e.caption,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              subtitle: Text('${name(e.fromId)} → ${name(e.toId)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: C.muted)),
              onTap: () => f.selectEdge(e.id),
            ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind});
  final SfKind kind;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<ScreenFlowController>();
    final on = f.tool == SfTool.node && f.toolKind == kind;
    final color = Color(sfNodeColor(SfNode(id: '', kind: kind)));
    final tile = Container(
      width: 108,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: on ? C.primaryTint : C.bg,
        border: Border.all(color: on ? C.primary : C.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Icon(sfKindIcon(kind), size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(sfKindLabel(kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
      ]),
    );
    return Tooltip(
      message: '${sfKindLabel(kind)} (${sfKindShortcut(kind)})',
      child: Draggable<Object>(
        data: kind,
        feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.8, child: tile)),
        child: InkWell(key: ValueKey('sf-kind-${kind.name}'), borderRadius: BorderRadius.circular(6), onTap: () => f.setNodeTool(kind), child: tile),
      ),
    );
  }
}

/// แผงขวาของแท็บ Screen Flow
class ScreenFlowRightPanel extends StatelessWidget {
  const ScreenFlowRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.watch<ScreenFlowController>();
    context.watch<WorkspaceController>();
    final node = f.selectedNode;
    final edge = f.selectedEdge;
    final Widget body;
    if (node != null) {
      body = _NodeProps(node: node);
    } else if (edge != null) {
      body = _EdgeProps(edge: edge);
    } else if (f.selectedIds.length > 1) {
      body = _MultiProps(ids: f.selectedIds);
    } else {
      body = const _Overview();
    }
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: C.border))),
      child: Material(color: C.surface, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body)),
    );
  }
}

class _NodeProps extends StatelessWidget {
  const _NodeProps({required this.node});
  final SfNode node;

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    final w = context.read<WorkspaceController>();
    final a = ScreenFlowActions(context);
    final d = f.diagram;
    final wfDocs = w.workspace.documentsOf(DocType.wireframe).toList();
    final linked = f.linkedWireframe(node);
    const none = '';
    final current = node.wireframeId;
    final broken = current != null && linked == null;
    final outs = [for (final e in d.edges) if (e.fromId == node.id) e];
    final ins = [for (final e in d.edges) if (e.toId == node.id) e];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(sfKindIcon(node.kind), size: 18, color: Color(sfNodeColor(node))),
        const SizedBox(width: 8),
        Expanded(child: Text(sfKindLabel(node.kind), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        IconButton(
          key: const ValueKey('sf-delete'),
          tooltip: tr('ลบหน้าจอ'),
          icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
          onPressed: f.deleteSelection,
        ),
      ]),
      const SizedBox(height: 10),
      LabeledField(
        label: tr('ชนิด'),
        child: KeyedSubtree(
          key: const ValueKey('sf-kind'),
          child: Dropdown<SfKind>(
            value: node.kind,
            items: SfKind.values,
            labelOf: sfKindLabel,
            onChanged: (k) => f.updateNodes([node.id], (n) => n.kind = k),
          ),
        ),
      ),
      const SizedBox(height: 12),
      CommitField(
        key: ValueKey('sf-title-${node.id}-${node.title}'),
        label: tr('ชื่อ'),
        value: node.title,
        onCommit: (v) => f.setTitle(node.id, v.trim()),
      ),
      if (node.kind == SfKind.screen) ...[
        const SizedBox(height: 12),
        LabeledField(
          label: tr('Wireframe ของหน้าจอนี้'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KeyedSubtree(
              key: const ValueKey('sf-wireframe'),
              child: Dropdown<String>(
                value: broken ? none : (current ?? none),
                items: [none, for (final x in wfDocs) x.id],
                labelOf: (id) => id == none ? tr('— ไม่ผูก —') : (w.documentById(id)?.name ?? id),
                onChanged: (v) => f.linkWireframe(node.id, v == none ? null : v),
              ),
            ),
            if (broken)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Wireframe ที่ผูกไว้ถูกลบไปแล้ว'), style: TextStyle(fontSize: 12, color: C.danger)),
              ),
            if (linked != null) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.all(4),
                child: WireframeThumbnail(diagram: linked, height: 110),
              ),
            ],
            const SizedBox(height: 4),
            Wrap(spacing: 4, children: [
              if (linked != null)
                TextButton.icon(
                  key: const ValueKey('sf-open-wireframe'),
                  onPressed: () => a.openWireframe(node.id),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text(tr('เปิด Wireframe')),
                )
              else
                TextButton.icon(
                  key: const ValueKey('sf-create-wireframe'),
                  onPressed: () => f.createWireframeFor(node.id),
                  icon: const Icon(Icons.add_box_outlined, size: 15),
                  label: Text(tr('สร้าง Wireframe สำหรับหน้าจอนี้')),
                ),
            ]),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      LabeledField(
        label: tr('สีเส้นขอบ'),
        child: ColorSwatchRow(
          keyPrefix: 'sf-color',
          palette: kWfPalette.take(8).toList(),
          current: node.color,
          onPick: (v) => f.updateNodes([node.id], (n) => n.color = v),
          onCustom: () async {
            final r = await showColorPickerDialog(context, title: tr('สีเส้นขอบ (กำหนดเอง)'), initial: node.color, presets: kWfPalette);
            if (r != null) f.updateNodes([node.id], (n) => n.color = r.argb);
          },
        ),
      ),
      const SizedBox(height: 14),
      Text(tr('ไปต่อ {0} · มาจาก {1}', [outs.length, ins.length]), style: TextStyle(fontSize: 12, color: C.muted)),
      for (final e in outs)
        InkWell(
          onTap: () => f.selectEdge(e.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '→ ${d.nodeById(e.toId) == null ? '?' : sfNodeTitle(d.nodeById(e.toId)!)}${e.caption.isEmpty ? '' : '  ·  ${e.caption}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
    ]);
  }
}

class _EdgeProps extends StatelessWidget {
  const _EdgeProps({required this.edge});
  final SfEdge edge;

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    final d = f.diagram;
    final from = d.nodeById(edge.fromId), to = d.nodeById(edge.toId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.arrow_right_alt_rounded, size: 20, color: C.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('การเปลี่ยนหน้า'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        IconButton(
          key: const ValueKey('sf-delete'),
          tooltip: tr('ลบเส้นการเปลี่ยนหน้า'),
          icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
          onPressed: f.deleteSelection,
        ),
      ]),
      const SizedBox(height: 6),
      Text('${from == null ? '?' : sfNodeTitle(from)}  →  ${to == null ? '?' : sfNodeTitle(to)}', style: TextStyle(fontSize: 12.5, color: C.muted)),
      const SizedBox(height: 12),
      CommitField(
        key: ValueKey('sf-label-${edge.id}-${edge.label}'),
        label: tr('เมื่อ (trigger) เช่น กด Login'),
        value: edge.label,
        onCommit: (v) => f.updateEdge(edge.id, (e) => e.label = v.trim()),
      ),
      const SizedBox(height: 12),
      CommitField(
        key: ValueKey('sf-condition-${edge.id}-${edge.condition}'),
        label: tr('เงื่อนไข (ไม่บังคับ)'),
        value: edge.condition,
        onCommit: (v) => f.updateEdge(edge.id, (e) => e.condition = v.trim()),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('sf-reverse'),
        onPressed: () => f.reverseEdge(edge.id),
        icon: const Icon(Icons.swap_horiz_rounded, size: 16),
        label: Text(tr('สลับทิศทาง')),
      ),
    ]);
  }
}

class _MultiProps extends StatelessWidget {
  const _MultiProps({required this.ids});
  final Set<String> ids;

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    Widget btn(String key, IconData icon, String tip, VoidCallback tap) =>
        IconButton(key: ValueKey(key), tooltip: tip, visualDensity: VisualDensity.compact, icon: Icon(icon, size: 18, color: C.muted), onPressed: tap);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(tr('เลือก {0} หน้าจอ', [ids.length]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        IconButton(
          key: const ValueKey('sf-delete'),
          tooltip: tr('ลบหน้าจอ'),
          icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
          onPressed: f.deleteSelection,
        ),
      ]),
      const SizedBox(height: 8),
      LabeledField(
        label: tr('จัดแนว'),
        child: Wrap(children: [
          btn('sf-al-left', Icons.align_horizontal_left_rounded, tr('จัดชิดซ้าย'), () => f.align(BoxAlign.left)),
          btn('sf-al-center', Icons.align_horizontal_center_rounded, tr('จัดกึ่งกลางแนวตั้ง'), () => f.align(BoxAlign.centerH)),
          btn('sf-al-top', Icons.align_vertical_top_rounded, tr('จัดชิดบน'), () => f.align(BoxAlign.top)),
          btn('sf-al-middle', Icons.align_vertical_center_rounded, tr('จัดกึ่งกลางแนวนอน'), () => f.align(BoxAlign.middle)),
        ]),
      ),
      const SizedBox(height: 6),
      LabeledField(
        label: tr('กระจาย / ขนาด'),
        child: Wrap(children: [
          btn('sf-dist-h', Icons.horizontal_distribute_rounded, tr('กระจายแนวนอน (3 ชิ้นขึ้นไป)'), () => f.distribute(horizontal: true)),
          btn('sf-dist-v', Icons.vertical_distribute_rounded, tr('กระจายแนวตั้ง (3 ชิ้นขึ้นไป)'), () => f.distribute(horizontal: false)),
          btn('sf-same-size', Icons.photo_size_select_small_rounded, tr('ขนาดเท่ากับชิ้นแรกที่เลือก'), f.sameSize),
        ]),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('sf-duplicate'),
        onPressed: f.duplicateSelection,
        icon: const Icon(Icons.file_copy_outlined, size: 16),
        label: Text(tr('ทำสำเนา')),
      ),
    ]);
  }
}

class _Overview extends StatelessWidget {
  const _Overview();

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    final w = context.read<WorkspaceController>();
    final d = f.diagram;
    final issues = validateScreenFlow(d, workspace: w.workspace);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Screen Flow', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 4),
      Text(tr('{0} หน้าจอ · {1} การเปลี่ยนหน้า', [d.nodes.length, d.edges.length]), style: TextStyle(fontSize: 12.5, color: C.muted)),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const ValueKey('sf-layout'),
        onPressed: d.nodes.length < 2
            ? null
            : () {
                if (f.autoLayout()) f.fit(f.viewport);
              },
        icon: const Icon(Icons.east_rounded, size: 16),
        label: Text(tr('จัดวางซ้ายไปขวา')),
      ),
      const SizedBox(height: 14),
      Text.rich(TextSpan(children: [
        TextSpan(text: tr('ตรวจสอบแผนผัง'), style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: ' (${issues.length})', style: TextStyle(color: C.muted)),
      ])),
      const SizedBox(height: 8),
      if (d.nodes.isEmpty)
        Text(tr('วางจุดเริ่มและหน้าจอแล้วลากเส้นการเปลี่ยนหน้า ระบบจะตรวจให้'), style: TextStyle(fontSize: 12.5, color: C.muted))
      else if (issues.isEmpty)
        Text(tr('✓ ไม่พบปัญหา'), key: const ValueKey('sf-no-issues'), style: TextStyle(fontSize: 12.5, color: C.primaryDark))
      else
        for (final i in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: IssueCard(
              key: ValueKey('sf-issue-${i.code}-${i.tableId ?? i.relationId}'),
              issue: i,
              onTap: () {
                if (i.tableId != null) {
                  f.selectBox(i.tableId!);
                  f.reveal(i.tableId!, f.viewport);
                } else if (i.relationId != null) {
                  f.selectEdge(i.relationId);
                }
              },
            ),
          ),
    ]);
  }
}
