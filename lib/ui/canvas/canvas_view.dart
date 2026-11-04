import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_settings.dart';
import '../../state/project_controller.dart';
import '../theme.dart';
import '../../core/layout/diagram_geometry.dart';
import '../../core/models/project.dart';
import 'canvas_controller.dart';
import 'context_menu.dart';
import 'group_card.dart';
import 'relation_painter.dart';
import 'table_card.dart';
import '../../core/l10n/l10n.dart';

class CanvasView extends StatelessWidget {
  const CanvasView({super.key, required this.focusNode});

  /// โฟกัสของหน้าหลัก — ดึงกลับมาเมื่อคลิก canvas เพื่อให้คีย์ลัดทำงานต่อ
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final cv = context.watch<CanvasController>();

    final board = boardBounds(c.project);
    final extended = extendedEdges(c.project);
    // ตอนลากตาราง: ขอบที่เข้าใกล้ (ถ้าลากชนจะขยาย) ใช้ทั้งไฮไลต์ขอบและข้อความ hint
    final dragging = c.gestureActive && !cv.panning;
    final near = dragging ? edgesNearTables(c.project, c.selectedTableIds) : const <BoardEdge>{};
    final hint = !dragging
        ? null
        : extended.isNotEmpty
            ? _EdgeHintKind.extending
            : near.isNotEmpty
                ? _EdgeHintKind.willExtend
                : null;

