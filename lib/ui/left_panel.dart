import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/column_model.dart';
import '../core/models/enums.dart';
import '../state/project_controller.dart';
import 'canvas/canvas_controller.dart';
import 'theme.dart';

class LeftPanel extends StatefulWidget {
  const LeftPanel({super.key});

  @override
  State<LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<LeftPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final cv = context.read<CanvasController>();
    final q = _query.trim().toLowerCase();
    final tables = c.project.tables.where((t) {
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) ||
          t.columns.any((col) => col.name.toLowerCase().contains(q));
    }).toList();

    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(right: BorderSide(color: C.border)),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(children: [
              const Text('ตาราง', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(' (${c.project.tables.length})', style: const TextStyle(color: C.muted)),
              const Spacer(),
              SizedBox(
                width: 28,
                height: 28,
                child: OutlinedButton(
                  onPressed: () => c.addTable(
                    x: 40 + 30.0 * c.project.tables.length,
                    y: 60 + 30.0 * c.project.tables.length,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: C.primary,
                    side: const BorderSide(color: C.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Tooltip(message: 'เพิ่มตาราง', child: Icon(Icons.add, size: 18)),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SizedBox(
              height: 34,
              child: TextField(
                focusNode: cv.searchFocus,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'ค้นหาตาราง / คอลัมน์',
                  hintStyle: const TextStyle(fontSize: 13, color: C.muted),
                  prefixIcon: const Icon(Icons.search, size: 16, color: C.muted),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: C.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: C.primary, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          if (tables.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Text(
                c.project.tables.isEmpty ? 'ยังไม่มีตาราง กด + เพื่อเพิ่ม' : 'ไม่พบที่ค้นหา',
                style: const TextStyle(color: C.muted, fontSize: 12.5),
              ),
            ),
          for (final t in tables) ...[
            _TableTile(
              name: t.name,
              count: t.columns.length,
              selected: c.isTableSelected(t.id),
              onTap: () {
                final multi = HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isShiftPressed;
                if (multi) {
                  c.toggleTableSelection(t.id); // Ctrl/Shift+คลิก = เพิ่ม/เอาออกจากที่เลือก
                } else {
                  c.selectTable(t.id);
                  cv.focusTable(t); // เลื่อนมุมมอง canvas ไปที่ตารางนี้
                }
              },
            ),
            // ค้นหาแล้วเจอที่ชื่อคอลัมน์: แสดงคอลัมน์ที่ตรงใต้ตาราง คลิกเพื่อไปที่คอลัมน์นั้น
            if (q.isNotEmpty)
              for (final col in t.columns.where((x) => x.name.toLowerCase().contains(q)))
                _ColumnHit(
                  name: col.name,
                  type: typeLabel(col),
                  selected: t.id == c.selectedTableId && col.id == c.selectedColumnId,
                  onTap: () {
                    c.selectTable(t.id, columnId: col.id);
                    cv.focusTable(t);
                  },
                ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Divider(height: 1),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Text('เทมเพลตตาราง', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          _TemplateTile('+ users (id, email, password)', () => _usersTemplate(c)),
          _TemplateTile(
            '+ audit (created_at, updated_at)',
            () => _addToSelected(context, c, _auditCols(c)),
          ),
          _TemplateTile(
            '+ soft delete (deleted_at)',
            () => _addToSelected(context, c, [
              ColumnModel(id: c.newId('c'), name: 'deleted_at', type: DataType.datetime),
            ]),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _usersTemplate(ProjectController c) {
    c.addTableWith('users', [
      ColumnModel(
          id: c.newId('c'),
          name: 'id',
          isPrimaryKey: true,
          notNull: true,
          autoIncrement: true),
      ColumnModel(
          id: c.newId('c'),
          name: 'email',
          type: DataType.varchar,
          length: 255,
          notNull: true,
          unique: true),
      ColumnModel(
          id: c.newId('c'),
          name: 'password',
          type: DataType.varchar,
          length: 255,
          notNull: true),
    ], x: 40 + 30.0 * c.project.tables.length, y: 60 + 30.0 * c.project.tables.length);
  }

  List<ColumnModel> _auditCols(ProjectController c) => [
        ColumnModel(
            id: c.newId('c'), name: 'created_at', type: DataType.datetime, notNull: true),
        ColumnModel(
            id: c.newId('c'), name: 'updated_at', type: DataType.datetime, notNull: true),
      ];

  void _addToSelected(BuildContext context, ProjectController c, List<ColumnModel> cols) {
    final id = c.selectedTableId;
    final msg = ScaffoldMessenger.of(context);
    if (id == null) {
      msg
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('เลือกตารางก่อน แล้วค่อยกดเทมเพลตนี้')));
      return;
    }
    final n = c.appendColumns(id, cols);
    if (n == 0) {
      msg
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('ตารางนี้มีคอลัมน์เหล่านี้อยู่แล้ว')));
    }
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.name,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected ? C.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Icon(Icons.table_rows_outlined, size: 15, color: selected ? C.primaryDark : C.text),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: selected ? C.primaryDark : C.text,
                    ),
                  ),
                ),
                Text('$count คอลัมน์', style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ),
        ),
      );
}

/// คอลัมน์ที่ตรงกับคำค้น (แสดงใต้ตารางของมัน)
class _ColumnHit extends StatelessWidget {
  const _ColumnHit({required this.name, required this.type, required this.selected, required this.onTap});
  final String name;
  final String type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 30, right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? C.primaryTint : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              const Icon(Icons.subdirectory_arrow_right, size: 13, color: C.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle.copyWith(fontSize: 12, color: selected ? C.primaryDark : C.text)),
              ),
              Text(type, style: monoStyle.copyWith(fontSize: 10.5, color: C.muted)),
            ]),
          ),
        ),
      );
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
      );
}
