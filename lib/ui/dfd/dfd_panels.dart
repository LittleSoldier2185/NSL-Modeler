import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/dfd_model.dart';
import '../../core/validate/dfd_validator.dart';
import '../../core/validate/issue.dart';
import '../../state/dfd_controller.dart';
import '../../state/project_controller.dart';
import '../../state/workspace_controller.dart';
import '../issue_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'dfd_actions.dart';
import 'dfd_painter.dart';

IconData dfdKindIcon(DfdKind k) => switch (k) {
  DfdKind.entity => Icons.crop_square_rounded,
  DfdKind.process => Icons.rounded_corner_rounded,
  DfdKind.store => Icons.storage_rounded,
};

String dfdKindName(DfdKind k) => switch (k) {
  DfdKind.entity => tr('ผู้ใช้ภายนอก'),
  DfdKind.process => tr('กระบวนการ'),
  DfdKind.store => tr('ที่เก็บข้อมูล'),
};

/// แผงซ้ายของแท็บ DFD: ค้นหา + รายการวัตถุและเส้นข้อมูล (คลิก = เลือกและเลื่อนไปที่นั่น)
class DfdLeftPanel extends StatefulWidget {
  const DfdLeftPanel({super.key});

  @override
  State<DfdLeftPanel> createState() => _DfdLeftPanelState();
}

class _DfdLeftPanelState extends State<DfdLeftPanel> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    final w = context.watch<WorkspaceController>();
    final dg = d.diagram;
    final q = _q.trim().toLowerCase();
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);

    String nodeName(String id) => dg.nodeById(id)?.title ?? '?';
    final nodes = [
      for (final n in dg.nodes)
        if (match(n.title)) n,
    ];
    final flows = [
      for (final f in dg.flows)
        if (match('${f.label} ${nodeName(f.fromId)} ${nodeName(f.toId)}')) f,
    ];

    Widget section(String title, int n) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            TextSpan(
              text: ' ($n)',
              style: TextStyle(color: C.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );

    // ListTile วาดพื้น/ริปเปิลบน Material ที่ใกล้สุด: ต้องมี Material ของตัวเองคั่นกลาง (ห้ามอยู่ใต้ DecoratedBox ที่มีสีพื้น)
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: C.border)),
      ),
      child: Material(
        color: C.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: Text(
                w.activeDocument.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: SizedBox(
                height: kFieldHeight,
                child: TextField(
                  key: const ValueKey('dfd-search'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('ค้นหาวัตถุ / เส้นข้อมูล'),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            ),
            for (final k in DfdKind.values) ...[
              section(dfdKindName(k), nodes.where((n) => n.kind == k).length),
              for (final n in nodes.where((n) => n.kind == k))
                ListTile(
                  key: ValueKey('dfd-item-${n.id}'),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  selected: d.selectedNodeIds.contains(n.id),
                  leading: Icon(
                    dfdKindIcon(k),
                    size: 16,
                    color: Color(dfdNodeColor(n)),
                  ),
                  title: Text(
                    n.title.isEmpty ? tr('(ไม่มีชื่อ)') : n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () {
                    d.selectNode(n.id);
                    d.reveal(n.id, d.viewport);
                  },
                ),
            ],
            section(tr('เส้นข้อมูล'), flows.length),
            for (final f in flows)
              ListTile(
                key: ValueKey('dfd-flow-${f.id}'),
                dense: true,
                visualDensity: VisualDensity.compact,
                selected: d.selectedFlowId == f.id,
                leading: Icon(
                  f.bidirectional
                      ? Icons.sync_alt_rounded
                      : Icons.arrow_right_alt_rounded,
                  size: 16,
                  color: C.muted,
                ),
                title: Text(
                  f.label.isEmpty ? tr('(ไม่มีชื่อ)') : f.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${nodeName(f.fromId)} → ${nodeName(f.toId)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: C.muted),
                ),
                onTap: () => d.selectFlow(f.id),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// แผงขวาของแท็บ DFD: คุณสมบัติของวัตถุ/เส้นที่เลือก หรือสรุปปัญหาของแผนภาพเมื่อไม่ได้เลือกอะไร
class DfdRightPanel extends StatelessWidget {
  const DfdRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    context.watch<ProjectController>();
    final node = d.selectedNode;
    final flow = d.selectedFlow;
    final boundary = d.selectedBoundary;
    final Widget body;
    if (boundary != null) {
      body = _BoundaryProps(boundary: boundary);
    } else if (node != null) {
      body = _NodeProps(node: node);
    } else if (flow != null) {
      body = _FlowProps(flow: flow);
    } else if (d.selectedNodeIds.length > 1) {
      body = _MultiProps(ids: d.selectedNodeIds);
    } else {
      body = _Issues(diagram: d.diagram);
    }
    // Material คั่นกลาง: CheckboxListTile/ListTile วาดพื้นบน Material ใกล้สุด (ห้ามอยู่ใต้ DecoratedBox ที่มีสีพื้น)
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: C.border))),
      child: Material(
        color: C.surface,
        child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.current,
    required this.defaultColor,
    required this.onPick,
    required this.onCustom,
  });
  final int? current;
  final int defaultColor;
  final ValueChanged<int?> onPick;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    Widget sw(Key k, String tip, bool on, VoidCallback tap, Widget child) =>
        Tooltip(
          message: tip,
          child: InkResponse(
            key: k,
            onTap: tap,
            radius: 18,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: on ? C.text : C.border,
                  width: on ? 2 : 1,
                ),
              ),
              child: child,
            ),
          ),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        sw(
          const ValueKey('dfd-color-default'),
          tr('ใช้สีตามชนิด'),
          current == null,
          () => onPick(null),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(defaultColor).withValues(alpha: 0.35),
            ),
          ),
        ),
        for (var i = 0; i < kDfdPalette.length; i++)
          sw(
            ValueKey('dfd-color-$i'),
            '#${(kDfdPalette[i] & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}',
            current == kDfdPalette[i],
            () => onPick(kDfdPalette[i]),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(kDfdPalette[i]),
              ),
            ),
          ),
        sw(
          const ValueKey('dfd-color-custom'),
          tr('กำหนดสีเอง…'),
          current != null && !kDfdPalette.contains(current),
          onCustom,
          current != null && !kDfdPalette.contains(current)
              ? Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(current!),
                  ),
                )
              : Icon(Icons.colorize_rounded, size: 15, color: C.muted),
        ),
      ],
    );
  }
}

