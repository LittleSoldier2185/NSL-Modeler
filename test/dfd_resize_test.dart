import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/layout/dfd_resize.dart';
import 'package:nsl_modeler/core/models/dfd_model.dart';
import 'package:nsl_modeler/core/models/diagram.dart';
import 'package:nsl_modeler/state/dfd_controller.dart';
import 'package:nsl_modeler/state/project_controller.dart';

import 'migration_fixtures.dart';

void main() {
  const r = Rect.fromLTWH(100, 100, 200, 100);

  group('resizeDfdRect', () {
    test('มุมขวาล่าง: ขอบซ้าย/บนอยู่กับที่', () {
      final n = resizeDfdRect(r, DfdHandle.se, 40, 20);
      expect((n.left, n.top, n.width, n.height), (100, 100, 240, 120));
    });

    test('มุมซ้ายบน: ขอบขวา/ล่างอยู่กับที่', () {
      final n = resizeDfdRect(r, DfdHandle.nw, -30, -10);
      expect((n.right, n.bottom, n.width, n.height), (300, 200, 230, 110));
    });

    test('กึ่งกลางด้านขยับได้แกนเดียว', () {
      final e = resizeDfdRect(r, DfdHandle.e, 50, 999);
      expect((e.width, e.height), (250, 100));
      final s = resizeDfdRect(r, DfdHandle.s, 999, 30);
      expect((s.width, s.height), (200, 130));
    });

    test('ไม่เล็กกว่าขั้นต่ำและไม่ใหญ่กว่าขั้นสูงสุด ; ขอบฝั่งตรงข้ามไม่ขยับ', () {
      final small = resizeDfdRect(r, DfdHandle.w, 500, 0);
      expect(small.width, kDfdMinW);
      expect(small.right, 300);
      final big = resizeDfdRect(r, DfdHandle.e, 5000, 0);
      expect(big.width, kDfdMaxSide);
      expect(big.left, 100);
      final tiny = resizeDfdRect(r, DfdHandle.n, 0, 900);
      expect((tiny.height, tiny.bottom), (kDfdMinH, 200));
    });

    test('ปัดเข้าช่องเมื่อกำหนด grid', () {
      final n = resizeDfdRect(r, DfdHandle.se, 13, 7, grid: 20);
      expect((n.right, n.bottom), (320.0, 200.0)); // ขวา 313->320 , ล่าง 207->200
    });
  });

  test('dfdHandleAt เลือกจุดจับใกล้สุดในรัศมี', () {
    final n = DfdNode(id: 'a', kind: DfdKind.process, x: 100, y: 100, w: 200, h: 100);
    expect(dfdHandleAt(n, const Offset(301, 201), 8), DfdHandle.se);
    expect(dfdHandleAt(n, const Offset(200, 99), 8), DfdHandle.n);
    expect(dfdHandleAt(n, const Offset(200, 150), 8), isNull);
  });

  group('DfdController', () {
    late ProjectController pc;
    late DfdController d;
    late DfdNode n;

    setUp(() {
      pc = ProjectController(base());
      d = DfdController(pc);
      pc.addDiagram(DiagramKind.dfd);
      n = d.addNode(DfdKind.process, 300, 200)!;
    });

    DfdNode cur() => pc.project.dfdOf(pc.activeDiagramId).nodeById(n.id)!;

    test('ลากจุดจับ = ปรับขนาดสด และ undo กลับขั้นเดียว', () {
      final w0 = cur().w, h0 = cur().h;
      final h = d.handleAt(Offset(n.right, n.bottom))!;
      expect(h, DfdHandle.se);
      d.beginResize(h);
      d.resizeBy(30, 0);
      d.resizeBy(0, 20);
      d.endResize();
      expect((cur().w, cur().h), (w0 + 30, h0 + 20));
      pc.undo();
      expect((cur().w, cur().h), (w0, h0));
    });

    test('เลือกหลายตัวหรือไม่ได้เลือก = ไม่มีจุดจับ', () {
      d.clearSelection();
      expect(d.handleAt(Offset(n.right, n.bottom)), isNull);
    });
  });
}
