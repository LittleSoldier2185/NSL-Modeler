import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/ui/file_actions.dart';
import 'package:nsl_modeler/ui/migration_dialog.dart';

import 'migration_fixtures.dart';

void main() {
  Future<void> open(WidgetTester tester, MigrationDialog dialog) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(context: ctx, builder: (_) => dialog),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('แสดงรายการเปลี่ยนแปลง คำเตือนข้อมูลหาย และสคริปต์', (tester) async {
    final a = base();
    final b = clone(a);
    tb(b, 'tu').columns.removeWhere((c) => c.id == 'u4');
    tb(b, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
    await open(tester, MigrationDialog(old: a, neu: b, oldLabel: 'v1.erd'));

    expect(find.text('Migration: v1.erd → โปรเจกต์ปัจจุบัน'), findsOneWidget);
    expect(find.textContaining('2 การเปลี่ยนแปลง · สร้างสคริปต์สำหรับ MySQL'), findsOneWidget);
    expect(find.text('users: ลบคอลัมน์ age'), findsOneWidget);
    expect(find.text('users: เพิ่มคอลัมน์ phone VARCHAR(20)'), findsOneWidget);
    // กล่องเตือนด้านบน (ข้อความเดียวกันอยู่ในหัวสคริปต์ด้วย จึงจับเฉพาะ Text ธรรมดา)
    expect(find.text('⚠ 1 รายการอาจทำให้ข้อมูลหาย — สำรองฐานข้อมูลก่อนรันสคริปต์'), findsOneWidget);
    expect(find.textContaining('ALTER TABLE', findRichText: true), findsWidgets);
  });

  testWidgets('ไม่มีความแตกต่าง: ไม่แสดงสคริปต์และไม่มีปุ่มคัดลอก', (tester) async {
    await open(tester, MigrationDialog(old: base(), neu: clone(base()), oldLabel: 'v1.erd'));
    expect(find.text('โครงสร้างเหมือนกัน ไม่ต้อง migrate'), findsOneWidget);
    expect(find.text('คัดลอกสคริปต์'), findsNothing);
    expect(find.text('ปิด'), findsOneWidget);
  });

  testWidgets('คัดลอกสคริปต์ทั้งหมดไป clipboard', (tester) async {
    final a = base();
    final b = clone(a);
    tb(b, 'tu').name = 'members';
    await open(tester, MigrationDialog(old: a, neu: b, oldLabel: 'v1.erd'));

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(find.text('คัดลอกสคริปต์'));
    await tester.pump();
    expect(copied, contains('RENAME TABLE `users` TO `members`;'));
    expect(find.text('คัดลอกแล้ว ✓'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('ไฟล์เก่าคนละ dialect: แจ้งให้ทราบ', (tester) async {
    final a = base(Dialect.postgres);
    final b = clone(base(Dialect.mysql));
    tb(b, 'tu').name = 'members';
    await open(tester, MigrationDialog(old: a, neu: b, oldLabel: 'v1.erd'));
    expect(find.textContaining('ไฟล์เก่าใช้ PostgreSQL'), findsOneWidget);
  });

  test('ชื่อไฟล์ migration', () {
    expect(FileActions.sqlFileName('shop_migration', Dialect.mssql), 'shop_migration_mssql.sql');
  });
}
