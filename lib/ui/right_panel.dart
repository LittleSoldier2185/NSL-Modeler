import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/column_model.dart';
import '../core/models/enums.dart';
import '../core/models/relation_model.dart';
import '../core/models/table_model.dart';
import '../state/project_controller.dart';
import 'issue_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

class RightPanel extends StatelessWidget {
  const RightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final t = c.selectedTable;

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(left: BorderSide(color: C.border)),
      ),
      child: t == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'เลือกตารางทางซ้ายเพื่อแก้ไข',
                  style: TextStyle(color: C.muted),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _TableEditor(key: ValueKey(t.id), table: t),
    );
  }
}

class _TableEditor extends StatelessWidget {
  const _TableEditor({super.key, required this.table});
  final TableModel table;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    context.watch<ProjectController>();
    final col = c.selectedColumn;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (c.selectionCount > 1)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: C.primaryTint, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(
                child: Text('เลือกอยู่ ${c.selectionCount} ตาราง · แก้ไขทีละตาราง (กำลังแสดงตารางล่าสุดที่เลือก)',
                    style: const TextStyle(fontSize: 12, color: C.primaryDark)),
              ),
              TextButton(
                onPressed: c.duplicateSelected,
                child: const Text('ทำสำเนา'),
              ),
              TextButton(
                onPressed: c.removeSelectedTables,
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFB42318)),
                child: const Text('ลบ'),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('คุณสมบัติของตาราง', style: TextStyle(fontSize: 12, color: C.muted)),
                const SizedBox(height: 2),
                Text(
                  table.name,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'ทำสำเนาตาราง',
              onPressed: () => c.duplicateTable(table.id),
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'ลบตาราง',
              onPressed: () => _confirmDelete(context, c),
              icon: const Icon(Icons.delete_outline, size: 19, color: Color(0xFFB42318)),
            ),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            CommitField(
              key: ValueKey('tn-${table.id}-${table.name}'),
              label: 'ชื่อตาราง',
              value: table.name,
              mono: true,
              onCommit: (v) => c.renameTable(table.id, v.trim().isEmpty ? table.name : v.trim()),
            ),
            const SizedBox(height: 12),
            CommitField(
              key: ValueKey('tc-${table.id}-${table.comment}'),
              label: 'หมายเหตุ (COMMENT)',
              value: table.comment,
              onCommit: (v) => c.setTableComment(table.id, v),
            ),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'คอลัมน์', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: ' (${table.columns.length})',
                      style: const TextStyle(color: C.muted)),
                ]),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            SmallButton(label: '+ เพิ่มคอลัมน์', onTap: () => c.addColumn(table.id)),
          ]),
        ),
        _ColumnList(table: table),
        if (col != null) ...[
          const Divider(height: 1),
          _ColumnEditor(key: ValueKey(col.id), table: table, column: col),
        ],
        _TableIssues(table: table),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, ProjectController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ลบตาราง ${table.name}?'),
        content: const Text('ความสัมพันธ์ FK ที่เกี่ยวข้องจะถูกลบด้วย (ย้อนกลับได้ด้วย Ctrl+Z)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok == true) c.removeTable(table.id);
  }
}

