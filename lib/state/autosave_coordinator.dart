import 'dart:async';

import '../core/storage/project_codec.dart';
import '../core/storage/autosave.dart';
import 'workspace_controller.dart';

/// ดูแลการ auto-save: เมื่อมีงานที่ยังไม่บันทึก จะเขียนสำเนาไว้เป็นระยะ
/// และลบสำเนาทิ้งทันทีที่บันทึกจริง / เริ่มโปรเจกต์ใหม่ / เปิดไฟล์
///
/// - [debounce]: เขียนเมื่อผู้ใช้หยุดแก้ครบเวลานี้
/// - [maxWait]: ถ้าแก้ต่อเนื่องไม่หยุด จะเขียนอย่างช้าที่สุดทุกช่วงนี้
class AutosaveCoordinator {
  AutosaveCoordinator(
    this.controller,
    this.store, {
    this.debounce = const Duration(seconds: 3),
    this.maxWait = const Duration(seconds: 30),
    this.onWrite,
  }) {
    controller.addListener(_onChange);
  }

  /// โปรเจกต์ที่ดูแล (ได้ยินการแก้ของทุกเอกสาร)
  final WorkspaceController controller;
  final AutosaveStore store;
  final Duration debounce;
  final Duration maxWait;

  /// เรียกหลังเขียนสำเร็จ (ใช้ในเทสต์)
  final void Function()? onWrite;

  Timer? _debounceTimer;
  Timer? _maxTimer;
  bool _disposed = false;
  bool _hadDirty = false;
  Future<void> _chain = Future.value(); // เรียงลำดับ I/O ไม่ให้เขียน/ลบสลับกัน

  /// error ล่าสุดของการเขียน (ไม่แสดงให้ผู้ใช้ — auto-save ล้มเหลวต้องไม่รบกวนการทำงาน)
  Object? lastError;

  void _onChange() {
    if (_disposed) return;
    if (controller.dirty) {
      _hadDirty = true;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, _writeNow);
      _maxTimer ??= Timer(maxWait, _writeNow);
    } else {
      _cancelTimers();
      if (_hadDirty) {
        _hadDirty = false;
        _enqueue(store.clear); // บันทึกแล้ว/เริ่มใหม่ -> ไม่ต้องมีสำเนา
      }
    }
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _maxTimer?.cancel();
    _debounceTimer = null;
    _maxTimer = null;
  }

  void _writeNow() {
    _cancelTimers();
    if (_disposed || !controller.dirty) return;
    final workspace = controller.workspace;
    final path = controller.filePath;
    // สำเนา ณ ตอนนี้ (โปรเจกต์อาจถูกแก้ต่อระหว่างรอคิว I/O)
    final snapshot = copyWorkspace(workspace);
    _enqueue(() async {
      try {
        await store.write(snapshot, originalPath: path);
        lastError = null;
        onWrite?.call();
      } catch (e) {
        lastError = e;
      }
    });
  }

  void _enqueue(Future<void> Function() job) {
    _chain = _chain.then((_) => job()).catchError((Object e) {
      lastError = e;
    });
  }

  /// เขียนทันที (เช่น ตอนจะปิดโปรแกรม) และรอจนเสร็จ
  Future<void> flush() async {
    if (controller.dirty) _writeNow();
    await _chain;
  }

  /// ผู้ใช้เลือกไม่กู้คืน -> ลบสำเนาทิ้ง
  Future<void> discard() {
    _enqueue(store.clear);
    return _chain;
  }

  /// รอให้งาน I/O ที่ค้างอยู่เสร็จ (ไว้เทสต์)
  Future<void> idle() => _chain;

  void dispose() {
    _disposed = true;
    _cancelTimers();
    controller.removeListener(_onChange);
  }
}
