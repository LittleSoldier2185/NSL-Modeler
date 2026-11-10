import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/layout/smart_guides.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/flowchart_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

/// เส้นช่วยจัดแนวตอนลากย้าย (smart guide)
void main() {
  group('computeGuides', () {
    const other = Rect.fromLTWH(100, 100, 160, 64); // ซ้าย 100 กลาง 180 ขวา 260 / บน 100 กลาง 132 ล่าง 164

    test('ไม่มีสัญลักษณ์อื่น = ไม่ทำอะไร', () {
      final r = computeGuides(const Rect.fromLTWH(0, 0, 50, 50), const [], tol: 6);
      expect(r.dx, 0);
      expect(r.dy, 0);
      expect(r.lines, isEmpty);
    });

    test('ขอบซ้ายใกล้กัน → ดูดเข้าและมีเส้นตั้งหนึ่งเส้น', () {
      final r = computeGuides(const Rect.fromLTWH(103, 300, 100, 40), const [other], tol: 6);
      expect(r.dx, -3);
      expect(r.dy, 0);
      expect(r.lines.length, 1);
      final l = r.lines.single;
      expect(l.vertical, isTrue);
      expect(l.pos, 100);
      expect(l.from, 100); // ครอบตั้งแต่ขอบบนของตัวบนสุด
      expect(l.to, 340); // ถึงขอบล่างของตัวล่างสุด
    });

    test('กึ่งกลางแนวนอนตรงกัน → ดูดแกน y และมีเส้นนอน', () {
      final r = computeGuides(const Rect.fromLTWH(400, 115, 80, 40), const [other], tol: 6); // กลาง y=135 ห่าง 132 อยู่ 3
      expect(r.dy, -3);
      expect(r.dx, 0);
      final l = r.lines.single;
      expect(l.vertical, isFalse);
      expect(l.pos, 132);
    });

    test('ไกลเกินระยะ = ไม่ดูด ไม่มีเส้น', () {
      final r = computeGuides(const Rect.fromLTWH(120, 300, 100, 40), const [other], tol: 6);
      expect(r.dx, 0);
      expect(r.lines.where((l) => l.vertical), isEmpty);
    });

    test('ชิดทั้งสองแกนพร้อมกันได้ ; เลือกแนวที่ใกล้ที่สุดต่อแกน', () {
      const near = Rect.fromLTWH(500, 500, 40, 40);
      final r = computeGuides(const Rect.fromLTWH(102, 98, 100, 40), const [other, near], tol: 6);
      expect(r.dx, -2);
      expect(r.dy, 2);
      expect(r.lines.length, 2); // ซ้ายตรงซ้าย และบนตรงบน เท่านั้น
    });

    test('ขนาดเท่ากันและเกือบทับกัน → ตรงแนวครบทั้งซ้าย/กลาง/ขวา และบน/กลาง/ล่าง', () {
      final r = computeGuides(const Rect.fromLTWH(102, 98, 160, 64), const [other], tol: 6);
      expect(r.dx, -2);
      expect(r.dy, 2);
      expect(r.lines.length, 6);
    });

    test('หลายสัญลักษณ์อยู่แนวเดียวกัน → รวมเป็นเส้นเดียวที่ครอบทั้งหมด', () {
      const a = Rect.fromLTWH(100, 0, 60, 30);
      const b = Rect.fromLTWH(100, 400, 60, 30);
      final r = computeGuides(const Rect.fromLTWH(100, 200, 60, 30), const [a, b], tol: 6);
      final v = r.lines.where((l) => l.vertical && l.pos == 100).toList();
      expect(v.length, 1);
      expect(v.single.from, 0);
      expect(v.single.to, 430);
    });
  });

  group('ลากย้ายบนแคนวาส', () {
    late WorkspaceController w;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true, snapToGrid: false)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      await tester.pump();
    }

    FlowchartController fc(WidgetTester tester) => tester.element(find.byType(HomePage)).read<FlowchartController>();

    Offset screen(WidgetTester tester, FlowchartController f, double x, double y) =>
        tester.getTopLeft(find.byKey(const ValueKey('fc-canvas'))) + f.toScreen(Offset(x, y));

    Future<FlowchartController> setup(WidgetTester tester) async {
      await boot(tester);
      final doc = w.addDocument(DocType.flowchart, name: 'G')!;
      doc.content = FlowchartDiagram(nodes: [
        FcNode(id: 'a', shape: FcShape.process, text: 'A', x: 100, y: 100), // 160x64
        FcNode(id: 'b', shape: FcShape.process, text: 'B', x: 400, y: 300),
      ]);
      await tester.pump();
      return fc(tester);
    }

    testWidgets('ลาก B ให้เกือบตรงแนวซ้ายของ A → ชิดแนวพอดี และเห็นเส้นช่วยระหว่างลาก ; ปล่อยแล้วเส้นหาย', (tester) async {
      final f = await setup(tester);
      // จับกลาง B (480, 332) ลากไปให้ขอบซ้ายอยู่ที่ x=103 (A อยู่ที่ 100) = เลื่อน dx=-297
      final from = screen(tester, f, 480, 332);
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(from + Offset(-297 * f.scale * i / 10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(f.guides, isNotEmpty);
      expect(f.diagram.nodeById('b')!.x, closeTo(100, 0.001));
      await g.up();
      await tester.pumpAndSettle();
      expect(f.guides, isEmpty);
      expect(f.diagram.nodeById('b')!.x, closeTo(100, 0.001));
      expect(f.diagram.nodeById('b')!.y, closeTo(300, 0.001)); // แกน y ไม่เกี่ยว ไม่ถูกดูด
    });

    testWidgets('กด Alt ค้าง = ไม่ชิดแนว', (tester) async {
      final f = await setup(tester);
      final from = screen(tester, f, 480, 332);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(from + Offset(-297 * f.scale * i / 10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(f.guides, isEmpty);
      expect(f.diagram.nodeById('b')!.x, closeTo(103, 0.5));
      await g.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
    });
  });
}
