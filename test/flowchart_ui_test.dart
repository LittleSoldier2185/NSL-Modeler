import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/l10n/l10n_en.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/flowchart_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/ui/palette/command_palette.dart';
import 'package:nsl_dev/ui/shortcuts_help.dart';
import 'package:provider/provider.dart';

void main() {
  late WorkspaceController w;
  String? clipboardText;

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, bool explorer = true}) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    clipboardText = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clipboardText};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: explorer)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    await tester.pump();
  }

  FlowchartController fc(WidgetTester tester) => tester.element(find.byType(HomePage)).read<FlowchartController>();

  /// เพิ่ม Flowchart (ใส่เนื้อหาได้) แล้วเปิด
  Future<FlowchartController> addFlow(WidgetTester tester, [FlowchartDiagram? content]) async {
    final doc = w.addDocument(DocType.flowchart, name: 'Login')!;
    if (content != null) doc.content = content;
    await tester.pump();
    final f = fc(tester);
    expect(f.docId, doc.id);
    return f;
  }

  Finder canvas() => find.byKey(const ValueKey('fc-canvas'));
  Offset screen(WidgetTester tester, FlowchartController f, double x, double y) =>
      tester.getTopLeft(canvas()) + f.toScreen(Offset(x, y));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool ctrl = false}) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(k);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  FlowchartDiagram two() => FlowchartDiagram(nodes: [
        FcNode(id: 'a', shape: FcShape.start, text: 'Begin', x: 100, y: 100),
        FcNode(id: 'b', shape: FcShape.process, text: 'Work', x: 100, y: 300),
      ]);

  group('แท็บ / ตัวสำรวจ / Project Home', () {
    testWidgets('ปุ่ม + ของแถบแท็บสร้าง Flowchart แล้วแสดงแคนวาส แผงซ้าย/ขวาของ Flowchart', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('tab-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flowchart (ผังงาน)'));
      await tester.pumpAndSettle();
      expect(w.activeDocument.type, DocType.flowchart);
      expect(w.activeDocument.name, 'Flowchart');
      expect(canvas(), findsOneWidget);
      expect(find.byKey(const ValueKey('fc-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('fc-shape-decision')), findsOneWidget);
      expect(find.text('Export .sql'), findsNothing);
      expect(find.text('Flowchart ว่างอยู่'), findsOneWidget);
      // คลิกขวาที่แท็บ: ทำสำเนา -> ได้ Flowchart 2
      final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('tab-${w.activeId}'))),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('ทำสำเนาแผนภาพ'));
      await tester.pumpAndSettle();
      expect(w.activeDocument.name, 'Flowchart 2');
      expect(w.activeDocument.type, DocType.flowchart);
      // ปุ่ม × ลบได้ (ไม่มีลิงก์ข้ามเอกสาร)
      await tester.tap(find.byKey(ValueKey('tab-close-${w.activeId}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ลิงก์จากแผนภาพอื่น'), findsNothing);
      await tester.tap(find.text('ลบ'));
      await tester.pumpAndSettle();
      expect(w.documents.where((d) => d.type == DocType.flowchart).length, 1);
    });

    testWidgets('ตัวสำรวจ: กลุ่ม "ผังงาน (Flowchart)" และเพิ่มจากปุ่ม + ; ป้ายปัญหา', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('explorer-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flowchart (ผังงาน)'));
      await tester.pumpAndSettle();
      expect(find.text('ผังงาน (Flowchart) (1)'), findsOneWidget);
      final id = w.activeId;
      expect(find.byKey(ValueKey('explorer-row-$id')), findsOneWidget);
      // มีสัญลักษณ์แต่ไม่มีเริ่มต้น/สิ้นสุด = error -> ป้ายตัวเลข
      fc(tester).addNode(FcShape.process, 0, 0);
      await tester.pump();
      expect(find.byKey(ValueKey('explorer-issues-$id')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('explorer-group-flowchart')));
      await tester.pump();
      expect(find.byKey(ValueKey('explorer-row-$id')), findsNothing);
    });

    testWidgets('Project Home: ปุ่มเพิ่ม Flowchart, การ์ด, ตัวเลขสัญลักษณ์ ; คลิกการ์ดเปิดเอกสาร', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      w.showHome();
      await tester.pumpAndSettle();
      final home = find.byKey(const ValueKey('project-home'));
      expect(find.descendant(of: home, matching: find.text('ผังงาน (Flowchart) (1)')), findsOneWidget);
      expect(find.descendant(of: home, matching: find.text('2 สัญลักษณ์ · 0 เส้นเชื่อม')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('home-stat-symbols')), matching: find.text('2')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('home-card-${f.docId}')));
      await tester.pumpAndSettle();
      expect(w.homeView, isFalse);
      expect(w.activeId, f.docId);
      w.showHome();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-add-flowchart')));
      await tester.pumpAndSettle();
      expect(w.activeDocument.name, 'Flowchart');
      expect(w.homeView, isFalse);
    });
  });

  group('แคนวาส', () {
    testWidgets('คีย์ลัด O แล้วคลิก = วางเริ่มต้นและพิมพ์ข้อความทันที ; Ctrl+Enter บันทึก ; undo', (tester) async {
      await boot(tester);
      final f = await addFlow(tester);
      await key(tester, LogicalKeyboardKey.keyO);
      expect((f.tool, f.toolShape), (FcTool.shape, FcShape.start));
      await tester.tapAt(screen(tester, f, 300, 200));
      await tester.pumpAndSettle();
      final n = f.diagram.nodes.single;
      expect(n.shape, FcShape.start);
      final field = find.byKey(const ValueKey('fc-inline-field'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'เริ่มระบบ\nบรรทัดสอง');
      await key(tester, LogicalKeyboardKey.enter, ctrl: true);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(f.diagram.nodes.single.text, 'เริ่มระบบ\nบรรทัดสอง');
      // O ครั้งต่อไป = สิ้นสุด ; พิมพ์ระหว่างแก้ข้อความไม่สลับเครื่องมือ
      await key(tester, LogicalKeyboardKey.keyO);
      expect(f.toolShape, FcShape.end);
      await tester.tapAt(screen(tester, f, 300, 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(f.tool, FcTool.select);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(f.editing, isNull);
      expect(f.diagram.nodes.length, 2);
      await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(f.diagram.nodes.length, 1);
    });

    testWidgets('ดับเบิลคลิกสัญลักษณ์ = พิมพ์ข้อความ ; คลิกที่อื่น = บันทึก ; F2 ; Esc ยกเลิก', (tester) async {
      var t = DateTime(2026, 11, 7, 12);
      await withClock(Clock(() => t), () async {
        await boot(tester);
        final f = await addFlow(tester, two());
        final at = screen(tester, f, 170, 330);
        await tester.tapAt(at);
        t = t.add(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        expect(f.editing, (id: 'b', isEdge: false));
        await tester.enterText(find.byKey(const ValueKey('fc-inline-field')), 'Check');
        await tester.tapAt(screen(tester, f, 500, 450));
        await tester.pumpAndSettle();
        expect(f.diagram.nodeById('b')!.text, 'Check');
        expect(f.editing, isNull);

        f.selectNode('a');
        await tester.pump();
        await key(tester, LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        expect(f.editing, (id: 'a', isEdge: false));
        await tester.enterText(find.byKey(const ValueKey('fc-inline-field')), 'ignored');
        await key(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(f.diagram.nodeById('a')!.text, 'Begin');
      });
    });

    testWidgets('ลากจากคลังสัญลักษณ์มาวางบนแคนวาส', (tester) async {
      await boot(tester);
      final f = await addFlow(tester);
      final from = tester.getCenter(find.byKey(const ValueKey('fc-shape-decision')));
      final to = screen(tester, f, 400, 300);
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(f.diagram.nodes.single.shape, FcShape.decision);
      expect(f.editing?.id, f.diagram.nodes.single.id);
    });

    testWidgets('เครื่องมือเส้น (F): คลิกต้นทาง/ปลายทาง ; ลากย้าย ; กรอบเลือก ; Delete ; Ctrl+C/V', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      await key(tester, LogicalKeyboardKey.keyF);
      expect(f.tool, FcTool.edge);
      await tester.tapAt(screen(tester, f, 170, 125));
      await tester.pump();
      await tester.tapAt(screen(tester, f, 170, 330));
      await tester.pumpAndSettle();
      expect(f.diagram.edges.single.fromId, 'a');
      expect(f.diagram.edges.single.toId, 'b');

      await key(tester, LogicalKeyboardKey.escape); // กลับเครื่องมือเลือก
      // ลากย้าย b
      final x0 = f.diagram.nodeById('b')!.x;
      await tester.dragFrom(screen(tester, f, 170, 330), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(f.diagram.nodeById('b')!.x, greaterThan(x0 + 50));

      // กรอบเลือกทั้งหมด
      await tester.dragFrom(screen(tester, f, 20, 20), const Offset(600, 500));
      await tester.pumpAndSettle();
      expect(f.selectedNodeIds, {'a', 'b'});
      await key(tester, LogicalKeyboardKey.keyC, ctrl: true);
      await tester.pumpAndSettle();
      expect(clipboardText, contains('nsl-dev-flowchart'));
      await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await tester.pumpAndSettle();
      expect(f.diagram.nodes.length, 4);
      expect(f.diagram.edges.length, 2);
      await key(tester, LogicalKeyboardKey.delete);
      expect(f.diagram.nodes.length, 2);
      await key(tester, LogicalKeyboardKey.keyD, ctrl: true); // ไม่มีอะไรเลือก = ไม่ทำอะไร
      expect(f.diagram.nodes.length, 2);
    });

    testWidgets('แผงขวา: เลือกสัญลักษณ์แก้สีพื้น/รูปทรง ; หลายชิ้นจัดแนว ; เส้นแก้หัวลูกศร ; ไม่เลือก = ผลตรวจ', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      expect(find.byKey(const ValueKey('fc-issue-fc_no_end-null')), findsOneWidget);
      f.selectNode('b');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fc-fill-0')));
      await tester.pump();
      expect(f.diagram.nodeById('b')!.fill, isNotNull);
      await tester.tap(find.byKey(const ValueKey('fc-bold')));
      await tester.pump();
      expect(f.diagram.nodeById('b')!.bold, isTrue);
      f.setNodeSelection(['a', 'b']);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fc-al-left')));
      await tester.pump();
      expect(f.diagram.nodeById('a')!.x, f.diagram.nodeById('b')!.x);
      final e = f.addEdge('a', 'b')!;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fc-reverse')));
      await tester.pump();
      expect(f.diagram.edgeById(e.id)!.fromId, 'b');
      await tester.tap(find.byKey(const ValueKey('fc-edge-color-1')));
      await tester.pump();
      expect(f.diagram.edgeById(e.id)!.color, isNotNull);
    });

    testWidgets('คลิกขวาพื้นว่าง: วางสัญลักษณ์ ; ปุ่มจัดวางอัตโนมัติ', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two()..edges.add(FcEdge(id: 'k', fromId: 'a', toId: 'b')));
      final g = await tester.startGesture(screen(tester, f, 600, 600), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('วางการตัดสินใจที่นี่'));
      await tester.pumpAndSettle();
      expect(f.diagram.nodes.last.shape, FcShape.decision);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      f.updateNode('b', (n) => n.x = 900);
      await tester.tap(find.byKey(const ValueKey('fc-autolayout')));
      await tester.pumpAndSettle();
      expect(f.diagram.nodeById('b')!.y, greaterThan(f.diagram.nodeById('a')!.y));
    });

    testWidgets('ซูม/เลื่อนแยกต่อแท็บ และแถบสถานะแสดงสรุปของ Flowchart', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      await tester.tap(find.byKey(const ValueKey('fc-zoom-in')));
      await tester.pump();
      expect(find.byKey(const ValueKey('fc-zoom-label')), findsOneWidget);
      expect(f.scale, closeTo(1.2, 0.001));
      expect(find.textContaining('2 สัญลักษณ์ · 0 เส้นเชื่อม'), findsWidgets);
      w.openDocument(w.mainEr.docId);
      await tester.pumpAndSettle();
      w.openDocument(f.docId);
      await tester.pumpAndSettle();
      expect(fc(tester).scale, closeTo(1.2, 0.001));
      // แท็บ ER: คีย์ของ Flowchart ไม่ทำอะไร
      w.openDocument(w.mainEr.docId);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.keyO);
      await key(tester, LogicalKeyboardKey.keyI);
      expect(f.tool, FcTool.select);
    });
  });

  group('ค้นหา / ช่วยเหลือ / ปัญหา', () {
    testWidgets('palette ":" ค้นสัญลักษณ์ข้ามแท็บ แล้วเปิดแท็บและเลือกให้', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      w.openDocument(w.mainEr.docId);
      await tester.pumpAndSettle();
      final entries = buildPaletteEntries(tester.element(find.byType(HomePage)));
      final hit = paletteResults(entries, ':Work');
      expect(hit.first.kind, PaletteKind.fcNode);
      hit.first.run();
      await tester.pumpAndSettle();
      expect(w.activeId, f.docId);
      expect(f.selectedNodeIds, {'b'});
      expect(paletteResults(entries, '').any((e) => e.kind == PaletteKind.fcNode), isFalse);
    });

    testWidgets('F1 มีกลุ่ม Flowchart', (tester) async {
      await boot(tester);
      await key(tester, LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(ShortcutsHelpDialog), matching: find.text('Flowchart')), findsOneWidget);
      expect(find.text('วางจุดเริ่มต้น / สิ้นสุด (Start / End)'), findsOneWidget);
    });

    testWidgets('หน้าต่างปัญหาทั้งโปรเจกต์: คลิกปัญหาของ Flowchart แล้วไปที่สัญลักษณ์', (tester) async {
      await boot(tester);
      final f = await addFlow(tester, two());
      w.openDocument(w.mainEr.docId);
      await tester.pumpAndSettle();
      w.showHome();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-issues')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Work ไม่ใช่จุดสิ้นสุด'));
      await tester.pumpAndSettle();
      expect(w.activeId, f.docId);
      expect(f.selectedNodeIds, {'b'});
    });
  });

  testWidgets('ภาษาอังกฤษ: แผงซ้าย/ขวา แถบเครื่องมือ และหน้าว่างไม่มีอักษรไทยหลุด', (tester) async {
    await boot(tester, lang: Lang.en);
    final f = await addFlow(tester, two());
    final thai = RegExp(r'[฀-๿]');
    void noThai() {
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        if (t.data == 'Begin' || t.data == 'Work') continue;
        expect(thai.hasMatch(t.data ?? ''), isFalse, reason: t.data);
      }
    }

    noThai();
    expect(find.text('Shape library (10)'), findsOneWidget);
    f.selectNode('b');
    await tester.pump();
    noThai();
    f.setNodeSelection(['a', 'b']);
    await tester.pump();
    noThai();
    f.selectEdge(f.addEdge('a', 'b')!.id);
    await tester.pump();
    noThai();
    for (final m in find.byType(Tooltip).evaluate()) {
      final msg = (m.widget as Tooltip).message ?? '';
      expect(thai.hasMatch(msg), isFalse, reason: msg);
    }
    currentLang = Lang.th;
  });

  test('ข้อความไทยทุกข้อความในโค้ด Flowchart มีคำแปลอังกฤษ', () {
    final files = [
      ...Directory('lib/ui/flowchart').listSync().whereType<File>(),
      File('lib/core/validate/flowchart_validator.dart'),
      File('lib/state/flowchart_controller.dart'),
      File('lib/core/export/flowchart_svg.dart'),
    ];
    final thai = RegExp(r'[฀-๿]');
    final call = RegExp(r"\btr\(\s*'([^'\n]*)'");
    final missing = <String>[];
    for (final f in files) {
      for (final m in call.allMatches(f.readAsStringSync())) {
        final k = m.group(1)!;
        if (thai.hasMatch(k) && !kEn.containsKey(k)) missing.add('${f.path}: $k');
      }
    }
    expect(missing, isEmpty);
  });
}
