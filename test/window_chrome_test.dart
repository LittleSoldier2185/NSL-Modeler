import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:nsl_modeler/ui/window_chrome.dart';
import 'package:provider/provider.dart';

class _FakeWindow implements WindowBackend {
  final calls = <String>[];
  bool maximized = false;
  final _ctl = StreamController<bool>.broadcast();

  @override
  Future<void> minimize() async => calls.add('min');
  @override
  Future<void> toggleMaximize() async {
    calls.add('toggle');
    maximized = !maximized;
    _ctl.add(maximized);
  }

  @override
  Future<void> startDrag() async => calls.add('drag');
  @override
  Future<void> destroy() async => calls.add('destroy');
  @override
  Future<bool> isMaximized() async => maximized;
  @override
  Stream<bool> get maximizedChanges => _ctl.stream;
}

void main() {
  late _FakeWindow win;

  setUp(() {
    win = _FakeWindow();
    WindowChrome.backend = win;
    WindowChrome.leadingInset = 0;
  });
  tearDown(() {
    WindowChrome.backend = null;
    WindowChrome.leadingInset = 0;
    WindowChrome.closeHandler = null;
  });

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: lang)));
    await tester.pump();
  }

  testWidgets('ไม่มี backend (ปกติ/เทสต์) = ไม่มีปุ่มควบคุมหน้าต่าง', (tester) async {
    WindowChrome.backend = null;
    await boot(tester);
    expect(find.byKey(const ValueKey('win-close')), findsNothing);
  });

  testWidgets('มีปุ่ม ย่อ / ขยาย / ปิด บนแถบบน และปุ่มขยายสลับเป็นคืนขนาด', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('win-min')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('win-min')));
    expect(win.calls, ['min']);

    expect(find.byIcon(Icons.crop_square_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('win-max')));
    await tester.pump();
    await tester.pump();
    expect(win.calls.last, 'toggle');
    expect(find.byIcon(Icons.filter_none_rounded), findsOneWidget); // ขยายแล้ว -> ไอคอนคืนขนาด
  });

  testWidgets('ปุ่มปิด: ไม่มีอะไรค้าง = ปิดทันที', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('win-close')));
    await tester.pumpAndSettle();
    expect(win.calls, ['destroy']);
  });

  testWidgets('ปุ่มปิด: มีการแก้ค้างอยู่ = ถามก่อน ยกเลิก = ไม่ปิด, ไม่บันทึก = ปิด', (tester) async {
    await boot(tester);
    tester.element(find.byType(HomePage)).read<ProjectController>().addTable(name: 'x');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('win-close')));
    await tester.pumpAndSettle();
    expect(find.text('มีการแก้ไขที่ยังไม่ได้บันทึก'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(win.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('win-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ไม่บันทึก'));
    await tester.pumpAndSettle();
    expect(win.calls, ['destroy']);
  });

  testWidgets('ลากพื้นที่ว่างบนแถบบน = ย้ายหน้าต่าง; ดับเบิลคลิก = ขยาย/คืนขนาด', (tester) async {
    // หน้าต่างกว้างพอให้มีที่ว่างบนแถบ (ที่ 1440 กลุ่มปุ่มขวากินพื้นที่ที่เหลือหมด)
    await boot(tester, size: const Size(1900, 900));
    // จุดว่างบนแถบ = ซ้ายของกลุ่มปุ่มขวา
    final blank = tester.getTopLeft(find.byTooltip('ย้อนกลับ (Ctrl+Z)')) + const Offset(-30, 20);
    final g = await tester.startGesture(blank, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await tester.pump();
    expect(win.calls, contains('drag'));

    win.calls.clear();
    await tester.tapAt(blank, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(blank, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(win.calls, contains('toggle'));
  });

  testWidgets('macOS (มี inset ซ้าย) = ไม่วาดปุ่มของเราเอง', (tester) async {
    WindowChrome.leadingInset = 78;
    await boot(tester);
    expect(find.byKey(const ValueKey('win-close')), findsNothing);
  });

  testWidgets('ภาษาอังกฤษ: ทูลทิปปุ่มแปลครบ', (tester) async {
    await boot(tester, lang: Lang.en);
    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Maximize'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    currentLang = Lang.th;
  });
}
