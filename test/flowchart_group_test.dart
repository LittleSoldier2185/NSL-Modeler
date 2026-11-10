import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/clipboard/flowchart_clipboard.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/flowchart_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

/// จัดกลุ่มสัญลักษณ์ใน Flowchart (Ctrl+G / Ctrl+Shift+G): เลือก/ย้าย/คัดลอกทั้งกลุ่มพร้อมกัน
void main() {
  group('โมเดล', () {
    test('รหัสกลุ่มบันทึกและอ่านกลับได้ ; ค่าว่าง/ชนิดผิด = ไม่อยู่กลุ่ม', () {
      final d = FlowchartDiagram(nodes: [
        FcNode(id: 'a', shape: FcShape.process, text: 'A', group: 'g1'),
        FcNode(id: 'b', shape: FcShape.process, text: 'B'),
      ]);
      final back = FlowchartDiagram.fromJson(d.toJson());
      expect(back.nodeById('a')!.group, 'g1');
      expect(back.nodeById('b')!.group, isNull);
      expect((d.toJson()['nodes'] as List)[1].containsKey('group'), isFalse); // ไฟล์เก่าไม่เปลี่ยนรูป
      final bad = FlowchartDiagram.fromJson({
        'nodes': [
          {'id': 'x', 'shape': 'process', 'group': ''},
          {'id': 'y', 'shape': 'process', 'group': 5},
        ],
      });
      expect(bad.nodes.map((n) => n.group), [null, null]);
    });

    test('คลิปบอร์ดคงรหัสกลุ่มไว้ให้ตัววางจับคู่ใหม่', () {
      final d = FlowchartDiagram(nodes: [
        FcNode(id: 'a', shape: FcShape.process, group: 'g1'),
        FcNode(id: 'b', shape: FcShape.process, group: 'g1'),
      ]);
      final back = decodeFlowchartClipboard(encodeFlowchartClipboard(d, {'a', 'b'}))!;
      expect(back.nodes.map((n) => n.group), ['g1', 'g1']);
    });
  });

  group('การทำงาน', () {
    late WorkspaceController w;

    Future<FlowchartController> setup(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true, snapToGrid: false)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      await tester.pump();
      final doc = w.addDocument(DocType.flowchart, name: 'G')!;
      doc.content = FlowchartDiagram(nodes: [
        FcNode(id: 'a', shape: FcShape.process, text: 'A', x: 100, y: 100),
        FcNode(id: 'b', shape: FcShape.process, text: 'B', x: 400, y: 100),
        FcNode(id: 'c', shape: FcShape.process, text: 'C', x: 100, y: 400),
      ], edges: [
        FcEdge(id: 'k', fromId: 'a', toId: 'b'),
      ]);
      await tester.pump();
      return tester.element(find.byType(HomePage)).read<FlowchartController>();
    }

    Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey k, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(k);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('Ctrl+G จัดกลุ่ม ; เลือกตัวเดียวในกลุ่ม = ได้ทั้งกลุ่ม ; Ctrl+Shift+G เลิกกลุ่ม ; undo ขั้นเดียว', (tester) async {
      final f = await setup(tester);
      f.setNodeSelection({'a', 'b'});
      await ctrl(tester, LogicalKeyboardKey.keyG);
      final g = f.diagram.nodeById('a')!.group;
      expect(g, isNotNull);
      expect(f.diagram.nodeById('b')!.group, g);
      expect(f.diagram.nodeById('c')!.group, isNull);

      f.selectNode('c');
      f.selectNode('a'); // ไม่ได้ add → แทนที่ด้วยทั้งกลุ่ม
      expect(f.selectedNodeIds, {'a', 'b'});

      await ctrl(tester, LogicalKeyboardKey.keyG, shift: true);
      expect(f.diagram.nodeById('a')!.group, isNull);
      expect(f.diagram.nodeById('b')!.group, isNull);

      f.undo(); // เลิกกลุ่ม → กลับมาเป็นกลุ่ม
      expect(f.diagram.nodeById('a')!.group, g);
      f.undo(); // จัดกลุ่ม → ยังไม่มีกลุ่ม
      expect(f.diagram.nodeById('a')!.group, isNull);
    });

    testWidgets('เลือกน้อยกว่า 2 ตัว = จัดกลุ่มไม่ได้ ; ไม่มีกลุ่ม = เลิกกลุ่มไม่ได้', (tester) async {
      final f = await setup(tester);
      f.selectNode('a');
      expect(f.groupSelection(), isFalse);
      expect(f.ungroupSelection(), isFalse);
      expect(f.diagram.nodes.every((n) => n.group == null), isTrue);
    });

    testWidgets('กรอบเลือกที่แตะตัวเดียวของกลุ่ม = ได้ทั้งกลุ่ม ; Ctrl+คลิกสลับทั้งกลุ่มเข้า/ออก', (tester) async {
      final f = await setup(tester);
      f.setNodeSelection({'a', 'b'});
      f.groupSelection();
      f.clearSelection();
      f.setNodeSelection({'b'});
      expect(f.selectedNodeIds, {'a', 'b'});
      f.selectNode('c', add: true);
      expect(f.selectedNodeIds, {'a', 'b', 'c'});
      f.selectNode('a', add: true); // ถอดทั้งกลุ่มออก
      expect(f.selectedNodeIds, {'c'});
    });

    testWidgets('ย้ายตัวหนึ่งของกลุ่ม = ทั้งกลุ่มเลื่อนเท่ากัน ตัวนอกกลุ่มอยู่ที่เดิม', (tester) async {
      final f = await setup(tester);
      f.setNodeSelection({'a', 'b'});
      f.groupSelection();
      f.clearSelection();
      f.selectNode('b');
      f.beginMove();
      f.moveBy(50, 20);
      f.endMove();
      expect((f.diagram.nodeById('a')!.x, f.diagram.nodeById('a')!.y), (150.0, 120.0));
      expect((f.diagram.nodeById('b')!.x, f.diagram.nodeById('b')!.y), (450.0, 120.0));
      expect((f.diagram.nodeById('c')!.x, f.diagram.nodeById('c')!.y), (100.0, 400.0));
    });

    testWidgets('ทำสำเนากลุ่ม = ได้กลุ่มใหม่ของตัวเอง ไม่ปนกับกลุ่มเดิม', (tester) async {
      final f = await setup(tester);
      f.setNodeSelection({'a', 'b'});
      f.groupSelection();
      final old = f.diagram.nodeById('a')!.group;
      expect(f.duplicateSelection(), 2);
      expect(f.diagram.nodes.length, 5);
      final copies = f.selectedNodes;
      expect(copies.length, 2);
      final ng = copies.first.group;
      expect(ng, isNotNull);
      expect(ng, isNot(old));
      expect(copies.every((n) => n.group == ng), isTrue);
      expect(f.diagram.nodeById('a')!.group, old);
      f.selectNode(copies.first.id); // เลือกสำเนาตัวเดียว → ได้เฉพาะกลุ่มสำเนา
      expect(f.selectedNodeIds, copies.map((n) => n.id).toSet());
    });

    testWidgets('ลบกลุ่มที่เลือก = ลบทุกตัวในกลุ่มพร้อมเส้น', (tester) async {
      final f = await setup(tester);
      f.setNodeSelection({'a', 'b'});
      f.groupSelection();
      f.clearSelection();
      f.selectNode('a');
      expect(f.deleteSelection(), 2);
      expect(f.diagram.nodes.map((n) => n.id), ['c']);
      expect(f.diagram.edges, isEmpty);
    });
  });
}
