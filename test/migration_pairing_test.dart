import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/diff/migration.dart';
import 'package:nsl_modeler/core/diff/schema_diff.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/ui/migration_dialog.dart';

import 'migration_fixtures.dart';

/// "ไฟล์เก่า/ฐานข้อมูลที่อ่านมา" : id ไม่ตรงกับโปรเจกต์ปัจจุบัน และตาราง users ถูกเปลี่ยนชื่อเป็น members
Project readFromDb() {
  final p = clone(base());
  // ทำให้ id ต่างกันหมดเหมือนโปรเจกต์ที่ import มา
  for (final t in p.tables) {
    final cols = [for (final c in t.columns) col('x_${c.id}', c.name, type: c.type, len: c.length, pk: c.isPrimaryKey, nn: c.notNull, ai: c.autoIncrement)];
    for (final i in t.indexes) {
      i.columnIds = [for (final id in i.columnIds) 'x_$id'];
    }
    t
      ..id = 'x_${t.id}'
      ..columns = cols;
  }
  p.relations.clear();
  return p;
}

Project renamed(Project old) {
  // โปรเจกต์ใหม่ = โครงสร้างเดิมแต่ users -> members (id ใหม่ทั้งหมด)
  final p = readFromDb();
  for (final t in p.tables) {
    t.id = t.id.replaceFirst('x_', 'n_');
  }
  p.tableById('n_tu')!.name = 'members';
  return p;
}

void main() {
  group('diffProjects + manualTablePairs', () {
    test('ไม่จับคู่ = ลบ users + สร้าง members (ข้อมูลหาย)', () {
      final old = readFromDb();
      final neu = renamed(old);
      final d = diffProjects(old, neu);
      expect(d.droppedTables.map((t) => t.name), ['users']);
      expect(d.addedTables.map((t) => t.name), ['members']);
      expect(generateMigration(old, neu, diff: d), contains('DROP TABLE'));
    });

    test('จับคู่ด้วยมือ = เปลี่ยนชื่อตาราง ไม่ลบ ไม่สร้างใหม่ ข้อมูลอยู่', () {
      final old = readFromDb();
      final neu = renamed(old);
      final d = diffProjects(old, neu, manualTablePairs: {'x_tu': 'n_tu'});
      expect(d.droppedTables, isEmpty);
      expect(d.addedTables, isEmpty);
      expect(d.modified.where((m) => m.hasChanges).map((m) => '${m.old.name}->${m.neu.name}').toList(), ['users->members'], reason: d.summary(old, neu).map((l) => l.text).join(' / '));
      final sql = generateMigration(old, neu, diff: d);
      expect(sql, contains('RENAME TABLE'));
      expect(sql, isNot(contains('DROP TABLE')));
      expect(sql, isNot(contains('CREATE TABLE')));
    });

    test('คู่ที่ผิด (id ไม่มี / ตารางใหม่ถูกใช้แล้ว) ถูกข้าม ไม่พัง', () {
      final old = readFromDb();
      final neu = renamed(old);
      final d = diffProjects(old, neu, manualTablePairs: {'nope': 'n_tu', 'x_tu': 'zzz', 'x_to': 'n_tu'});
      expect(d.tableMap['x_to'], 'n_tu'); // คู่ที่ถูกต้องข้อเดียว
      expect(d.droppedTables.map((t) => t.name), ['users']);
    });

    test('คู่ที่จับด้วยมือไม่ถูกเขียนทับด้วยการจับคู่ตาม id/ชื่ออัตโนมัติ', () {
      final old = clone(base());
      final neu = clone(old);
      // สลับชื่อ users/orders ในโปรเจกต์ใหม่ แล้วจับคู่ข้ามกันด้วยมือ
      tb(neu, 'tu').name = 'orders_new';
      final d = diffProjects(old, neu, manualTablePairs: {'tu': 'tu'});
      expect(d.tableMap['tu'], 'tu');
    });
  });

  group('หน้า Migration : ส่วนจับคู่ตาราง', () {
    Future<void> open(WidgetTester tester, Project old, Project neu) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(context: ctx, builder: (_) => MigrationDialog(old: old, neu: neu, oldLabel: 'db')),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('เลือกคู่ → รายการเปลี่ยนจาก ลบ+สร้าง เป็นเปลี่ยนชื่อ ; เลิกจับคู่ได้', (tester) async {
      final old = readFromDb();
      final neu = renamed(old);
      await open(tester, old, neu);
      expect(find.byKey(const ValueKey('pair-section')), findsOneWidget);
      expect(find.text('ลบตาราง users'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pair-x_tu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('members').last);
      await tester.pumpAndSettle();
      expect(find.text('ลบตาราง users'), findsNothing);
      expect(find.textContaining('เปลี่ยนชื่อตาราง'), findsWidgets);
      // แถวจับคู่ยังอยู่ให้เลิกจับคู่ได้
      expect(find.byKey(const ValueKey('pair-x_tu')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pair-x_tu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('— ถูกลบจริง —').last);
      await tester.pumpAndSettle();
      expect(find.text('ลบตาราง users'), findsOneWidget);
    });

    testWidgets('ไม่มีตารางถูกลบ/เพิ่มคู่กัน = ไม่แสดงส่วนจับคู่', (tester) async {
      final old = clone(base());
      await open(tester, old, clone(old));
      expect(find.byKey(const ValueKey('pair-section')), findsNothing);
    });
  });
}
