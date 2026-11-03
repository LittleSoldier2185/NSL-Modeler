import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/layout/auto_layout.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/state/project_controller.dart';

TableModel t(String id, {int cols = 3}) => TableModel(
      id: id,
      name: id,
      columns: [for (var i = 0; i < cols; i++) ColumnModel(id: '$id$i', name: 'c$i')],
    );

/// child.fk -> parent
RelationModel fk(String child, String parent) => RelationModel(
      id: '$child>$parent',
      fromTableId: child,
      fromColumnId: '${child}1',
      toTableId: parent,
      toColumnId: '${parent}0',
    );

bool overlaps(Project p, Map<String, Pos> pos) {
  const h = 36.0, r = 28.0;
  final rects = [
    for (final tb in p.tables)
      (id: tb.id, l: pos[tb.id]!.x, t: pos[tb.id]!.y, r: pos[tb.id]!.x + tb.width, b: pos[tb.id]!.y + h + r * tb.columns.length),
  ];
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final a = rects[i], b = rects[j];
      if (a.l < b.r && b.l < a.r && a.t < b.b && b.t < a.b) return true;
    }
  }
  return false;
}

void main() {
  test('ว่างเปล่า', () {
    expect(autoLayout(Project()), isEmpty);
  });

  test('ตารางแม่อยู่ซ้ายของตารางลูกเสมอ', () {
    // order_items -> orders -> users, order_items -> products
    final p = Project(
      tables: [t('order_items'), t('orders'), t('users'), t('products')],
      relations: [fk('order_items', 'orders'), fk('orders', 'users'), fk('order_items', 'products')],
    );
    final pos = autoLayout(p);
    expect(pos['users']!.x, lessThan(pos['orders']!.x));
    expect(pos['orders']!.x, lessThan(pos['order_items']!.x));
    expect(pos['products']!.x, lessThan(pos['order_items']!.x));
    expect(overlaps(p, pos), false);
  });

  test('ชั้น = เส้นทางยาวสุด (ลูกของสองสายอยู่ถัดจากสายที่ลึกกว่า)', () {
    // c -> b -> a  และ c -> a : c ต้องอยู่ขวาสุด
    final p = Project(tables: [t('a'), t('b'), t('c')], relations: [fk('b', 'a'), fk('c', 'b'), fk('c', 'a')]);
    final pos = autoLayout(p);
    expect(pos['a']!.x, lessThan(pos['b']!.x));
    expect(pos['b']!.x, lessThan(pos['c']!.x));
  });

  test('FK วนเป็นวงไม่ค้างและไม่ซ้อนกัน', () {
    final p = Project(tables: [t('a'), t('b'), t('c')], relations: [fk('a', 'b'), fk('b', 'c'), fk('c', 'a')]);
    final pos = autoLayout(p);
    expect(pos.length, 3);
    expect(overlaps(p, pos), false);
  });

  test('FK ชี้ตัวเอง (self-reference) นับเป็นตารางโดดเดี่ยว', () {
    final p = Project(tables: [t('emp')], relations: [fk('emp', 'emp')]);
    final pos = autoLayout(p);
    expect(pos['emp'], isNotNull);
  });

  test('ตารางโดดเดี่ยวอยู่ใต้กลุ่มที่เชื่อมกัน เรียงเป็นตาราง', () {
    final p = Project(
      tables: [t('a'), t('b'), t('x1'), t('x2'), t('x3'), t('x4'), t('x5')],
      relations: [fk('b', 'a')],
    );
    final pos = autoLayout(p);
    final bottom = [pos['a']!.y, pos['b']!.y].reduce((m, v) => m > v ? m : v);
    for (final id in ['x1', 'x2', 'x3', 'x4', 'x5']) {
      expect(pos[id]!.y, greaterThan(bottom));
    }
    expect(overlaps(p, pos), false);
    // 5 ตาราง -> 3 คอลัมน์ (ceil(sqrt 5)) แถวแรกมี 3 ตัวบน y เดียวกัน
    expect(pos['x1']!.y, pos['x2']!.y);
    expect(pos['x2']!.y, pos['x3']!.y);
    expect(pos['x4']!.y, greaterThan(pos['x1']!.y));
  });

  test('หลายกลุ่มที่แยกกันไม่ทับกัน', () {
    final p = Project(
      tables: [t('a'), t('b'), t('c'), t('d')],
      relations: [fk('b', 'a'), fk('d', 'c')],
    );
    expect(overlaps(p, autoLayout(p)), false);
  });

  test('ผลลัพธ์คงที่ และไม่แก้ข้อมูลเดิม', () {
    final p = Project(tables: [t('a'), t('b'), t('c')], relations: [fk('b', 'a'), fk('c', 'a')]);
    final x0 = p.tables.map((e) => e.x).toList();
    final one = autoLayout(p);
    final two = autoLayout(p);
    expect(one, two);
    expect(p.tables.map((e) => e.x).toList(), x0);
  });

  test('FK ที่ชี้ตารางที่ไม่มีอยู่ถูกข้าม', () {
    final p = Project(tables: [t('a')], relations: [fk('a', 'ghost')]);
    expect(autoLayout(p).keys, ['a']);
  });

  test('ตารางสูงต่างกันในชั้นเดียวกันไม่ทับกัน', () {
    final p = Project(
      tables: [t('p'), t('big', cols: 15), t('small', cols: 1)],
      relations: [fk('big', 'p'), fk('small', 'p')],
    );
    expect(overlaps(p, autoLayout(p)), false);
  });

  test('ลดเส้นไขว้: ลูกของแม่ลำดับแรกควรอยู่ด้านบน', () {
    // a1<-c1, a2<-c2 : ไม่ควรสลับ c1/c2 จนเส้นไขว้
    final p = Project(
      tables: [t('a1'), t('a2'), t('c2'), t('c1')], // ใส่ c2 ก่อน c1 โดยตั้งใจ
      relations: [fk('c1', 'a1'), fk('c2', 'a2')],
    );
    final pos = autoLayout(p);
    final aOrder = pos['a1']!.y < pos['a2']!.y;
    final cOrder = pos['c1']!.y < pos['c2']!.y;
    expect(cOrder, aOrder);
  });

  group('ProjectController.autoLayoutTables', () {
    test('ย้ายตารางและ undo ขั้นเดียวกลับที่เดิม', () {
      final c = ProjectController();
      final a = c.addTable(name: 'a', x: 500, y: 500);
      final b = c.addTable(name: 'b', x: 10, y: 10);
      c.addRelation(
          fromTableId: b.id, fromColumnId: b.columns.first.id, toTableId: a.id, toColumnId: a.columns.first.id);
      expect(c.autoLayoutTables(), true);
      expect(a.x, lessThan(b.x));
      c.undo(); // undo สร้างโปรเจกต์ใหม่จาก snapshot ต้องดึงตารางใหม่
      final a2 = c.project.tableById(a.id)!, b2 = c.project.tableById(b.id)!;
      expect((a2.x, a2.y), (500.0, 500.0));
      expect((b2.x, b2.y), (10.0, 10.0));
    });

    test('จัดซ้ำแล้วไม่มีอะไรเปลี่ยน = ไม่สร้างประวัติ', () {
      final c = ProjectController();
      c.addTable(name: 'a');
      c.autoLayoutTables();
      c.addTable(name: 'b', x: 0, y: 0);
      c.autoLayoutTables();
      expect(c.autoLayoutTables(), false);
    });

    test('โปรเจกต์ว่างคืน false', () {
      expect(ProjectController().autoLayoutTables(), false);
    });
  });
}
