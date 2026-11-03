import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/ui/export/text_export_dialog.dart';
import 'package:nsl_modeler/ui/file_actions.dart';

import 'migration_fixtures.dart';

void main() {
  Future<void> open(WidgetTester tester, {TextExportKind kind = TextExportKind.dictionary}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => TextExportDialog(project: base(), initial: kind),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder rich(String s) => find.textContaining(s, findRichText: true);

  testWidgets('เริ่มที่ Data dictionary และสลับแท็บแล้วเนื้อหาเปลี่ยน', (tester) async {
    await open(tester);
    expect(rich('Data Dictionary'), findsOneWidget);
    expect(rich('erDiagram'), findsNothing);

    await tester.tap(find.text('Mermaid'));
    await tester.pumpAndSettle();
    expect(rich('erDiagram'), findsOneWidget);
    expect(find.textContaining('GitHub'), findsOneWidget); // คำอธิบายการใช้งาน

    await tester.tap(find.text('DBML'));
    await tester.pumpAndSettle();
    expect(rich('Table users {'), findsOneWidget);
  });

  testWidgets('ข้อมูลตัวอย่าง: เปลี่ยนจำนวนแถวแล้วสร้างใหม่', (tester) async {
    await open(tester, kind: TextExportKind.sample);
    expect(rich('INSERT INTO `users`'), findsOneWidget);
    final dropdown = find.byType(DropdownButton<int>);
    expect(tester.widget<DropdownButton<int>>(dropdown).value, 10); // ค่าเริ่มต้น
    expect(rich('(10 แถวต่อตาราง)'), findsOneWidget);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last); // รายการในเมนู
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<int>>(dropdown).value, 5);
    expect(rich('(5 แถวต่อตาราง)'), findsOneWidget);
    expect(rich('(10 แถวต่อตาราง)'), findsNothing);
  });

  testWidgets('คัดลอกส่งเนื้อหาของแท็บปัจจุบัน', (tester) async {
    await open(tester, kind: TextExportKind.dbml);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(find.text('คัดลอก'));
    await tester.pump();
    expect(copied, contains('Table users {'));
    expect(copied, contains('Ref: orders.user_id > users.id'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('ข้อความที่ไม่ใช่ SQL ไม่ถูกไฮไลต์ (สีเดียว)', (tester) async {
    await open(tester, kind: TextExportKind.dictionary);
    // ไม่มี TextSpan ลูกที่ระบายสี keyword ในแท็บ Markdown: ทุก span เป็นข้อความตรง ๆ
    final spans = tester.widgetList<RichText>(find.byType(RichText)).where((r) => r.text.toPlainText().contains('Data Dictionary'));
    expect(spans, isNotEmpty);
    final root = spans.first.text as TextSpan;
    expect(root.children!.every((c) => (c as TextSpan).style == null), true);
  });

  test('safeName / ชื่อไฟล์', () {
    expect(FileActions.safeName('a/b:c'), 'a_b_c');
    expect(FileActions.safeName('   '), 'schema');
    expect(FileActions.sqlFileName('shop', Dialect.sqlite), 'shop_sqlite.sql');
  });
}
