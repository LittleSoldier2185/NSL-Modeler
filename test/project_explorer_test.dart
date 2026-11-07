import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

/// ขั้น 8: Project Explorer เหนือแผงซ้าย
void main() {
  late WorkspaceController w;

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, AppSettings? settings}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: settings ?? AppSettings(lang: lang, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    await tester.pump();
  }

  Finder row(String id) => find.byKey(ValueKey('explorer-row-$id'));

  Future<void> rightClick(WidgetTester tester, Finder f) async {
    final g = await tester.startGesture(tester.getCenter(f), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('ปิดไว้เป็นค่าเริ่มต้นของ AppSettings ในเทสต์: ไม่มีแผง', (tester) async {
    await boot(tester, settings: AppSettings(lang: Lang.th));
    expect(find.byKey(const ValueKey('project-explorer')), findsNothing);
  });

  testWidgets('แสดงเอกสารจัดกลุ่ม ER / DFD ตามลำดับ และไฮไลต์เอกสารที่เปิดอยู่', (tester) async {
    await boot(tester);
    final d1 = w.addDocument(DocType.dfd, name: 'Level 0')!;
    final e2 = w.addDocument(DocType.er, name: 'Billing')!;
    await tester.pump();
    expect(find.text('แผนภาพ ER (2)'), findsOneWidget);
    expect(find.text('แผนภาพกระแสข้อมูล (DFD) (1)'), findsOneWidget);
    expect(find.descendant(of: row(d1.id), matching: find.text('Level 0')), findsOneWidget);
    expect(find.descendant(of: row(e2.id), matching: find.text('Billing')), findsOneWidget);
    // ER ก่อน DFD
    expect(tester.getTopLeft(row(e2.id)).dy, lessThan(tester.getTopLeft(row(d1.id)).dy));
    // ยุบกลุ่ม
    await tester.tap(find.byKey(const ValueKey('explorer-group-dfd')));
    await tester.pump();
    expect(row(d1.id), findsNothing);
  });

  testWidgets('คลิกแถว = เปิดเอกสารนั้น (DFD แล้วกลับ ER)', (tester) async {
    await boot(tester);
    final d = w.addDocument(DocType.dfd, name: 'Flow')!;
    w.openDocument(w.mainEr.docId);
    await tester.pump();
    await tester.tap(row(d.id));
    await tester.pump();
    expect(w.activeId, d.id); // เปิดทันที ไม่รอเกณฑ์ดับเบิลคลิก
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(row(w.mainEr.docId));
    await tester.pumpAndSettle();
    expect(w.activeId, w.mainEr.docId);
  });

  testWidgets('เปลี่ยนชื่อด้วย F2 / ดับเบิลคลิก: ชื่อซ้ำถูกปฏิเสธ ชื่อใหม่ผ่าน', (tester) async {
    var t = DateTime(2026, 11, 7, 12); // เวลาจำลอง ไม่ผันตามเวลาจริง
    await withClock(Clock(() => t), () async {
      await boot(tester);
      final d = w.addDocument(DocType.dfd, name: 'Flow')!;
      await tester.pump();
      await tester.tap(row(d.id));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'er'); // ซ้ำกับ ER (ไม่สนตัวพิมพ์)
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
      expect(w.documentById(d.id)!.name, 'Flow');
      expect(find.text('ชื่อว่างหรือซ้ำกับแผนภาพอื่น'), findsOneWidget);

      t = t.add(const Duration(seconds: 1));
      await tester.tap(row(d.id));
      t = t.add(const Duration(milliseconds: 50));
      await tester.tap(row(d.id)); // ดับเบิลคลิก
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Level 1');
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
      expect(w.documentById(d.id)!.name, 'Level 1');
    });
  });

  testWidgets('เมนูคลิกขวา: ทำสำเนา ; ลบมีกล่องยืนยัน (ยกเลิก = ไม่ลบ) ; ER อันสุดท้ายไม่มีเมนูลบ', (tester) async {
    await boot(tester);
    final d = w.addDocument(DocType.dfd, name: 'Flow')!;
    await tester.pump();

    await rightClick(tester, row(w.mainEr.docId));
    expect(find.text('เปลี่ยนชื่อ…'), findsOneWidget);
    expect(find.text('ลบแผนภาพ'), findsNothing); // ER เดียว
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await rightClick(tester, row(d.id));
    await tester.tap(find.text('ทำสำเนาแผนภาพ'));
    await tester.pumpAndSettle();
    expect(w.documents.where((x) => x.type == DocType.dfd).length, 2);

    await rightClick(tester, row(d.id));
    await tester.tap(find.text('ลบแผนภาพ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ลบแผนภาพ "Flow"'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(w.documentById(d.id), isNotNull);

    await rightClick(tester, row(d.id));
    await tester.tap(find.text('ลบแผนภาพ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบ'));
    await tester.pumpAndSettle();
    expect(w.documentById(d.id), isNull);
    expect(row(d.id), findsNothing);
  });

  testWidgets('ปุ่ม + ในหัวแผง: เพิ่ม ER / DFD', (tester) async {
    await boot(tester);
    for (final (label, type) in [('DFD (Data Flow Diagram)', DocType.dfd), ('ER Diagram (ตารางฐานข้อมูล)', DocType.er)]) {
      await tester.tap(find.byKey(const ValueKey('explorer-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(w.activeDocument.type, type);
    }
    expect(w.documents.length, 3);
    expect(row(w.activeId), findsOneWidget);
  });

  testWidgets('เมนูมุมมอง: สลับแสดง/ซ่อน และบันทึกลงไฟล์ตั้งค่า', (tester) async {
    final dir = Directory.systemTemp.createTempSync('explorer_settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/settings.json')..writeAsStringSync('{"lang":"th"}');
    final s = AppSettings.load(file);
    expect(s.showExplorer, isTrue); // ไฟล์ตั้งค่าเก่าที่ไม่มีคีย์ = แสดง
    await boot(tester, settings: s);
    expect(find.byKey(const ValueKey('project-explorer')), findsOneWidget);

    await tester.tap(find.text('มุมมอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('แสดงตัวสำรวจโปรเจกต์'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-explorer')), findsNothing);
    expect(AppSettings.load(file).showExplorer, isFalse);

    await tester.tap(find.text('มุมมอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('แสดงตัวสำรวจโปรเจกต์'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-explorer')), findsOneWidget);
    expect(AppSettings.load(file).showExplorer, isTrue);
  });

  testWidgets('ภาษาอังกฤษ: หัวแผง กลุ่ม เมนู แปลครบ', (tester) async {
    await boot(tester, lang: Lang.en);
    expect(find.text('Project Explorer'), findsOneWidget);
    expect(find.text('ER Diagrams (1)'), findsOneWidget);
    await rightClick(tester, row(w.mainEr.docId));
    expect(find.text('Rename…'), findsOneWidget);
    expect(find.text('Duplicate diagram'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Show Project Explorer'), findsOneWidget);
    currentLang = Lang.th;
  });
}
