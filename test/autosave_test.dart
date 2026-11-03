import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/storage/autosave.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/autosave_coordinator.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:nsl_modeler/ui/recovery_dialog.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// ที่เก็บในหน่วยความจำ ไว้ทดสอบ UI โดยไม่แตะดิสก์
class MemoryStore implements AutosaveStore {
  AutosaveInfo? saved;
  int writes = 0;
  int clears = 0;
  Object? failWith;

  @override
  Future<void> write(Project p, {String? originalPath, DateTime? now}) async {
    if (failWith != null) throw failWith!;
    writes++;
    saved = AutosaveInfo(Project.fromJson(p.toJson()), now ?? DateTime.now(), originalPath);
  }

  @override
  Future<AutosaveInfo?> readRecoverable() async => saved;

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

void main() {
  group('FileAutosaveStore', () {
    late Directory dir;
    late FileAutosaveStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nsl_auto');
      store = FileAutosaveStore(Directory('${dir.path}/sub')); // โฟลเดอร์ยังไม่มี ต้องสร้างให้เอง
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('ไม่มีไฟล์ = null', () async {
      expect(await store.readRecoverable(), isNull);
    });

    test('เขียนแล้วอ่านได้โปรเจกต์ เวลา และไฟล์เดิม ครบ (รวมภาษาไทย)', () async {
      final p = base();
      p.name = 'ร้านค้า';
      p.tables.first.comment = 'ผู้ใช้';
      final t = DateTime.utc(2026, 11, 3, 10, 30);
      await store.write(p, originalPath: r'C:\งาน\shop.erd', now: t);
      final info = (await store.readRecoverable())!;
      expect(info.project.name, 'ร้านค้า');
      expect(info.project.tables.first.comment, 'ผู้ใช้');
      expect(info.project.tables.length, 2);
      expect(info.project.relations.length, 1);
      expect(info.originalPath, r'C:\งาน\shop.erd');
      expect(info.savedAt.toUtc(), t);
      expect(File('${store.file.path}.tmp').existsSync(), false); // ไม่ทิ้งไฟล์ชั่วคราว
    });

    test('โปรเจกต์ที่ยังไม่เคยบันทึก: originalPath เป็น null', () async {
      await store.write(base());
      expect((await store.readRecoverable())!.originalPath, isNull);
    });

    test('เขียนทับครั้งใหม่ได้ค่าล่าสุด', () async {
      await store.write(base());
      final p = base()..name = 'v2';
      await store.write(p);
      expect((await store.readRecoverable())!.project.name, 'v2');
    });

    test('ไฟล์เสีย: คืน null, ย้ายไฟล์ไปเป็น .corrupt และไม่ถามซ้ำ', () async {
      await store.write(base());
      await store.file.writeAsString('{ไม่ใช่ json');
      expect(await store.readRecoverable(), isNull);
      expect(store.file.existsSync(), false);
      expect(File('${store.file.path}.corrupt').existsSync(), true);
      expect(await store.readRecoverable(), isNull);
    });

    test('JSON ถูกต้องแต่ไม่ใช่ autosave: ถือว่าเสีย', () async {
      await Directory('${dir.path}/sub').create();
      await store.file.writeAsString('{"hello":1}');
      expect(await store.readRecoverable(), isNull);
    });

    test('ไฟล์เดิมถูกบันทึกใหม่กว่า autosave แล้ว: ไม่ต้องกู้ และลบทิ้ง', () async {
      final orig = File('${dir.path}/shop.erd')..writeAsStringSync('{}');
      await store.write(base(), originalPath: orig.path, now: DateTime.now().subtract(const Duration(hours: 1)));
      expect(await store.readRecoverable(), isNull);
      expect(store.file.existsSync(), false);
    });

    test('ไฟล์เดิมเก่ากว่า autosave: ต้องกู้', () async {
      final orig = File('${dir.path}/shop.erd')..writeAsStringSync('{}');
      orig.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
      await store.write(base(), originalPath: orig.path, now: DateTime.now());
      expect(await store.readRecoverable(), isNotNull);
    });

    test('ไฟล์เดิมหายไปแล้ว: ยังกู้ได้', () async {
      await store.write(base(), originalPath: '${dir.path}/gone.erd');
      expect(await store.readRecoverable(), isNotNull);
    });

    test('clear ลบไฟล์ และเรียกซ้ำได้โดยไม่ error', () async {
      await store.write(base());
      await store.clear();
      expect(store.file.existsSync(), false);
      await store.clear();
    });
  });

  group('AutosaveCoordinator', () {
    late ProjectController c;
    late MemoryStore store;
    late int notified;
    AutosaveCoordinator make({int debounceMs = 30, int maxMs = 1000}) {
      notified = 0;
      return AutosaveCoordinator(c, store,
          debounce: Duration(milliseconds: debounceMs),
          maxWait: Duration(milliseconds: maxMs),
          onWrite: () => notified++);
    }

    setUp(() {
      c = ProjectController();
      store = MemoryStore();
    });

    Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));

    test('ยังไม่แก้อะไร = ไม่เขียน', () async {
      final a = make();
      await wait(80);
      expect(store.writes, 0);
      a.dispose();
    });

    test('แก้แล้วหยุด -> เขียนครั้งเดียวหลัง debounce ด้วยค่าล่าสุด', () async {
      final a = make();
      c.addTable(name: 'a');
      c.addTable(name: 'b');
      c.addTable(name: 'c');
      expect(store.writes, 0); // ยังไม่ถึงเวลา
      await wait(120);
      await a.idle();
      expect(store.writes, 1);
      expect(store.saved!.project.tables.length, 3);
      expect(notified, 1);
      a.dispose();
    });

    test('แก้ต่อเนื่องไม่หยุด: เขียนตาม maxWait ไม่ถูก debounce เลื่อนไปเรื่อย ๆ', () async {
      final a = make(debounceMs: 200, maxMs: 150);
      for (var i = 0; i < 8; i++) {
        c.addTable(name: 't$i');
        await wait(40);
      }
      await a.idle();
      expect(store.writes, greaterThanOrEqualTo(1));
      a.dispose();
    });

    test('บันทึกจริง (markSaved) -> ลบสำเนา', () async {
      final a = make();
      c.addTable();
      await wait(100);
      await a.idle();
      expect(store.saved, isNotNull);
      c.markSaved('x.erd');
      await a.idle();
      expect(store.saved, isNull);
      expect(store.clears, 1);
      a.dispose();
    });

    test('บันทึกก่อนถึงเวลา debounce -> ไม่เขียนเลย', () async {
      final a = make(debounceMs: 80);
      c.addTable();
      c.markSaved('x.erd');
      await wait(160);
      await a.idle();
      expect(store.writes, 0);
      a.dispose();
    });

    test('เริ่มโปรเจกต์ใหม่ / เปิดไฟล์ -> ลบสำเนาของงานเดิม', () async {
      final a = make();
      c.addTable();
      await wait(100);
      await a.idle();
      c.newProject();
      await a.idle();
      expect(store.saved, isNull);

      c.addTable();
      await wait(100);
      await a.idle();
      c.loadProject(base(), 'y.erd');
      await a.idle();
      expect(store.saved, isNull);
      a.dispose();
    });

    test('สำเนาเก็บ originalPath ของไฟล์ที่เปิดอยู่', () async {
      final a = make();
      c.loadProject(base(), 'shop.erd');
      c.addTable();
      await wait(100);
      await a.idle();
      expect(store.saved!.originalPath, 'shop.erd');
      a.dispose();
    });

    test('flush เขียนทันทีโดยไม่รอ timer', () async {
      final a = make(debounceMs: 5000);
      c.addTable();
      await a.flush();
      expect(store.writes, 1);
      a.dispose();
    });

    test('flush ตอนไม่มีอะไรค้างไม่เขียน', () async {
      final a = make();
      await a.flush();
      expect(store.writes, 0);
      a.dispose();
    });

    test('สำเนาที่เขียนเป็นภาพ ณ ตอนนั้น ไม่เปลี่ยนตามการแก้หลังจากนั้น', () async {
      final a = make(debounceMs: 20);
      c.addTable(name: 'first');
      await wait(60);
      await a.idle();
      c.renameTable(c.project.tables.first.id, 'changed');
      expect(store.saved!.project.tables.first.name, 'first');
      a.dispose();
    });

    test('เขียนล้มเหลวไม่ทำให้แอปพัง เก็บ error ไว้ และครั้งต่อไปลองใหม่ได้', () async {
      final a = make(debounceMs: 20);
      store.failWith = const FileSystemException('disk full');
      c.addTable();
      await wait(60);
      await a.idle();
      expect(a.lastError, isA<FileSystemException>());
      expect(store.writes, 0);

      store.failWith = null;
      c.addTable();
      await wait(60);
      await a.idle();
      expect(a.lastError, isNull);
      expect(store.writes, 1);
      a.dispose();
    });

    test('dispose แล้วไม่เขียนอีก', () async {
      final a = make(debounceMs: 30);
      c.addTable();
      a.dispose();
      await wait(100);
      expect(store.writes, 0);
      c.addTable(); // ไม่ error แม้ listener ถูกถอดแล้ว
    });

    test('discard ลบสำเนา', () async {
      final a = make();
      store.saved = AutosaveInfo(base(), DateTime.now(), null);
      await a.discard();
      expect(store.saved, isNull);
      a.dispose();
    });

    test('ลำดับ I/O ไม่สลับ: เขียนแล้วบันทึกทันที สุดท้ายต้องไม่เหลือสำเนา', () async {
      final a = make(debounceMs: 5000);
      c.addTable();
      final f = a.flush(); // เขียน (ยังไม่เสร็จ)
      c.markSaved('x.erd'); // แล้วลบ
      await f;
      await a.idle();
      expect(store.saved, isNull);
      a.dispose();
    });
  });

  group('กู้คืนตอนเปิดโปรแกรม', () {
    Future<(ProjectController, MemoryStore)> boot(WidgetTester tester, AutosaveInfo? info) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryStore()..saved = info;
      await tester.pumpWidget(NslModelerApp(autosave: store, recovery: info));
      await tester.pump();
      await tester.pump();
      final ctx = tester.element(find.byType(HomePage));
      return (ctx.read<ProjectController>(), store);
    }

    final info = AutosaveInfo(base()..name = 'งานค้าง', DateTime(2026, 11, 3, 9, 5), r'C:\งาน\shop.erd');

    testWidgets('ไม่มีงานค้าง: ไม่ถาม', (tester) async {
      await boot(tester, null);
      expect(find.byType(RecoveryDialog), findsNothing);
    });

    testWidgets('มีงานค้าง: แสดงรายละเอียดก่อนตัดสินใจ', (tester) async {
      await boot(tester, info);
      expect(find.text('พบงานที่ยังไม่ได้บันทึก'), findsOneWidget);
      expect(find.text('งานค้าง'), findsOneWidget);
      expect(find.textContaining('2 ตาราง · 8 คอลัมน์ · 1 FK'), findsOneWidget);
      expect(find.text('03/11/2026 09:05'), findsOneWidget);
      expect(find.text(r'C:\งาน\shop.erd'), findsOneWidget);
    });

    testWidgets('กู้คืน: โหลดโปรเจกต์ ผูกไฟล์เดิม และถือว่ามีการแก้ค้างอยู่', (tester) async {
      final (c, store) = await boot(tester, info);
      await tester.tap(find.text('กู้คืน'));
      await tester.pumpAndSettle();
      expect(c.project.name, 'งานค้าง');
      expect(c.project.tables.length, 2);
      expect(c.filePath, r'C:\งาน\shop.erd');
      expect(c.dirty, true);
      expect(c.canUndo, false);
      expect(store.clears, 0); // ยังเก็บสำเนาไว้จนกว่าจะบันทึกจริง
      expect(find.byType(RecoveryDialog), findsNothing);
    });

    testWidgets('ทิ้ง: ลบสำเนา และเริ่มโปรเจกต์ว่าง', (tester) async {
      final (c, store) = await boot(tester, info);
      await tester.tap(find.text('ทิ้ง'));
      await tester.pumpAndSettle();
      expect(c.project.tables, isEmpty);
      expect(c.dirty, false);
      expect(store.saved, isNull);
      expect(store.clears, 1);
    });

    testWidgets('ปิด dialog ด้วยการคลิกข้างนอกไม่ได้ (กันกดพลาดแล้วงานหาย)', (tester) async {
      await boot(tester, info);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryDialog), findsOneWidget);
    });

    testWidgets('เปิดแอปโดยไม่มี auto-save ก็ทำงานปกติ', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslModelerApp());
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  test('formatDateTime', () {
    expect(formatDateTime(DateTime(2026, 1, 5, 7, 3)), '05/01/2026 07:03');
  });
}
