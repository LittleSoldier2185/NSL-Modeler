import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/column_model.dart';
import '../core/models/enums.dart';
import '../core/models/relation_model.dart';
import '../core/models/table_model.dart';
import '../state/project_controller.dart';
import 'issue_widgets.dart';
import 'theme.dart';
import 'seed_data_dialog.dart';
import 'style_actions.dart';
import 'widgets.dart';
import '../core/l10n/l10n.dart';

class RightPanel extends StatelessWidget {
  const RightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final t = c.selectedTable;

    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(left: BorderSide(color: C.border)),
      ),
      child: t == null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  tr('เลือกตารางทางซ้ายเพื่อแก้ไข'),
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
                child: Text(tr('เลือกอยู่ {0} ตาราง · แก้ไขทีละตาราง (กำลังแสดงตารางล่าสุดที่เลือก)', [c.selectionCount]),
                    style: TextStyle(fontSize: 12, color: C.primaryDark)),
              ),
              TextButton(
                onPressed: c.duplicateSelected,
                child: Text(tr('ทำสำเนา')),
              ),
              TextButton(
                onPressed: c.removeSelectedTables,
                style: TextButton.styleFrom(foregroundColor: C.danger),
                child: Text(tr('ลบ')),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('คุณสมบัติของตาราง'), style: TextStyle(fontSize: 12, color: C.muted)),
                const SizedBox(height: 2),
                Text(
                  table.name,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ]),
            ),
            IconButton(
              tooltip: tr('ทำสำเนาตาราง'),
              onPressed: () => c.duplicateTable(table.id),
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
            IconButton(
              tooltip: tr('ลบตาราง'),
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
              label: tr('ชื่อตาราง'),
              value: table.name,
              mono: true,
              height: 42,
              fontSize: 15,
              onCommit: (v) => c.renameTable(table.id, v.trim().isEmpty ? table.name : v.trim()),
            ),
            const SizedBox(height: 12),
            CommitField(
              key: ValueKey('tc-${table.id}-${table.comment}'),
              label: tr('หมายเหตุ (COMMENT)'),
              value: table.comment,
              minLines: 4,
              maxLines: 10,
              hint: tr('อธิบายว่าตารางนี้เก็บอะไร (ใช้เป็น COMMENT ใน SQL)'),
              onCommit: (v) => c.setTableComment(table.id, v),
            ),
            const SizedBox(height: 14),
            _ColorPicker(
              selected: table.colorIndex,
              custom: table.customColor,
              onPick: (i) => c.setTablesColor(c.selectedTableIds, i),
              onCustom: () => StyleActions.tableColor(context, c, c.selectedTableIds, current: table.colorValue),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: tr('ฟอนต์ตาราง'),
              child: SizedBox(
                width: double.infinity,
                height: kFieldHeight,
                child: OutlinedButton.icon(
                  key: const ValueKey('table-font'),
                  onPressed: () => StyleActions.tableFont(context, c, c.selectedTableIds, current: table.fontFamily),
                  icon: const Icon(Icons.font_download_outlined, size: 16),
                  label: Text(table.fontFamily ?? tr('ค่าเริ่มต้น (Noto Sans Thai)'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tableFont(const TextStyle(fontSize: 13), table.fontFamily)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: tr('ข้อมูลตั้งต้น (Seed data)'),
              child: SizedBox(
                width: double.infinity,
                height: kFieldHeight,
                child: OutlinedButton.icon(
                  key: const ValueKey('seed-open'),
                  onPressed: () async {
                    final rows = await showSeedDataDialog(context, project: c.project, table: table);
                    if (rows != null) c.setSeedRows(table.id, rows);
                  },
                  icon: const Icon(Icons.dataset_outlined, size: 16),
                  label: Text(
                    table.seedRows.isEmpty ? tr('เพิ่มข้อมูลตั้งต้น…') : tr('{0} แถว — แก้ไข…', [table.seedRows.length]),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.text,
                    alignment: Alignment.centerLeft,
                    side: BorderSide(color: C.inputBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
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
                  TextSpan(text: tr('คอลัมน์'), style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: ' (${table.columns.length})',
                      style: TextStyle(color: C.muted)),
                ]),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            SmallButton(label: tr('+ เพิ่มคอลัมน์'), onTap: () => c.addColumn(table.id)),
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
        title: Text(tr('ลบตาราง {0}?', [table.name])),
        content: Text(tr('ความสัมพันธ์ FK ที่เกี่ยวข้องจะถูกลบด้วย (ย้อนกลับได้ด้วย Ctrl+Z)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
        ],
      ),
    );
    if (ok == true) c.removeTable(table.id);
  }
}

/// ความกว้างช่องป้าย (PK/FK/NN/AI) และช่องชนิดข้อมูลในรายการคอลัมน์ — คงที่เพื่อให้ขอบขวาตรงกันทุกแถว
const double kColumnBadgeWidth = 80;
const double kColumnTypeWidth = 88;

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
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator, size: 16, color: C.muted),
                    ),
                  ),
                  // จัดเป็นช่อง: ชื่อ (ยืดได้) | ป้าย (ชิดขวา ความกว้างคงที่) | ชนิดข้อมูล (ชิดขวา ความกว้างคงที่)
                  // ขอบขวาของป้ายและชนิดข้อมูลจึงตรงกันทุกแถว ไม่เหลื่อมตามความยาวชื่อ/จำนวนป้าย
                  Expanded(
                    child: Text(col.name,
                        key: ValueKey('col-name-${col.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    key: ValueKey('col-badges-${col.id}'),
                    width: kColumnBadgeWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final b in [
                          if (col.isPrimaryKey) Chip2('PK', C.pkBg, C.pkText),
                          if (fkCols.contains(col.id)) Chip2('FK', C.fkChip, C.primaryDark),
                          if (col.notNull) Chip2('NN', C.nnBg, C.nnText),
                          if (col.autoIncrement) Chip2('AI', C.infoBg, C.infoText),
                        ].indexed) ...[
                          if (b.$1 > 0) const SizedBox(width: 3),
                          b.$2,
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    key: ValueKey('col-type-${col.id}'),
                    width: kColumnTypeWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(typeLabel(col), maxLines: 1, style: monoStyle.copyWith(fontSize: 11.5, color: C.muted)),
                    ),
                  ),
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
          TextSpan(text: tr('คอลัมน์ที่เลือก: '), style: TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: column.name, style: monoStyle.copyWith(color: C.primaryDark)),
        ])),
        const SizedBox(height: 12),
        CommitField(
          key: ValueKey('cn-${column.id}-${column.name}'),
          label: tr('ชื่อคอลัมน์'),
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
              label: tr('ชนิดข้อมูล'),
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
              label: tr('ค่าเริ่มต้น'),
              hint: tr('ไม่มี'),
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
                label: column.type == DataType.decimal ? 'Precision' : tr('ความยาว'),
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
        const SizedBox(height: 12),
        // ช่องติ๊กเรียงเป็นตารางคอลัมน์เท่ากัน (2 คอลัมน์ในแผงปกติ, 4 คอลัมน์เมื่อแผงกว้าง) ไม่ปล่อยให้ตัดบรรทัดเหลื่อมกัน
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 440 ? 4 : 2;
          const gap = 8.0;
          final w = (box.maxWidth - gap * (cols - 1)) / cols;
          Widget cell(Widget child) => SizedBox(width: w, child: child);
          return Wrap(spacing: gap, runSpacing: 2, children: [
            cell(_Check('PK', column.isPrimaryKey, (v) => edit((x) {
                  x.isPrimaryKey = v;
                  if (v) x.notNull = true;
                }))),
            cell(_Check('NOT NULL', column.notNull, (v) => edit((x) => x.notNull = v), enabled: !column.isPrimaryKey)),
            cell(_Check('UNIQUE', column.unique, (v) => edit((x) => x.unique = v))),
            cell(_Check('AUTO INCREMENT', column.autoIncrement, (v) => edit((x) => x.autoIncrement = v), enabled: canAi)),
          ]);
        }),
        if (rel != null) ...[
          const SizedBox(height: 14),
          _FkBox(relation: rel),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => c.removeColumn(table.id, column.id),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(tr('ลบคอลัมน์นี้')),
            style: TextButton.styleFrom(foregroundColor: C.danger),
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
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: tr('ตรวจสอบก่อน Export'), style: TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: ' (${mine.length})', style: TextStyle(color: C.muted)),
        ])),
        const SizedBox(height: 8),
        if (mine.isEmpty)
          Text(tr('✓ ตารางนี้ไม่พบปัญหา'), style: TextStyle(fontSize: 12.5, color: C.primaryDark))
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
        child: Row(children: [
          Checkbox(
            value: value,
            onChanged: enabled ? (v) => onChanged(v ?? false) : null,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeColor: C.primary,
          ),
          const SizedBox(width: 4),
          // ป้ายย่อตามความกว้างของช่อง (เช่น AUTO INCREMENT ในแผงแคบ) ไม่ตัดบรรทัดและไม่ล้น
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, style: TextStyle(fontSize: 13, color: enabled ? C.text : C.muted)),
            ),
          ),
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
          Expanded(
            child: Text('Foreign Key',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
          ),
          InkWell(
            onTap: () => c.removeRelation(relation.id),
            child: Text(tr('ลบ FK'), style: TextStyle(fontSize: 12, color: C.danger)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('→ ${to?.name ?? '?'} (${toCol?.name ?? '?'})',
            style: monoStyle.copyWith(fontSize: 12.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(tr('สีเส้น'), style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500))),
          InkResponse(
            key: const ValueKey('fk-color'),
            onTap: () => StyleActions.relationColor(context, c, relation.id, current: relation.color),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: relation.color == null ? null : Color(relation.color!),
                  border: Border.all(color: C.border)),
              child: relation.color == null ? Icon(Icons.colorize_rounded, size: 13, color: C.muted) : null,
            ),
          ),
          if (relation.color != null) ...[
            const SizedBox(width: 6),
            InkResponse(
              key: const ValueKey('fk-color-reset'),
              onTap: () => c.setRelationColor(relation.id, null),
              child: Icon(Icons.close_rounded, size: 15, color: C.muted),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: LabeledField(
              label: 'ON DELETE',
              child: Dropdown<RefAction>(
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

/// ชื่อสีของตาราง (ตามลำดับ [kTableColors]) ใช้เป็นทูลทิปและรายการเมนู
const kTableColorNames = ['เขียวน้ำทะเล', 'ม่วง', 'น้ำเงิน', 'ส้ม', 'ชมพู', 'เขียว', 'เทา'];

/// แถบเลือกสีตาราง: วงกลมสีต่าง ๆ + "ไม่มีสี" (กลับเป็นสีเริ่มต้น) — ใช้กับทุกตารางที่เลือกอยู่
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onPick, this.custom, this.onCustom});
  final int? selected;
  final int? custom;
  final ValueChanged<int?> onPick;
  final VoidCallback? onCustom;

  @override
  Widget build(BuildContext context) {
    Widget swatch({required Key key, required String tip, required bool on, required VoidCallback onTap, required Widget child}) =>
        Tooltip(
          message: tip,
          child: InkResponse(
            key: key,
            onTap: onTap,
            radius: 18,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: on ? C.text : C.border, width: on ? 2 : 1),
              ),
              child: child,
            ),
          ),
        );
    return LabeledField(
      label: tr('สีตาราง'),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        swatch(
          key: const ValueKey('table-color-none'),
          tip: tr('ไม่มีสี (ค่าเริ่มต้น)'),
          on: selected == null && custom == null,
          onTap: () => onPick(null),
          child: Icon(Icons.block_rounded, size: 15, color: C.muted),
        ),
        for (var i = 0; i < kTableColors.length; i++)
          swatch(
            key: ValueKey('table-color-$i'),
            tip: tr(kTableColorNames[i]),
            on: selected == i && custom == null,
            onTap: () => onPick(i),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Color(kTableColors[i])),
              child: selected == i && custom == null ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
            ),
          ),
        if (onCustom != null)
          swatch(
            key: const ValueKey('table-color-custom'),
            tip: tr('กำหนดสีเอง…'),
            on: custom != null,
            onTap: onCustom!,
            child: custom == null
                ? Icon(Icons.colorize_rounded, size: 15, color: C.muted)
                : Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(custom!))),
          ),
      ]),
    );
  }
}
