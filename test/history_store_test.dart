import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/storage/history_store.dart';

Project proj(int tables) => Project(name: 'p', tables: [
      for (var i = 0; i < tables; i++)
        TableModel(id: 't$i', name: 'tb$i', columns: [ColumnModel(id: 'c$i', name: 'id', isPrimaryKey: true)]),
    ]);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nslhist'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('keyFor: ไม่สนตัวพิมพ์/ทิศของ slash และต่างไฟล์ต่างคีย์', () {
    expect(HistoryStore.keyFor(r'C:\A\b.nsld'), HistoryStore.keyFor('c:/a/B.NSLD'));
    expect(HistoryStore.keyFor(r'C:\A\b.nsld'), isNot(HistoryStore.keyFor(r'C:\A\c.nsld')));
    expect(HistoryStore.keyFor(null), 'unsaved');
  });

  test('add/list/load: ใหม่สุดก่อน และอ่านกลับได้เท่าเดิม', () async {
    final h = HistoryStore(dir);
    final k = HistoryStore.keyFor('x.nsld');
    final t0 = DateTime(2026, 1, 1, 10);
    await h.add(k, proj(1), now: t0);
    await h.add(k, proj(2), now: t0.add(const Duration(minutes: 5)), kind: SnapshotKind.manual, label: 'ก่อนรีแฟกเตอร์');
    final l = await h.list(k);
    expect(l.length, 2);
    expect(l.first.tables, 2);
    expect(l.first.kind, SnapshotKind.manual);
    expect(l.first.label, 'ก่อนรีแฟกเตอร์');
    expect(l.last.tables, 1);
    final back = await h.load(k, l.first.id);
    expect(back!.tables.length, 2);
    expect(back.tables.first.name, 'tb0');
  });

  test('เนื้อหาเหมือนล่าสุด = ไม่เก็บซ้ำ (force เก็บได้)', () async {
    final h = HistoryStore(dir);
    expect(await h.add('k', proj(1)), isNotNull);
    expect(await h.add('k', proj(1)), isNull);
    expect(await h.add('k', proj(1), force: true), isNotNull);
    expect((await h.list('k')).length, 2);
  });

  test('เวลาเดียวกันเป๊ะ (ms) ไม่ทับกัน', () async {
    final h = HistoryStore(dir);
    final t = DateTime(2026, 1, 1);
    await h.add('k', proj(1), now: t);
    await h.add('k', proj(2), now: t);
    await h.add('k', proj(3), now: t);
    expect((await h.list('k')).length, 3);
  });

  test('เกินจำนวนสูงสุด ลบอันเก่าสุด แต่เก็บ manual ไว้ก่อน', () async {
    final h = HistoryStore(dir, maxPerProject: 3);
    final t = DateTime(2026, 1, 1);
    await h.add('k', proj(1), now: t, kind: SnapshotKind.manual);
    for (var i = 2; i <= 5; i++) {
      await h.add('k', proj(i), now: t.add(Duration(minutes: i)));
    }
    final l = await h.list('k');
    expect(l.length, 3);
    expect(l.any((s) => s.kind == SnapshotKind.manual), isTrue);
    expect(l.map((s) => s.tables), containsAll([5, 4]));
  });

  test('ไฟล์เสียถูกข้าม ไม่ทำให้รายการพัง', () async {
    final h = HistoryStore(dir);
    await h.add('k', proj(1));
    File('${dir.path}/k/bad.json').writeAsStringSync('{{{');
    expect((await h.list('k')).length, 1);
    expect(await h.load('k', 'bad'), isNull);
    expect(await h.load('k', 'missing'), isNull);
  });

  test('delete และ adopt (ย้ายประวัติของงานที่ยังไม่บันทึกไปไฟล์ใหม่)', () async {
    final h = HistoryStore(dir);
    final s = await h.add('unsaved', proj(1));
    await h.adopt('unsaved', 'pnew');
    expect(await h.list('unsaved'), isEmpty);
    expect((await h.list('pnew')).length, 1);
    await h.delete('pnew', s!.id);
    expect(await h.list('pnew'), isEmpty);
  });
}