    return ClipRect(
      child: LayoutBuilder(builder: (context, box) {
        cv.viewport = box.biggest;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            focusNode.requestFocus();
            // ปุ่มกลางเมาส์ = จับแล้วลากเพื่อเลื่อนมุมมอง (ใช้ได้ทุกที่ รวมถึงบนการ์ดตาราง)
            if (e.buttons == kMiddleMouseButton) cv.setPanning(true);
          },
          onPointerMove: (e) {
            if (e.buttons == kMiddleMouseButton) cv.panBy(e.delta);
          },
          onPointerUp: (e) {
            if (cv.panning && e.buttons == 0) cv.setPanning(false);
          },
          onPointerCancel: (_) => cv.setPanning(false),
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            if (HardwareKeyboard.instance.isControlPressed) {
              cv.zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
            } else {
              cv.panBy(-e.scrollDelta);
            }
          },
          child: Stack(children: [
            // พื้นหลัง: จุด + รับการลากเพื่อ pan + คลิกเพื่อวางของ/ยกเลิกเลือก
            Positioned.fill(
              child: MouseRegion(
                cursor: _backgroundCursor(cv),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _backgroundTap(context, c, cv, d.localPosition),
                  // คลิกขวา: ถ้ามีเครื่องมือค้างอยู่ให้ยกเลิกเครื่องมือก่อน ไม่งั้นเปิดเมนูคำสั่ง
                  onSecondaryTapDown: (d) {
                    if (cv.tool != CanvasTool.select) {
                      cv.setTool(CanvasTool.select);
                      return;
                    }
                    final w = cv.toWorld(d.localPosition);
                    // คลิกขวาโดนเส้นความสัมพันธ์ = เมนูของเส้น (เปลี่ยนสี / ลบ)
                    final rid = relationAt(c.project, w.dx, w.dy);
                    if (rid != null) {
                      _selectRelation(c, rid);
                      showContextMenu(context, d.globalPosition, relationMenuEntries(context, rid));
                      return;
                    }
                    showContextMenu(context, d.globalPosition, backgroundMenuEntries(context, w));
                  },
                  // ลากซ้ายบนพื้นว่าง = กรอบเลือก (Ctrl/Shift = เลือกเพิ่ม); กด Space ค้าง = เลื่อนมุมมองแทน
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: (d) {
                    if (cv.tool != CanvasTool.select) return;
                    if (_spaceDown) {
                      cv.setPanning(true);
                      return;
                    }
                    final add = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
                    cv.beginMarquee(d.localPosition, base: add ? c.selectedTableIds : const {});
                    cv.marqueeBaseGroups = add ? c.attachedGroupIds : const {};
                  },
                  onPanUpdate: (d) {
                    if (cv.panning) {
                      cv.panBy(d.delta);
                    } else if (cv.marquee != null) {
                      cv.updateMarquee(d.localPosition);
                      // กรอบที่ครอบกลุ่มทั้งกลุ่ม = กรอบกลุ่มติดไปกับตารางที่เลือกด้วย
                      c.setTableSelection({...cv.marqueeBase, ...cv.tablesInMarquee(c.project)},
                          groups: {...cv.marqueeBaseGroups, ...cv.groupsInMarquee(c.project)});
                    }
                  },
                  onPanEnd: (_) {
                    cv.setPanning(false);
                    cv.endMarquee();
                  },
                  onPanCancel: () {
                    cv.setPanning(false);
                    cv.endMarquee();
                  },
                  child: CustomPaint(
                    painter: DotsPainter(cv.scale, cv.offset, board, baseBoard(c.project),
                        nearEdges: near, extendedEdges: extended),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
            // world: ตาราง/โน้ต/เส้น FK ย่อขยายและเลื่อนด้วย Matrix เดียว
            Positioned.fill(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: CanvasController.worldSize,
                maxHeight: CanvasController.worldSize,
                child: Transform(
                  alignment: Alignment.topLeft,
                  transform: Matrix4(
                    cv.scale, 0, 0, 0, //
                    0, cv.scale, 0, 0,
                    0, 0, 1, 0,
                    // จุด (0,0) ของโปรเจกต์อยู่ที่ (worldOrigin, worldOrigin) ของชั้นวาด จึงหักชดเชย
                    cv.offset.dx - CanvasController.worldOrigin * cv.scale,
                    cv.offset.dy - CanvasController.worldOrigin * cv.scale, 0, 1,
                  ),
                  child: SizedBox(
                    width: CanvasController.worldSize,
                    height: CanvasController.worldSize,
                    child: Stack(clipBehavior: Clip.none, children: [
                      // กลุ่มอยู่ล่างสุด (ใต้เส้น FK และตาราง)
                      for (final g in c.project.groups) GroupCard(key: ValueKey('group-${g.id}'), group: g),
                      Positioned.fill(
                        child: _RelationLayer(
                          project: c.project,
                          selectedTableId: c.selectedTableId,
                          focusRelationId: _focusRelation(c),
                          showFlow: context.select<AppSettings, bool>((s) => s.showFlow),
                          animate: context.select<AppSettings, bool>((s) => s.flowAnimation),
                          always: context.select<AppSettings, bool>((s) => s.flowAlways),
                          speed: context.select<AppSettings, FlowSpeed>((s) => s.flowSpeed),
                        ),
                      ),
                      for (final t in c.project.tables) TableCard(key: ValueKey('table-${t.id}'), table: t),
                      for (final n in c.project.notes) NoteCard(key: ValueKey('note-${n.id}'), note: n),
                    ]),
                  ),
                ),
              ),
            ),
            if (cv.marquee != null) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _MarqueePainter(cv.marquee!)))),
            // ระหว่างเลื่อนมุมมองให้เคอร์เซอร์เป็นมือกำทั่วทั้งจอ (แม้เมาส์ผ่านบนการ์ดตาราง)
            // ไม่บังเหตุการณ์ของเมาส์: MouseRegion แบบโปร่ง
            if (cv.panning)
              const Positioned.fill(
                child: MouseRegion(opaque: false, cursor: SystemMouseCursors.grabbing, child: SizedBox.expand()),
              ),
            const Positioned(left: 16, top: 16, child: _ToolBar()),
            if (cv.tool != CanvasTool.select)
              Positioned(left: 0, right: 0, top: 18, child: Center(child: _Hint(cv: cv))),
            if (hint != null && cv.tool == CanvasTool.select)
              Positioned(left: 0, right: 0, top: 18, child: IgnorePointer(child: Center(child: _EdgeHint(hint)))),
            const Positioned(right: 16, bottom: 16, child: _ZoomBar()),
          ]),
        );
      }),
    );
  }

  /// เคอร์เซอร์บนพื้นว่าง: โหมดเลือก = ลูกศรปกติ (ลาก = กรอบเลือก), กำลังเลื่อนมุมมอง = มือกำ, เครื่องมือวางของ = กากบาท
  static MouseCursor _backgroundCursor(CanvasController cv) {
    if (cv.panning) return SystemMouseCursors.grabbing;
    return switch (cv.tool) {
      CanvasTool.select => SystemMouseCursors.basic,
      CanvasTool.table || CanvasTool.note => SystemMouseCursors.precise,
      CanvasTool.fk => SystemMouseCursors.basic,
    };
  }

  /// ตำแหน่งที่จะวางของใหม่: ปัดเข้าช่องตารางถ้าเปิด snap
  static Offset _placed(BuildContext context, Offset w) => context.read<AppSettings>().snapToGrid
      ? Offset(snapToGrid(w.dx), snapToGrid(w.dy))
      : w;

  /// เส้นที่ควรเน้น (ดู [_RelationLayer]) คอลัมน์ FK ที่เลือกอยู่ (ฝั่งลูก) ชี้ไปที่ความสัมพันธ์ไหน
  String? _focusRelation(ProjectController c) {
    final col = c.selectedColumnId;
    final tid = c.selectedTableId;
    if (col == null || tid == null) return null;
    return c.project.relations.where((r) => r.fromTableId == tid && r.fromColumnId == col).firstOrNull?.id;
  }

  void _selectRelation(ProjectController c, String id) {
    final r = c.project.relations.where((r) => r.id == id).firstOrNull;
    if (r == null) return;
    c.selectTable(r.fromTableId);
    c.selectColumn(r.fromColumnId);
  }

  void _backgroundTap(BuildContext context, ProjectController c, CanvasController cv, Offset local) {
    final w = cv.toWorld(local);
    switch (cv.tool) {
      case CanvasTool.select:
        // คลิกโดนเส้น FK = เลือกคอลัมน์ FK นั้น (แผงขวาแสดงกล่อง Foreign Key พร้อมตัวเลือกสีเส้น)
        final rid = relationAt(c.project, w.dx, w.dy);
        if (rid != null) {
          _selectRelation(c, rid);
          return;
        }
        c.selectTable(null);
      case CanvasTool.table:
        final at = _placed(context, w);
        c.addTable(x: at.dx, y: at.dy);
        cv.setTool(CanvasTool.select);
      case CanvasTool.note:
        final at = _placed(context, w);
        cv.pendingNoteEditId = c.addNote(x: at.dx, y: at.dy).id;
        cv.setTool(CanvasTool.select);
      case CanvasTool.fk:
        cv.clearFkSource();
    }
  }
}

