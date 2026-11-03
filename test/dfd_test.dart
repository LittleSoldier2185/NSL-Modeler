import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/export/dfd_svg.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/core/models/dfd_model.dart';
import 'package:nsl_modeler/core/models/diagram.dart';
import 'package:nsl_modeler/core/storage/project_file.dart';
import 'package:nsl_modeler/core/validate/dfd_validator.dart';
import 'package:nsl_modeler/core/validate/issue.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/dfd_controller.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/export/dfd_png.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

DfdNode ent(String id, double x, double y, {String name = 'E'}) => DfdNode(id: id, kind: DfdKind.entity, name: name, x: x, y: y);
DfdNode proc(String id, double x, double y, {String name = 'P', String number = '1.0'}) =>
    DfdNode(id: id, kind: DfdKind.process, name: name, number: number, x: x, y: y);
DfdNode store(String id, double x, double y, {String name = 'S', String number = 'D1'}) =>
    DfdNode(id: id, kind: DfdKind.store, name: name, number: number, x: x, y: y);

/// Customer -> Process -> Store ที่ต่อกันครบ
DfdDiagram sample() => DfdDiagram(
      nodes: [ent('e', 0, 0, name: 'Customer'), proc('p', 400, 0, name: 'Order'), store('s', 800, 0, name: 'Orders')],
      flows: [
        DfdFlow(id: 'f1', fromId: 'e', toId: 'p', label: 'Order'),
        DfdFlow(id: 'f2', fromId: 'p', toId: 's', label: 'Save'),
      ],
    );

bool axisAligned(List<DfdPoint> pts) {
  for (var i = 1; i < pts.length; i++) {
    if ((pts[i - 1].$1 - pts[i].$1).abs() > 0.001 && (pts[i - 1].$2 - pts[i].$2).abs() > 0.001) return false;
  }
  return true;
}

