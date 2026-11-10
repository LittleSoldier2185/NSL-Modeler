import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/layout/dfd_resize.dart' show DfdHandle, dfdHandlePos;
import '../../core/layout/diagram_geometry.dart' show kGridSize;
import '../../state/app_settings.dart';
import '../../state/box_diagram_controller.dart';
import '../theme.dart';
import 'dot_grid_painter.dart';

/// ผลการคลิกบนแคนวาส: กล่อง [box] หรือเส้น [edge] (ไม่โดนอะไร = ทั้งคู่ null)
typedef BoxHit = ({String? box, String? edge});

enum _Drag { none, move, marquee, pan, resize }

/// ฐานร่วมของแคนวาสแผนภาพแบบกล่อง (Wireframe, Screen Flow): เลื่อน/ซูม (ล้อเมาส์, Ctrl+ล้อ, เมาส์กลาง, Space+ลาก),
/// คลิกเลือก/Ctrl-Shift คลิก, ดับเบิลคลิก, ลากย้าย, จุดจับปรับขนาด, กรอบลากเลือก, ลากของจากแผงซ้ายมาวาง, เมนูคลิกขวา
///
/// ชนิดย่อยกำหนดเฉพาะส่วนที่ต่างกัน: การคลิกโดน, เครื่องมือวาง, เมนู, ตัววาด และของที่วางทับ (ช่องพิมพ์ แถบเครื่องมือ ฯลฯ)
abstract class BoxCanvasState<W extends StatefulWidget, Ctl extends BoxDiagramController> extends State<W> {
  _Drag _drag = _Drag.none;
  Offset? _marqueeStart, _marqueeEnd;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastTapId;
  Set<String> _marqueeBase = const {};
  final _stackKey = GlobalKey();

  /// ตำแหน่งเมาส์ (พิกัดแผนภาพ) ขณะลากเส้น — ใช้วาดเส้นตามเมาส์
  final ValueNotifier<Offset?> cursor = ValueNotifier(null);

  @override
  void dispose() {
    cursor.dispose();
    super.dispose();
  }

  // ---------- ส่วนที่ชนิดย่อยกำหนด ----------

  /// โฟกัสของหน้าหลัก (รับคีย์ลัด) — ขอกลับมาทุกครั้งที่คลิกบนแคนวาส
  FocusNode? get focusNode;

  /// key ของพื้นที่รับเมาส์ (ใช้ในเทสต์)
  String get canvasKey;

  Ctl get ctl => context.read<Ctl>();

  BoxHit hitTest(Ctl c, Offset world);

  /// อยู่ในเครื่องมือเลือกหรือไม่ (ไม่ใช่ = คลิกแล้วส่งให้ [toolTap])
  bool isSelectTool(Ctl c);

  /// คลิกด้วยเครื่องมือที่ไม่ใช่เครื่องมือเลือก
  void toolTap(Ctl c, Offset world, BoxHit hit);

  /// คลิกขวาขณะใช้เครื่องมืออื่น = กลับเครื่องมือเลือก
  void resetTool(Ctl c);

  /// เลือกเส้น (แผนภาพที่ไม่มีเส้นไม่ต้องทำอะไร)
  void selectEdge(Ctl c, String id) {}

  /// ดับเบิลคลิก (ค่าเริ่มต้น = พิมพ์ข้อความของกล่อง/เส้น)
  void doubleTap(Ctl c, BoxHit hit) {
    if (hit.box != null) {
      c.beginEdit(hit.box!);
    } else if (hit.edge != null) {
      c.beginEdit(hit.edge!, isEdge: true);
    }
  }

  void contextMenu(Ctl c, TapDownDetails t, Offset world, BoxHit hit);

  /// วางของที่ลากมาจากแผงซ้าย ([data]) ที่จุด [world]
  void drop(Ctl c, Object data, Offset world);

  /// ชนิดข้อมูลที่รับจากการลากวาง
  bool acceptsDrop(Object? data);

  CustomPainter foregroundPainter(Ctl c, Rect? marquee);

  /// ของที่วางทับแคนวาส (ช่องพิมพ์ แถบเครื่องมือ แถบซูม ข้อความตอนว่าง ฯลฯ)
  List<Widget> overlays(Ctl c, Size size);

  /// เคอร์เซอร์ขณะใช้เครื่องมือ
  MouseCursor toolCursor(Ctl c) => SystemMouseCursors.precise;

  /// ต้องติดตามเมาส์ (เช่น กำลังลากเส้น)
  bool trackCursor(Ctl c) => false;

  // ---------- การทำงานร่วม ----------

