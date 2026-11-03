import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/column_model.dart';
import '../../core/models/note_model.dart';
import '../../core/models/table_model.dart';
import '../../state/project_controller.dart';
import '../theme.dart';
import '../prompt_dialog.dart';
import 'canvas_controller.dart';

double _clampPos(double v) => v.clamp(0.0, CanvasController.worldSize - 400);

bool get _multiSelectKeyDown =>
    HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;

/// กด Space ค้างอยู่ -> ลากเพื่อเลื่อนมุมมอง (แทนที่จะย้ายสิ่งที่ลากทับ)
bool get _spaceDown => HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.table});
  final TableModel table;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final cv = context.read<CanvasController>();
    final selected = c.isTableSelected(table.id);
    final fkCols = {
      for (final r in c.project.relations)
        if (r.fromTableId == table.id) r.fromColumnId
    };

    return Positioned(
      left: table.x,
      top: table.y,
      width: table.width,
      child: GestureDetector(
        onTap: () {
          if (cv.tool != CanvasTool.select) return;
          // Ctrl/Shift+คลิก = เพิ่ม/เอาออกจากที่เลือก; คลิกธรรมดา = เลือกตัวเดียว
          if (_multiSelectKeyDown) {
            c.toggleTableSelection(table.id);
          } else {
            c.selectTable(table.id);
          }
        },
        onPanStart: (_) {
          if (_spaceDown) return; // Space+ลาก = เลื่อนมุมมอง ไม่ใช่ย้ายตาราง
          // ลากตารางที่ยังไม่ได้เลือก -> เลือกมันก่อน; ถ้าเลือกอยู่แล้วให้ลากทั้งกลุ่ม
          if (!c.isTableSelected(table.id)) {
            if (_multiSelectKeyDown) {
              c.toggleTableSelection(table.id);
            } else {
              c.selectTable(table.id);
            }
          }
          c.beginGesture();
        },
        onPanUpdate: (d) {
          if (_spaceDown) {
            cv.panBy(d.delta);
            return;
          }
          c.moveSelectedBy(d.delta.dx / cv.scale, d.delta.dy / cv.scale);
        },
        onPanEnd: (_) => c.endGesture(),
        onPanCancel: c.endGesture,
        child: Container(
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? const [
                    BoxShadow(color: C.primary, spreadRadius: 2),
                    BoxShadow(color: Color(0x2915172A), blurRadius: 20, offset: Offset(0, 8)),
                  ]
                : const [
                    BoxShadow(color: Color(0xFFC9D1DC), spreadRadius: 1),
                    BoxShadow(color: Color(0x14172A0F), blurRadius: 12, offset: Offset(0, 4)),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              height: CardMetrics.header,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: selected ? C.primary : C.tableHead,
              child: Row(children: [
                Expanded(
                  child: Text(
                    table.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Text('${table.columns.length}',
                    style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 11)),
              ]),
            ),
            for (final col in table.columns)
              _Row(table: table, column: col, isFk: fkCols.contains(col.id)),
          ]),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.table, required this.column, required this.isFk});
  final TableModel table;
  final ColumnModel column;
  final bool isFk;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final cv = context.read<CanvasController>();
    final src = cv.fkSource;
    final isSource = src != null && src.tableId == table.id && src.columnId == column.id;
    final picked = c.selectedColumnId == column.id && c.selectedTableId == table.id;

    final (flag, bg, fg) = column.isPrimaryKey
        ? ('PK', C.pkBg, C.pkText)
        : isFk
            ? ('FK', const Color(0xFFD9F0EC), C.primaryDark)
            : column.unique
                ? ('UQ', C.uqBg, C.uqText)
                : ('', Colors.transparent, Colors.transparent);

    return MouseRegion(
      cursor: cv.tool == CanvasTool.fk ? SystemMouseCursors.precise : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tap(context, c, cv),
        child: Container(
          height: CardMetrics.row,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSource
                ? const Color(0xFFFFE9A8)
                : picked
                    ? C.primaryTint
                    : null,
            border: const Border(top: BorderSide(color: C.borderSoft)),
          ),
          child: Row(children: [
            Container(
              width: 24,
              padding: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
              alignment: Alignment.center,
              child: Text(flag,
                  style: monoStyle.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(column.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
            ),
            Text(typeLabel(column), style: monoStyle.copyWith(fontSize: 11, color: C.muted)),
          ]),
        ),
      ),
    );
  }

  void _tap(BuildContext context, ProjectController c, CanvasController cv) {
    if (cv.tool != CanvasTool.fk) {
      c.selectTable(table.id, columnId: column.id);
      return;
    }
    final src = cv.fkSource;
    if (src == null) {
      cv.setFkSource(table.id, column.id); // คลิกแรก = คอลัมน์ลูก (ถือ FK)
      return;
    }
    if (src.tableId == table.id && src.columnId == column.id) {
      cv.clearFkSource();
      return;
    }
    // คลิกสอง = คอลัมน์แม่ที่ถูกอ้างถึง
    final r = c.addRelation(
      fromTableId: src.tableId,
      fromColumnId: src.columnId,
      toTableId: table.id,
      toColumnId: column.id,
    );
    if (r == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('มี FK นี้อยู่แล้ว')));
      cv.clearFkSource();
      return;
    }
    c.selectTable(src.tableId, columnId: src.columnId);
    cv.setTool(CanvasTool.select);
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note});
  final NoteModel note;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final cv = context.read<CanvasController>();

    return Positioned(
      left: note.x,
      top: note.y,
      width: note.width,
      child: GestureDetector(
        onDoubleTap: () => _edit(context, c),
        onPanStart: (_) {
          if (!_spaceDown) c.beginGesture();
        },
        onPanUpdate: (d) {
          if (_spaceDown) {
            cv.panBy(d.delta);
            return;
          }
          c.moveNote(
            note.id,
            _clampPos(note.x + d.delta.dx / cv.scale),
            _clampPos(note.y + d.delta.dy / cv.scale),
          );
        },
        onPanEnd: (_) => c.endGesture(),
        onPanCancel: c.endGesture,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: C.warnBg,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Color(0x1F0F172A), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('โน้ต',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: C.warnText)),
            const SizedBox(height: 2),
            Text(note.text.isEmpty ? 'ดับเบิลคลิกเพื่อแก้ไข' : note.text,
                style: TextStyle(
                    fontSize: 12,
                    color: note.text.isEmpty ? const Color(0x995C3D00) : C.warnText)),
          ]),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, ProjectController c) async {
    final r = await showDialog<PromptResult>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'แก้ไขโน้ต',
        initial: note.text,
        maxLines: 5,
        minLines: 3,
        confirmLabel: 'บันทึก',
        deleteLabel: 'ลบโน้ต',
      ),
    );
    if (r == null) return;
    if (r.deleted) {
      c.removeNote(note.id);
    } else if (r.text != note.text) {
      c.updateNote(note.id, (n) => n.text = r.text);
    }
  }
}
