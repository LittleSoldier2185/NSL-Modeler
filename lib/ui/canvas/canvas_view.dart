import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/project_controller.dart';
import '../theme.dart';
import 'canvas_controller.dart';
import 'relation_painter.dart';
import 'table_card.dart';

class CanvasView extends StatelessWidget {
  const CanvasView({super.key, required this.focusNode});

  /// โฟกัสของหน้าหลัก — ดึงกลับมาเมื่อคลิก canvas เพื่อให้คีย์ลัดทำงานต่อ
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final cv = context.watch<CanvasController>();

    return ClipRect(
      child: LayoutBuilder(builder: (context, box) {
        cv.viewport = box.biggest;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => focusNode.requestFocus(),
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _backgroundTap(c, cv, d.localPosition),
                onPanUpdate: (d) => cv.panBy(d.delta),
                child: ColoredBox(
                  color: C.canvas,
                  child: CustomPaint(
                    painter: DotsPainter(cv.scale, cv.offset),
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
                    cv.offset.dx, cv.offset.dy, 0, 1,
                  ),
                  child: SizedBox(
                    width: CanvasController.worldSize,
                    height: CanvasController.worldSize,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: RelationPainter(c.project, c.selectedTableId),
                        ),
                      ),
                      for (final t in c.project.tables) TableCard(key: ValueKey('table-${t.id}'), table: t),
                      for (final n in c.project.notes) NoteCard(key: ValueKey('note-${n.id}'), note: n),
                    ]),
                  ),
                ),
              ),
            ),
            const Positioned(left: 16, top: 16, child: _ToolBar()),
            if (cv.tool != CanvasTool.select)
              Positioned(left: 0, right: 0, top: 18, child: Center(child: _Hint(cv: cv))),
            const Positioned(right: 16, bottom: 16, child: _ZoomBar()),
          ]),
        );
      }),
    );
  }

  void _backgroundTap(ProjectController c, CanvasController cv, Offset local) {
    final w = cv.toWorld(local);
    switch (cv.tool) {
      case CanvasTool.select:
        c.selectTable(null);
      case CanvasTool.table:
        c.addTable(x: w.dx, y: w.dy);
        cv.setTool(CanvasTool.select);
      case CanvasTool.note:
        c.addNote(x: w.dx, y: w.dy);
        cv.setTool(CanvasTool.select);
      case CanvasTool.fk:
        cv.clearFkSource();
    }
  }
}

const _panelDecoration = BoxDecoration(
  color: C.surface,
  borderRadius: BorderRadius.all(Radius.circular(9)),
  border: Border.fromBorderSide(BorderSide(color: C.border)),
  boxShadow: [BoxShadow(color: Color(0x140F172A), blurRadius: 8, offset: Offset(0, 2))],
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
        btn('เลือก', CanvasTool.select, 'โหมดเลือก (Esc)'),
        btn('+ ตาราง', CanvasTool.table, 'เพิ่มตาราง (T)'),
        btn('เชื่อม FK', CanvasTool.fk, 'โหมดเชื่อม FK (F)'),
        btn('โน้ต', CanvasTool.note, 'เพิ่มโน้ต (N)'),
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
      CanvasTool.table => 'คลิกบนพื้นที่ว่างเพื่อวางตาราง (Esc ยกเลิก)',
      CanvasTool.note => 'คลิกบนพื้นที่ว่างเพื่อวางโน้ต (Esc ยกเลิก)',
      CanvasTool.fk => cv.fkSource == null
          ? 'คลิกคอลัมน์ที่จะเป็น FK (ฝั่งลูก)'
          : 'คลิกคอลัมน์ที่ถูกอ้างถึง (ฝั่งแม่) — Esc ยกเลิก',
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
        icon('ย่อ', Icons.remove, () => cv.zoomCenter(1 / 1.2)),
        SizedBox(
          width: 48,
          child: Text('${(cv.scale * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
        ),
        icon('ขยาย', Icons.add, () => cv.zoomCenter(1.2)),
        TextButton(
          onPressed: () => cv.fit(c.project),
          style: TextButton.styleFrom(
            foregroundColor: C.primaryDark,
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
          child: const Text('พอดีหน้าจอ'),
        ),
      ]),
    );
  }
}
