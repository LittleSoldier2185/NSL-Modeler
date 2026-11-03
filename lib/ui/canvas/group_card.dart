import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/diagram_geometry.dart';
import '../../core/models/group_model.dart';
import '../../state/app_settings.dart';
import '../../state/project_controller.dart';
import '../theme.dart';
import 'canvas_controller.dart';
import 'context_menu.dart';

Color groupColor(int index) => Color(kGroupColors[index % kGroupColors.length]);

/// กลุ่มตาราง: กรอบเส้นประมีชื่อ วาดอยู่ใต้ตาราง/เส้น FK
/// - ลากแถบชื่อ = ย้ายกลุ่มพร้อมของข้างใน; ดับเบิลคลิกแถบชื่อ = พิมพ์ชื่อบนแถบเลย; คลิกขวา = เมนู
/// - ลากมุมขวาล่าง = ปรับขนาด
/// - ส่วนตัวกรอบ (พื้นที่ข้างใน) ไม่รับเมาส์ จึงคลิก/ลากกรอบเลือกบนพื้นว่างในกลุ่มได้ตามปกติ
class GroupCard extends StatefulWidget {
  const GroupCard({super.key, required this.group});
  final GroupModel group;

  @override
  State<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<GroupCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'group-name');
  late final CanvasController _cv;
  bool _editing = false;

  GroupModel get group => widget.group;

  bool get _spaceDown => HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

  double? _grid() =>
      context.read<AppSettings>().snapToGrid && !HardwareKeyboard.instance.isAltPressed ? kGridSize : null;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    final cv = _cv = context.read<CanvasController>();
    cv.addListener(_checkEditRequest);
    if (cv.pendingGroupEditId == group.id) {
      cv.pendingGroupEditId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startEditing(selectAll: true));
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

  void _checkEditRequest() {
    if (_cv.pendingGroupEditId == group.id && !_editing) {
      _cv.pendingGroupEditId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startEditing(selectAll: true));
    }
  }

  void _onFocus() {
    if (!_focus.hasFocus && _editing) _finish(save: true);
  }

  void _startEditing({bool selectAll = false}) {
    if (!mounted || _editing) return;
    _controller.value = TextEditingValue(
      text: group.name,
      selection: selectAll
          ? TextSelection(baseOffset: 0, extentOffset: group.name.length)
          : TextSelection.collapsed(offset: group.name.length),
    );
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  void _finish({required bool save}) {
    if (!_editing) return;
    final c = context.read<ProjectController>();
    final text = _controller.text.trim();
    setState(() => _editing = false);
    if (save && text.isNotEmpty) c.renameGroup(group.id, text);
    if (_focus.hasFocus) _focus.unfocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _finish(save: false);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter) {
      _finish(save: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<ProjectController>();
    final cv = context.read<CanvasController>();
    final color = Color(group.colorValue);
    final selected = c.selectedGroupId == group.id;
    final nameStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.isDark ? color : _darken(color));

    return Positioned(
      left: group.x + CanvasController.worldOrigin,
      top: group.y + CanvasController.worldOrigin,
      width: group.width,
      height: group.height,
      child: Stack(clipBehavior: Clip.none, children: [
        // ตัวกรอบ: ไม่รับเมาส์ (ให้พื้นว่างในกลุ่มยังลากกรอบเลือก/คลิกขวาเมนูพื้นที่ว่างได้)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: GroupPainter(color: color, dark: C.isDark, selected: selected)),
          ),
        ),
        // แถบชื่อ: ลากย้าย / ดับเบิลคลิกพิมพ์ชื่อ / คลิกขวาเมนู
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: kGroupHeader,
          child: MouseRegion(
            cursor: _editing ? SystemMouseCursors.text : SystemMouseCursors.move,
            child: GestureDetector(
              key: ValueKey('group-header-${group.id}'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => c.selectGroup(group.id),
              onDoubleTap: _editing ? null : _startEditing,
              onSecondaryTapDown: (d) {
                c.selectGroup(group.id);
                showContextMenu(context, d.globalPosition, groupMenuEntries(context, group));
              },
              onPanStart: _editing
                  ? null
                  : (_) {
                      if (_spaceDown) {
                        cv.setPanning(true);
                      } else {
                        c.beginGroupDrag(group.id);
                      }
                    },
              onPanUpdate: _editing
                  ? null
                  : (d) {
                      if (_spaceDown) {
                        cv.panBy(d.delta);
                        return;
                      }
                      c.moveGroupBy(group.id, d.delta.dx / cv.scale, d.delta.dy / cv.scale, grid: _grid());
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _editing
                      ? Focus(
                          onKeyEvent: _onKey,
                          child: TextField(
                            key: ValueKey('group-name-field-${group.id}'),
                            controller: _controller,
                            focusNode: _focus,
                            style: nameStyle,
                            cursorColor: color,
                            maxLines: 1,
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: tr('ชื่อกลุ่ม'),
                            ),
                          ),
                        )
                      : Text(
                          group.name.isEmpty ? tr('ดับเบิลคลิกเพื่อตั้งชื่อกลุ่ม') : group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                ),
              ),
            ),
          ),
        ),
        // มุมขวาล่าง: ปรับขนาด
        Positioned(
          right: 0,
          bottom: 0,
          width: 22,
          height: 22,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeDownRight,
            child: GestureDetector(
              key: ValueKey('group-resize-${group.id}'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => c.beginGroupResize(group.id),
              onPanUpdate: (d) => c.resizeGroupBy(group.id, d.delta.dx / cv.scale, d.delta.dy / cv.scale, grid: _grid()),
              onPanEnd: (_) => c.endGesture(),
              onPanCancel: c.endGesture,
              child: CustomPaint(painter: _HandlePainter(color)),
            ),
          ),
        ),
      ]),
    );
  }

  static Color _darken(Color c) => Color.lerp(c, Colors.black, 0.35)!;
}

/// วาดกรอบกลุ่ม: พื้นจาง ๆ, แถบชื่อ, ขอบเส้นประ
class GroupPainter extends CustomPainter {
  const GroupPainter({required this.color, required this.dark, this.selected = false});
  final Color color;
  final bool dark;

  /// ถูกเลือกอยู่: ขอบหนาขึ้นและมีวงเรืองรอบนอก
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    canvas.drawRRect(r, Paint()..color = color.withValues(alpha: dark ? 0.10 : 0.07));

    // แถบชื่อ (มุมบนมน)
    final header = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, size.width, kGroupHeader),
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
    );
    canvas.drawRRect(header, Paint()..color = color.withValues(alpha: dark ? 0.20 : 0.14));

    if (selected) {
      canvas.drawRRect(
        r.inflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: 0.35),
      );
    }
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.4 : 1.6
      ..color = color.withValues(alpha: selected ? 1 : 0.9);
    final path = Path()..addRRect(r.deflate(0.8));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 8, m.length)), border);
        d += 14; // เส้น 8 ช่อง 6
      }
    }
  }

  @override
  bool shouldRepaint(GroupPainter old) => old.color != color || old.dark != dark || old.selected != selected;
}

class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final k in [6.0, 11.0]) {
      canvas.drawLine(Offset(size.width - 4, size.height - 4 - k), Offset(size.width - 4 - k, size.height - 4), p);
    }
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.color != color;
}
