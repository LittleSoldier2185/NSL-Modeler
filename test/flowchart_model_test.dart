import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/clipboard/flowchart_clipboard.dart';
import 'package:nsl_dev/core/layout/flowchart_geometry.dart';
import 'package:nsl_dev/core/layout/flowchart_layout.dart';
import 'package:nsl_dev/core/layout/ortho_route.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';

FlowchartDiagram sample() => FlowchartDiagram(nodes: [
      FcNode(id: 's', shape: FcShape.start, text: 'Start', x: 0, y: 0),
      FcNode(id: 'p', shape: FcShape.process, text: 'Do it', x: 0, y: 120, fill: 0xFFFFEEAA, bold: true, align: FcAlign.left),
      FcNode(id: 'd', shape: FcShape.decision, text: 'OK?', x: 0, y: 260, dash: FcDash.dashed),
      FcNode(id: 'e', shape: FcShape.end, text: 'End', x: 0, y: 420, fontSize: 16, italic: true, textColor: 0xFF112233),
    ], edges: [
      FcEdge(id: 'k1', fromId: 's', toId: 'p'),
      FcEdge(id: 'k2', fromId: 'p', toId: 'd'),
      FcEdge(id: 'k3', fromId: 'd', toId: 'e', label: 'Yes', color: 0xFFFF0000, dash: FcDash.dotted, width: 2.5),
      FcEdge(id: 'k4', fromId: 'd', toId: 'p', label: 'No', startArrow: FcArrow.open, endArrow: FcArrow.none),
    ]);

Map<String, dynamic> roundTrip(Object o) => jsonDecode(jsonEncode(o)) as Map<String, dynamic>;

