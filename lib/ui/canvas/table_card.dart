import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/layout/diagram_geometry.dart';
import '../../core/models/color_utils.dart';
import '../../core/models/column_model.dart';
import '../../core/models/note_model.dart';
import '../../core/models/table_model.dart';
import '../../state/app_settings.dart';
import '../../state/project_controller.dart';
import '../theme.dart';
import 'canvas_controller.dart';
import 'context_menu.dart';
import '../../core/l10n/l10n.dart';

/// ขนาดช่องที่ใช้ปัด (null = ไม่ปัด) ตามการตั้งค่า และกด Alt ค้างเพื่อข้ามชั่วคราว
double? _gridFor(BuildContext context) =>
    context.read<AppSettings>().snapToGrid && !HardwareKeyboard.instance.isAltPressed ? kGridSize : null;

double _clampPos(double v) => v.clamp(kWorldMin, kWorldMax);

bool get _multiSelectKeyDown =>
    HardwareKeyboard.instance.isControlPressed ||
    HardwareKeyboard.instance.isShiftPressed;

/// กด Space ค้างอยู่ -> ลากเพื่อเลื่อนมุมมอง (แทนที่จะย้ายสิ่งที่ลากทับ)
bool get _spaceDown =>
    HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.table});
  final TableModel table;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final cv = context.read<CanvasController>();
    final selected = c.isTableSelected(table.id);
    // กำลังถูกหยิบ (ลากอยู่): ยกขึ้นเล็กน้อย — ขยายนิด เงาลึกขึ้น แล้วค่อย ๆ วางลงเมื่อปล่อย
    final lifted = selected && c.gestureActive && !cv.panning;
    // สีที่ผู้ใช้เลือก: ใช้ที่หัวตารางและแต้มพื้นตารางจาง ๆ (ตารางที่เลือกยังมีวงสีหลักบอกสถานะ)
    final custom = table.colorValue == null ? null : Color(table.colorValue!);
    final headBase = custom ?? (selected ? C.primary : C.tableHead);
    // สีตัวอักษรบนหัวตาราง: ขาวหรือเกือบดำตามความสว่างของสีพื้น (สีกำหนดเองอาจอ่อนมาก)
    final headFg = Color(onColor(headBase.toARGB32()));
    final font = table.fontFamily;
    final fkCols = {
      for (final r in c.project.relations)
        if (r.fromTableId == table.id) r.fromColumnId,
    };

    return Positioned(
      left: table.x + CanvasController.worldOrigin,
      top: table.y + CanvasController.worldOrigin,
      width: table.width,
      child: GestureDetector(
        onSecondaryTapDown: (d) => showContextMenu(context, d.globalPosition, tableMenuEntries(context, table, at: d.globalPosition)),
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
          if (_spaceDown) {
            cv.setPanning(true); // Space+ลาก = เลื่อนมุมมอง ไม่ใช่ย้ายตาราง
            return;
          }
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
          c.moveSelectedBy(d.delta.dx / cv.scale, d.delta.dy / cv.scale, grid: _gridFor(context));
        },
        onPanEnd: (_) {
          cv.setPanning(false);
          c.endGesture();
        },
        onPanCancel: () {
          cv.setPanning(false);
          c.endGesture();
        },
        child: AnimatedScale(
          scale: lifted ? 1.025 : 1,
          duration: Duration(milliseconds: lifted ? 140 : 200),
          curve: lifted ? Curves.easeOutCubic : Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: custom == null
                  ? C.surface
                  : Color.alphaBlend(custom.withValues(alpha: C.isDark ? 0.14 : 0.06), C.surface),
              borderRadius: BorderRadius.circular(8),
              // ความลึก: การ์ดปกติลอยต่ำ, ตัวที่เลือกมีวงสีหลักและลอยสูงขึ้น, ตัวที่ถูกหยิบลอยสูงสุด
              boxShadow: [
                BoxShadow(
                  color: selected ? C.primary : C.border,
                  spreadRadius: selected ? 2 : 1,
                ),
                if (lifted)
                  BoxShadow(
                    color: C.palette.shadow.withValues(
                      alpha: C.isDark ? 0.6 : 0.22,
                    ),
                    blurRadius: 36,
                    offset: const Offset(0, 22),
                  )
                else
                  BoxShadow(
                    color: C.palette.shadow.withValues(alpha: 0),
                    blurRadius: 0,
                    offset: Offset.zero,
                  ),
                ...(selected ? C.shadowLg : C.shadowMd),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: CardMetrics.header,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.lerp(headBase, Colors.white, 0.10)!,
                        headBase,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          table.name,
                          overflow: TextOverflow.ellipsis,
                          style: tableFont(
                            TextStyle(color: headFg, fontWeight: FontWeight.w600, fontSize: 13),
                            font,
                          ),
                        ),
                      ),
                      Text(
                        '${table.columns.length}',
                        style: tableFont(TextStyle(color: headFg.withValues(alpha: 0.85), fontSize: 11), font),
                      ),
                    ],
                  ),
                ),
                for (final col in table.columns)
                  _Row(
                    table: table,
                    column: col,
                    isFk: fkCols.contains(col.id),
                  ),
              ],
            ),
          ),
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
    final isSource =
        src != null && src.tableId == table.id && src.columnId == column.id;
    final picked =
        c.selectedColumnId == column.id && c.selectedTableId == table.id;

    final (flag, bg, fg) = column.isPrimaryKey
        ? ('PK', C.pkBg, C.pkText)
        : isFk
        ? ('FK', C.fkChip, C.primaryDark)
        : column.unique
        ? ('UQ', C.uqBg, C.uqText)
        : ('', Colors.transparent, Colors.transparent);

    return MouseRegion(
      cursor: cv.tool == CanvasTool.fk
          ? SystemMouseCursors.precise
          : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tap(context, c, cv),
        onSecondaryTapDown: (d) => showContextMenu(context, d.globalPosition, tableMenuEntries(context, table, column: column, at: d.globalPosition)),
        child: Container(
          height: CardMetrics.row,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSource
                ? C.fkSource
                : picked
                ? C.primaryTint
                : null,
            border: Border(top: BorderSide(color: C.borderSoft)),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                padding: const EdgeInsets.symmetric(vertical: 1),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  flag,
                  style: monoStyle.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  column.name,
                  overflow: TextOverflow.ellipsis,
                  style: tableFont(const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500), table.fontFamily),
                ),
              ),
              Text(
                typeLabel(column),
                // ชนิดข้อมูลใช้ฟอนต์ที่ผู้ใช้เลือกด้วย (ไม่ได้เลือก = ฟอนต์เว้นระยะเท่ากัน)
                style: table.fontFamily == null
                    ? monoStyle.copyWith(fontSize: 11, color: C.muted)
                    : tableFont(TextStyle(fontSize: 11, color: C.muted), table.fontFamily),
              ),
            ],
          ),
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
        ..showSnackBar(SnackBar(content: Text(tr('มี FK นี้อยู่แล้ว'))));
      cv.clearFkSource();
      return;
    }
    c.selectTable(src.tableId, columnId: src.columnId);
    cv.setTool(CanvasTool.select);
  }
}

