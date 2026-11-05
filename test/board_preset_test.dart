import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/layout/diagram_geometry.dart';
import 'package:nsl_dev/core/models/board_presets.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/board_size_dialog.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

void main() {
  group('โมเดล / ไฟล์', () {
    test('ค่าเริ่มต้นคือ preset กลาง', () {
      final p = Project();
      expect((p.boardWidth, p.boardHeight), (kDefaultBoardWidth, kDefaultBoardHeight));
      expect(kBoardPresets.any((x) => x.matches(p.boardWidth, p.boardHeight)), true);
    });

    test('บันทึกแล้วเปิดกลับมาได้ขนาดเดิม', () {
      final p = Project(boardWidth: 5000, boardHeight: 3200);
      final back = ProjectFile.decode(ProjectFile.encode(p));
      expect((back.boardWidth, back.boardHeight), (5000.0, 3200.0));
    });

    test('ไฟล์เก่าที่ไม่มีฟิลด์ board = ใช้ค่าเริ่มต้น', () {
      final j = Project().toJson()..remove('board');
      final back = Project.fromJson(j);
      expect((back.boardWidth, back.boardHeight), (kDefaultBoardWidth, kDefaultBoardHeight));
    });

    test('ค่าในไฟล์ที่ผิดปกติ (ติดลบ/ใหญ่เกิน/ไม่ใช่ตัวเลข) ถูกแทนด้วยค่าเริ่มต้น', () {
      for (final bad in [
        {'width': -5, 'height': 100000},
        {'width': 'abc', 'height': null},
        {'width': 10, 'height': 10},
      ]) {
        final j = Project().toJson()..['board'] = bad;
        final back = Project.fromJson(j);
        expect((back.boardWidth, back.boardHeight), (kDefaultBoardWidth, kDefaultBoardHeight), reason: '$bad');
      }
    });

    test('กรอบกระดานใช้ขนาดของโปรเจกต์เป็นขั้นต่ำ', () {
      final b = boardBounds(Project(boardWidth: 4000, boardHeight: 2500));
      expect((b.left, b.top, b.right, b.bottom), (0.0, 0.0, 4000.0, 2500.0));
    });

    test('ตรวจค่าที่กรอกเอง', () {
      expect(validateBoardSide('abc'), isNotNull);
      expect(validateBoardSide(''), isNotNull);
      expect(validateBoardSide('799'), isNotNull);
      expect(validateBoardSide('20001'), isNotNull);
      expect(validateBoardSide('800'), isNull);
      expect(validateBoardSide(' 3000 '), isNull);
    });

    test('setBoardSize: undo ได้, บีบให้อยู่ในช่วง, ค่าเดิมไม่สร้างประวัติ', () {
      final c = ProjectController();
      c.setBoardSize(kDefaultBoardWidth, kDefaultBoardHeight);
      expect(c.canUndo, false);
      c.setBoardSize(4000, 99999);
      expect((c.project.boardWidth, c.project.boardHeight), (4000.0, kMaxBoardSide));
      c.undo();
      expect((c.project.boardWidth, c.project.boardHeight), (kDefaultBoardWidth, kDefaultBoardHeight));
    });

    test('newProject รับขนาด', () {
      final c = ProjectController()..newProject(boardWidth: 1600, boardHeight: 1000);
      expect((c.project.boardWidth, c.project.boardHeight), (1600.0, 1000.0));
      c.newProject();
      expect(c.project.boardWidth, kDefaultBoardWidth);
    });
  });

  group('หน้าต่างสร้างโปรเจกต์', () {
    late ProjectController c;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
    }

    Future<void> ctrlN(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+N เปิดหน้าต่างให้เลือก preset แล้วสร้างด้วยขนาดนั้น', (tester) async {
      await boot(tester);
      await ctrlN(tester);
      expect(find.byType(BoardSizeDialog), findsOneWidget);
      for (final p in kBoardPresets) {
        expect(find.byKey(ValueKey('preset-${p.id}')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('preset-custom')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('preset-large')));
      await tester.pump();
      await tester.tap(find.text('สร้าง'));
      await tester.pumpAndSettle();
      expect(find.byType(BoardSizeDialog), findsNothing);
      expect((c.project.boardWidth, c.project.boardHeight), (4000.0, 2500.0));
    });

    testWidgets('กดสร้างทันที = ค่าเริ่มต้น (กลาง) ถูกเลือกไว้แล้ว', (tester) async {
      await boot(tester);
      await ctrlN(tester);
      await tester.tap(find.text('สร้าง'));
      await tester.pumpAndSettle();
      expect((c.project.boardWidth, c.project.boardHeight), (kDefaultBoardWidth, kDefaultBoardHeight));
    });

    testWidgets('กำหนดเอง: กรอกกว้าง/สูงเองแล้วสร้างได้', (tester) async {
      await boot(tester);
      await ctrlN(tester);
      await tester.tap(find.byKey(const ValueKey('preset-custom')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('board-width')), '3000');
      await tester.enterText(find.byKey(const ValueKey('board-height')), '1800');
      await tester.pump();
      await tester.tap(find.text('สร้าง'));
      await tester.pumpAndSettle();
      expect((c.project.boardWidth, c.project.boardHeight), (3000.0, 1800.0));
    });

    testWidgets('กำหนดเอง: ค่าผิดช่วง/ไม่ใช่ตัวเลข = ปุ่มสร้างกดไม่ได้และมีข้อความแจ้ง', (tester) async {
      await boot(tester);
      await ctrlN(tester);
      await tester.tap(find.byKey(const ValueKey('preset-custom')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('board-width')), '100');
      await tester.pump();
      expect(find.textContaining('ต้องอยู่ระหว่าง'), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'สร้าง'));
      expect(btn.onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('board-width')), '');
      await tester.pump();
      expect(find.text('กรอกเป็นตัวเลข'), findsOneWidget);
    });

    testWidgets('ยกเลิก = ไม่สร้างโปรเจกต์ใหม่ และงานเดิมอยู่ครบ', (tester) async {
      await boot(tester);
      c.addTable(name: 'keep');
      await tester.pump();
      c.markSaved('/tmp/x.erd');
      await ctrlN(tester);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(c.project.tables.length, 1);
    });

    testWidgets('เมนูมุมมอง > ขนาดกระดาน เปลี่ยนขนาดของโปรเจกต์ที่เปิดอยู่ (undo ได้)', (tester) async {
      await boot(tester);
      await tester.tap(find.text('มุมมอง'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ขนาดกระดาน…'));
      await tester.pumpAndSettle();
      expect(find.byType(BoardSizeDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('preset-xlarge')));
      await tester.pump();
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
      expect((c.project.boardWidth, c.project.boardHeight), (8000.0, 5000.0));
      c.undo();
      expect(c.project.boardWidth, kDefaultBoardWidth);
    });
  });
}