void main() {
  group('โมเดล', () {
    test('JSON ไป-กลับได้ค่าเดิมทุกช่อง และค่าเริ่มต้นไม่ถูกเขียน', () {
      final d = sample();
      final j = roundTrip(d.toJson());
      final back = FlowchartDiagram.fromJson(j);
      expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
      final s = (j['nodes'] as List).first as Map;
      expect(s.containsKey('fill'), isFalse);
      expect(s.containsKey('fontSize'), isFalse);
      final k1 = (j['edges'] as List).first as Map;
      expect(k1.keys.toSet(), {'id', 'from', 'to', 'label'});
      expect(back.nodeById('p')!.align, FcAlign.left);
      expect(back.edgeById('k4')!.startArrow, FcArrow.open);
      expect(back.edgeById('k4')!.endArrow, FcArrow.none);
    });

    test('ซ่อมข้อมูลผิดปกติ: รูปทรงแปลก/id ซ้ำ/ขนาดเพี้ยน/เส้นชี้ไปที่ไม่มี', () {
      final d = FlowchartDiagram.fromJson({
        'nodes': [
          {'id': 'a', 'shape': 'process', 'w': 3, 'h': double.nan, 'fontSize': 500, 'align': 'weird', 'fill': 'red'},
          {'id': 'a', 'shape': 'end'},
          {'id': 'b', 'shape': 'pentagon-of-doom'},
          {'id': '', 'shape': 'process'},
          'junk',
          {'id': 'c', 'shape': 'end', 'w': 99999},
        ],
        'edges': [
          {'id': 'x', 'from': 'a', 'to': 'c', 'width': 99},
          {'id': 'x', 'from': 'c', 'to': 'a'},
          {'id': 'y', 'from': 'a', 'to': 'missing'},
          {'id': 'z', 'from': 'a', 'to': 'a'},
          {'from': 'a', 'to': 'c'},
        ],
      });
      expect(d.nodes.map((n) => n.id), ['a', 'c']);
      final a = d.nodeById('a')!;
      expect((a.w, a.h), fcDefaultSize(FcShape.process));
      expect(a.fontSize, 13);
      expect(a.align, FcAlign.center);
      expect(a.fill, isNull);
      expect(d.nodeById('c')!.w, kFcMaxSide);
      expect(d.edges.map((e) => e.id), ['x', 'z']); // วนเข้าตัวเองเก็บไว้ให้ตัวตรวจเตือน
      expect(d.edges.first.width, 1.8);
      expect(FlowchartDiagram.fromJson(null).nodes, isEmpty);
      expect(FlowchartDiagram.fromJson('x').edges, isEmpty);
    });
  });

  group('ไฟล์ v3', () {
    Workspace ws() => Workspace(name: 'P', documents: [
          ProjectDocument.er(id: 'er', name: 'ER', content: Project(name: 'P')),
          ProjectDocument.flowchart(id: 'f1', name: 'Login flow', content: sample()),
        ]);

    test('บันทึกเป็น v3 ชนิด "flowchart" และเปิดกลับได้เนื้อหาเดิม', () {
      final j = roundTrip(encodeProjectMap(ws()));
      expect(j['format'], 'nsl-erd');
      expect(j['version'], 3);
      final doc = (j['documents'] as List).firstWhere((d) => d['id'] == 'f1') as Map;
      expect(doc['type'], 'flowchart');
      final back = decodeProjectMap(j);
      final f = back.documentById('f1')!;
      expect(f.type, DocType.flowchart);
      expect(f.name, 'Login flow');
      expect(jsonEncode(f.flowchart!.toJson()), jsonEncode(sample().toJson()));
      expect(jsonEncode(encodeProjectMap(back)), jsonEncode(j));
    });

    test('ชนิดที่ไม่รู้จักยังเก็บกลับครบ (ชนิดอื่นจากไฟล์รุ่นใหม่กว่า)', () {
      final j = roundTrip(encodeProjectMap(ws()));
      (j['documents'] as List).add({'id': 'x', 'type': 'mindmap', 'name': 'Screens', 'typeVersion': 2, 'extra': 1, 'content': {'any': [1, 2]}});
      final back = decodeProjectMap(j);
      expect(back.documentById('x')!.type, isNull);
      expect(jsonEncode(encodeProjectMap(back)), jsonEncode(j));
    });

    test('จำลองรุ่น 0.6.0 (ไม่รู้จัก flowchart): เอกสาร Flowchart ถูกเก็บดิบและเขียนกลับไม่เปลี่ยน แล้วรุ่นนี้เปิดได้ครบ', () {
      final j = roundTrip(encodeProjectMap(ws()));
      // รุ่น 0.6.0 อ่านชนิดที่ไม่อยู่ใน DocType เป็น RawDocContent — จำลองด้วยชื่อชนิดที่รุ่นนี้ไม่รู้จัก
      final raw = jsonEncode(j).replaceAll('"type":"flowchart"', '"type":"flowchart-unknown"');
      final old = decodeProjectMap(jsonDecode(raw) as Map<String, dynamic>);
      final kept = old.documentById('f1')!;
      expect(kept.type, isNull);
      expect(kept.content, isA<RawDocContent>());
      final saved = jsonEncode(encodeProjectMap(old)).replaceAll('"type":"flowchart-unknown"', '"type":"flowchart"');
      expect(saved, jsonEncode(j)); // เนื้อหาไม่หายสักตัวอักษร
      final reopened = decodeProjectMap(jsonDecode(saved) as Map<String, dynamic>);
      expect(reopened.documentById('f1')!.flowchart!.nodes.length, 4);
    });

    test('เอกสาร RawDocContent ชนิด "flowchart" (แบบที่ 0.6.0 ถือในหน่วยความจำ) เขียนออกแล้วรุ่นนี้อ่านเป็น Flowchart', () {
      final w = Workspace(documents: [
        ProjectDocument.er(id: 'er', name: 'ER', content: Project()),
        ProjectDocument(id: 'f', typeName: 'flowchart', name: 'F', content: RawDocContent(sample().toJson())),
      ]);
      expect(w.documentById('f')!.type, isNull);
      final back = decodeProjectMap(roundTrip(encodeProjectMap(w)));
      expect(back.documentById('f')!.type, DocType.flowchart);
      expect(back.documentById('f')!.flowchart!.edges.length, 4);
    });

    test('ชื่อว่าง = "Flowchart" ; ชื่อซ้ำทั้งโปรเจกต์ต่อเลข ; เนื้อหาเสียได้แผนภาพว่าง', () {
      final w = decodeProjectMap({
        'format': 'nsl-erd',
        'version': 3,
        'documents': [
          {'id': 'er', 'type': 'er', 'name': 'flow', 'content': {}},
          {'id': 'f1', 'type': 'flowchart', 'name': ' ', 'content': 5},
          {'id': 'f2', 'type': 'flowchart', 'name': 'FLOW', 'content': null},
        ],
      });
      expect(w.documents.map((d) => d.name), ['flow', 'Flowchart', 'FLOW 2']);
      expect(w.documentById('f1')!.flowchart!.nodes, isEmpty);
    });
  });

  group('เรขาคณิต', () {
    test('เส้นหักมุมฉาก บนลงล่าง ปลายเส้นแตะเส้นรอบรูปจริง (ข้าวหลามตัด/แคปซูล)', () {
      final d = sample();
      final r = fcRoutes(d);
      expect(r.keys.toSet(), {'k1', 'k2', 'k3', 'k4'});
      for (final pts in r.values) {
        for (var i = 1; i < pts.length; i++) {
          final horizontal = (pts[i].$2 - pts[i - 1].$2).abs() < 0.001;
          final vertical = (pts[i].$1 - pts[i - 1].$1).abs() < 0.001;
          expect(horizontal || vertical, isTrue, reason: '$pts');
        }
      }
      // k1: start (บน) -> process (ล่าง) ออกด้านล่างของ start เข้าด้านบนของ process
      final k1 = r['k1']!;
      expect(k1.first.$2, closeTo(50, 0.01));
      expect(k1.last.$2, closeTo(120, 0.01));
      // ทุกปลายเส้นอยู่บนเส้นรอบรูป (เผื่อ 0.5px)
      for (final e in d.edges) {
        final pts = r[e.id]!;
        expect(fcNodeContains(d.nodeById(e.fromId)!, pts.first.$1, pts.first.$2, tol: 0.5), isTrue);
        expect(fcNodeContains(d.nodeById(e.toId)!, pts.last.$1, pts.last.$2, tol: 0.5), isTrue);
      }
    });

    test('เส้นเข้าข้างข้าวหลามตัดแบบหลายช่อง ถูกเลื่อนเข้าไปแตะขอบเฉียง', () {
      final dia = FcNode(id: 'd', shape: FcShape.decision, x: 0, y: 0, w: 100, h: 100);
      final p = fcSnapToOutline(dia, RouteSide.left, (0, 30));
      expect(p.$2, 30);
      expect(p.$1, closeTo(20, 0.001)); // |dy|=20 -> 20/50 ของครึ่งความกว้าง
      final io = FcNode(id: 'i', shape: FcShape.io, x: 0, y: 0, w: 160, h: 64);
      expect(fcSnapToOutline(io, RouteSide.left, (0, 0)).$1, closeTo(fcIoSkew(io), 0.001));
      expect(fcSnapToOutline(io, RouteSide.right, (160, 64)).$1, closeTo(160 - fcIoSkew(io), 0.001));
    });

    test('เส้นวนเข้าตัวเองเป็นห่วงทางขวา ; คลิกโดนรูปทรงตามรูปจริง', () {
      final d = FlowchartDiagram(nodes: [FcNode(id: 'a', shape: FcShape.decision, x: 0, y: 0, w: 100, h: 100)], edges: [
        FcEdge(id: 'l', fromId: 'a', toId: 'a'),
      ]);
      final r = fcRoutes(d)['l']!;
      expect(r.first.$1, 100);
      expect(r[1].$1, greaterThan(100));
      expect(fcNodeAt(d, 50, 50)?.id, 'a');
      expect(fcNodeAt(d, 5, 5), isNull); // มุมนอกข้าวหลามตัด
      expect(fcEdgeAt(d, r[1].$1, (r[1].$2 + r[2].$2) / 2), 'l');
    });

    test('ขอบเขต: ว่าง = null ; เฉพาะที่เลือก', () {
      expect(fcBounds(FlowchartDiagram()), isNull);
      final b = fcBounds(sample(), pad: 0, only: {'s'})!;
      expect((b.left, b.top, b.right, b.bottom), (0, 0, 140, 50));
    });

    test('หัวลูกศร: ทึบ = สามเหลี่ยมปิด, โปร่ง = เส้นสามจุด, ไม่มี = ว่าง', () {
      expect(fcArrowHead(FcArrow.none, (0, 0), (10, 0)).$2, isEmpty);
      final (filled, pts) = fcArrowHead(FcArrow.arrow, (0, 0), (20, 0));
      expect(filled, isTrue);
      expect(pts.first, (20, 0));
      final (f2, p2) = fcArrowHead(FcArrow.open, (0, 0), (20, 0));
      expect(f2, isFalse);
      expect(p2[1], (20, 0));
    });

    test('routePointAt / routeParamAt', () {
      final pts = <RoutePoint>[(0, 0), (10, 0), (10, 10)];
      expect(routePointAt(pts, 0.5), (10.0, 0.0));
      expect(routePointAt(pts, 0.75), (10.0, 5.0));
      expect(routeParamAt(pts, 10, 5), closeTo(0.75, 0.001));
    });
  });

  group('จัดวางอัตโนมัติ', () {
    test('บนลงล่าง: ชั้นเรียงตามทิศเส้น ไม่ซ้อนกัน โน้ตไม่ขยับ ผลคงที่', () {
      final d = sample()..nodes.add(FcNode(id: 'n', shape: FcShape.note, x: 900, y: 900));
      final p = fcAutoLayout(d);
      expect(p.containsKey('n'), isFalse);
      expect(p['s']!.y, lessThan(p['p']!.y));
      expect(p['p']!.y, lessThan(p['d']!.y));
      expect(p['d']!.y, lessThan(p['e']!.y));
      expect(p['p']!.y - (p['s']!.y + 50), greaterThanOrEqualTo(kFcLayerGap - 0.01));
      expect(jsonEncode(fcAutoLayout(d).map((k, v) => MapEntry(k, [v.x, v.y]))),
          jsonEncode(p.map((k, v) => MapEntry(k, [v.x, v.y]))));
    });

    test('ซ้ายไปขวา: x เพิ่มตามลำดับ', () {
      final p = fcAutoLayout(sample(), kind: FcLayoutKind.leftRight);
      expect(p['s']!.x, lessThan(p['p']!.x));
      expect(p['d']!.x, lessThan(p['e']!.x));
    });

    test('ตัวจัดเส้นที่ใช้ร่วมกับ DFD: เส้น DFD ยังออกจากขอบขวาของกล่องต้นทาง', () {
      final d = DfdDiagram(nodes: [
        DfdNode(id: 'a', kind: DfdKind.entity, x: 5, y: 7),
        DfdNode(id: 'b', kind: DfdKind.process),
      ], flows: [
        DfdFlow(id: 'f', fromId: 'a', toId: 'b'),
      ]);
      final r = dfdRoutes(d);
      expect(r['f']!.first.$1, 155); // ขอบขวาของ a (x 5 + กว้าง 150)
    });
  });

  group('คลิปบอร์ด', () {
    test('คัดลอกเฉพาะที่เลือก + เส้นระหว่างกัน ; ข้อความอื่น/ข้อมูล DFD = null', () {
      final text = encodeFlowchartClipboard(sample(), {'d', 'e', 'p'});
      final back = decodeFlowchartClipboard(text)!;
      expect(back.nodes.map((n) => n.id), ['p', 'd', 'e']);
      expect(back.edges.map((e) => e.id).toSet(), {'k2', 'k3', 'k4'});
      expect(decodeFlowchartClipboard('hello'), isNull);
      expect(decodeFlowchartClipboard('{"format":"nsl-modeler-dfd","nodes":[]}'), isNull);
      expect(decodeFlowchartClipboard('{bad json'), isNull);
      expect(decodeFlowchartClipboard(encodeFlowchartClipboard(sample(), {})), isNull);
    });
  });
}