void main() {
  group('โมเดล / ไฟล์', () {
    test('บันทึกแล้วเปิดกลับมาครบ (เนื้อหาแยกต่อแท็บ) และเป็นไฟล์เวอร์ชัน 2', () {
      final c = ProjectController(base());
      final a = c.addDiagram(DiagramKind.dfd, name: 'L0')!;
      final b = c.addDiagram(DiagramKind.dfd, name: 'L1')!;
      c.project.dfd[a.id] = sample();
      c.project.dfd[b.id] = DfdDiagram(nodes: [ent('x', 5, 5, name: 'Solo')]);
      c.project.dfd[a.id]!.nodes.first.color = 0xFF336699;
      c.project.dfd[a.id]!.flows.first
        ..bidirectional = true
        ..color = 0xFFAA0000;
      final text = ProjectFile.encode(c.project);
      expect(jsonDecode(text)['version'], 2);
      final back = ProjectFile.decode(text);
      expect(back.dfd[a.id]!.nodes.map((n) => (n.id, n.kind, n.name, n.number)), [('e', DfdKind.entity, 'Customer', ''), ('p', DfdKind.process, 'Order', '1.0'), ('s', DfdKind.store, 'Orders', 'D1')]);
      expect(back.dfd[a.id]!.nodes.first.color, 0xFF336699);
      expect(back.dfd[a.id]!.flows.first.bidirectional, true);
      expect(back.dfd[a.id]!.flows.first.color, 0xFFAA0000);
      expect(back.dfd[b.id]!.nodes.single.name, 'Solo');
    });

    test('ไฟล์ ER ล้วนไม่มีฟิลด์ dfd', () {
      expect(base().toJson().containsKey('dfd'), false);
    });

    test('ข้อมูลผิดปกติถูกซ่อม: id ซ้ำ/ชนิดแปลก/เส้นชี้วัตถุที่ไม่มี/เส้นชี้ตัวเอง/ขนาดผิด', () {
      final d = DfdDiagram.fromJson({
        'nodes': [
          {'id': 'a', 'kind': 'entity', 'name': 'A', 'w': -5, 'h': 99999, 'x': 'bad'},
          {'id': 'a', 'kind': 'process', 'name': 'dup'},
          {'id': 'b', 'kind': 'ufo'},
          {'id': 'c', 'kind': 'process', 'name': 'C', 'color': 'red'},
          'junk',
          {'kind': 'entity'},
        ],
        'flows': [
          {'id': 'f1', 'from': 'a', 'to': 'c', 'label': 'ok'},
          {'id': 'f1', 'from': 'a', 'to': 'c'},
          {'id': 'f2', 'from': 'a', 'to': 'nope'},
          {'id': 'f3', 'from': 'a', 'to': 'a'},
          {'id': 'f4', 'from': 5, 'to': 'a'},
        ],
      });
      expect(d.nodes.map((n) => n.id), ['a', 'c']);
      expect(d.nodes.first.x, 0);
      expect(d.nodes.first.w, dfdDefaultSize(DfdKind.entity).$1);
      expect(d.nodes.first.h, kDfdMaxSide);
      expect(d.nodes.last.color, isNull);
      expect(d.flows.map((f) => f.id), ['f1']);
      expect(DfdDiagram.fromJson('garbage').nodes, isEmpty);
    });

    test('ลบแท็บ = เนื้อหาหาย; แท็บ ER ไม่มีเนื้อหา DFD; เลขลำดับถัดไปไม่ซ้ำ', () {
      final c = ProjectController(base());
      final a = c.addDiagram(DiagramKind.dfd)!;
      expect(c.project.dfd.containsKey(a.id), true);
      c.deleteDiagram(a.id);
      expect(c.project.dfd.containsKey(a.id), false);
      final d = DfdDiagram(nodes: [proc('1', 0, 0, number: '1.0'), proc('2', 0, 0, number: '3.0'), store('3', 0, 0, number: 'D2')]);
      expect(d.nextProcessNumber(), '2.0');
      expect(d.nextStoreNumber(), 'D1');
    });
  });

  group('เส้นทางของ flow', () {
    test('คนละฝั่ง: ออก/เข้าแนวนอน ทุกช่วงตรงแกน และปลายเส้นอยู่ที่ขอบกล่อง', () {
      final d = sample();
      final r = dfdRoutes(d);
      for (final route in r.values) {
        expect(axisAligned(route), true);
      }
      final f1 = r['f1']!;
      expect(f1.first.$1, d.nodeById('e')!.right);
      expect(f1.last.$1, d.nodeById('p')!.x);
    });

    test('วัตถุอยู่บน-ล่างกัน: ออกแนวตั้ง', () {
      final d = DfdDiagram(nodes: [ent('a', 0, 0), proc('b', 0, 300)], flows: [DfdFlow(id: 'f', fromId: 'a', toId: 'b')]);
      final r = dfdRoutes(d)['f']!;
      expect(r.first.$2, d.nodeById('a')!.bottom);
      expect(r.last.$2, d.nodeById('b')!.y);
      expect(axisAligned(r), true);
    });

    test('สองเส้นที่ออกด้านเดียวกันของกล่องเดียวกันถูกแยกเป็นคนละระดับ (ไม่ซ้อน) และสองทางระหว่างคู่เดียวกันก็แยก', () {
      final d = DfdDiagram(
        nodes: [proc('p', 0, 0), ent('a', 400, -100), ent('b', 400, 100)],
        flows: [DfdFlow(id: 'f1', fromId: 'p', toId: 'a'), DfdFlow(id: 'f2', fromId: 'p', toId: 'b')],
      );
      final r = dfdRoutes(d);
      expect(r['f1']!.first.$2, isNot(r['f2']!.first.$2));

      final two = DfdDiagram(
        nodes: [proc('p', 0, 0), ent('a', 400, 0)],
        flows: [DfdFlow(id: 'f1', fromId: 'p', toId: 'a'), DfdFlow(id: 'f2', fromId: 'a', toId: 'p')],
      );
      final r2 = dfdRoutes(two);
      expect(r2['f1']!.first.$2, isNot(r2['f2']!.last.$2));
    });

    test('เส้นแนวตั้งที่ทับกันในช่องเดียวกันถูกดันห่าง', () {
      final d = DfdDiagram(
        nodes: [ent('a', 0, 0), ent('b', 0, 200), proc('c', 500, 400), proc('d', 500, 600)],
        flows: [DfdFlow(id: 'f1', fromId: 'a', toId: 'c'), DfdFlow(id: 'f2', fromId: 'b', toId: 'd')],
      );
      final r = dfdRoutes(d);
      final x1 = r['f1']![1].$1, x2 = r['f2']![1].$1;
      expect((x1 - x2).abs(), greaterThanOrEqualTo(6));
    });

    test('จุดวางป้ายอยู่บนเส้น; hit test โดนเส้น/วัตถุ และไม่โดนที่ว่าง', () {
      final d = sample();
      final r = dfdRoutes(d)['f1']!;
      final (ax, ay) = dfdLabelAnchor(r);
      expect(dfdDistanceToRoute(r, ax, ay), lessThan(0.5));
      expect(dfdFlowAt(d, ax, ay), 'f1');
      expect(dfdFlowAt(d, ax, ay + 80), isNull);
      expect(dfdNodeAt(d, 10, 10)?.id, 'e');
      expect(dfdNodeAt(d, 300, 500), isNull);
    });

    test('ขอบเขตครอบทุกอย่าง; แผนภาพว่าง = null', () {
      expect(dfdBounds(DfdDiagram()), isNull);
      final b = dfdBounds(sample(), pad: 10)!;
      expect(b.left, -10);
      expect(b.right, greaterThanOrEqualTo(800 + 180 + 10));
    });
  });

  group('ตรวจสอบกฎของ DFD', () {
    Set<String> codes(DfdDiagram d) => validateDfd(d).map((i) => i.code).toSet();

    test('แผนภาพที่ต่อครบ = ไม่มีปัญหา', () {
      expect(validateDfd(sample()), isEmpty);
    });

    test('flow ที่ไม่ผ่าน process = error (entity↔entity, entity↔store, store↔store)', () {
      for (final other in [ent('x', 300, 0), store('x', 300, 0)]) {
        final d = DfdDiagram(nodes: [ent('a', 0, 0), other, proc('p', 0, 200)], flows: [
          DfdFlow(id: 'f', fromId: 'a', toId: 'x', label: 'L'),
          DfdFlow(id: 'g', fromId: 'p', toId: 'a', label: 'M'),
          DfdFlow(id: 'h', fromId: 'a', toId: 'p', label: 'M'),
        ]);
        final bad = validateDfd(d).where((i) => i.code == 'dfd_no_process').toList();
        expect(bad.length, 1);
        expect(bad.single.severity, Severity.error);
        expect(bad.single.relationId, 'f');
      }
    });

    test('process ไม่มีข้อมูลเข้า / ออก / ไม่เชื่อมอะไร', () {
      final onlyOut = DfdDiagram(nodes: [proc('p', 0, 0), ent('e', 300, 0)], flows: [DfdFlow(id: 'f', fromId: 'p', toId: 'e', label: 'x')]);
      expect(codes(onlyOut), contains('dfd_process_no_input'));
      final onlyIn = DfdDiagram(nodes: [proc('p', 0, 0), ent('e', 300, 0)], flows: [DfdFlow(id: 'f', fromId: 'e', toId: 'p', label: 'x')]);
      expect(codes(onlyIn), contains('dfd_process_no_output'));
      expect(codes(DfdDiagram(nodes: [proc('p', 0, 0)])), contains('dfd_process_isolated'));
    });

    test('flow สองทางนับเป็นทั้งเข้าและออก', () {
      final d = DfdDiagram(nodes: [proc('p', 0, 0), ent('e', 300, 0)], flows: [DfdFlow(id: 'f', fromId: 'e', toId: 'p', label: 'x', bidirectional: true)]);
      expect(codes(d), isNot(contains('dfd_process_no_output')));
    });

    test('flow ไม่มีชื่อ, วัตถุไม่มีชื่อ, เลขซ้ำ/ว่าง, entity/store ที่ไม่ต่ออะไร', () {
      final d = DfdDiagram(
        nodes: [proc('p', 0, 0, number: '1.0'), proc('q', 0, 200, number: '1.0'), proc('r', 0, 400, number: ''), ent('e', 300, 0, name: ''), store('s', 300, 200), store('t', 300, 400, number: 'D1')],
        flows: [DfdFlow(id: 'f', fromId: 'e', toId: 'p'), DfdFlow(id: 'g', fromId: 'p', toId: 'q', label: 'x')],
      );
      final c = codes(d);
      expect(c, containsAll(['dfd_flow_unlabeled', 'dfd_no_name', 'dfd_dup_number', 'dfd_no_number', 'dfd_isolated']));
    });

    test('เรียงตามความรุนแรง (error ก่อน)', () {
      final d = DfdDiagram(nodes: [ent('a', 0, 0), ent('b', 300, 0), proc('p', 0, 200)], flows: [DfdFlow(id: 'f', fromId: 'a', toId: 'b', label: 'x')]);
      final v = validateDfd(d);
      expect(v.first.severity, Severity.error);
      for (var i = 1; i < v.length; i++) {
        expect(v[i].severity.index, greaterThanOrEqualTo(v[i - 1].severity.index));
      }
    });
  });

  group('DfdController: แก้ไข / undo แยกต่อแท็บ', () {
    late ProjectController pc;
    late DfdController d;
    late String tab;

    setUp(() {
      pc = ProjectController(base());
      d = DfdController(pc);
      tab = pc.addDiagram(DiagramKind.dfd)!.id;
    });

    test('วางวัตถุ: เลขลำดับ/รหัสอัตโนมัติ ถูกเลือก กลับโหมดเลือก; ER วางไม่ได้', () {
      d.setTool(DfdTool.process);
      final p1 = d.addNode(DfdKind.process, 100, 100)!;
      final p2 = d.addNode(DfdKind.process, 300, 100)!;
      final s1 = d.addNode(DfdKind.store, 500, 100)!;
      expect([p1.number, p2.number, s1.number], ['1.0', '2.0', 'D1']);
      expect(d.selectedNodeIds, {s1.id});
      expect(d.tool, DfdTool.select);
      expect(d.diagram.nodes.length, 3);
      pc.selectDiagram(kErDiagramId);
      expect(d.addNode(DfdKind.entity, 0, 0), isNull);
    });

    test('snap: ตำแหน่งปัดเข้าช่อง 20', () {
      final n = d.addNode(DfdKind.entity, 133, 77, snap: true)!;
      expect(n.x % 20, 0);
      expect(n.y % 20, 0);
    });

    test('เส้นข้อมูล: ตัวเองไปตัวเองไม่ได้; สลับทิศทาง สองทาง ชื่อ สี; ลบวัตถุลบเส้นที่ต่ออยู่', () {
      final a = d.addNode(DfdKind.entity, 0, 0)!, b = d.addNode(DfdKind.process, 400, 0)!;
      expect(d.addFlow(a.id, a.id), isNull);
      final f = d.addFlow(a.id, b.id, label: 'Req')!;
      expect(d.selectedFlowId, f.id);
      d.reverseFlow(f.id);
      expect((d.diagram.flowById(f.id)!.fromId, d.diagram.flowById(f.id)!.toId), (b.id, a.id));
      d.setFlowBidirectional(f.id, true);
      d.setFlowLabel(f.id, 'New');
      d.setFlowColor(f.id, 0xFF112233);
      final g = d.diagram.flowById(f.id)!;
      expect((g.bidirectional, g.label, g.color), (true, 'New', 0xFF112233));
      d.selectNode(a.id);
      d.deleteSelection();
      expect(d.diagram.flows, isEmpty);
      expect(d.diagram.nodes.single.id, b.id);
    });

    test('Flow tool: คลิกต้นทาง แล้วปลายทาง = สร้างเส้น; คลิกตัวเดิมซ้ำ = ยกเลิก', () {
      final a = d.addNode(DfdKind.entity, 0, 0)!, b = d.addNode(DfdKind.process, 400, 0)!;
      d.setTool(DfdTool.flow);
      expect(d.linkClick(a.id), isNull);
      expect(d.linkSource, a.id);
      expect(d.linkClick(a.id), isNull);
      expect(d.linkSource, isNull);
      d.linkClick(a.id);
      final f = d.linkClick(b.id)!;
      expect((f.fromId, f.toId), (a.id, b.id));
      expect(d.linkSource, isNull);
    });

    test('ย้ายแบบสด = undo ขั้นเดียว; snap ย้ายทุกชิ้นเท่ากัน', () {
      final a = d.addNode(DfdKind.entity, 0, 0)!, b = d.addNode(DfdKind.entity, 300, 40)!;
      d.setNodeSelection({a.id, b.id});
      final ax = a.x, bx = b.x;
      d.beginMove();
      d.moveBy(33, 27, grid: 20);
      d.moveBy(5, 5, grid: 20);
      d.endMove();
      expect(d.diagram.nodeById(b.id)!.x - d.diagram.nodeById(a.id)!.x, bx - ax);
      pc.undo();
      expect(d.diagram.nodeById(a.id)!.x, ax);
      expect(d.diagram.nodeById(b.id)!.x, bx);
      pc.redo();
      expect(d.diagram.nodeById(a.id)!.x, isNot(ax));
    });

    test('ไม่ขยับ = ไม่มีประวัติ', () {
      d.addNode(DfdKind.entity, 0, 0);
      pc.undo();
      pc.redo();
      d.beginMove();
      d.endMove();
      pc.undo();
      expect(d.diagram.nodes, isEmpty);
    });

    test('undo/redo แยกต่อแท็บ และไม่ปนกับ ER', () {
      final other = pc.addDiagram(DiagramKind.dfd)!.id;
      d.addNode(DfdKind.entity, 0, 0); // อยู่ในแท็บ "other" (เปิดอยู่)
      pc.selectDiagram(tab);
      d.addNode(DfdKind.entity, 0, 0);
      d.addNode(DfdKind.process, 300, 0);
      pc.selectDiagram(kErDiagramId);
      pc.addTable(name: 'x');
      expect(pc.canUndo, true);

      // undo ที่แท็บ ER ย้อนตาราง ไม่แตะ DFD
      pc.undo();
      expect(pc.project.tables.any((t) => t.name == 'x'), false);
      expect(pc.project.dfdOf(tab).nodes.length, 2);
      expect(pc.project.dfdOf(other).nodes.length, 1);

      // undo ที่แท็บ DFD ย้อนเฉพาะแท็บนั้น
      pc.selectDiagram(tab);
      pc.undo();
      expect(pc.project.dfdOf(tab).nodes.length, 1);
      expect(pc.project.dfdOf(other).nodes.length, 1);
      pc.selectDiagram(other);
      expect(pc.canUndo, true);
      pc.undo();
      expect(pc.project.dfdOf(other).nodes, isEmpty);
      expect(pc.project.dfdOf(tab).nodes.length, 1);
      pc.selectDiagram(tab);
      pc.redo();
      expect(pc.project.dfdOf(tab).nodes.length, 2);
      // undo ของ ER ไม่ทำให้เนื้อหา DFD หาย
      pc.selectDiagram(kErDiagramId);
      pc.redo();
      expect(pc.project.dfdOf(tab).nodes.length, 2);
    });

    test('undo ทำให้ของที่เลือกหายไป = ล้างการเลือกที่ค้าง', () {
      final a = d.addNode(DfdKind.entity, 0, 0)!;
      expect(d.selectedNodeIds, {a.id});
      pc.undo();
      expect(d.selectedNodeIds, isEmpty);
    });

    test('ทำสำเนา: เลื่อน 30 px, เลขใหม่, เส้นระหว่างกันติดไปด้วย', () {
      final a = d.addNode(DfdKind.process, 0, 0)!, b = d.addNode(DfdKind.store, 400, 0)!;
      d.addFlow(a.id, b.id, label: 'W');
      d.setNodeSelection({a.id, b.id});
      expect(d.duplicateSelection(), 2);
      expect(d.diagram.nodes.length, 4);
      expect(d.diagram.flows.length, 2);
      final copies = d.diagram.nodes.skip(2).toList();
      expect(copies.map((n) => n.number), ['2.0', 'D2']);
      expect(copies.first.x, a.x + 30);
      expect(d.selectedNodeIds, copies.map((n) => n.id).toSet());
    });

    test('มุมมอง: ซูมตามจุดโฟกัส ไม่เกินช่วง แยกต่อแท็บ; fit/reveal', () {
      d.viewport = const Size(800, 600);
      final before = d.toWorld(const Offset(400, 300));
      d.zoomAt(const Offset(400, 300), 1.5);
      expect((d.toWorld(const Offset(400, 300)) - before).distance, lessThan(0.001));
      for (var i = 0; i < 40; i++) {
        d.zoomAt(const Offset(400, 300), 1.5);
      }
      expect(d.scale, DfdController.maxScale);
      final other = pc.addDiagram(DiagramKind.dfd)!.id;
      expect(other, isNot(tab));
      expect(d.scale, 1); // แท็บใหม่ใช้มุมมองของตัวเอง
      pc.selectDiagram(tab);
      expect(d.scale, DfdController.maxScale);
      d.addNode(DfdKind.entity, 5000, 5000);
      d.fit(d.viewport);
      expect(d.scale, lessThanOrEqualTo(1.2));
      final n = d.diagram.nodes.single;
      final c = d.offset + Offset(n.cx, n.cy) * d.scale;
      expect((c - const Offset(400, 300)).distance, lessThan(1));
    });

    test('Esc: ยกเลิกต่อเส้น/เครื่องมือก่อน แล้วล้างการเลือก', () {
      final a = d.addNode(DfdKind.entity, 0, 0)!;
      d.setTool(DfdTool.flow);
      d.linkClick(a.id);
      d.escape();
      expect((d.tool, d.linkSource), (DfdTool.select, null));
      expect(d.selectedNodeIds, {a.id});
      d.escape();
      expect(d.selectedNodeIds, isEmpty);
    });
  });

  group('Export', () {
    test('SVG: โครงสร้างถูกต้อง มีวัตถุ ป้ายชื่อ ลูกศร; ธีมมืดต่างจากสว่าง; สี/ชื่อถูก escape', () {
      final d = sample();
      d.nodes.first.color = 0xFFAA33CC;
      d.nodes.first.name = 'A & <B>';
      d.flows.first.bidirectional = true;
      final light = exportDfdSvg(d)!;
      final dark = exportDfdSvg(d, dark: true)!;
      expect(light, startsWith('<svg'));
      expect(light, contains('#F6F8FB'));
      expect(dark, contains('#121820'));
      expect(dark, isNot(contains('#F6F8FB')));
      expect(light, contains('A &amp; &lt;B&gt;'));
      expect(light, contains('#AA33CC'));
      expect('<polygon'.allMatches(light).length, 3); // 2 เส้น + หัวลูกศรสองทางอีก 1
      expect(light, contains('>Save<'));
      expect(exportDfdSvg(DfdDiagram()), isNull);
    });

    testWidgets('PNG: พิกเซลมุมภาพเป็นสีมืด/สว่างตามธีม; ว่าง = null', (tester) async {
      Future<int> corner(bool dark) async => (await tester.runAsync(() async {
            final out = await exportDfdPng(sample(), scale: 1, dark: dark);
            final codec = await ui.instantiateImageCodec(out!.bytes);
            final img = (await codec.getNextFrame()).image;
            final data = (await img.toByteData())!;
            return data.getUint8(0) + data.getUint8(1) + data.getUint8(2);
          }))!;
      expect(await corner(true), lessThan(200));
      expect(await corner(false), greaterThan(600));
      expect(await tester.runAsync(() => exportDfdPng(DfdDiagram())), isNull);
    });
  });

  group('บนจอ', () {
    late ProjectController c;
    late DfdController d;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, bool withSample = false}) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: lang)));
      final ctx = tester.element(find.byType(HomePage));
      c = ctx.read<ProjectController>();
      d = ctx.read<DfdController>();
      final tab = c.addDiagram(DiagramKind.dfd, name: 'L1')!;
      if (withSample) c.project.dfd[tab.id] = sample();
      await tester.pump();
      d.setTool(DfdTool.select);
      d.panBy(Offset.zero);
      await tester.pump();
    }

    Finder canvas() => find.byKey(const ValueKey('dfd-canvas'));
    Offset screen(WidgetTester tester, double wx, double wy) => tester.getTopLeft(canvas()) + d.offset + Offset(wx, wy) * d.scale;

    Future<void> promptText(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField).last, text);
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
    }

    testWidgets('แท็บ DFD แทนที่แผง ER ด้วยแผงของ DFD; ซ่อนปุ่ม Dialect/Export .sql/จัดวางอัตโนมัติ; กลับ ER แล้วกลับมา', (tester) async {
      await boot(tester);
      expect(canvas(), findsOneWidget);
      expect(find.byKey(const ValueKey('dfd-tool-entity')), findsOneWidget);
      expect(find.text('Export .sql'), findsNothing);
      expect(find.text('Dialect  '), findsNothing);
      expect(find.text('เลือกตารางทางซ้ายเพื่อแก้ไข'), findsNothing);
      expect(find.byKey(const ValueKey('dfd-search')), findsOneWidget);
      await tester.tap(find.text('ER'));
      await tester.pumpAndSettle();
      expect(canvas(), findsNothing);
      expect(find.text('Export .sql'), findsOneWidget);
    });

    testWidgets('วางวัตถุด้วยแถบเครื่องมือ: คลิกพื้นที่ว่าง > ตั้งชื่อ > ได้วัตถุที่เลือกอยู่และแผงขวาแสดงคุณสมบัติ', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('dfd-tool-process')));
      await tester.pump();
      await tester.tapAt(screen(tester, 300, 200));
      await tester.pumpAndSettle();
      await promptText(tester, 'Browse');
      final n = d.diagram.nodes.single;
      expect((n.kind, n.name, n.number), (DfdKind.process, 'Browse', '1.0'));
      expect(d.selectedNodeIds, {n.id});
      expect(find.byKey(ValueKey('dfd-name-${n.id}-Browse')), findsOneWidget);
      expect(d.tool, DfdTool.select);
      expect(find.byKey(ValueKey('dfd-item-${n.id}')), findsOneWidget); // อยู่ในรายการแผงซ้าย
    });

    testWidgets('คีย์ลัด E/P/D เลือกเครื่องมือ; S/Esc กลับ; คีย์ของ ER (T) ไม่ทำอะไรกับตาราง', (tester) async {
      await boot(tester);
      for (final (k, t) in [(LogicalKeyboardKey.keyE, DfdTool.entity), (LogicalKeyboardKey.keyP, DfdTool.process), (LogicalKeyboardKey.keyD, DfdTool.store), (LogicalKeyboardKey.keyF, DfdTool.flow)]) {
        await tester.sendKeyEvent(k);
        await tester.pump();
        expect(d.tool, t);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(d.tool, DfdTool.select);
      final before = c.project.tables.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      expect(c.project.tables.length, before);
      // ใน ER แล้ว E ไม่เปลี่ยนเครื่องมือ DFD
      await tester.tap(find.text('ER'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      expect(d.tool, DfdTool.select);
    });

    testWidgets('ต่อเส้นข้อมูลด้วย Flow tool: คลิกสองวัตถุแล้วตั้งชื่อเส้น', (tester) async {
      await boot(tester);
      c.project.dfd[c.activeDiagramId] = DfdDiagram(nodes: [ent('e', 0, 0, name: 'Cust'), proc('p', 400, 0, name: 'Pay')]);
      d.panBy(Offset.zero); // แจ้งหน้าจอว่าเนื้อหาเปลี่ยน
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dfd-tool-flow')));
      await tester.pump();
      await tester.tapAt(screen(tester, 70, 28));
      await tester.pump();
      expect(d.linkSource, 'e');
      await tester.tapAt(screen(tester, 480, 30));
      await tester.pumpAndSettle();
      await promptText(tester, 'Payment');
      final f = d.diagram.flows.single;
      expect((f.fromId, f.toId, f.label), ('e', 'p', 'Payment'));
      expect(d.selectedFlowId, f.id);
    });

    testWidgets('ลากวัตถุ = ย้าย (undo ขั้นเดียว); ลากพื้นว่าง = กรอบเลือก; คลิกพื้นว่าง = ล้างการเลือก', (tester) async {
      await boot(tester, withSample: true);
      final x0 = d.diagram.nodeById('p')!.x;
      final g = await tester.startGesture(screen(tester, 480, 30), kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(40, 0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(d.diagram.nodeById('p')!.x, greaterThan(x0 + 30));
      expect(d.selectedNodeIds, {'p'});
      c.undo();
      expect(d.diagram.nodeById('p')!.x, x0);

      // กรอบเลือกครอบ Customer + Order
      final m = await tester.startGesture(screen(tester, 700, 300), kind: PointerDeviceKind.mouse);
      await m.moveTo(screen(tester, -20, -30));
      await tester.pump();
      expect(d.selectedNodeIds, {'e', 'p'});
      await m.up();
      await tester.pump();
      await tester.tapAt(screen(tester, 600, 400));
      await tester.pump();
      expect(d.selectedNodeIds, isEmpty);
    });

    testWidgets('คลิกที่เส้น = เลือกเส้น; แผงขวาแก้ชื่อ/ทิศทาง/สองทางได้; Delete ลบเส้น', (tester) async {
      await boot(tester, withSample: true);
      final r = dfdRoutes(d.diagram)['f1']!;
      final (ax, ay) = dfdLabelAnchor(r);
      await tester.tapAt(screen(tester, ax, ay));
      await tester.pump();
      expect(d.selectedFlowId, 'f1');
      await tester.tap(find.byKey(const ValueKey('dfd-reverse')));
      await tester.pump();
      expect(d.diagram.flowById('f1')!.fromId, 'p');
      await tester.tap(find.byKey(const ValueKey('dfd-both')));
      await tester.pump();
      expect(d.diagram.flowById('f1')!.bidirectional, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(d.diagram.flowById('f1'), isNull);
      c.undo();
      expect(d.diagram.flowById('f1'), isNotNull);
    });

    testWidgets('ดับเบิลคลิกวัตถุ = เปลี่ยนชื่อ; F2 เปลี่ยนชื่อวัตถุที่เลือก', (tester) async {
      await boot(tester, withSample: true);
      final at = screen(tester, 480, 30);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      await promptText(tester, 'Checkout');
      expect(d.diagram.nodeById('p')!.name, 'Checkout');
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await promptText(tester, 'Pay');
      expect(d.diagram.nodeById('p')!.name, 'Pay');
    });

    testWidgets('คลิกขวา: วัตถุ/เส้น/พื้นว่าง ให้เมนูที่ถูกต้อง', (tester) async {
      await boot(tester, withSample: true);
      Future<void> rc(Offset o) async {
        final g = await tester.startGesture(o, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        await g.up();
        await tester.pumpAndSettle();
      }

      await rc(screen(tester, 480, 30));
      expect(find.text('ลากเส้นข้อมูลออกจากตัวนี้'), findsOneWidget);
      await tester.tap(find.text('ทำสำเนา'));
      await tester.pumpAndSettle();
      expect(d.diagram.nodes.length, 4);

      final r = dfdRoutes(d.diagram)['f2']!;
      final (ax, ay) = dfdLabelAnchor(r);
      await rc(screen(tester, ax, ay));
      expect(find.descendant(of: find.byType(PopupMenuItem<VoidCallback>), matching: find.text('ข้อมูลไหลสองทาง')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(PopupMenuItem<VoidCallback>), matching: find.text('ข้อมูลไหลสองทาง')));
      await tester.pumpAndSettle();
      expect(d.diagram.flowById('f2')!.bidirectional, true);

      await rc(screen(tester, 600, 600));
      await tester.tap(find.text('วางกระบวนการที่นี่'));
      await tester.pumpAndSettle();
      await promptText(tester, 'New P');
      expect(d.diagram.nodes.last.name, 'New P');
      expect(d.diagram.nodes.last.number, '3.0'); // 2.0 ถูกใช้โดยสำเนาของ process เดิมแล้ว
    });

    testWidgets('แผงขวา: ตั้งสีและเลขลำดับ; กล่องปัญหาแสดงเมื่อไม่ได้เลือกอะไร และคลิกปัญหาไปเลือกวัตถุ', (tester) async {
      await boot(tester);
      c.project.dfd[c.activeDiagramId] = DfdDiagram(nodes: [proc('p', 0, 0, name: 'Lonely')]);
      d.panBy(Offset.zero); // แจ้งหน้าจอว่าเนื้อหาเปลี่ยน
      await tester.pump();
      expect(find.byKey(const ValueKey('dfd-issue-dfd_process_isolated-p')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dfd-issue-dfd_process_isolated-p')));
      await tester.pumpAndSettle();
      expect(d.selectedNodeIds, {'p'});
      await tester.tap(find.byKey(const ValueKey('dfd-color-1')));
      await tester.pump();
      expect(d.diagram.nodeById('p')!.color, kDfdTestPalette1);
      await tester.tap(find.byKey(const ValueKey('dfd-color-default')));
      await tester.pump();
      expect(d.diagram.nodeById('p')!.color, isNull);
      await tester.enterText(find.byKey(ValueKey('dfd-number-p-${d.diagram.nodeById('p')!.number}')), '7.0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(d.diagram.nodeById('p')!.number, '7.0');
    });

    testWidgets('แผนภาพที่ต่อครบ = "ไม่พบปัญหา"', (tester) async {
      await boot(tester, withSample: true);
      expect(find.byKey(const ValueKey('dfd-no-issues')), findsOneWidget);
    });

    testWidgets('แผงซ้าย: ค้นหากรองรายการ; คลิกรายการ = เลือกวัตถุ', (tester) async {
      await boot(tester, withSample: true);
      expect(find.byKey(const ValueKey('dfd-item-e')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('dfd-search')), 'orders');
      await tester.pump();
      expect(find.byKey(const ValueKey('dfd-item-e')), findsNothing);
      expect(find.byKey(const ValueKey('dfd-item-s')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dfd-item-s')));
      await tester.pump();
      expect(d.selectedNodeIds, {'s'});
    });

    testWidgets('ซูมด้วยปุ่มและ Ctrl+ล้อเมาส์; เลื่อนด้วยล้อเมาส์', (tester) async {
      await boot(tester, withSample: true);
      await tester.tap(find.byKey(const ValueKey('dfd-zoom-in')));
      await tester.pump();
      expect(d.scale, closeTo(1.2, 0.001));
      expect(tester.widget<Text>(find.byKey(const ValueKey('dfd-zoom-label'))).data, '120%');
      final o = d.offset;
      final center = tester.getCenter(canvas());
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.pump();
      expect(d.offset.dy, lessThan(o.dy));
    });

    testWidgets('Export ภาพ: ถามเฉพาะรูปแบบ/ความละเอียด/ธีม (ไม่มีตัวเลือกพื้นที่); ว่างเปล่า = แจ้งเตือน', (tester) async {
      await boot(tester);
      await tester.tap(find.text('ไฟล์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export ภาพ (PNG / SVG)…'));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีวัตถุให้ Export เป็นภาพ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));

      c.project.dfd[c.activeDiagramId] = sample();
      d.panBy(Offset.zero); // แจ้งหน้าจอว่าเนื้อหาเปลี่ยน
      await tester.pump();
      await tester.tap(find.text('ไฟล์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export ภาพ (PNG / SVG)…'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('export-theme')), findsOneWidget);
      expect(find.byKey(const ValueKey('export-area')), findsNothing);
    });

    testWidgets('ภาษาอังกฤษ: แถบเครื่องมือ แผงข้อมูล และกฎแปลครบ', (tester) async {
      await boot(tester, lang: Lang.en);
      expect(find.text('External entity'), findsWidgets);
      expect(find.text('Process'), findsWidgets);
      expect(find.text('Data store'), findsWidgets);
      expect(find.text('The DFD diagram is empty'), findsOneWidget);
      c.project.dfd[c.activeDiagramId] = DfdDiagram(nodes: [proc('p', 0, 0, name: 'X')]);
      d.panBy(Offset.zero); // แจ้งหน้าจอว่าเนื้อหาเปลี่ยน
      await tester.pump();
      expect(find.text('Process is not connected'), findsOneWidget);
      currentLang = Lang.th;
    });
  });
}

const kDfdTestPalette1 = 0xFF9333EA;
