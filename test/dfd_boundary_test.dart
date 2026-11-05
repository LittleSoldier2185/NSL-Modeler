import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/dfd_svg.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/diagram.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/state/dfd_controller.dart';
import 'package:nsl_dev/state/project_controller.dart';

import 'migration_fixtures.dart';

void main() {
  late ProjectController pc;
  late DfdController d;
  late String tab;
  late DfdNode a, b;

  setUp(() {
    pc = ProjectController(base());
    d = DfdController(pc);
    tab = pc.addDiagram(DiagramKind.dfd)!.id;
    a = d.addNode(DfdKind.process, 200, 200)!;
    b = d.addNode(DfdKind.store, 500, 200)!;
  });

  DfdDiagram dia() => pc.project.dfdOf(tab);

  test('ครอบวัตถุที่เลือกด้วยขอบเขต: ครอบคลุมทุกตัวพร้อมเผื่อขอบ และถูกเลือก', () {
    d.setNodeSelection({a.id, b.id});
    final k = d.addBoundaryAround(name: 'ระบบขาย')!;
    expect(dia().boundaries.single.name, 'ระบบขาย');
    for (final n in [a, b]) {
      expect(k.x, lessThan(n.x));
      expect(k.y + kDfdBoundaryLabelH, lessThan(n.y));
      expect(k.right, greaterThan(n.right));
      expect(k.bottom, greaterThan(n.bottom));
    }
    expect(d.selectedBoundaryId, k.id);
    expect(d.selectedNodeIds, isEmpty);
    pc.undo();
    expect(dia().boundaries, isEmpty);
  });

  test('ไม่ได้เลือกวัตถุ = ครอบไม่ได้ ; วางเปล่าที่จุดที่ชี้ได้', () {
    d.clearSelection();
    expect(d.addBoundaryAround(), isNull);
    final k = d.addBoundaryAt(400, 400)!;
    expect(k.x + k.w / 2, 400);
  });

  test('ลากขอบเขต: วัตถุที่อยู่ในกรอบเลื่อนตาม วัตถุนอกกรอบอยู่ที่เดิม และ undo ขั้นเดียว', () {
    d.setNodeSelection({a.id});
    final k = d.addBoundaryAround()!;
    final outside = d.addNode(DfdKind.entity, 1200, 900)!;
    final ax = a.x, ay = a.y, ox = outside.x;
    d.selectBoundary(k.id);
    d.beginBoundaryMove();
    d.moveBoundaryBy(30, 10);
    d.moveBoundaryBy(10, 10);
    d.endBoundaryMove();
    expect((dia().nodeById(a.id)!.x, dia().nodeById(a.id)!.y), (ax + 40, ay + 20));
    expect(dia().nodeById(outside.id)!.x, ox);
    expect(dia().boundaryById(k.id)!.x, k.x);
    pc.undo();
    expect((dia().nodeById(a.id)!.x, dia().nodeById(a.id)!.y), (ax, ay));
  });

  test('ปรับขนาดขอบเขตด้วยจุดจับ ไม่เล็กเกินขั้นต่ำ และเกิน 600 ได้', () {
    final k = d.addBoundaryAt(300, 300)!;
    final w0 = k.w; // k เป็นออบเจ็กต์เดียวกับในแผนภาพ จึงต้องจำค่าก่อนแก้สด
    final h = d.handleAt(Offset(k.right, k.bottom))!;
    d.beginResize(h);
    d.resizeBy(900, 0);
    d.endResize();
    expect(dia().boundaryById(k.id)!.w, w0 + 900);
    d.beginResize(h);
    d.resizeBy(-5000, -5000);
    d.endResize();
    expect(dia().boundaryById(k.id)!.w, 80);
  });

  test('คลิกที่ขอบ/แถบชื่อโดน แต่ข้างในกรอบคลิกทะลุ', () {
    final k = d.addBoundaryAt(300, 300)!;
    expect(dfdBoundaryAt(dia(), k.x, k.y + 100), isNotNull); // ขอบซ้าย
    expect(dfdBoundaryAt(dia(), k.x + 100, k.y + 10), isNotNull); // แถบชื่อ
    expect(dfdBoundaryAt(dia(), k.x + k.w / 2, k.y + k.h / 2), isNull); // ข้างใน
    expect(dfdBoundaryAt(dia(), k.x - 200, k.y), isNull);
  });

  test('ลบขอบเขต ไม่ลบวัตถุข้างใน ; เปลี่ยนชื่อ/สี undo ได้', () {
    d.setNodeSelection({a.id});
    final k = d.addBoundaryAround()!;
    d.renameBoundary(k.id, 'X');
    d.setBoundaryColor(k.id, 0xFF112233);
    expect((dia().boundaryById(k.id)!.name, dia().boundaryById(k.id)!.color), ('X', 0xFF112233));
    d.selectBoundary(k.id);
    expect(d.deleteSelection(), 1);
    expect(dia().boundaries, isEmpty);
    expect(dia().nodeById(a.id), isNotNull);
  });

  test('บันทึก-โหลดไฟล์: ขอบเขตอยู่ครบ ; ข้อมูลผิดปกติถูกข้าม', () {
    d.setNodeSelection({a.id});
    final k = d.addBoundaryAround(name: 'B')!;
    final back = ProjectFile.decode(ProjectFile.encode(pc.project));
    final bk = back.dfdOf(tab).boundaries.single;
    expect((bk.id, bk.name, bk.w), (k.id, 'B', k.w));
    final bad = DfdDiagram.fromJson({
      'boundaries': [
        {'id': 'ok', 'w': 'x', 'h': -5},
        {'id': 'ok'},
        {'name': 'no id'},
        5,
      ]
    });
    expect(bad.boundaries.length, 1);
    expect(bad.boundaries.single.w, 300);
    expect(bad.boundaries.single.h, 200);
  });

  test('SVG มีกรอบเส้นประและชื่อ ; มีแต่ขอบเขตก็ export ได้', () {
    d.setNodeSelection({a.id});
    d.addBoundaryAround(name: 'ระบบขาย');
    final svg = exportDfdSvg(dia())!;
    expect(svg, contains('stroke-dasharray'));
    expect(svg, contains('ระบบขาย'));
    final only = DfdDiagram(boundaries: [DfdBoundary(id: 'k', name: 'solo')]);
    expect(exportDfdSvg(only), isNotNull);
  });
}
