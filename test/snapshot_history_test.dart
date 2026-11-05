import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/state/snapshot_history.dart';

void main() {
  test('push / undo / redo เดินหน้าถอยหลังได้ถูกลำดับ', () {
    final h = SnapshotHistory();
    expect(h.canUndo, isFalse);
    expect(h.undo('x'), isNull);
    expect(h.redo('x'), isNull);
    h.push('a');
    h.push('b');
    expect(h.undo('c'), 'b');
    expect(h.undo('b'), 'a');
    expect(h.canUndo, isFalse);
    expect(h.redo('a'), 'b');
    expect(h.redo('b'), 'c');
    expect(h.canRedo, isFalse);
    expect(h.undoLength, 2);
  });

  test('push ใหม่ล้าง redo', () {
    final h = SnapshotHistory()..push('a');
    h.undo('b');
    expect(h.canRedo, isTrue);
    h.push('z');
    expect(h.canRedo, isFalse);
    expect(h.undo('q'), 'z');
  });

  test('เกิน max ทิ้งอันเก่าสุด (ค่าเริ่มต้น 100)', () {
    final h = SnapshotHistory();
    for (var i = 0; i < 105; i++) {
      h.push('$i');
    }
    expect(h.undoLength, 100);
    String? last;
    for (var s = h.undo('cur'); s != null; s = h.undo(s)) {
      last = s;
    }
    expect(last, '5');
    final small = SnapshotHistory(max: 2)
      ..push('1')
      ..push('2')
      ..push('3');
    expect(small.undoLength, 2);
  });

  test('gesture: เก็บขั้นเดียวเมื่อเปลี่ยน ไม่เก็บถ้าเหมือนเดิม และซ้อนกันไม่ได้', () {
    final h = SnapshotHistory();
    h.beginGesture('a');
    expect(h.gestureActive, isTrue);
    h.beginGesture('ignored');
    expect(h.endGesture('a'), isFalse);
    expect(h.gestureActive, isFalse);
    expect(h.canUndo, isFalse);

    h.beginGesture('a');
    expect(h.endGesture('b'), isTrue);
    expect(h.undo('b'), 'a');

    expect(h.endGesture('zzz'), isFalse, reason: 'ไม่ได้เริ่มลาก');
  });

  test('gesture ที่เก็บแล้วล้าง redo; cancel / clear ไม่เก็บอะไร', () {
    final h = SnapshotHistory()..push('a');
    h.undo('b');
    h.beginGesture('a');
    h.endGesture('c');
    expect(h.canRedo, isFalse);

    h.beginGesture('x');
    h.cancelGesture();
    expect(h.gestureActive, isFalse);
    expect(h.endGesture('y'), isFalse);

    h.beginGesture('x');
    h.clear();
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isFalse);
    expect(h.gestureActive, isFalse);
  });
}