class _NodeProps extends StatelessWidget {
  const _NodeProps({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final a = DfdActions(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              dfdKindIcon(node.kind),
              size: 18,
              color: Color(dfdNodeColor(node)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                dfdKindName(node.kind),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('dfd-delete'),
              tooltip: tr('ลบวัตถุ'),
              icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
              onPressed: d.deleteSelection,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (node.kind != DfdKind.entity) ...[
          CommitField(
            key: ValueKey('dfd-number-${node.id}-${node.number}'),
            label: node.kind == DfdKind.process
                ? tr('เลขลำดับ (เช่น 1.0)')
                : tr('รหัส (เช่น D1)'),
            value: node.number,
            mono: true,
            onCommit: (v) => d.setNodeNumber(node.id, v),
          ),
          const SizedBox(height: 12),
        ],
        CommitField(
          key: ValueKey('dfd-name-${node.id}-${node.name}'),
          label: tr('ชื่อ'),
          value: node.name,
          onCommit: (v) => d.renameNode(node.id, v.trim()),
        ),
        if (node.kind == DfdKind.store) ...[
          const SizedBox(height: 14),
          _StoreTable(node: node),
        ],
        if (node.kind == DfdKind.process) ...[
          const SizedBox(height: 14),
          _ProcessChild(node: node),
        ],
        const SizedBox(height: 14),
        LabeledField(
          label: tr('สี'),
          child: _ColorRow(
            current: node.color,
            defaultColor: kDfdKindColors[node.kind]!,
            onPick: (c) => d.setNodesColor([node.id], c),
            onCustom: () => a.pickNodesColor([
              node.id,
            ], current: node.color ?? kDfdKindColors[node.kind]),
          ),
        ),
        const SizedBox(height: 14),
        _Connections(node: node),
      ],
    );
  }
}

/// แตกรายละเอียดกระบวนการเป็นแผนภาพย่อย (Level 0 → Level 1) : เลือกแท็บ DFD ที่มีอยู่ หรือสร้างใหม่ให้พร้อมเส้นข้อมูลเดียวกับแม่
class _ProcessChild extends StatelessWidget {
  const _ProcessChild({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final w = context.watch<WorkspaceController>();
    final cands = d.childCandidates(w.activeId);
    final cid = node.childId;
    final linked = cid == null ? null : w.documentById(cid);
    const none = '';
    final ids = [none, ...cands.map((t) => t.id)];
    final value = linked != null && ids.contains(linked.id) ? linked.id : none;
    return LabeledField(
      label: tr('แผนภาพย่อย (Level ถัดไป)'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KeyedSubtree(
          key: const ValueKey('dfd-child'),
          child: Dropdown<String>(
            value: value,
            items: ids,
            labelOf: (id) => id == none ? tr('— ไม่มี —') : w.documentById(id)!.name,
            onChanged: (id) => d.setProcessChild(node.id, id == none ? null : id),
          ),
        ),
        if (cid != null && linked == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('แผนภาพย่อยที่ชี้ไว้ไม่มีแล้ว'), style: TextStyle(fontSize: 12, color: C.danger)),
          ),
        Wrap(spacing: 4, children: [
          if (linked != null)
            TextButton.icon(
              key: const ValueKey('dfd-child-open'),
              onPressed: () => d.openChild(node.id),
              icon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 16),
              label: Text(tr('เปิดแผนภาพย่อย')),
            ),
          if (cid == null)
            TextButton.icon(
              key: const ValueKey('dfd-child-create'),
              onPressed: () => d.createChildFor(node.id),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(tr('สร้างแผนภาพย่อยใหม่')),
            ),
        ]),
      ]),
    );
  }
}