class NoteCard extends StatefulWidget {
  const NoteCard({super.key, required this.note});
  final NoteModel note;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'note-text');
  late final CanvasController _cv;
  bool _editing = false;
  bool _hover = false;

  /// ตำแหน่งตอนเริ่มลาก + ระยะสะสม (ไว้ปัดเข้าช่องโดยไม่สะสมความคลาดเคลื่อน)
  Offset _dragOrigin = Offset.zero;
  Offset _dragRaw = Offset.zero;

  NoteModel get note => widget.note;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    // โน้ตที่เพิ่งวางใหม่: เข้าโหมดพิมพ์ทันที
    final cv = _cv = context.read<CanvasController>();
    cv.addListener(_checkEditRequest);
    if (cv.pendingNoteEditId == note.id) {
      cv.pendingNoteEditId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startEditing());
    }
  }

  /// มีคำขอให้โน้ตนี้เข้าโหมดพิมพ์ (เช่นจากเมนูคลิกขวา)
  void _checkEditRequest() {
    final cv = _cv;
    if (cv.pendingNoteEditId == note.id && !_editing) {
      cv.pendingNoteEditId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startEditing());
    }
  }

  @override
  void dispose() {
    _cv.removeListener(_checkEditRequest);
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  /// คลิกที่อื่น (เสียโฟกัส) = บันทึกที่พิมพ์ไว้
  void _onFocus() {
    if (!_focus.hasFocus && _editing) _finish(save: true);
  }

  void _startEditing() {
    if (!mounted || _editing) return;
    _controller.value = TextEditingValue(
      text: note.text,
      selection: TextSelection.collapsed(offset: note.text.length),
    );
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  void _finish({required bool save}) {
    if (!_editing) return;
    final c = context.read<ProjectController>();
    final text = _controller.text;
    setState(() => _editing = false);
    if (save && text != note.text) c.updateNote(note.id, (n) => n.text = text);
    if (_focus.hasFocus) _focus.unfocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _finish(save: false); // Esc = ยกเลิกสิ่งที่พิมพ์
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && HardwareKeyboard.instance.isControlPressed) {
      _finish(save: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final cv = context.read<CanvasController>();
    final empty = note.text.isEmpty;
    final textStyle = TextStyle(fontSize: 12, color: C.warnText, height: 1.35);

    return Positioned(
      left: note.x + CanvasController.worldOrigin,
      top: note.y + CanvasController.worldOrigin,
      width: note.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: _editing ? SystemMouseCursors.text : MouseCursor.defer,
        child: GestureDetector(
          onDoubleTap: _editing ? null : _startEditing,
          onSecondaryTapDown: (d) => showContextMenu(context, d.globalPosition, noteMenuEntries(context, note)),
          // ระหว่างพิมพ์ให้ช่องข้อความรับการลาก (เลือกข้อความ) แทนการย้ายโน้ต
          onPanStart: _editing
              ? null
              : (_) {
                  if (_spaceDown) {
                    cv.setPanning(true);
                  } else {
                    c.beginGesture();
                    _dragOrigin = Offset(note.x, note.y);
                    _dragRaw = Offset.zero;
                  }
                },
          onPanUpdate: _editing
              ? null
              : (d) {
                  if (_spaceDown) {
                    cv.panBy(d.delta);
                    return;
                  }
                  _dragRaw += d.delta / cv.scale;
                  final grid = _gridFor(context);
                  var p = _dragOrigin + _dragRaw;
                  if (grid != null) p = Offset(snapToGrid(p.dx, grid), snapToGrid(p.dy, grid));
                  c.moveNote(note.id, _clampPos(p.dx), _clampPos(p.dy));
                },
          onPanEnd: _editing
              ? null
              : (_) {
                  cv.setPanning(false);
                  c.endGesture();
                },
          onPanCancel: _editing
              ? null
              : () {
                  cv.setPanning(false);
                  c.endGesture();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: C.warnBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _editing ? C.primary : Colors.transparent, width: 1.5),
              boxShadow: _editing ? C.shadowMd : C.shadowSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      tr('โน้ต'),
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: C.warnText),
                    ),
                  ),
                  // ปุ่มลบ: โผล่เมื่อเมาส์อยู่บนโน้ตหรือกำลังพิมพ์
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _hover || _editing ? 1 : 0,
                    child: Tooltip(
                      message: tr('ลบโน้ต'),
                      // ใช้ Listener แทน onTap: GestureDetector แม่มี onDoubleTap ซึ่งจะหน่วงการคลิกลูกไป ~300ms
                      child: Listener(
                        key: ValueKey('note-delete-${note.id}'),
                        behavior: HitTestBehavior.opaque,
                        onPointerUp: (e) {
                          if ((Offset.zero & const Size(22, 22)).contains(e.localPosition)) c.removeNote(note.id);
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: Icon(Icons.close_rounded, size: 15, color: C.warnText),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 2),
                if (_editing)
                  Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      key: ValueKey('note-field-${note.id}'),
                      controller: _controller,
                      focusNode: _focus,
                      style: textStyle,
                      cursorColor: C.primary,
                      maxLines: null,
                      minLines: 2,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: tr('พิมพ์โน้ตที่นี่ (Ctrl+Enter บันทึก · Esc ยกเลิก)'),
                        hintStyle: textStyle.copyWith(color: const Color(0x995C3D00)),
                      ),
                    ),
                  )
                else
                  Text(
                    empty ? tr('ดับเบิลคลิกเพื่อพิมพ์') : note.text,
                    style: empty ? textStyle.copyWith(color: const Color(0x995C3D00)) : textStyle,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
