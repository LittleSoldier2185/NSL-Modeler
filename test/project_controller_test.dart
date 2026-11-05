import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/state/project_controller.dart';

void main() {
  late ProjectController c;
  setUp(() => c = ProjectController());

  test('เพิ่มตารางได้ id PK และชื่อไม่ซ้ำ', () {
    final a = c.addTable();
    final b = c.addTable();
    expect(a.name, 'table_1');
    expect(b.name, 'table_2');
    expect(a.columns.single.isPrimaryKey, true);
    expect(c.selectedTableId, b.id);
    expect(c.dirty, true);
  });

  test('undo/redo ตาราง', () {
    c.addTable();
    c.addTable();
    c.undo();
    expect(c.project.tables.length, 1);
    c.redo();
    expect(c.project.tables.length, 2);
    expect(c.canRedo, false);
  });

  test('แก้ใหม่หลัง undo ล้าง redo', () {
    c.addTable();
    c.undo();
    c.addTable();
    expect(c.canRedo, false);
  });

  test('ลากตารางทั้งสายเป็น undo ขั้นเดียว', () {
    final t = c.addTable(x: 0, y: 0);
    c.beginGesture();
    for (var i = 1; i <= 10; i++) {
      c.moveTable(t.id, i * 5, i * 5);
    }
    c.endGesture();
    expect(c.project.tableById(t.id)!.x, 50);
    c.undo();
    expect(c.project.tableById(t.id)!.x, 0);
  });

  test('ลากแล้วไม่ขยับ ไม่เกิดประวัติ', () {
    final t = c.addTable();
    final before = c.canUndo;
    c.undo();
    c.redo();
    c.beginGesture();
    c.moveTable(t.id, t.x, t.y);
    c.endGesture();
    c.undo();
    expect(before, true);
    expect(c.project.tables, isEmpty);
  });

  test('ลบตารางลบ FK ที่เกี่ยวข้อง', () {
    final a = c.addTable();
    final b = c.addTable();
    final ca = c.addColumn(a.id)!;
    c.addRelation(
        fromTableId: a.id,
        fromColumnId: ca.id,
        toTableId: b.id,
        toColumnId: b.columns.first.id);
    expect(c.project.relations.length, 1);
    c.removeTable(b.id);
    expect(c.project.relations, isEmpty);
    c.undo();
    expect(c.project.relations.length, 1);
  });

  test('ลบคอลัมน์ลบ FK และ index ที่อ้างถึง', () {
    final t = c.addTable();
    final col = c.addColumn(t.id)!;
    c.addIndex(t.id, [col.id]);
    c.removeColumn(t.id, col.id);
    expect(c.project.tableById(t.id)!.indexes, isEmpty);
  });

  test('FK ปรับ type ให้ตรงกับคอลัมน์ปลายทาง', () {
    final users = c.addTable(name: 'users');
    final orders = c.addTable(name: 'orders', withId: false);
    c.updateColumn(users.id, users.columns.first.id, (x) => x.type = DataType.bigint);
    final uid = c.addColumn(orders.id, name: 'user_id')!;
    c.addRelation(
        fromTableId: orders.id,
        fromColumnId: uid.id,
        toTableId: users.id,
        toColumnId: users.columns.first.id);
    expect(uid.type, DataType.bigint);
  });

  test('ไม่สร้าง FK ซ้ำหรือชี้ไปคอลัมน์ที่ไม่มี', () {
    final a = c.addTable();
    final b = c.addTable();
    final r1 = c.addRelation(
        fromTableId: a.id,
        fromColumnId: a.columns.first.id,
        toTableId: b.id,
        toColumnId: b.columns.first.id);
    final r2 = c.addRelation(
        fromTableId: a.id,
        fromColumnId: a.columns.first.id,
        toTableId: b.id,
        toColumnId: b.columns.first.id);
    final r3 = c.addRelation(
        fromTableId: a.id, fromColumnId: 'nope', toTableId: b.id, toColumnId: 'x');
    expect(r1, isNotNull);
    expect(r2, isNull);
    expect(r3, isNull);
  });

  test('เรียงคอลัมน์ (newIndex = ตำแหน่งสุดท้าย)', () {
    final t = c.addTable();
    c.addColumn(t.id, name: 'a');
    c.addColumn(t.id, name: 'b');
    // [id, a, b] -> ย้าย id ไปท้ายสุด
    c.reorderColumn(t.id, 0, 2);
    expect(t.columns.map((x) => x.name), ['a', 'b', 'id']);
    c.reorderColumn(t.id, 2, 0);
    expect(t.columns.map((x) => x.name), ['id', 'a', 'b']);
  });

  test('duplicate ตารางได้ id ใหม่ และ index ชี้คอลัมน์ของสำเนา', () {
    final t = c.addTable(name: 'users');
    final col = c.addColumn(t.id, name: 'email')!;
    c.addIndex(t.id, [col.id], unique: true);
    final d = c.duplicateTable(t.id)!;
    expect(d.id, isNot(t.id));
    expect(d.name, 'users_1');
    final newColIds = d.columns.map((x) => x.id).toSet();
    expect(newColIds.intersection(t.columns.map((x) => x.id).toSet()), isEmpty);
    expect(newColIds.contains(d.indexes.single.columnIds.single), true);
  });

  test('undo แล้ว selection ที่หายไปถูกล้าง', () {
    final t = c.addTable();
    c.undo();
    expect(c.selectedTableId, isNull);
    expect(t.id, isNotEmpty);
  });

  test('loadProject ล้างประวัติและ dirty', () {
    c.addTable();
    c.newProject();
    expect(c.canUndo, false);
    expect(c.dirty, false);
    expect(c.project.tables, isEmpty);
  });
}