class _ColumnList extends StatelessWidget {
  const _ColumnList({required this.table});
  final TableModel table;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final fkCols = {
      for (final r in c.project.relations)
        if (r.fromTableId == table.id) r.fromColumnId
    };

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      itemCount: table.columns.length,
      onReorderItem: (a, b) => c.reorderColumn(table.id, a, b),
      itemBuilder: (_, i) {
        final col = table.columns[i];
        final sel = col.id == c.selectedColumnId;
        return Padding(
          key: ValueKey(col.id),
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Material(
            color: sel ? C.primaryTint : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => c.selectColumn(col.id),
              child: SizedBox(
                height: 34,
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator, size: 16, color: C.muted),
                    ),
                  ),
                  Flexible(
                    child: Text(col.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 6),
                  if (col.isPrimaryKey) const Chip2('PK', C.pkBg, C.pkText),
                  if (fkCols.contains(col.id)) const Chip2('FK', Color(0xFFD9F0EC), C.primaryDark),
                  if (col.notNull) const Padding(
                    padding: EdgeInsets.only(left: 3),
                    child: Chip2('NN', C.nnBg, C.nnText),
                  ),
                  if (col.autoIncrement) const Padding(
                    padding: EdgeInsets.only(left: 3),
                    child: Chip2('AI', C.infoBg, C.infoText),
                  ),
                  const Spacer(),
                  Text(typeLabel(col),
                      style: monoStyle.copyWith(fontSize: 11.5, color: C.muted)),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ColumnEditor extends StatelessWidget {
  const _ColumnEditor({super.key, required this.table, required this.column});
  final TableModel table;
  final ColumnModel column;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    void edit(void Function(ColumnModel) f) => c.updateColumn(table.id, column.id, f);

    final hasLen = column.type == DataType.varchar || column.type == DataType.decimal;
    final canAi = column.type == DataType.integer ||
        column.type == DataType.bigint ||
        column.type == DataType.smallint;
    RelationModel? rel;
    for (final r in c.project.relations) {
      if (r.fromTableId == table.id && r.fromColumnId == column.id) rel = r;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'คอลัมน์ที่เลือก: ', style: TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: column.name, style: monoStyle.copyWith(color: C.primaryDark)),
        ])),
        const SizedBox(height: 12),
        CommitField(
          key: ValueKey('cn-${column.id}-${column.name}'),
          label: 'ชื่อคอลัมน์',
          value: column.name,
          mono: true,
          onCommit: (v) {
            if (v.trim().isNotEmpty) edit((x) => x.name = v.trim());
          },
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: LabeledField(
              label: 'ชนิดข้อมูล',
              child: Dropdown<DataType>(
                value: column.type,
                items: DataType.values,
                labelOf: (t) => typeLabel(ColumnModel(id: '', name: '', type: t)).split('(').first,
                onChanged: (t) => edit((x) {
                  x.type = t;
                  if (t == DataType.varchar) x.length ??= 255;
                  if (t == DataType.decimal) {
                    x.length = 10;
                    x.scale = 2;
                  }
                  if (t != DataType.varchar && t != DataType.decimal) {
                    x.length = null;
                    x.scale = null;
                  }
                  if (!(t == DataType.integer || t == DataType.bigint || t == DataType.smallint)) {
                    x.autoIncrement = false;
                  }
                }),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CommitField(
              key: ValueKey('cd-${column.id}-${column.defaultValue}'),
              label: 'ค่าเริ่มต้น',
              hint: 'ไม่มี',
              value: column.defaultValue ?? '',
              onCommit: (v) => edit((x) => x.defaultValue = v.isEmpty ? null : v),
            ),
          ),
        ]),
        if (hasLen) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: CommitField(
                key: ValueKey('cl-${column.id}-${column.length}'),
                label: column.type == DataType.decimal ? 'Precision' : 'ความยาว',
                value: '${column.length ?? ''}',
                onCommit: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null && n > 0) edit((x) => x.length = n);
                },
              ),
            ),
            if (column.type == DataType.decimal) ...[
              const SizedBox(width: 10),
              Expanded(
                child: CommitField(
                  key: ValueKey('cs-${column.id}-${column.scale}'),
                  label: 'Scale',
                  value: '${column.scale ?? ''}',
                  onCommit: (v) {
                    final n = int.tryParse(v.trim());
                    if (n != null && n >= 0 && n <= (column.length ?? 10)) {
                      edit((x) => x.scale = n);
                    }
                  },
                ),
              ),
            ] else
              const Spacer(),
          ]),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 0, children: [
          _Check('PK', column.isPrimaryKey, (v) => edit((x) {
                x.isPrimaryKey = v;
                if (v) x.notNull = true;
              })),
          _Check('NOT NULL', column.notNull, (v) => edit((x) => x.notNull = v),
              enabled: !column.isPrimaryKey),
          _Check('UNIQUE', column.unique, (v) => edit((x) => x.unique = v)),
          _Check('AUTO INCREMENT', column.autoIncrement, (v) => edit((x) => x.autoIncrement = v),
              enabled: canAi),
        ]),
        if (rel != null) ...[
          const SizedBox(height: 10),
          _FkBox(relation: rel),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => c.removeColumn(table.id, column.id),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('ลบคอลัมน์นี้'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB42318)),
          ),
        ),
      ]),
    );
  }
}

/// ปัญหาที่เกี่ยวกับตารางที่เลือก (ทั้งโปรเจกต์ดูที่แท็บ "ปัญหา" ใน dock)
class _TableIssues extends StatelessWidget {
  const _TableIssues({required this.table});
  final TableModel table;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final mine = c.issues.where((i) => i.tableId == table.id).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 20),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'ตรวจสอบก่อน Export', style: TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: ' (${mine.length})', style: const TextStyle(color: C.muted)),
        ])),
        const SizedBox(height: 8),
        if (mine.isEmpty)
          const Text('✓ ตารางนี้ไม่พบปัญหา', style: TextStyle(fontSize: 12.5, color: C.primaryDark))
        else
          for (final i in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: IssueCard(
                issue: i,
                onTap: i.columnId == null ? null : () => c.selectColumn(i.columnId),
              ),
            ),
      ]),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(this.label, this.value, this.onChanged, {this.enabled = true});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(
            value: value,
            onChanged: enabled ? (v) => onChanged(v ?? false) : null,
            visualDensity: VisualDensity.compact,
            activeColor: C.primary,
          ),
          Text(label,
              style: TextStyle(fontSize: 13, color: enabled ? C.text : C.muted)),
        ]),
      );
}

class _FkBox extends StatelessWidget {
  const _FkBox({required this.relation});
  final RelationModel relation;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final to = c.project.tableById(relation.toTableId);
    final toCol = to?.columnById(relation.toColumnId);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Foreign Key',
              style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
          const Spacer(),
          InkWell(
            onTap: () => c.removeRelation(relation.id),
            child: const Text('ลบ FK', style: TextStyle(fontSize: 12, color: Color(0xFFB42318))),
          ),
        ]),
        const SizedBox(height: 4),
        Text('→ ${to?.name ?? '?'} (${toCol?.name ?? '?'})',
            style: monoStyle.copyWith(fontSize: 12.5)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: LabeledField(
              label: 'ON DELETE',
              child: Dropdown<RefAction>(
                height: 32,
                value: relation.onDelete,
                items: RefAction.values,
                labelOf: (a) => a.sql,
                onChanged: (a) => c.updateRelation(relation.id, (r) => r.onDelete = a),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LabeledField(
              label: 'ON UPDATE',
              child: Dropdown<RefAction>(
                height: 32,
                value: relation.onUpdate,
                items: RefAction.values,
                labelOf: (a) => a.sql,
                onChanged: (a) => c.updateRelation(relation.id, (r) => r.onUpdate = a),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
