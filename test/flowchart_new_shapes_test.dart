import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/flowchart_svg.dart';
import 'package:nsl_dev/core/layout/flowchart_geometry.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/validate/flowchart_validator.dart';

/// รูปทรงเพิ่มเติมของ Flowchart: ข้อความลอย / หกเหลี่ยม / ทรงกระบอก / เอกสาร
void main() {
  const added = [FcShape.text, FcShape.hexagon, FcShape.cylinder, FcShape.document];

  FcNode node(FcShape s, {int? fill, int? stroke}) =>
      FcNode(id: 'n', shape: s, text: 'ทดสอบ', x: 100, y: 200, fill: fill, stroke: stroke);

  group('เรขาคณิต', () {
    for (final s in added) {
      test('${s.name}: เส้นรอบรูปปิดและอยู่ในกรอบของสัญลักษณ์', () {
        final n = node(s);
        final g = fcShapeGeom(n);
        expect(g.outline.first.$1, 'M');
        expect(g.outline.last.$1, 'Z');
        for (final (op, pts) in [...g.outline, ...g.details]) {
          if (op == 'Z') continue;
          for (final p in pts) {
            // จุดควบคุมของเส้นโค้งอาจเลยกรอบได้ (ตัวเส้นจริงไม่เลย) จึงตรวจเฉพาะจุดปลาย
            if (op == 'C' && !identical(p, pts.last)) continue;
            expect(p.$1, inInclusiveRange(n.x - 0.001, n.right + 0.001), reason: '$op x');
            expect(p.$2, inInclusiveRange(n.y - 0.001, n.bottom + 0.001), reason: '$op y');
          }
        }
      });

      test('${s.name}: กรอบข้อความอยู่ในตัวสัญลักษณ์และมีที่ว่าง', () {
        final n = node(s);
        final b = fcTextBox(n);
        expect(b.width, greaterThan(20));
        expect(b.height, greaterThan(10));
        expect(b.left, greaterThanOrEqualTo(n.x));
        expect(b.top, greaterThanOrEqualTo(n.y));
        expect(b.left + b.width, lessThanOrEqualTo(n.right));
        expect(b.top + b.height, lessThanOrEqualTo(n.bottom));
      });

      test('${s.name}: มีขนาดเริ่มต้น สีประจำรูปทรง และป้ายชื่อ', () {
        final (w, h) = fcDefaultSize(s);
        expect(w, greaterThanOrEqualTo(kFcMinSide));
        expect(h, greaterThanOrEqualTo(kFcMinSide));
        expect(kFcShapeColors[s], isNotNull);
        expect(fcShapeLabel(s), isNotEmpty);
      });
    }

    test('ทรงกระบอกมีเส้นตกแต่ง (ขอบฝา) ; เอกสารกับหกเหลี่ยมไม่มี', () {
      expect(fcShapeGeom(node(FcShape.cylinder)).details, isNotEmpty);
      expect(fcShapeGeom(node(FcShape.document)).details, isEmpty);
      expect(fcShapeGeom(node(FcShape.hexagon)).details, isEmpty);
    });

    test('หกเหลี่ยม: จุดยอดซ้าย/ขวาอยู่กึ่งกลางความสูง', () {
      final n = node(FcShape.hexagon);
      final pts = [for (final (op, p) in fcShapeGeom(n).outline) if (op != 'Z') p.first];
      expect(pts.length, 6);
      expect(pts.any((p) => p.$1 == n.x && p.$2 == n.cy), isTrue);
      expect(pts.any((p) => p.$1 == n.right && p.$2 == n.cy), isTrue);
    });
  });

  group('ข้อความลอย', () {
    test('เป็นคำอธิบาย ไม่นับในกฎการไหล', () {
      expect(fcIsAnnotation(FcShape.text), isTrue);
      expect(fcIsAnnotation(FcShape.note), isTrue);
      for (final s in [FcShape.hexagon, FcShape.cylinder, FcShape.document]) {
        expect(fcIsAnnotation(s), isFalse, reason: s.name);
      }
    });

    test('แผนภาพที่มีแต่ข้อความลอย = ไม่มีปัญหา ; ข้อความลอยไม่ทำให้เกิดทางตัน/ไปไม่ถึง', () {
      expect(validateFlowchart(FlowchartDiagram(nodes: [node(FcShape.text)])), isEmpty);
      final d = FlowchartDiagram(nodes: [
        FcNode(id: 's', shape: FcShape.start, text: 'Start', x: 0, y: 0),
        FcNode(id: 'e', shape: FcShape.end, text: 'End', x: 0, y: 200),
        FcNode(id: 't', shape: FcShape.text, text: 'หมายเหตุ', x: 300, y: 0),
      ], edges: [
        FcEdge(id: 'k', fromId: 's', toId: 'e'),
      ]);
      expect(validateFlowchart(d), isEmpty);
    });

    test('SVG: ไม่กำหนดสีพื้น/สีเส้น = มีแต่ตัวอักษร ; กำหนดสีเส้น = มีกรอบ', () {
      final plain = exportFlowchartSvg(FlowchartDiagram(nodes: [node(FcShape.text)]))!;
      expect(plain, contains('ทดสอบ'));
      expect(plain, isNot(contains('stroke-width="1.7"')));
      final framed = exportFlowchartSvg(FlowchartDiagram(nodes: [node(FcShape.text, stroke: 0xFFDC2626)]))!;
      expect(framed, contains('stroke-width="1.7"'));
      final filled = exportFlowchartSvg(FlowchartDiagram(nodes: [node(FcShape.text, fill: 0xFFFFEE88)]))!;
      expect(filled, contains('fill="#FFEE88"'));
    });
  });

  group('บันทึก / อ่านไฟล์ / ส่งออก', () {
    test('รูปทรงใหม่ทั้งหมดอ่านกลับเป็นรูปทรงเดิม', () {
      final d = FlowchartDiagram(nodes: [
        for (var i = 0; i < added.length; i++) FcNode(id: 'n$i', shape: added[i], text: 't$i', x: i * 200.0, y: 0),
      ]);
      final back = FlowchartDiagram.fromJson(d.toJson());
      expect([for (final n in back.nodes) n.shape], added);
    });

    test('SVG ของทรงกระบอก/เอกสาร/หกเหลี่ยมมีเส้นรอบรูปและเส้นโค้งตามชนิด', () {
      for (final s in [FcShape.hexagon, FcShape.cylinder, FcShape.document]) {
        final svg = exportFlowchartSvg(FlowchartDiagram(nodes: [node(s)]))!;
        expect(svg, contains('<path d="M'), reason: s.name);
        if (s != FcShape.hexagon) expect(svg, contains(' C'), reason: s.name);
      }
    });
  });
}
