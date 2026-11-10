import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/layout/flowchart_geometry.dart';
import 'package:nsl_dev/core/layout/ortho_route.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/flowchart_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

/// จุดต่อเส้นที่โผล่ตอนชี้สัญลักษณ์ (แบบ draw.io): คลิก = สร้างสัญลักษณ์ต่อ, ลากไปสัญลักษณ์อื่น = ต่อเส้น,
/// ลากไปที่ว่าง = สร้างสัญลักษณ์ใหม่ตรงนั้น
void main() {
  group('เรขาคณิตของจุดต่อเส้น', () {
    final n = FcNode(id: 'n', shape: FcShape.process, x: 100, y: 100); // 160x64
    test('ตำแหน่งจุดอยู่นอกขอบตามด้าน', () {
      expect(fcLinkHandlePos(n, RouteSide.bottom, 18), (180.0, 182.0));
      expect(fcLinkHandlePos(n, RouteSide.top, 18), (180.0, 82.0));
      expect(fcLinkHandlePos(n, RouteSide.left, 18), (82.0, 132.0));
      expect(fcLinkHandlePos(n, RouteSide.right, 18), (278.0, 132.0));
    });

    test('ชี้จุดไหนได้ด้านนั้น ; ชี้ที่อื่น = null', () {
      expect(fcLinkHandleAt(n, 180, 182, gap: 18, radius: 9), RouteSide.bottom);
      expect(fcLinkHandleAt(n, 185, 186, gap: 18, radius: 9), RouteSide.bottom);
      expect(fcLinkHandleAt(n, 180, 132, gap: 18, radius: 9), isNull); // กลางตัวสัญลักษณ์
      expect(fcLinkHandleAt(n, 180, 210, gap: 18, radius: 9), isNull);
    });

    test('ศูนย์กลางสัญลักษณ์ถัดไปห่างจากต้นทางตามระยะที่กำหนด', () {
      final (cx, cy) = fcNextNodeCenter(n, RouteSide.bottom, FcShape.process);
      expect(cx, n.cx);
      expect(cy, n.bottom + 60 + 32);
      final (rx, ry) = fcNextNodeCenter(n, RouteSide.right, FcShape.process);
      expect(rx, n.right + 60 + 80);
      expect(ry, n.cy);
    });

    test('จุดไม่หายตอนเมาส์ข้ามช่องว่างระหว่างตัวสัญลักษณ์กับจุด', () {
      final d = FlowchartDiagram(nodes: [n]);
      expect(fcLinkHoverNode(d, 180, 170, gap: 18, radius: 9)?.id, 'n'); // ช่องว่างใต้ตัว
      expect(fcLinkHoverNode(d, 180, 400, gap: 18, radius: 9), isNull);
    });
  });

  group('หน้าจอ', () {
    late WorkspaceController w;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      await tester.pump();
    }

    FlowchartController fc(WidgetTester tester) => tester.element(find.byType(HomePage)).read<FlowchartController>();

    Future<FlowchartController> addFlow(WidgetTester tester, FlowchartDiagram content) async {
      final doc = w.addDocument(DocType.flowchart, name: 'Login')!;
      doc.content = content;
      await tester.pump();
      return fc(tester);
    }

    Offset screen(WidgetTester tester, FlowchartController f, double x, double y) =>
        tester.getTopLeft(find.byKey(const ValueKey('fc-canvas'))) + f.toScreen(Offset(x, y));

    FlowchartDiagram two({FcShape top = FcShape.start}) => FlowchartDiagram(nodes: [
          FcNode(id: 'a', shape: top, text: 'Begin', x: 100, y: 100),
          FcNode(id: 'b', shape: FcShape.process, text: 'Work', x: 100, y: 400),
        ]);

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    // a = เริ่มต้น 140x50 ที่ (100,100) → จุดล่างอยู่ที่ (170, 150+18)
    Offset bottomHandleOfA(WidgetTester tester, FlowchartController f) {
      final s = f.scale;
      return screen(tester, f, 170, 150 + 18 / s);
    }

    testWidgets('คลิกจุดต่อเส้นด้านล่าง = สร้างสัญลักษณ์ใหม่พร้อมเส้น เปิดช่องพิมพ์ ; undo ขั้นเดียว', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      await tester.tapAt(bottomHandleOfA(tester, f));
      await tester.pumpAndSettle();
      expect(f.diagram.nodes.length, 3);
      expect(f.diagram.edges.length, 1);
      final made = f.diagram.nodes.last;
      expect(made.shape, FcShape.process);
      expect(f.diagram.edges.single.fromId, 'a');
      expect(f.diagram.edges.single.toId, made.id);
      expect(made.y, greaterThan(150)); // อยู่ใต้ต้นทาง
      expect(f.editing, (id: made.id, isEdge: false));
      f.cancelEditing();
      f.undo();
      await tester.pump();
      expect(f.diagram.nodes.length, 2);
      expect(f.diagram.edges, isEmpty);
    });

    testWidgets('ลากจากจุดต่อเส้นไปบนสัญลักษณ์อื่น = ต่อเส้น ไม่สร้างสัญลักษณ์ใหม่', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      await drag(tester, bottomHandleOfA(tester, f), screen(tester, f, 180, 430));
      expect(f.diagram.nodes.length, 2);
      expect(f.diagram.edges.single.fromId, 'a');
      expect(f.diagram.edges.single.toId, 'b');
    });

    testWidgets('ลากจากจุดต่อเส้นไปที่ว่าง = สร้างสัญลักษณ์ใหม่ตรงนั้นพร้อมเส้น', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      await drag(tester, bottomHandleOfA(tester, f), screen(tester, f, 600, 250));
      expect(f.diagram.nodes.length, 3);
      final made = f.diagram.nodes.last;
      expect(made.cx, closeTo(600, 12));
      expect(made.cy, closeTo(250, 12));
      expect(f.diagram.edges.single.fromId, 'a');
      expect(f.diagram.edges.single.toId, made.id);
      f.cancelEditing();
      f.undo();
      await tester.pump();
      expect(f.diagram.nodes.length, 2);
      expect(f.diagram.edges, isEmpty);
    });

    testWidgets('ปล่อยใกล้ตัวต้นทางเอง = ไม่เกิดอะไร', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      await drag(tester, bottomHandleOfA(tester, f), screen(tester, f, 170, 125));
      expect(f.diagram.nodes.length, 2);
      expect(f.diagram.edges, isEmpty);
    });

    testWidgets('ต้นทางเป็นการตัดสินใจ: เปิดช่องพิมพ์ป้ายเส้นก่อน', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two(top: FcShape.decision));
      // การตัดสินใจ 150x90 ที่ (100,100) → จุดล่างอยู่ที่ (175, 190+18)
      await tester.tapAt(screen(tester, f, 175, 190 + 18 / f.scale));
      await tester.pumpAndSettle();
      expect(f.diagram.edges.length, 1);
      expect(f.editing, (id: f.diagram.edges.single.id, isEdge: true));
    });
  });
}