  bool get _ctrlOrShift => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
  bool get _spaceDown => HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space);
  bool get snap => context.read<AppSettings>().snapToGrid;

  void _tapUp(Offset local) {
    focusNode?.requestFocus();
    final c = ctl;
    // กำลังพิมพ์อยู่: คลิกนี้ใช้จบการพิมพ์อย่างเดียว (ช่องพิมพ์เสียโฟกัสแล้วบันทึกเอง)
    if (c.editing != null) return;
    final world = c.toWorld(local);
    final hit = hitTest(c, world);
    if (!isSelectTool(c)) {
      toolTap(c, world, hit);
      return;
    }
    final now = clock.now();
    final id = hit.box ?? hit.edge;
    final dbl = id != null && id == _lastTapId && now.difference(_lastTap).inMilliseconds < 400;
    _lastTap = now;
    _lastTapId = id;
    if (hit.box != null) {
      c.selectBox(hit.box!, add: _ctrlOrShift && !dbl);
    } else if (hit.edge != null) {
      selectEdge(c, hit.edge!);
    } else {
      c.clearSelection();
    }
    if (dbl) doubleTap(c, hit);
  }

  void _secondary(TapDownDetails t) {
    final c = ctl;
    if (c.editing != null) return;
    if (!isSelectTool(c)) {
      resetTool(c);
      return;
    }
    final world = c.toWorld(t.localPosition);
    contextMenu(c, t, world, hitTest(c, world));
  }

  void _panStart(DragStartDetails s) {
    final c = ctl;
    _marqueeBase = _ctrlOrShift ? c.selectedIds : const {};
    if (c.editing != null) {
      _drag = _Drag.none;
      return;
    }
    if (_spaceDown) {
      _drag = _Drag.pan;
      return;
    }
    if (!isSelectTool(c)) {
      _drag = _Drag.none;
      return;
    }
    final world = c.toWorld(s.localPosition);
    final handle = c.handleAt(world);
    if (handle != null) {
      c.beginResize(handle);
      _drag = _Drag.resize;
      return;
    }
    final hit = hitTest(c, world);
    if (hit.box != null) {
      if (!c.selectedIds.contains(hit.box)) c.selectBox(hit.box!, add: _ctrlOrShift);
      c.beginMove();
      _drag = _Drag.move;
    } else {
      _drag = _Drag.marquee;
      _marqueeStart = s.localPosition;
      _marqueeEnd = s.localPosition;
      if (!_ctrlOrShift) c.clearSelection();
    }
  }

  void _panUpdate(DragUpdateDetails u) {
    final c = ctl;
    final grid = snap ? kGridSize : null;
    switch (_drag) {
      case _Drag.pan:
        c.panBy(u.delta);
      case _Drag.move:
        c.moveBy(u.delta.dx / c.scale, u.delta.dy / c.scale, grid: grid);
      case _Drag.resize:
        c.resizeBy(u.delta.dx / c.scale, u.delta.dy / c.scale, grid: grid);
      case _Drag.marquee:
        setState(() => _marqueeEnd = u.localPosition);
        final r = Rect.fromPoints(c.toWorld(_marqueeStart!), c.toWorld(_marqueeEnd!));
        c.setSelection({
          ..._marqueeBase,
          for (final b in c.boxes)
            if (r.overlaps(Rect.fromLTWH(b.x, b.y, b.w, b.h))) b.id,
        });
      case _Drag.none:
        break;
    }
  }

  void _panEnd() {
    final c = ctl;
    if (_drag == _Drag.move) c.endMove();
    if (_drag == _Drag.resize) c.endResize();
    setState(() {
      _drag = _Drag.none;
      _marqueeStart = null;
      _marqueeEnd = null;
    });
  }

  void _drop(Object data, Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final c = ctl;
    drop(c, data, c.toWorld(box.globalToLocal(global)));
    focusNode?.requestFocus();
  }

  /// สี่เหลี่ยมพิกัดแผนภาพ -> พิกัดจอของแคนวาส
  Rect toScreenRect(Ctl c, Rect world) => Rect.fromPoints(c.toScreen(world.topLeft), c.toScreen(world.bottomRight));

  @override
  Widget build(BuildContext context) {
    final c = context.watch<Ctl>();
    final marquee = _marqueeStart == null ? null : Rect.fromPoints(_marqueeStart!, _marqueeEnd ?? _marqueeStart!);
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      c.viewport = size;
      return DragTarget<Object>(
        onWillAcceptWithDetails: (d) => acceptsDrop(d.data),
        onAcceptWithDetails: (d) => _drop(d.data, d.offset + const Offset(28, 20)),
        builder: (context, cand, _) => Listener(
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            if (HardwareKeyboard.instance.isControlPressed) {
              c.zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
            } else {
              c.panBy(-e.scrollDelta);
            }
          },
          onPointerMove: (e) {
            if (e.buttons == kMiddleMouseButton) c.panBy(e.delta);
          },
          onPointerHover: (e) {
            if (trackCursor(c)) cursor.value = c.toWorld(e.localPosition);
          },
          child: MouseRegion(
            cursor: isSelectTool(c)
                ? (_drag == _Drag.pan ? SystemMouseCursors.grabbing : SystemMouseCursors.basic)
                : toolCursor(c),
            child: Stack(key: _stackKey, children: [
              Positioned.fill(
                child: GestureDetector(
                  key: ValueKey(canvasKey),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (t) => _tapUp(t.localPosition),
                  onSecondaryTapDown: _secondary,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: _panStart,
                  onPanUpdate: _panUpdate,
                  onPanEnd: (_) => _panEnd(),
                  onPanCancel: _panEnd,
                  child: CustomPaint(
                    painter: DotGridPainter(c.offset, c.scale),
                    foregroundPainter: foregroundPainter(c, marquee),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (cand.isNotEmpty) IgnorePointer(child: Container(color: C.primary.withValues(alpha: 0.05))),
              ...overlays(c, size),
            ]),
          ),
        ),
      );
    });
  }
}

/// วาดจุดจับ 8 ทิศรอบกล่อง [r] (พิกัดแผนภาพ ; ผู้เรียก translate/scale แล้ว)
void paintResizeHandles(Canvas canvas, Rect r, double scale) {
  final hs = 4.5 / scale;
  for (final h in DfdHandle.values) {
    final box = Rect.fromCenter(center: dfdHandlePos(r, h), width: hs * 2, height: hs * 2);
    canvas.drawRect(box, Paint()..color = C.surface);
    canvas.drawRect(box, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 / scale
      ..color = C.primary);
  }
}

/// วาดกรอบลากเลือก (พิกัดจอ)
void paintMarquee(Canvas canvas, Rect? m) {
  if (m == null) return;
  canvas.drawRect(m, Paint()..color = C.primary.withValues(alpha: 0.10));
  canvas.drawRect(m, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = C.primary);
}