/// ขอบเขตระบบที่เลือก : ชื่อ สี ลบ
class _BoundaryProps extends StatelessWidget {
  const _BoundaryProps({required this.boundary});
  final DfdBoundary boundary;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final a = DfdActions(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.crop_free_rounded, size: 18, color: C.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('ขอบเขตระบบ'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          IconButton(
            key: const ValueKey('dfd-delete'),
            tooltip: tr('ลบขอบเขต (ไม่ลบวัตถุข้างใน)'),
            icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
            onPressed: d.deleteSelection,
          ),
        ]),
        const SizedBox(height: 12),
        CommitField(
          key: ValueKey('dfd-boundary-name-${boundary.id}-${boundary.name}'),
          label: tr('ชื่อ'),
          value: boundary.name,
          onCommit: (v) => d.renameBoundary(boundary.id, v.trim()),
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: tr('สี'),
          child: _ColorRow(
            current: boundary.color,
            defaultColor: C.muted.toARGB32(),
            onPick: (c) => d.setBoundaryColor(boundary.id, c),
            onCustom: () => a.pickBoundaryColor(boundary),
          ),
        ),
        const SizedBox(height: 10),
        Text(tr('ลากเส้นประเพื่อย้าย (วัตถุข้างในเลื่อนตาม) · ลากจุดจับเพื่อปรับขนาด'),
            style: TextStyle(fontSize: 12, color: C.muted)),
      ],
    );
  }
}

/// ผูกที่เก็บข้อมูลกับตารางใน ER (ตัวเลือก = ตารางทุกใบของโปรเจกต์)
class _StoreTable extends StatelessWidget {
  const _StoreTable({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final pc = context.watch<ProjectController>();
    final tables = pc.project.tables;
    final linked = node.tableId == null ? null : pc.project.tableById(node.tableId!);
    const none = '';
    final ids = [none, ...tables.map((t) => t.id)];
    final value = linked == null ? none : linked.id;
    return LabeledField(
      label: tr('ตารางใน ER'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KeyedSubtree(
          key: const ValueKey('dfd-store-table'),
          child: Dropdown<String>(
            value: value,
            items: ids,
            labelOf: (id) => id == none ? tr('— ไม่ผูก —') : pc.project.tableById(id)!.name,
            onChanged: (id) => d.setStoreTable(node.id, id == none ? null : id),
          ),
        ),
        if (node.tableId != null && linked == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('ตารางที่ผูกไว้ถูกลบไปแล้ว'), style: TextStyle(fontSize: 12, color: C.danger)),
          ),
        if (linked != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('dfd-store-goto'),
              onPressed: () => d.gotoLinkedTable(node.id),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text(tr('ไปที่ตารางใน ER')),
            ),
          ),
      ]),
    );
  }
}

