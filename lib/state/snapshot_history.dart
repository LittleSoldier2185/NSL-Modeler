/// ประวัติ undo/redo แบบ snapshot (ข้อความ JSON ของเนื้อหาทั้งชิ้น) ของเอกสารหนึ่งชิ้น
///
/// - [push] เก็บสถานะก่อนแก้ (เกิน [max] ทิ้งอันเก่าสุด) และล้าง redo
/// - การลาก: [beginGesture] จดสถานะก่อนลาก, [endGesture] เก็บเป็นขั้นเดียวเฉพาะเมื่อเนื้อหาเปลี่ยน
class SnapshotHistory {
  SnapshotHistory({this.max = 100});

  final int max;
  final List<String> _undo = [];
  final List<String> _redo = [];
  String? _gestureBefore;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoLength => _undo.length;
  int get redoLength => _redo.length;

  /// กำลังลากอยู่ (ระหว่าง [beginGesture] กับ [endGesture])
  bool get gestureActive => _gestureBefore != null;

  void push(String snap) {
    _undo.add(snap);
    if (_undo.length > max) _undo.removeAt(0);
    _redo.clear();
  }

  /// ถอยหนึ่งขั้น: เก็บ [current] ไว้ใน redo แล้วคืนสถานะก่อนหน้า ; null = ไม่มีให้ถอย
  String? undo(String current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  /// ทำซ้ำหนึ่งขั้น: เก็บ [current] ไว้ใน undo แล้วคืนสถานะถัดไป ; null = ไม่มีให้ทำซ้ำ
  String? redo(String current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }

  /// เริ่มลาก (ซ้อนกันไม่ได้ — ถ้ากำลังลากอยู่แล้วไม่ทำอะไร)
  void beginGesture(String before) {
    _gestureBefore ??= before;
  }

  /// จบการลาก: เก็บสถานะก่อนลากเป็นหนึ่งขั้นถ้า [current] ต่างจากเดิม — คืน true ถ้าเก็บ
  bool endGesture(String current) {
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before == null || before == current) return false;
    push(before);
    return true;
  }

  /// ยกเลิกการลากที่ค้างอยู่โดยไม่เก็บอะไร
  void cancelGesture() => _gestureBefore = null;

  void clear() {
    _undo.clear();
    _redo.clear();
    _gestureBefore = null;
  }
}
