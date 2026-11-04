import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/diff/merge3.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/index_model.dart';
import 'package:nsl_modeler/core/models/note_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';

Project base() => Project(name: 'shop', tables: [
      TableModel(id: 't1', name: 'users', x: 10, y: 10, columns: [
        ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'c2', name: 'email', type: DataType.varchar, length: 100),
        ColumnModel(id: 'c3', name: 'nick'),
      ], indexes: [
        IndexModel(id: 'i1', name: 'idx_nick', columnIds: ['c3']),
      ]),
      TableModel(id: 't2', name: 'orders', x: 300, y: 10, columns: [
        ColumnModel(id: 'c4', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'c5', name: 'user_id'),
      ]),
    ], relations: [
      RelationModel(id: 'r1', fromTableId: 't2', fromColumnId: 'c5', toTableId: 't1', toColumnId: 'c1'),
    ], notes: [
      NoteModel(id: 'n1', text: 'hello', x: 0, y: 0),
    ]);

Project copy(Project p) => Project.fromJson(p.toJson());

void main() {
  test('ไม่มีใครเปลี่ยนอะไร = เหมือนเดิม ไม่มีความขัดแย้ง', () {
    final r = mergeProjects(base: base(), mine: base(), theirs: base());
    expect(r.conflicts, isEmpty);
    expect(r.merged.toJson(), base().toJson());
  });

  test('แก้คนละส่วน รวมกันได้ทั้งสองฝั่ง', () {
    final mine = copy(base())..tables[0].columns.add(ColumnModel(id: 'c9', name: 'phone'));
    final theirs = copy(base())
      ..tables[1].columns.add(ColumnModel(id: 'c8', name: 'total', type: DataType.decimal))
      ..tables[0].columns[1].length = 200;
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.conflicts, isEmpty);
    final users = r.merged.tables[0];
    expect(users.columns.map((c) => c.name), ['id', 'email', 'nick', 'phone']);
    expect(users.columns[1].length, 200);
    expect(r.merged.tables[1].columns.map((c) => c.name), contains('total'));
  });

  test('แก้ฟิลด์เดียวกันเป็นคนละค่า = ขัดแย้ง ค่าเริ่มต้นเลือก mine และเลือก theirs ได้', () {
    final mine = copy(base())..tables[0].columns[1].name = 'mail';
    final theirs = copy(base())..tables[0].columns[1].name = 'email_address';
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.conflicts.length, 1);
    final c = r.conflicts.single;
    expect(c.title, contains('users'));
    expect(c.mine, 'mail');
    expect(c.theirs, 'email_address');
    expect(r.merged.tables[0].columns[1].name, 'mail');

    final r2 = mergeProjects(base: base(), mine: mine, theirs: theirs, useTheirs: {c.id});
    expect(r2.merged.tables[0].columns[1].name, 'email_address');
  });

  test('แก้เป็นค่าเดียวกันทั้งสองฝั่ง ไม่ขัดแย้ง', () {
    final mine = copy(base())..tables[0].name = 'members';
    final theirs = copy(base())..tables[0].name = 'members';
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.conflicts, isEmpty);
    expect(r.merged.tables[0].name, 'members');
  });

  test('ตำแหน่งที่ย้ายต่างกัน ใช้ของ mine เงียบ ๆ ; ถ้า mine ไม่ได้ย้ายตาม theirs', () {
    final mine = copy(base())..tables[0].x = 500;
    final theirs = copy(base())..tables[0].x = 900;
    var r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.conflicts, isEmpty);
    expect(r.merged.tables[0].x, 500);
    r = mergeProjects(base: base(), mine: copy(base()), theirs: theirs);
    expect(r.merged.tables[0].x, 900);
  });

  test('ฝั่งหนึ่งลบตาราง อีกฝั่งไม่แตะ = ลบ', () {
    final theirs = copy(base())
      ..tables.removeWhere((t) => t.id == 't2')
      ..relations.clear();
    final r = mergeProjects(base: base(), mine: copy(base()), theirs: theirs);
    expect(r.conflicts, isEmpty);
    expect(r.merged.tables.map((t) => t.id), ['t1']);
    expect(r.merged.relations, isEmpty);
  });

  test('ฝั่งหนึ่งลบ อีกฝั่งแก้ = ขัดแย้ง ค่าเริ่มต้นตาม mine', () {
    final mine = copy(base())..tables[1].name = 'purchases';
    final theirs = copy(base())
      ..tables.removeWhere((t) => t.id == 't2')
      ..relations.clear();
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.conflicts.length, 1);
    expect(r.merged.tables.any((t) => t.id == 't2' && t.name == 'purchases'), isTrue);
    final r2 = mergeProjects(base: base(), mine: mine, theirs: theirs, useTheirs: {r.conflicts.single.id});
    expect(r2.merged.tables.any((t) => t.id == 't2'), isFalse);
  });

  test('theirs ลบคอลัมน์ที่ mine เพิ่ง FK ไป → ตัด FK และแจ้ง', () {
    final mine = copy(base())
      ..relations.add(RelationModel(id: 'r2', fromTableId: 't2', fromColumnId: 'c4', toTableId: 't1', toColumnId: 'c3'));
    final theirs = copy(base())..tables[0].columns.removeWhere((c) => c.id == 'c3');
    theirs.tables[0].indexes.clear();
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.merged.relations.map((x) => x.id), ['r1']);
    expect(r.notes, isNotEmpty);
    expect(r.merged.tables[0].indexes, isEmpty);
  });

  test('INDEX ที่คอลัมน์บางตัวถูกลบ ถูกปรับให้เหลือเท่าที่มี', () {
    final mine = copy(base())..tables[0].indexes[0].columnIds = ['c3', 'c2'];
    final theirs = copy(base())..tables[0].columns.removeWhere((c) => c.id == 'c3');
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.merged.tables[0].indexes.single.columnIds, ['c2']);
    expect(r.notes, isNotEmpty);
  });

  test('เพิ่มตารางใหม่คนละตาราง = ได้ทั้งคู่ ; โน้ตแก้ฝั่งเดียว', () {
    final mine = copy(base())..tables.add(TableModel(id: 'tm', name: 'mine_t', columns: [ColumnModel(id: 'cm', name: 'id')]));
    final theirs = copy(base())
      ..tables.add(TableModel(id: 'tt', name: 'theirs_t', columns: [ColumnModel(id: 'ct', name: 'id')]))
      ..notes[0].text = 'edited';
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.conflicts, isEmpty);
    expect(r.merged.tables.map((t) => t.id), containsAll(['t1', 't2', 'tm', 'tt']));
    expect(r.merged.notes.single.text, 'edited');
  });

  test('จัดลำดับคอลัมน์ใหม่ฝั่ง theirs (mine ไม่ได้จัด) ลำดับตาม theirs', () {
    final theirs = copy(base());
    theirs.tables[0].columns = [theirs.tables[0].columns[2], theirs.tables[0].columns[0], theirs.tables[0].columns[1]];
    final mine = copy(base())..tables[0].columns.add(ColumnModel(id: 'c9', name: 'phone'));
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.merged.tables[0].columns.map((c) => c.id), ['c3', 'c1', 'c2', 'c9']);
  });

  test('ผลรวมอ่านกลับเป็นโปรเจกต์ที่ถูกต้อง (encode/decode ซ้ำได้เท่าเดิม)', () {
    final mine = copy(base())..dialect = Dialect.postgres;
    final theirs = copy(base())..name = 'shop2';
    final r = mergeProjects(base: base(), mine: mine, theirs: theirs);
    expect(r.merged.dialect, Dialect.postgres);
    expect(r.merged.name, 'shop2');
    expect(Project.fromJson(r.merged.toJson()).toJson(), r.merged.toJson());
  });
}
