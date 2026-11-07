import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/layout/dfd_resize.dart';
import 'package:nsl_dev/core/layout/flowchart_layout.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/state/flowchart_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';

void main() {
  late WorkspaceController w;
  late FlowchartController f;

  setUp(() {
    w = WorkspaceController();
    final doc = w.addDocument(DocType.flowchart)!;
    f = w.flowchartController(doc.id)!;
  });
  tearDown(() => w.dispose());

  String snap() => jsonEncode(f.diagram.toJson());

  group('เอกสาร', () {
    test('เพิ่ม Flowchart: ชื่อ "Flowchart", เปิดเป็นแท็บที่ใช้งาน, controller ปัจจุบันคือตัวนี้', () {
      expect(w.activeDocument.name, 'Flowchart');
      expect(w.activeDocument.type, DocType.flowchart);
      expect(w.currentFlowchart, same(f));
      expect(w.structureDirty, isTrue);
      final second = w.addDocument(DocType.flowchart)!;
      expect(second.name, 'Flowchart 2');
      expect(w.renameDocument(second.id, 'flowchart'), isFalse); // ชื่อซ้ำทั้งโปรเจกต์ (ไม่สนตัวพิมพ์)
    });

    test('แท็บที่ไม่ใช่ Flowchart: ตัวแทนว่างแก้ไขไม่ได้', () {
      w.openDocument(w.mainEr.docId);
      final ph = w.currentFlowchart;
      expect(ph, isNot(same(f)));
      expect(ph.active, isFalse);
      expect(ph.addNode(FcShape.process, 0, 0), isNull);
      expect(ph.diagram.nodes, isEmpty);
    });

    test('ทำสำเนาเอกสาร: เนื้อหาแยกขาด ประวัติเริ่มใหม่ ; ลบได้ไม่มีกล่องลิงก์', () {
      f.addNode(FcShape.start, 100, 100);
      final copy = w.duplicateDocument(f.docId)!;
      expect(copy.type, DocType.flowchart);
      expect(copy.name, 'Flowchart 2');
      final c2 = w.flowchartController(copy.id)!;
      expect(c2.diagram.nodes.length, 1);
      expect(c2.canUndo, isFalse);
      c2.addNode(FcShape.end, 0, 0);
      expect(f.diagram.nodes.length, 1);
      expect(w.backlinksOf(f.docId), isEmpty);
      expect(w.canDeleteDocument(f.docId), isTrue);
      w.deleteDocument(f.docId);
      expect(w.documentById(f.docId), isNull);
      expect(f.active, isFalse);
    });

    test('บันทึก/เปิดผ่าน codec ได้เนื้อหาเดิม', () {
      f.addNode(FcShape.start, 0, 0);
      final n2 = f.addNode(FcShape.end, 0, 200)!;
      f.addEdge(f.diagram.nodes.first.id, n2.id, label: 'go');
      final back = decodeProjectMap(jsonDecode(jsonEncode(encodeProjectMap(w.workspace))) as Map<String, dynamic>);
      expect(jsonEncode(back.documentById(f.docId)!.flowchart!.toJson()), snap());
    });
  });

  group('undo/redo ต่อเอกสาร', () {
    test('แก้แล้ว undo/redo ; Flowchart สองแท็บไม่ย้อนของกันและกัน ; ER ไม่ถูกแตะ', () {
      final g = w.flowchartController(w.addDocument(DocType.flowchart)!.id)!;
      f.addNode(FcShape.process, 0, 0);
      g.addNode(FcShape.decision, 0, 0);
      g.addNode(FcShape.end, 0, 0);
      expect(f.diagram.nodes.length, 1);
      f.undo();
      expect(f.diagram.nodes, isEmpty);
      expect(g.diagram.nodes.length, 2);
      f.redo();
      expect(f.diagram.nodes.length, 1);
      expect(w.mainEr.canUndo, isFalse);
      // undo ผ่าน WorkspaceController ใช้แท็บที่เปิดอยู่
      w.openDocument(g.docId);
      w.undo();
      expect(g.diagram.nodes.length, 1);
      expect(f.diagram.nodes.length, 1);
    });

    test('ลากย้าย/ปรับขนาด = undo ขั้นเดียว ; ไม่ขยับ = ไม่เข้าประวัติ', () {
      final n = f.addNode(FcShape.process, 0, 0)!;
      final x0 = n.x;
      final before = f.history.undoLength;
      f.beginMove();
      f.moveBy(10, 0);
      f.moveBy(15, 5);
      f.endMove();
      expect(f.diagram.nodeById(n.id)!.x, x0 + 25);
      expect(f.history.undoLength, before + 1);
      f.beginMove();
      f.endMove();
      expect(f.history.undoLength, before + 1);
      f.undo();
      expect(f.diagram.nodeById(n.id)!.x, x0);
      // snap: เลื่อนตามช่องตาราง
      f.selectNode(n.id);
      f.beginMove();
      f.moveBy(13, 0, grid: 20);
      f.endMove();
      expect((f.diagram.nodeById(n.id)!.x) % 20, closeTo(0, 0.001));

      f.selectNode(n.id);
      f.beginResize(DfdHandle.se);
      f.resizeBy(40, 10);
      f.endResize();
      final r = f.diagram.nodeById(n.id)!;
      expect((r.w, r.h), (200.0, 74.0));
      f.beginResize(DfdHandle.se);
      f.resizeBy(-1000, -1000);
      f.endResize();
      expect(f.diagram.nodeById(n.id)!.w, kFcMinSide);
    });

    test('แก้รูปแบบที่ไม่เปลี่ยนค่า = ไม่เข้าประวัติ ; หลายชิ้น = undo ขั้นเดียว', () {
      final a = f.addNode(FcShape.process, 0, 0)!;
      final b = f.addNode(FcShape.process, 300, 0)!;
      final before = f.history.undoLength;
      f.setNodesStyle([a.id, b.id], (n) => n.bold = false);
      expect(f.history.undoLength, before);
      f.setNodesStyle([a.id, b.id], (n) {
        n.fill = 0xFF00FF00;
        n.fontSize = 18;
      });
      expect(f.history.undoLength, before + 1);
      expect(f.diagram.nodes.every((n) => n.fill == 0xFF00FF00 && n.fontSize == 18), isTrue);
      f.undo();
      expect(f.diagram.nodes.every((n) => n.fill == null), isTrue);
      f.setShape([a.id], FcShape.decision);
      expect(f.diagram.nodeById(a.id)!.shape, FcShape.decision);
    });
  });

  group('สัญลักษณ์และเส้น', () {
    test('วางสัญลักษณ์: ข้อความเริ่มต้นตามชนิด, เลือกตัวใหม่, กลับเครื่องมือเลือก ; snap', () {
      f.setShapeTool(FcShape.decision);
      final n = f.addNode(FcShape.decision, 103, 77, snap: true)!;
      expect(n.text, isNotEmpty);
      expect(n.x % 20, 0);
      expect(f.selectedNodeIds, {n.id});
      expect(f.tool, FcTool.select);
      expect(f.addNode(FcShape.connector, 0, 0)!.text, '');
    });

    test('เครื่องมือ Start/End: ยังไม่มีเริ่มต้น = เริ่มต้น ไม่งั้น = สิ้นสุด', () {
      f.setTerminatorTool();
      expect((f.tool, f.toolShape), (FcTool.shape, FcShape.start));
      f.addNode(FcShape.start, 0, 0);
      f.setTerminatorTool();
      expect(f.toolShape, FcShape.end);
      f.escape();
      expect(f.tool, FcTool.select);
    });

    test('ต่อเส้นด้วยการคลิกสองครั้ง ; แก้ป้าย สลับทิศ หัวลูกศร ; ลบสัญลักษณ์แล้วเส้นที่ต่ออยู่หายไปด้วย', () {
      final a = f.addNode(FcShape.process, 0, 0)!;
      final b = f.addNode(FcShape.end, 0, 200)!;
      f.setTool(FcTool.edge);
      expect(f.linkClick(a.id), isNull);
      expect(f.linkSource, a.id);
      final e = f.linkClick(b.id)!;
      expect((e.fromId, e.toId), (a.id, b.id));
      expect(f.selectedEdgeId, e.id);
      f.setEdgeLabel(e.id, 'Yes');
      f.reverseEdge(e.id);
      f.updateEdge(e.id, (x) {
        x.dash = FcDash.dashed;
        x.startArrow = FcArrow.open;
      });
      final got = f.diagram.edgeById(e.id)!;
      expect((got.fromId, got.label, got.dash, got.startArrow), (b.id, 'Yes', FcDash.dashed, FcArrow.open));
      final before = f.history.undoLength;
      f.updateEdge(e.id, (x) => x.label = 'Yes');
      expect(f.history.undoLength, before);
      f.selectNode(a.id);
      expect(f.deleteSelection(), 1);
      expect(f.diagram.edges, isEmpty);
      f.undo();
      expect(f.diagram.edges.length, 1);
    });

    test('จัดแนว / กระจาย / ขนาดเท่ากัน / ลำดับการซ้อน', () {
      final a = f.addNode(FcShape.process, 100, 100)!;
      final b = f.addNode(FcShape.process, 400, 160)!;
      final c = f.addNode(FcShape.decision, 1000, 40)!;
      expect(f.align(FcAlignKind.left), isFalse); // เลือกชิ้นเดียว
      f.setNodeSelection([a.id, b.id, c.id]);
      f.align(FcAlignKind.top);
      expect(f.diagram.nodes.map((n) => n.y).toSet().length, 1);
      f.align(FcAlignKind.left);
      expect(f.diagram.nodes.map((n) => n.x).toSet().length, 1);
      f.undo();
      f.distribute(horizontal: true);
      final xs = [for (final id in [a.id, b.id, c.id]) f.diagram.nodeById(id)!];
      final gap1 = xs[1].x - xs[0].right, gap2 = xs[2].x - xs[1].right;
      expect(gap1, closeTo(gap2, 0.001));
      final before = f.history.undoLength;
      f.distribute(horizontal: true); // กระจายแล้วอีกรอบ = ไม่เปลี่ยน ไม่เข้าประวัติ
      expect(f.history.undoLength, before);
      f.sameSize();
      expect(f.diagram.nodes.map((n) => '${n.w}x${n.h}').toSet().length, 1);
      f.setNodeSelection([a.id]);
      f.reorder(front: true);
      expect(f.diagram.nodes.last.id, a.id);
      f.reorder(front: false);
      expect(f.diagram.nodes.first.id, a.id);
    });

    test('ทำสำเนา / คัดลอก-วาง (ข้ามโปรเจกต์) ได้ id ใหม่ เลื่อนตำแหน่ง พร้อมเส้นระหว่างกัน ; undo ขั้นเดียว', () {
      final a = f.addNode(FcShape.start, 0, 0)!;
      final b = f.addNode(FcShape.end, 0, 200)!;
      f.addEdge(a.id, b.id, label: 'go');
      f.setNodeSelection([a.id, b.id]);
      expect(f.duplicateSelection(), 2);
      expect(f.diagram.nodes.length, 4);
      expect(f.diagram.edges.length, 2);
      expect(f.selectedNodeIds.intersection({a.id, b.id}), isEmpty);
      f.undo();
      expect(f.diagram.nodes.length, 2);

      f.setNodeSelection([a.id, b.id]);
      final text = f.copySelectionText()!;
      final other = WorkspaceController();
      addTearDown(other.dispose);
      final g = other.flowchartController(other.addDocument(DocType.flowchart)!.id)!;
      expect(g.pasteText(text, offset: 60), 2);
      expect(g.diagram.edges.single.label, 'go');
      expect(g.diagram.nodes.first.x, a.x + 60);
      expect(g.pasteText('not a flowchart'), 0);
      expect(g.pasteText('{"format":"nsl-modeler-dfd","version":1,"nodes":[]}'), 0);
    });

    test('จัดวางอัตโนมัติบนลงล่าง: undo ขั้นเดียว ; จัดซ้ำ = false', () {
      final a = f.addNode(FcShape.start, 500, 500)!;
      final b = f.addNode(FcShape.process, 0, 0)!;
      final c = f.addNode(FcShape.end, 900, 10)!;
      f.addEdge(a.id, b.id);
      f.addEdge(b.id, c.id);
      expect(f.autoLayout(), isTrue);
      final y = [for (final id in [a.id, b.id, c.id]) f.diagram.nodeById(id)!.y];
      expect(y[0] < y[1] && y[1] < y[2], isTrue);
      expect(f.autoLayout(), isFalse);
      expect(f.autoLayout(kind: FcLayoutKind.leftRight), isTrue);
      f.undo();
      f.undo();
      expect(f.diagram.nodeById(a.id)!.x, 500 - fcDefaultSize(FcShape.start).$1 / 2);
    });
  });

  group('พิมพ์ข้อความบนแคนวาส', () {
    test('เริ่ม/บันทึก/ยกเลิก ; undo ย้อนข้อความ ; ป้ายเส้นตัดช่องว่าง', () {
      final a = f.addNode(FcShape.process, 0, 0)!;
      f.beginEditNode(a.id);
      expect(f.editing, (id: a.id, isEdge: false));
      f.commitEditing('บรรทัด 1\nบรรทัด 2');
      expect(f.editing, isNull);
      expect(f.diagram.nodeById(a.id)!.text, 'บรรทัด 1\nบรรทัด 2');
      f.beginEditNode(a.id);
      f.escape();
      expect(f.editing, isNull);
      expect(f.diagram.nodeById(a.id)!.text, 'บรรทัด 1\nบรรทัด 2');
      f.undo();
      expect(f.diagram.nodeById(a.id)!.text, isNot(contains('บรรทัด')));

      final b = f.addNode(FcShape.end, 0, 300)!;
      final e = f.addEdge(a.id, b.id)!;
      f.beginEditEdge(e.id);
      f.commitEditing('  Yes ');
      expect(f.diagram.edgeById(e.id)!.label, 'Yes');
    });

    test('undo ทำให้สิ่งที่กำลังแก้/เลือกหายไป = ล้างสถานะ', () {
      final a = f.addNode(FcShape.process, 0, 0)!;
      f.beginEditNode(a.id);
      f.undo();
      expect(f.editing, isNull);
      expect(f.selectedNodeIds, isEmpty);
    });
  });

  group('มุมมอง', () {
    test('ซูม/เลื่อน แยกต่อแท็บ ; พอดีหน้าจอ ; พอดีกับที่เลือก', () {
      final g = w.flowchartController(w.addDocument(DocType.flowchart)!.id)!;
      f.zoomAt(const Offset(100, 100), 2);
      expect(f.scale, 2);
      expect(g.scale, 1);
      f.zoomAt(Offset.zero, 100);
      expect(f.scale, 3);
      final a = f.addNode(FcShape.process, 0, 0)!;
      f.addNode(FcShape.process, 2000, 2000);
      f.fit(const Size(800, 600));
      expect(f.scale, lessThan(1));
      f.selectNode(a.id);
      f.fitSelection(const Size(800, 600));
      expect(f.scale, greaterThan(1));
      final c = f.toScreen(Offset(a.cx, a.cy));
      expect(c.dx, closeTo(400, 0.5));
      expect(f.toWorld(c).dx, closeTo(a.cx, 0.001));
    });
  });
}
