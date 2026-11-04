import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/layout/refresh_import.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/group_model.dart';
import 'package:nsl_modeler/core/models/note_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/core/parser/sql_importer.dart';

var _n = 0;
String nid(String p) => '$p${_n++}';

/// แผนภาพที่ผู้ใช้จัดวางไว้แล้ว
Project mine() => Project(name: 'mine', tables: [
      TableModel(id: 'mt1', name: 'users', x: 700, y: 300, width: 260, colorIndex: 2, comment: 'เก่า', columns: [
        ColumnModel(id: 'mc1', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'mc2', name: 'email', type: DataType.varchar, length: 50),
      ], seedRows: [
        {'mc2': 'a@b.c'}
      ]),
      TableModel(id: 'mt2', name: 'orders', x: 100, y: 100, columns: [
        ColumnModel(id: 'mc3', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'mc4', name: 'user_id'),
      ]),
      TableModel(id: 'mt3', name: 'draft_only', x: 50, y: 600, columns: [ColumnModel(id: 'mc5', name: 'id')]),
    ], relations: [
      RelationModel(id: 'mr1', fromTableId: 'mt2', fromColumnId: 'mc4', toTableId: 'mt1', toColumnId: 'mc1', color: 0xFFFF0000, name: 'fk_mine'),
    ], notes: [
      NoteModel(id: 'mn1', text: 'note', x: 5, y: 5)
    ], groups: [
      GroupModel(id: 'mg1', name: 'g', x: 0, y: 0, width: 300, height: 300)
    ]);

Project fromDb(String sql) => importSql(sql, name: 'db').project;

const dbSql = '''
CREATE TABLE users (
  id INT NOT NULL AUTO_INCREMENT,
  email VARCHAR(255) NOT NULL,
  phone VARCHAR(20),
  PRIMARY KEY (id),
  KEY idx_email (email)
);
CREATE TABLE orders (
  id INT NOT NULL,
  user_id INT NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_o FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE TABLE products (
  id INT NOT NULL,
  name VARCHAR(80),
  PRIMARY KEY (id)
);
''';

void main() {
  test('คงตำแหน่ง/สี/ขนาด/id ของตารางเดิม และใช้โครงสร้างตามฐานข้อมูล', () {
    final cur = mine();
    final r = refreshFromImport(cur, fromDb(dbSql), newId: nid);
    final users = r.tables.firstWhere((t) => t.name == 'users');
    expect(users.id, 'mt1');
    expect(users.x, 700);
    expect(users.y, 300);
    expect(users.width, 260);
    expect(users.colorIndex, 2);
    expect(users.columns.map((c) => c.name), ['id', 'email', 'phone']);
    expect(users.columns[0].id, 'mc1');
    expect(users.columns[1].id, 'mc2');
    expect(users.columns[1].length, 255); // ตามฐานข้อมูล
    expect(users.columns[2].id, isNot(anyOf('mc1', 'mc2')));
    expect(users.indexes.single.columnIds, [users.columns[1].id]);
    expect(users.seedRows.single, {'mc2': 'a@b.c'});
    // ไม่แตะต้นฉบับ
    expect(cur.tables.firstWhere((t) => t.name == 'users').columns.length, 2);
  });

  test('ตารางใหม่ถูกวางต่อจากของเดิม ไม่ทับ และ id ไม่ซ้ำ', () {
    final r = refreshFromImport(mine(), fromDb(dbSql), newId: nid);
    final products = r.tables.firstWhere((t) => t.name == 'products');
    final olds = r.tables.where((t) => ['users', 'orders', 'draft_only'].contains(t.name));
    final oldRight = olds.map((t) => t.x + t.width).reduce((a, b) => a > b ? a : b);
    expect(products.x, greaterThan(oldRight));
    expect({for (final t in r.tables) t.id}.length, r.tables.length);
    final colIds = [for (final t in r.tables) ...t.columns.map((c) => c.id)];
    expect(colIds.toSet().length, colIds.length);
  });

  test('ตารางที่มีแต่ในแผนภาพถูกเก็บไว้ (หรือลบเมื่อสั่ง)', () {
    var r = refreshFromImport(mine(), fromDb(dbSql), newId: nid);
    expect(r.tables.map((t) => t.name), contains('draft_only'));
    r = refreshFromImport(mine(), fromDb(dbSql), newId: nid, removeMissing: true);
    expect(r.tables.map((t) => t.name), isNot(contains('draft_only')));
  });

  test('FK ที่ตรงกันคงสี/ชื่อเดิมแต่ใช้ ON DELETE ตามฐานข้อมูล ; ไม่ซ้ำ', () {
    final r = refreshFromImport(mine(), fromDb(dbSql), newId: nid);
    expect(r.relations.length, 1);
    final fk = r.relations.single;
    expect(fk.id, 'mr1');
    expect(fk.color, 0xFFFF0000);
    expect(fk.name, 'fk_mine');
    expect(fk.onDelete, RefAction.cascade);
  });

  test('FK ที่ฐานข้อมูลไม่มี (ระหว่างตารางที่ฐานข้อมูลมีทั้งคู่) ถูกตัด ; FK ใหม่ถูกเพิ่ม', () {
    final noFk = '''
CREATE TABLE users (id INT NOT NULL, PRIMARY KEY (id));
CREATE TABLE orders (id INT NOT NULL, user_id INT, PRIMARY KEY (id));
CREATE TABLE items (id INT NOT NULL, order_id INT, PRIMARY KEY (id), FOREIGN KEY (order_id) REFERENCES orders(id));
''';
    final r = refreshFromImport(mine(), fromDb(noFk), newId: nid);
    String nameOf(String id) => r.tableById(id)!.name;
    expect(r.relations.map((x) => '${nameOf(x.fromTableId)}>${nameOf(x.toTableId)}'), ['items>orders']);
  });

  test('คงโน้ต กลุ่ม ขนาดกระดาน และแท็บ', () {
    final cur = mine()..boardWidth = 5000;
    final r = refreshFromImport(cur, fromDb(dbSql), newId: nid);
    expect(r.notes.single.text, 'note');
    expect(r.groups.single.id, 'mg1');
    expect(r.boardWidth, 5000);
  });

  test('ชื่อตาราง/คอลัมน์จับคู่แบบไม่สนตัวพิมพ์ ; refresh ซ้ำไม่มีอะไรเปลี่ยนเพิ่ม', () {
    final db = fromDb(dbSql.replaceAll('users', 'USERS').replaceAll('email', 'EMAIL'));
    final r1 = refreshFromImport(mine(), db, newId: nid);
    expect(r1.tables.where((t) => t.name.toLowerCase() == 'users').length, 1);
    expect(r1.tables.firstWhere((t) => t.name == 'USERS').id, 'mt1');
    final r2 = refreshFromImport(r1, fromDb(dbSql.replaceAll('users', 'USERS').replaceAll('email', 'EMAIL')), newId: nid);
    expect(r2.tables.length, r1.tables.length);
    expect(r2.relations.length, r1.relations.length);
    expect([for (final t in r2.tables) '${t.id}:${t.x}:${t.y}'], [for (final t in r1.tables) '${t.id}:${t.x}:${t.y}']);
  });

  test('แผนภาพว่างเปล่า = ได้ตารางทั้งหมดตามฐานข้อมูล', () {
    final r = refreshFromImport(Project(), fromDb(dbSql), newId: nid);
    expect(r.tables.length, 3);
    expect(r.relations.length, 1);
    expect(r.tables.every((t) => t.columns.every((c) => c.id.isNotEmpty)), isTrue);
  });
}
