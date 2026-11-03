import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/layout/diagram_geometry.dart';
import '../../core/models/project.dart';
import '../../core/models/table_model.dart';

enum CanvasTool { select, table, fk, note }

enum DockTab { sql, issues }

/// ขนาดคงที่ของการ์ดตาราง (ใช้ทั้งตอนวาดการ์ดและตอนคำนวณจุดต่อเส้น FK)
class CardMetrics {
  static const header = kCardHeaderHeight;
  static const row = kCardRowHeight;
  static double height(int columns) => header + row * columns;
  static double rowCenterY(double tableY, int index) => tableY + header + row * index + row / 2;
}

/// state ของมุมมอง canvas (ไม่เกี่ยวกับข้อมูลโปรเจกต์ จึงไม่เข้า undo)
class CanvasController extends ChangeNotifier {
  static const minScale = 0.25;
  static const maxScale = 2.0;
  static const worldSize = 20000.0;

  double _scale = 1;
  Offset _offset = Offset.zero;
  CanvasTool _tool = CanvasTool.select;
  ({String tableId, String columnId})? _fkSource;

  DockTab _dockTab = DockTab.sql;
  bool _dockCollapsed = false;

  DockTab get dockTab => _dockTab;
  bool get dockCollapsed => _dockCollapsed;

  /// เปิดแท็บของ dock (และขยาย dock ถ้าย่ออยู่)
  void showDock(DockTab t) {
    _dockTab = t;
    _dockCollapsed = false;
    notifyListeners();
  }

  void toggleDockCollapsed() {
    _dockCollapsed = !_dockCollapsed;
    notifyListeners();
  }

  /// ขนาดพื้นที่แสดง canvas (กำหนดโดย widget ตอน layout)
  Size viewport = Size.zero;

  double get scale => _scale;
  Offset get offset => _offset;
  CanvasTool get tool => _tool;
  ({String tableId, String columnId})? get fkSource => _fkSource;

  /// จุดบนจอ -> จุดใน world
  Offset toWorld(Offset screen) => (screen - _offset) / _scale;

  void setTool(CanvasTool t) {
    if (t == _tool && _fkSource == null) return;
    _tool = t;
    _fkSource = null;
    notifyListeners();
  }

  void setFkSource(String tableId, String columnId) {
    _fkSource = (tableId: tableId, columnId: columnId);
    notifyListeners();
  }

  void clearFkSource() {
    if (_fkSource == null) return;
    _fkSource = null;
    notifyListeners();
  }

  void panBy(Offset d) {
    _offset += d;
    notifyListeners();
  }

  /// ซูมโดยให้จุด [focal] (พิกัดจอ) อยู่ที่เดิม
  void zoomAt(Offset focal, double factor) {
    final next = (_scale * factor).clamp(minScale, maxScale);
    if (next == _scale) return;
    final k = next / _scale;
    _offset = focal - (focal - _offset) * k;
    _scale = next;
    notifyListeners();
  }

  void zoomCenter(double factor) => zoomAt(viewport.center(Offset.zero), factor);

  void resetZoom() {
    zoomAt(viewport.center(Offset.zero), 1 / _scale);
  }

  /// เลื่อนมุมมองให้จุด [worldPoint] อยู่กลางจอ (ถ้าซูมออกไกลเกินไปจะซูมเข้าให้อ่านออกอย่างน้อย [atLeastScale])
  void centerOn(Offset worldPoint, {double? atLeastScale}) {
    if (atLeastScale != null && _scale < atLeastScale) {
      _scale = atLeastScale.clamp(minScale, maxScale);
    }
    _offset = viewport.center(Offset.zero) - worldPoint * _scale;
    notifyListeners();
  }

  /// กระโดดไปที่ตาราง (ใช้จากช่องค้นหา / command palette)
  void focusTable(TableModel t) =>
      centerOn(Offset(t.x + t.width / 2, t.y + tableHeight(t) / 2), atLeastScale: 0.6);

  /// ช่องค้นหาตาราง/คอลัมน์ทางซ้าย — Ctrl+F ดึงโฟกัสมาที่นี่
  final searchFocus = FocusNode(debugLabel: 'search');

  @override
  void dispose() {
    searchFocus.dispose();
    super.dispose();
  }

  /// จัดให้เห็นทุกตาราง/โน้ตพอดีหน้าจอ
  void fit(Project p, {double padding = 48}) {
    Rect? box;
    void add(Rect r) => box = box == null ? r : box!.expandToInclude(r);
    for (final t in p.tables) {
      add(Rect.fromLTWH(t.x, t.y, t.width, CardMetrics.height(t.columns.length)));
    }
    for (final n in p.notes) {
      add(Rect.fromLTWH(n.x, n.y, n.width, 80));
    }
    final b = box;
    if (b == null || viewport.isEmpty) {
      _scale = 1;
      _offset = Offset.zero;
    } else {
      final s = math
          .min((viewport.width - padding * 2) / b.width, (viewport.height - padding * 2) / b.height)
          .clamp(minScale, 1.5);
      _scale = s;
      _offset = Offset(
        (viewport.width - b.width * s) / 2 - b.left * s,
        (viewport.height - b.height * s) / 2 - b.top * s,
      );
    }
    notifyListeners();
  }
}