/// เส้นข้อมูลเข้า/ออกของวัตถุที่เลือก (คลิกเพื่อไปเลือกเส้น)
class _Connections extends StatelessWidget {
  const _Connections({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final dg = d.diagram;
    final ins = [
      for (final f in dg.flows)
        if (f.toId == node.id || (f.bidirectional && f.fromId == node.id)) f,
    ];
    final outs = [
      for (final f in dg.flows)
        if (f.fromId == node.id || (f.bidirectional && f.toId == node.id)) f,
    ];
    Widget list(String title, List<DfdFlow> fs, bool incoming) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '$title (${fs.length})',
            style: TextStyle(
              fontSize: 12,
              color: C.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        for (final f in fs)
          InkWell(
            onTap: () => d.selectFlow(f.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${f.label.isEmpty ? tr('(ไม่มีชื่อ)') : f.label}  ·  ${dg.nodeById(incoming ? (f.toId == node.id ? f.fromId : f.toId) : (f.fromId == node.id ? f.toId : f.fromId))?.title ?? '?'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        list(tr('ข้อมูลเข้า'), ins, true),
        list(tr('ข้อมูลออก'), outs, false),
      ],
    );
  }
}

class _FlowProps extends StatelessWidget {
  const _FlowProps({required this.flow});
  final DfdFlow flow;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final a = DfdActions(context);
    final dg = d.diagram;
    final from = dg.nodeById(flow.fromId), to = dg.nodeById(flow.toId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.arrow_right_alt_rounded, size: 20, color: C.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('เส้นข้อมูล'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('dfd-delete'),
              tooltip: tr('ลบเส้นข้อมูล'),
              icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
              onPressed: d.deleteSelection,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${from?.title ?? '?'}  →  ${to?.title ?? '?'}',
          style: TextStyle(fontSize: 12.5, color: C.muted),
        ),
        const SizedBox(height: 12),
        CommitField(
          key: ValueKey('dfd-label-${flow.id}-${flow.label}'),
          label: tr('ชื่อข้อมูลที่ไหล'),
          value: flow.label,
          onCommit: (v) => d.setFlowLabel(flow.id, v.trim()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('dfd-reverse'),
                onPressed: () => d.reverseFlow(flow.id),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: Text(tr('สลับทิศทาง')),
              ),
            ),
          ],
        ),
        CheckboxListTile(
          key: const ValueKey('dfd-both'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: flow.bidirectional,
          onChanged: (v) => d.setFlowBidirectional(flow.id, v ?? false),
          title: Text(
            tr('ข้อมูลไหลสองทาง'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 6),
        LabeledField(
          label: tr('สีเส้น'),
          child: _ColorRow(
            current: flow.color,
            defaultColor: C.primary.toARGB32(),
            onPick: (c) => d.setFlowColor(flow.id, c),
            onCustom: () => a.pickFlowColor(flow),
          ),
        ),
      ],
    );
  }
}

class _MultiProps extends StatelessWidget {
  const _MultiProps({required this.ids});
  final Set<String> ids;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final a = DfdActions(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('เลือก {0} วัตถุ', [ids.length]),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('dfd-delete'),
              tooltip: tr('ลบวัตถุ'),
              icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
              onPressed: d.deleteSelection,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: tr('สี'),
          child: _ColorRow(
            current: null,
            defaultColor: kDfdKindColors[DfdKind.process]!,
            onPick: (c) => d.setNodesColor(ids, c),
            onCustom: () => a.pickNodesColor(ids),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('dfd-duplicate'),
          onPressed: d.duplicateSelection,
          icon: const Icon(Icons.file_copy_outlined, size: 16),
          label: Text(tr('ทำสำเนา')),
        ),
      ],
    );
  }
}

/// สรุปปัญหาของแผนภาพ (กฎของ DFD) — คลิกรายการเพื่อไปเลือกวัตถุ/เส้นที่เกี่ยวข้อง
class _Issues extends StatelessWidget {
  const _Issues({required this.diagram});
  final DfdDiagram diagram;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final w = context.read<WorkspaceController>();
    final issues = validateDfd(diagram, workspace: w.workspace, diagramId: w.activeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('แผนภาพ DFD'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          tr('{0} วัตถุ · {1} เส้นข้อมูล', [
            diagram.nodes.length,
            diagram.flows.length,
          ]),
          style: TextStyle(fontSize: 12.5, color: C.muted),
        ),
        for (final (tab, proc) in d.parentsOf(w.activeId))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              key: ValueKey('dfd-parent-${proc.id}'),
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                w.openDocument(tab.id);
                d.selectNode(proc.id);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(Icons.subdirectory_arrow_left_rounded, size: 16, color: C.primaryDark),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(tr('รายละเอียดของ {0} ใน {1}', [proc.title, tab.name]),
                        style: TextStyle(fontSize: 12.5, color: C.primaryDark), overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: tr('ตรวจสอบแผนภาพ'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: ' (${issues.length})',
                style: TextStyle(color: C.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (diagram.nodes.isEmpty)
          Text(
            tr('วางวัตถุแล้วต่อเส้นข้อมูล ระบบจะตรวจกฎของ DFD ให้'),
            style: TextStyle(fontSize: 12.5, color: C.muted),
          )
        else if (issues.isEmpty)
          Text(
            tr('✓ ไม่พบปัญหา'),
            key: const ValueKey('dfd-no-issues'),
            style: TextStyle(fontSize: 12.5, color: C.primaryDark),
          )
        else
          for (final i in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: IssueCard(
                key: ValueKey(
                  'dfd-issue-${i.code}-${i.tableId ?? i.relationId}',
                ),
                issue: i,
                onTap: () {
                  if (i.tableId != null) {
                    d.selectNode(i.tableId!);
                    d.reveal(i.tableId!, d.viewport);
                  } else if (i.relationId != null) {
                    d.selectFlow(i.relationId);
                  }
                },
              ),
            ),
        if (issues.any((i) => i.severity == Severity.error))
          const SizedBox(height: 2),
      ],
    );
  }
}
