import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/clipboard/table_clipboard.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/state/project_controller.dart';

import 'migration_fixtures.dart';

ProjectController loaded() {
  final c = ProjectController();
  c.loadProject(base(), null);
  tb(c.project, 'tu')
    ..x = 100
    ..y = 100;
  tb(c.project, 'to')
    ..x = 400
    ..y = 100;
  return c;
}

void main() {
  group('การเลือกหลายตาราง', () {
    test('selectTable = เลือกตัวเดียว ล้างตัวเสริม', () {
      final c = loaded();
      c.selectAllTables();
      expect(c.selectionCount, 2);
      c.selectTable('tu');
      expect(c.selectedTableIds, {'tu'});
    });

    test('toggle: เพิ่ม ตัวที่เพิ่มเป็นตัวหลัก; เอาตัวหลักออก ตัวอื่นขึ้นแทน', () {
      final c = loaded();
      c.selectTable('tu');
      c.toggleTableSelection('to');
      expect(c.selectedTableIds, {'tu', 'to'});
      expect(c.selectedTableId, 'to');
      expect(c.isTableSelected('tu'), true);

      c.toggleTableSelection('to'); // เอาตัวหลักออก
      expect(c.selectedTableIds, {'tu'});
      expect(c.selectedTableId, 'tu');

      c.toggleTableSelection('tu'); // เอาตัวสุดท้ายออก
      expect(c.selectedTableIds, isEmpty);
      expect(c.selectedTableId, isNull);
    });

    test('toggle เอาตัวเสริมออก ไม่กระทบตัวหลัก', () {
      final c = loaded();
      c.selectTable('tu');
      c.toggleTableSelection('to');
      c.toggleTableSelection('tu'); // tu เป็นตัวเสริมอยู่
      expect(c.selectedTableIds, {'to'});
      expect(c.selectedTableId, 'to');
    });

    test('toggle ตารางที่ไม่มีอยู่ไม่ทำอะไร', () {
      final c = loaded();
      c.toggleTableSelection('ghost');
      expect(c.selectedTableIds, isEmpty);
    });

    test('selectAll เก็บตัวหลักเดิม และ clearSelection ล้างทั้งหมด', () {
      final c = loaded();
      c.selectTable('to');
      c.selectAllTables();
      expect(c.selectedTableId, 'to');
      expect(c.selectedTableIds, {'tu', 'to'});
      c.clearSelection();
      expect(c.selectedTableIds, isEmpty);
      expect(c.selectedColumnId, isNull);
    });

    test('selectAll เมื่อไม่มีตาราง ไม่ error', () {
      final c = ProjectController()..selectAllTables();
      expect(c.selectedTableIds, isEmpty);
    });

    test('undo ที่ทำให้ตารางที่เลือกหายไป: ตัวที่เหลือขึ้นเป็นตัวหลัก', () {
      final c = loaded();
      final extra = c.addTable(name: 'extra'); // เลือก extra
      c.toggleTableSelection('tu');
      expect(c.selectedTableIds, {extra.id, 'tu'});
      c.undo(); // ลบ extra
      expect(c.selectedTableIds, {'tu'});
      expect(c.selectedTableId, 'tu');
    });

    test('เพิ่มตารางใหม่เลือกเฉพาะตารางนั้น', () {
      final c = loaded();
      c.selectAllTables();
      final t = c.addTable();
      expect(c.selectedTableIds, {t.id});
    });
  });

  group('ย้าย / ขยับ / ลบ หลายตาราง', () {
    test('moveSelectedBy ย้ายทุกตัวที่เลือก ไม่ติดลบ', () {
      final c = loaded();
      c.selectAllTables();
      c.moveSelectedBy(30, -500);
      expect(tb(c.project, 'tu').x, 130);
      expect(tb(c.project, 'to').x, 430);
      expect(tb(c.project, 'tu').y, 0);
      expect(tb(c.project, 'to').y, 0);
    });

    test('ลากทั้งกลุ่มเป็น undo ขั้นเดียว', () {
      final c = loaded();
      c.selectAllTables();
      c.beginGesture();
      for (var i = 0; i < 5; i++) {
        c.moveSelectedBy(10, 10);
      }
      c.endGesture();
      expect(tb(c.project, 'tu').x, 150);
      c.undo();
      expect(tb(c.project, 'tu').x, 100);
      expect(tb(c.project, 'to').x, 400);
    });

    test('nudgeSelected ขั้นเดียวต่อครั้ง; ขยับไม่ได้ (ชนขอบ 0) คืน false ไม่สร้างประวัติ', () {
      final c = loaded();
      c.selectTable('tu');
      expect(c.nudgeSelected(10, 0), true);
      expect(tb(c.project, 'tu').x, 110);
      c.undo();
      expect(tb(c.project, 'tu').x, 100);

      final d = ProjectController();
      final t = d.addTable(x: 0, y: 0);
      d.undo();
      d.redo();
      d.selectTable(t.id);
      final before = d.canUndo;
      expect(d.nudgeSelected(-10, -10), false);
      expect(d.canUndo, before);
      expect(ProjectController().nudgeSelected(1, 1), false); // ไม่มีอะไรเลือก
    });

    test('removeSelectedTables ลบทุกตัวพร้อม FK ใน undo ขั้นเดียว', () {
      final c = loaded();
      c.selectAllTables();
      expect(c.removeSelectedTables(), 2);
      expect(c.project.tables, isEmpty);
      expect(c.project.relations, isEmpty);
      expect(c.selectedTableIds, isEmpty);
      c.undo();
      expect(c.project.tables.length, 2);
      expect(c.project.relations.length, 1);
    });

    test('ลบเฉพาะบางตาราง FK ที่ชี้เข้าตารางที่ลบก็หายด้วย', () {
      final c = loaded();
      c.selectTable('tu');
      c.removeSelectedTables();
      expect(c.project.tables.map((t) => t.id), ['to']);
      expect(c.project.relations, isEmpty);
    });

    test('removeSelectedTables เมื่อไม่มีอะไรเลือก = 0', () {
      expect(loaded().removeSelectedTables(), 0);
    });
  });

  group('คัดลอก / วาง / ทำสำเนา', () {
    test('ทำสำเนากลุ่ม: id ใหม่ทั้งหมด FK ระหว่างกันถูกคัดลอกและชี้ไปที่สำเนา', () {
      final c = loaded();
      c.selectAllTables();
      final copies = c.duplicateSelected();
      expect(copies.length, 2);
      expect(c.project.tables.length, 4);
      expect(c.project.relations.length, 2);
      final origIds = {'tu', 'to'};
      expect(copies.map((t) => t.id).toSet().intersection(origIds), isEmpty);

      final r = c.project.relations.last;
      final child = c.project.tableById(r.fromTableId)!, parent = c.project.tableById(r.toTableId)!;
      expect(copies.map((t) => t.id), containsAll([child.id, parent.id]));
      expect(child.columnById(r.fromColumnId), isNotNull);
      expect(parent.columnById(r.toColumnId), isNotNull);
      expect(r.onDelete, RefAction.cascade);
      expect(r.name, isNull);
      // เลือกสำเนาทั้งหมด
      expect(c.selectedTableIds, copies.map((t) => t.id).toSet());
    });

    test('ชื่อซ้ำถูกต่อท้าย _1 ชื่อว่างใช้ชื่อเดิม', () {
      final c = loaded();
      c.selectTable('tu');
      expect(c.duplicateSelected().single.name, 'users_1');
      c.selectTable('tu');
      expect(c.duplicateSelected().single.name, 'users_2');
    });

    test('สำเนาเลื่อนตำแหน่ง และ undo ขั้นเดียว', () {
      final c = loaded();
      c.selectTable('tu');
      final t = c.duplicateSelected(offset: 50).single;
      expect([t.x, t.y], [150, 150]);
      c.undo();
      expect(c.project.tables.length, 2);
    });

    test('ทำสำเนาเฉพาะตารางเดียวที่มี FK ไปตารางที่ไม่ได้เลือก: ไม่คัดลอก FK ที่ชี้ออกนอก', () {
      final c = loaded();
      c.selectTable('to');
      c.duplicateSelected();
      expect(c.project.relations.length, 1); // ยังมีของเดิมอันเดียว
    });

    test('คัดลอก -> วางข้ามโปรเจกต์ (ผ่านข้อความ) ชื่อว่างใช้ชื่อเดิม', () {
      final a = loaded();
      a.selectAllTables();
      final text = a.copySelectionText()!;

      final b = ProjectController();
      final pasted = b.pasteTableText(text);
      expect(pasted.map((t) => t.name), ['users', 'orders']);
      expect(b.project.relations.length, 1);
      expect(b.selectedTableIds.length, 2);
      // id ไม่ชนกับต้นฉบับ
      expect(pasted.map((t) => t.id).toSet().intersection({'tu', 'to'}), isEmpty);
      // วางซ้ำในโปรเจกต์เดิม -> ชื่อซ้ำถูกเติม _1
      final again = b.pasteTableText(text);
      expect(again.map((t) => t.name), ['users_1', 'orders_1']);
      expect(b.project.relations.length, 2);
    });

    test('วางข้อความที่ไม่ใช่ข้อมูลของโปรแกรม = ไม่ทำอะไร', () {
      final c = loaded();
      expect(c.pasteTableText('hello'), isEmpty);
      expect(c.pasteTableText(null), isEmpty);
      expect(c.pasteTableText('{"a":1}'), isEmpty);
      expect(c.pasteTableText('{ไม่ใช่ json'), isEmpty);
      expect(c.project.tables.length, 2);
    });

    test('copySelectionText เมื่อไม่ได้เลือกอะไร = null', () {
      expect(loaded().copySelectionText(), isNull);
    });

    test('วางแล้ว FK, INDEX ของสำเนาอ้างคอลัมน์ของสำเนา ไม่ใช่ของเดิม', () {
      final c = loaded();
      c.selectAllTables();
      final copies = c.duplicateSelected();
      final orders = copies.firstWhere((t) => t.name == 'orders_1');
      final idx = orders.indexes.single;
      expect(orders.columnById(idx.columnIds.single), isNotNull);
      final origCols = tb(c.project, 'to').columns.map((x) => x.id).toSet();
      expect(origCols.contains(idx.columnIds.single), false);
    });
  });

  group('codec', () {
    test('encode เฉพาะ FK ที่ปลายทั้งสองอยู่ในกลุ่ม', () {
      final p = base();
      final both = decodeTableClipboard(encodeTableClipboard(p, {'tu', 'to'}))!;
      expect(both.relations.length, 1);
      final one = decodeTableClipboard(encodeTableClipboard(p, {'to'}))!;
      expect(one.relations, isEmpty);
    });

    test('decode ปฏิเสธข้อมูลผิดรูปแบบโดยไม่ throw', () {
      expect(decodeTableClipboard(''), isNull);
      expect(decodeTableClipboard('[1,2]'), isNull);
      expect(decodeTableClipboard('{"format":"nsl-modeler-tables","tables":[]}'), isNull);
      expect(decodeTableClipboard('{"format":"nsl-modeler-tables","tables":[{"bad":1}]}'), isNull);
    });

    test('Project ทั้งก้อนไม่ถูกแก้ตอน encode', () {
      final p = base();
      final before = p.toJson().toString();
      encodeTableClipboard(p, {'tu'});
      expect(p.toJson().toString(), before);
      expect(Project.fromJson(p.toJson()).tables.length, 2);
    });
  });
}