BoxDecoration get _panelDecoration => BoxDecoration(
      color: C.surface,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      border: Border.fromBorderSide(BorderSide(color: C.border)),
      boxShadow: C.shadowMd,
    );

class _ToolBar extends StatelessWidget {
  const _ToolBar();

  @override
  Widget build(BuildContext context) {
    final cv = context.watch<CanvasController>();
    Widget btn(String label, CanvasTool t, String tip) {
      final on = cv.tool == t;
      return Tooltip(
        message: tip,
        child: TextButton(
          onPressed: () => cv.setTool(t),
          style: TextButton.styleFrom(
            backgroundColor: on ? C.primaryTint : null,
            foregroundColor: on ? C.primaryDark : C.text,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(label),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: _panelDecoration,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(tr('เลือก'), CanvasTool.select, tr('โหมดเลือก (S)')),
        btn(tr('+ ตาราง'), CanvasTool.table, tr('เพิ่มตาราง (T)')),
        btn(tr('เชื่อม FK'), CanvasTool.fk, tr('โหมดเชื่อม FK (F)')),
        btn(tr('โน้ต'), CanvasTool.note, tr('เพิ่มโน้ต (N)')),
      ]),
    );
  }
}

/// กรอบเลือกสีหลักจาง ๆ ตอนลากบนพื้นว่าง
class _MarqueePainter extends CustomPainter {
  const _MarqueePainter(this.rect);
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = C.primary.withValues(alpha: C.isDark ? 0.18 : 0.10));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = C.primary.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_MarqueePainter old) => old.rect != rect;
}

enum _EdgeHintKind { willExtend, extending }

/// hint ตอนลากตารางเข้าใกล้/ชนขอบกระดาน — บอกผู้ใช้ว่ากระดานจะขยาย/ขยายอยู่
class _EdgeHint extends StatelessWidget {
  const _EdgeHint(this.kind);
  final _EdgeHintKind kind;

