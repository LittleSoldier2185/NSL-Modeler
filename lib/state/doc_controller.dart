import 'package:flutter/foundation.dart';

import '../core/models/workspace.dart';
import 'snapshot_history.dart';

/// controller ของเอกสารหนึ่งชิ้นใน workspace: ถือ [doc] + ประวัติ undo/redo (แบบ snapshot ของเนื้อหาเอกสารนี้เท่านั้น)
/// + สถานะ "แก้แล้วยังไม่บันทึก" ของเอกสารนี้
///
/// ชนิดย่อยบอกวิธีทำ snapshot ([snapshot]) และวิธีใส่ snapshot กลับ ([restoreSnapshot])
abstract class DocController extends ChangeNotifier {
  DocController(this._doc);

  static const maxHistory = 100;

  ProjectDocument _doc;

  /// เอกสารที่ controller นี้ดูแล (object จริงใน workspace)
  ProjectDocument get doc => _doc;
  String get docId => _doc.id;

  /// ประวัติ undo/redo ของเอกสารนี้
  final SnapshotHistory history = SnapshotHistory(max: maxHistory);

  int _revision = 0;

  /// นับขึ้นทุกครั้งที่เนื้อหาเปลี่ยน (แก้/ลากสด/undo/redo) — ใช้เทียบว่าเนื้อหาเปลี่ยนหรือยัง
  int get revision => _revision;

  bool _docDirty = false;

  /// เอกสารนี้ถูกแก้หลังบันทึก/เปิดครั้งล่าสุด
  bool get docDirty => _docDirty;

  /// แก้แล้วยังไม่บันทึก (ของเอกสารนี้)
  bool get dirty => _docDirty;

  bool _disposed = false;
  bool get disposed => _disposed;

  /// เนื้อหาปัจจุบันเป็นข้อความ (ใช้เก็บในประวัติ)
  @protected
  String snapshot();

  /// ใส่เนื้อหาจาก [snap] กลับเข้า [doc] (object ใหม่)
  @protected
  void restoreSnapshot(String snap);

  /// เรียกหลัง undo/redo ใส่เนื้อหากลับแล้ว (เช่น ล้างการเลือกที่หายไป)
  @protected
  void afterRestore() {}

  /// ผูก controller กับเอกสารใหม่ (เปิดไฟล์ใหม่แต่ใช้ controller ตัวเดิม) — ล้างประวัติและสถานะ dirty
  @protected
  void rebind(ProjectDocument doc) {
    _doc = doc;
    history.clear();
    _docDirty = false;
    _revision++;
  }

  /// เนื้อหาเปลี่ยนและนับว่าแก้แล้ว
  @protected
  void markEdited() {
    _docDirty = true;
    _revision++;
  }

  /// เนื้อหาเปลี่ยนชั่วคราวระหว่างลาก (ยังไม่นับว่าแก้)
  @protected
  void markLive() => _revision++;

  /// บันทึกแล้ว / เปิดใหม่
  void markClean() => _docDirty = false;

  /// แก้เนื้อหาแบบมีประวัติ (undo ขั้นเดียว)
  @protected
  void editWithHistory(void Function() change) {
    history.push(snapshot());
    change();
    markEdited();
    notifyListeners();
  }

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  void undo() {
    if (!history.canUndo) return;
    _apply(history.undo(snapshot())!);
  }

  void redo() {
    if (!history.canRedo) return;
    _apply(history.redo(snapshot())!);
  }

  void _apply(String snap) {
    restoreSnapshot(snap);
    markEdited();
    afterRestore();
    notifyListeners();
  }

  /// กำลังลากอยู่ (ตั้งแต่ [beginGesture] ถึง [endGesture])
  bool get gestureActive => history.gestureActive;

  /// เริ่มลาก: การแก้สดจนถึง [endGesture] นับเป็น undo ขั้นเดียว
  void beginGesture() {
    if (history.gestureActive) return;
    history.beginGesture(snapshot());
  }

  /// จบการลาก — คืน true ถ้าเนื้อหาเปลี่ยน (เก็บเข้าประวัติแล้ว)
  bool endGesture() {
    if (!history.gestureActive) return false;
    final changed = history.endGesture(snapshot());
    if (changed) markEdited();
    notifyListeners();
    return changed;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