  @override
  Widget build(BuildContext context) {
    final extending = kind == _EdgeHintKind.extending;
    return Container(
      key: ValueKey(extending ? 'edge-hint-extending' : 'edge-hint-will-extend'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: extending ? C.primary : C.tableHead,
        borderRadius: BorderRadius.circular(8),
        boxShadow: C.shadowMd,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(extending ? Icons.open_in_full_rounded : Icons.expand_rounded, size: 16, color: Colors.white),
        const SizedBox(width: 8),
        Text(
          extending
              ? tr('กระดานกำลังขยายตามตารางที่ชนขอบ — ลากกลับเข้ามากระดานจะหดกลับ')
              : tr('ลากตารางชนขอบกระดานเพื่อขยายกระดาน'),
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
        ),
      ]),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.cv});
  final CanvasController cv;

  @override
  Widget build(BuildContext context) {
    final text = switch (cv.tool) {
      CanvasTool.table => tr('คลิกบนพื้นที่ว่างเพื่อวางตาราง (Esc ยกเลิก)'),
      CanvasTool.note => tr('คลิกบนพื้นที่ว่างเพื่อวางโน้ต (Esc ยกเลิก)'),
      CanvasTool.fk => cv.fkSource == null
          ? tr('คลิกคอลัมน์ที่จะเป็น FK (ฝั่งลูก)')
          : tr('คลิกคอลัมน์ที่ถูกอ้างถึง (ฝั่งแม่) — Esc ยกเลิก'),
      CanvasTool.select => '',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: C.primaryDark, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
    );
  }
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar();

  @override
  Widget build(BuildContext context) {
    final cv = context.watch<CanvasController>();
    final c = context.read<ProjectController>();
    final settings = context.watch<AppSettings>();
    Widget icon(String tip, IconData i, VoidCallback f) => Tooltip(
          message: tip,
          child: SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              onPressed: f,
              icon: Icon(i),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: _panelDecoration,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message: tr('จัดแนวตามตาราง (Snap) — กด Alt ค้างตอนลากเพื่อข้ามชั่วคราว'),
          child: SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              key: const ValueKey('snap-toggle'),
              padding: EdgeInsets.zero,
              iconSize: 16,
              isSelected: settings.snapToGrid,
              style: IconButton.styleFrom(
                backgroundColor: settings.snapToGrid ? C.primaryTint : null,
                foregroundColor: settings.snapToGrid ? C.primaryDark : C.muted,
              ),
              onPressed: () => settings.setSnapToGrid(!settings.snapToGrid),
              icon: const Icon(Icons.grid_4x4_rounded),
            ),
          ),
        ),
        const SizedBox(width: 2),
        icon(tr('ย่อ'), Icons.remove, () => cv.zoomCenter(1 / 1.2)),
        SizedBox(
          width: 48,
          child: Text('${(cv.scale * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
        ),
        icon(tr('ขยาย'), Icons.add, () => cv.zoomCenter(1.2)),
        TextButton(
          onPressed: () => cv.fit(c.project),
          style: TextButton.styleFrom(
            foregroundColor: C.primaryDark,
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
          child: Text(tr('พอดีหน้าจอ')),
        ),
      ]),
    );
  }
}

/// กด Space ค้างอยู่ -> ลากพื้นว่างเพื่อเลื่อนมุมมองแทนการลากกรอบเลือก
bool get _spaceDown => HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

/// ชั้นเส้น FK: ถ้าเปิดอนิเมชัน และมีเส้นที่เด่นอยู่ (ตารางที่เลือก/เส้นที่เลือก) จะมี Ticker วิ่งให้เส้นประไหลตามทิศทางข้อมูล
/// ไม่มีอะไรเด่น = ไม่วิ่ง (ไม่ปลุกเฟรมโดยเปล่าประโยชน์ และไม่กินแบตเตอรี่)
class _RelationLayer extends StatefulWidget {
  const _RelationLayer({
    required this.project,
    required this.selectedTableId,
    required this.focusRelationId,
    required this.showFlow,
    required this.animate,
    this.always = false,
    this.speed = FlowSpeed.normal,
  });

  final Project project;
  final String? selectedTableId;
  final String? focusRelationId;
  final bool showFlow;
  final bool animate;

  /// เส้นประวิ่งทุกเส้นตลอดเวลา (ไม่ต้องเลือกตาราง)
  final bool always;
  final FlowSpeed speed;

  @override
  State<_RelationLayer> createState() => _RelationLayerState();
}

class _RelationLayerState extends State<_RelationLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: widget.speed.cycle);

  bool get _wantAnimation =>
      widget.animate &&
      (widget.always || widget.selectedTableId != null || widget.focusRelationId != null) &&
      widget.project.relations.isNotEmpty;

  void _sync() {
    if (_ctl.duration != widget.speed.cycle) {
      _ctl.duration = widget.speed.cycle;
      if (_ctl.isAnimating) _ctl.repeat();
    }
    if (_wantAnimation) {
      if (!_ctl.isAnimating) _ctl.repeat();
    } else if (_ctl.isAnimating) {
      _ctl.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_RelationLayer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctl,
        builder: (context, _) => CustomPaint(
          painter: RelationPainter(
            widget.project,
            widget.selectedTableId,
            origin: CanvasController.worldOrigin,
            focusRelationId: widget.focusRelationId,
            flow: widget.showFlow,
            flowPhase: _wantAnimation ? _ctl.value : null,
            flowAll: widget.always,
          ),
        ),
      );
}
