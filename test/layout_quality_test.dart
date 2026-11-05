import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/layout/auto_layout.dart';
import 'package:nsl_dev/core/layout/diagram_geometry.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/group_model.dart';
import 'package:nsl_dev/core/models/note_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/parser/sql_importer.dart';
import 'package:nsl_dev/state/project_controller.dart';

TableModel t(String id, {int cols = 3}) => TableModel(
      id: id,
      name: id,
      columns: [for (var i = 0; i < cols; i++) ColumnModel(id: '$id$i', name: 'c$i')],
    );

RelationModel fk(String child, String parent, {int col = 1}) => RelationModel(
      id: '$child.$col>$parent',
      fromTableId: child,
      fromColumnId: '$child$col',
      toTableId: parent,
      toColumnId: '${parent}0',
    );

double hOf(TableModel tb) => 36.0 + 28.0 * tb.columns.length;

bool overlaps(Project p, Map<String, Pos> pos) {
  for (var i = 0; i < p.tables.length; i++) {
    for (var j = i + 1; j < p.tables.length; j++) {
      final a = p.tables[i], b = p.tables[j];
      final ax = pos[a.id]!, bx = pos[b.id]!;
      if (ax.x < bx.x + b.width && bx.x < ax.x + a.width && ax.y < bx.y + hOf(b) && bx.y < ax.y + hOf(a)) return true;
    }
  }
  return false;
}

void apply(Project p, Map<String, Pos> pos) {
  for (final tb in p.tables) {
    tb.x = pos[tb.id]!.x;
    tb.y = pos[tb.id]!.y;
  }
}

/// มีเส้นสองเส้นที่ส่วนแนวตั้งซ้อนกัน/ชิดกันเกินไป (ห่างน้อยกว่า [kRouteMinSeparation]) ในช่วง y ที่ซ้อนกันหรือไม่
bool verticalOverlap(List<RoutePoint> a, List<RoutePoint> b) {
  for (var s = 1; s < a.length; s++) {
    if ((a[s - 1].$1 - a[s].$1).abs() > 0.001) continue;
    final a0 = a[s - 1].$2 < a[s].$2 ? a[s - 1].$2 : a[s].$2, a1 = a[s - 1].$2 < a[s].$2 ? a[s].$2 : a[s - 1].$2;
    if (a1 - a0 < 2) continue;
    for (var u = 1; u < b.length; u++) {
      if ((b[u - 1].$1 - b[u].$1).abs() > 0.001 || (b[u].$1 - a[s].$1).abs() > kRouteMinSeparation) continue;
      final b0 = b[u - 1].$2 < b[u].$2 ? b[u - 1].$2 : b[u].$2, b1 = b[u - 1].$2 < b[u].$2 ? b[u].$2 : b[u - 1].$2;
      final lo = a0 > b0 ? a0 : b0, hi = a1 < b1 ? a1 : b1;
      if (hi - lo > 1.5) return true;
    }
  }
  return false;
}

void main() {
  group('auto layout: คุณภาพ', () {
    test('ตารางอ้างอิงที่ไม่มีแม่ถูกดึงเข้ามาชิดลูกที่ลึกสุด (ไม่ไปอยู่ซ้ายสุดโดยไม่จำเป็น)', () {
      // a <- b <- c <- d  และ ref <- d : ref ไม่ควรอยู่ชั้น 0 ห่างจาก d
      final p = Project(
        tables: [t('a'), t('b'), t('c'), t('d'), t('ref')],
        relations: [fk('b', 'a'), fk('c', 'b'), fk('d', 'c'), fk('d', 'ref', col: 2)],
      );
      final pos = autoLayout(p);
      expect(pos['ref']!.x, greaterThan(pos['a']!.x)); // ไม่ใช่ชั้น 0
      expect(pos['ref']!.x, lessThan(pos['d']!.x)); // แม่ยังอยู่ซ้ายลูก
      expect(pos['ref']!.x, pos['c']!.x); // อยู่ชั้นเดียวกับ c (ชิด d ที่สุด)
      expect(overlaps(p, pos), false);
    });

    test('แม่ที่มีลูกหลายตัว: อยู่ระดับกึ่งกลางของลูก (เส้นไม่เอียงยาว)', () {
      final p = Project(
        tables: [t('p'), t('c1'), t('c2'), t('c3')],
        relations: [fk('c1', 'p'), fk('c2', 'p'), fk('c3', 'p')],
      );
      final pos = autoLayout(p);
      double center(String id) => pos[id]!.y + hOf(p.tableById(id)!) / 2;
      final avg = (center('c1') + center('c2') + center('c3')) / 3;
      expect(center('p'), closeTo(avg, 1));
      expect(overlaps(p, pos), false);
    });

    test('ลูกสองตัวต่อแม่คนละตัว: เรียงขนานกันตรงๆ (ระดับเดียวกับแม่ของตัวเอง)', () {
      final p = Project(
        tables: [t('a1'), t('a2', cols: 6), t('c1'), t('c2')],
        relations: [fk('c1', 'a1'), fk('c2', 'a2')],
      );
      final pos = autoLayout(p);
      double center(String id) => pos[id]!.y + hOf(p.tableById(id)!) / 2;
      expect(center('c1'), closeTo(center('a1'), 1));
      expect(center('c2'), closeTo(center('a2'), 1));
    });

    test('ช่องว่างระหว่างชั้นกว้างขึ้นเมื่อมีเส้นผ่านมาก (เส้นแยกเลนมีที่)', () {
      double gap(Project p) {
        final pos = autoLayout(p);
        return pos['child']!.x - (pos['parent']!.x + p.tableById('parent')!.width);
      }

      final one = Project(tables: [t('parent'), t('child', cols: 12)], relations: [fk('child', 'parent')]);
      final many = Project(tables: [t('parent'), t('child', cols: 12)], relations: [
        for (var i = 1; i <= 8; i++) fk('child', 'parent', col: i),
      ]);
      expect(gap(many), greaterThan(gap(one)));
      expect(gap(one), greaterThanOrEqualTo(90));
    });

    test('ชุดตารางที่เชื่อมกันหลายชุดเรียงเป็นแถวห่อบรรทัด ไม่ต่อกันยาวเป็นแนวตั้งหรือแนวนอนอย่างเดียว', () {
      final tables = <TableModel>[];
      final rels = <RelationModel>[];
      for (var i = 0; i < 16; i++) {
        tables.addAll([t('p$i'), t('c$i')]);
        rels.add(fk('c$i', 'p$i'));
      }
      final p = Project(tables: tables, relations: rels);
      final pos = autoLayout(p);
      expect(overlaps(p, pos), false);
      final ys = {for (final tb in p.tables) pos[tb.id]!.y.round()};
      expect(ys.length, greaterThan(1)); // มีหลายแถว
      final right = p.tables.map((tb) => pos[tb.id]!.x + tb.width).reduce((a, b) => a > b ? a : b);
      final bottom = p.tables.map((tb) => pos[tb.id]!.y + hOf(tb)).reduce((a, b) => a > b ? a : b);
      expect(right, lessThan(3200)); // กว้างไม่เกินเป้า
      expect(bottom, lessThan(right * 2.5)); // สัดส่วนไม่ยาวเป็นแนวตั้งผิดปกติ
    });

    test('ผลลัพธ์คงที่ (เรียกซ้ำได้ค่าเดิม) แม้มีกลุ่ม', () {
      final p = Project(
        tables: [t('a'), t('b'), t('c')],
        relations: [fk('b', 'a'), fk('c', 'a')],
        groups: [GroupModel(id: 'g', name: 'G', x: -100, y: -100, width: 100000, height: 100000)],
      );
      expect(autoLayoutAll(p).tables, autoLayoutAll(p).tables);
    });
  });

  group('auto layout: กลุ่ม', () {
    Project grouped() {
      final p = Project(
        tables: [t('u1'), t('u2'), t('o1'), t('o2'), t('free')],
        relations: [fk('u2', 'u1'), fk('o2', 'o1'), fk('free', 'u1', col: 2)],
        groups: [
          GroupModel(id: 'gu', name: 'Users', x: 0, y: 0, width: 700, height: 300),
          GroupModel(id: 'go', name: 'Orders', x: 900, y: 0, width: 700, height: 300),
        ],
      );
      // วางตารางสมาชิกไว้ในกรอบเดิม
      p.tableById('u1')!
        ..x = 20
        ..y = 60;
      p.tableById('u2')!
        ..x = 300
        ..y = 60;
      p.tableById('o1')!
        ..x = 920
        ..y = 60;
      p.tableById('o2')!
        ..x = 1200
        ..y = 60;
      p.tableById('free')!
        ..x = 2000
        ..y = 800;
      return p;
    }

    bool inside(TableModel tb, GroupRect r, Map<String, Pos> pos) =>
        pos[tb.id]!.x >= r.x &&
        pos[tb.id]!.y >= r.y &&
        pos[tb.id]!.x + tb.width <= r.x + r.width &&
        pos[tb.id]!.y + hOf(tb) <= r.y + r.height;

    test('ตารางสมาชิกอยู่ในกรอบกลุ่มของตัวเองเสมอ ตารางอิสระอยู่นอกทุกกรอบ กรอบกลุ่มไม่ทับกัน', () {
      final p = grouped();
      final res = autoLayoutAll(p);
      final pos = res.tables;
      expect(overlaps(p, pos), false);
      for (final id in ['u1', 'u2']) {
        expect(inside(p.tableById(id)!, res.groups['gu']!, pos), true, reason: id);
      }
      for (final id in ['o1', 'o2']) {
        expect(inside(p.tableById(id)!, res.groups['go']!, pos), true, reason: id);
      }
      for (final r in res.groups.values) {
        expect(inside(p.tableById('free')!, r, pos), false);
      }
      final a = res.groups['gu']!, b = res.groups['go']!;
      final apart = a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y;
      expect(apart, true);
    });

    test('กรอบกลุ่มครอบสมาชิกพอดี: เผื่อขอบเท่ากันทุกด้านและเหลือที่ให้แถบชื่อกลุ่มด้านบน', () {
      final p = grouped();
      final res = autoLayoutAll(p);
      final members = [p.tableById('u1')!, p.tableById('u2')!];
      final r = res.groups['gu']!;
      final minX = members.map((m) => res.tables[m.id]!.x).reduce((a, b) => a < b ? a : b);
      final minY = members.map((m) => res.tables[m.id]!.y).reduce((a, b) => a < b ? a : b);
      expect(minX - r.x, 28);
      expect(minY - r.y, 28 + kGroupHeader);
    });

    test('ภายในกลุ่มยังเป็นตามกฎเดิม: แม่ซ้ายลูก', () {
      final p = grouped();
      final pos = autoLayout(p);
      expect(pos['u1']!.x, lessThan(pos['u2']!.x));
      expect(pos['o1']!.x, lessThan(pos['o2']!.x));
    });

    test('ProjectController.autoLayoutTables: กรอบกลุ่มปรับตาม โน้ตในกลุ่มย้ายตามกลุ่ม และ undo กลับครบ', () {
      final p = grouped();
      p.notes.add(NoteModel(id: 'n1', text: 'in users', x: 100, y: 200));
      final c = ProjectController(p);
      final g0 = c.project.groupById('gu')!;
      final before = (g0.x, g0.y, g0.width, g0.height, c.project.notes.single.x, c.project.notes.single.y);
      expect(c.autoLayoutTables(), true);
      final g1 = c.project.groupById('gu')!;
      final n1 = c.project.notes.single;
      // โน้ตเลื่อนตามกรอบกลุ่ม (ระยะสัมพัทธ์ต่อมุมซ้ายบนของกลุ่มเท่าเดิม)
      expect(n1.x - g1.x, closeTo(100 - before.$1, 0.001));
      expect(n1.y - g1.y, closeTo(200 - before.$2, 0.001));
      expect(overlapsProject(c.project), false);
      c.undo();
      final g2 = c.project.groupById('gu')!;
      expect((g2.x, g2.y, g2.width, g2.height), (before.$1, before.$2, before.$3, before.$4));
      expect((c.project.notes.single.x, c.project.notes.single.y), (before.$5, before.$6));
    });

    test('กลุ่มที่ไม่มีตารางสมาชิก: ไม่ถูกแตะ', () {
      final p = Project(tables: [t('a')], groups: [GroupModel(id: 'e', name: 'Empty', x: 5000, y: 5000)]);
      final res = autoLayoutAll(p);
      expect(res.groups.containsKey('e'), false);
      final c = ProjectController(p);
      c.autoLayoutTables();
      expect(c.project.groupById('e')!.x, 5000);
    });
  });

  group('ข้อมูลจริงจากไฟล์ตัวอย่าง', () {
    for (final f in ['shop_mysql.sql', 'blog_postgres.sql', 'school_sqlite.sql']) {
      test('$f: จัดแล้วไม่ทับกัน แม่อยู่ซ้ายลูก และเส้น FK ไม่วิ่งซ้อนกันบนแนวตั้งเดียวกัน', () {
        final p = importSql(File('samples/$f').readAsStringSync()).project;
        final pos = autoLayout(p);
        expect(overlaps(p, pos), false);
        for (final r in p.relations) {
          if (r.fromTableId == r.toTableId) continue;
          expect(pos[r.toTableId]!.x, lessThanOrEqualTo(pos[r.fromTableId]!.x), reason: '${r.fromTableId}->${r.toTableId}');
        }
        apply(p, pos);
        final routes = relationRoutes(p).values.toList();
        for (var i = 0; i < routes.length; i++) {
          for (var j = i + 1; j < routes.length; j++) {
            expect(verticalOverlap(routes[i], routes[j]), false, reason: 'เส้น $i ซ้อนเส้น $j');
          }
        }
      });
    }
  });

  group('เส้นไม่วิ่งซ้อนกัน', () {
    test('เส้นที่ไปแม่เดียวกันจากคนละตาราง ต่างอยู่คนละเลน แนวตั้งไม่ซ้อนกัน', () {
      final p = Project(
        tables: [t('prod'), t('items', cols: 4), t('reviews', cols: 5)],
        relations: [fk('items', 'prod'), fk('reviews', 'prod')],
      );
      p.tableById('prod')!
        ..x = 40
        ..y = 200;
      p.tableById('items')!
        ..x = 500
        ..y = 20;
      p.tableById('reviews')!
        ..x = 500
        ..y = 420;
      final routes = relationRoutes(p).values.toList();
      expect(verticalOverlap(routes[0], routes[1]), false);
    });

    test('แนวตั้งสองเส้นที่ตกห่างกันแค่ 2px (คนละกลุ่มเลน) ถูกดันออกจนห่างอย่างน้อย kRouteMinSeparation', () {
      // กึ่งกลางช่องว่างของสองเส้นต่างกัน 2 px และคาบเกี่ยวกันในแนวตั้ง
      final p = Project(
        tables: [t('p1'), t('x1', cols: 6), t('p2'), t('x2', cols: 6)],
        relations: [fk('x1', 'p1'), fk('x2', 'p2')],
      );
      p.tableById('p1')!
        ..x = 40
        ..y = 100;
      p.tableById('x1')!
        ..x = 368 // กลางช่อง = (260 + 368) / 2 = 314
        ..y = 120;
      p.tableById('p2')!
        ..x = 40
        ..y = 400;
      p.tableById('x2')!
        ..x = 372 // กลางช่อง = (260 + 372) / 2 = 316
        ..y = 80;
      final routes = relationRoutes(p).values.toList();
      expect(verticalOverlap(routes[0], routes[1]), false, reason: '$routes');
      // และเส้นทางยังเป็นแนวตั้ง/แนวนอนล้วน เริ่ม-จบที่คอลัมน์เดิม
      for (final r in routes) {
        for (var i = 1; i < r.length; i++) {
          expect((r[i - 1].$1 - r[i].$1).abs() < 0.001 || (r[i - 1].$2 - r[i].$2).abs() < 0.001, true);
        }
      }
    });

    test('เส้นเข้าคอลัมน์แม่เดียวกันห่างกันพอเห็นเป็นสองเส้น (ไม่ซ้อนเป็นเส้นหนา)', () {
      expect(kEndSpread, greaterThanOrEqualTo(10));
    });
  });
}

bool overlapsProject(Project p) {
  final pos = {for (final tb in p.tables) tb.id: (x: tb.x, y: tb.y)};
  for (var i = 0; i < p.tables.length; i++) {
    for (var j = i + 1; j < p.tables.length; j++) {
      final a = p.tables[i], b = p.tables[j];
      final ax = pos[a.id]!, bx = pos[b.id]!;
      if (ax.x < bx.x + b.width && bx.x < ax.x + a.width && ax.y < bx.y + hOf(b) && bx.y < ax.y + hOf(a)) return true;
    }
  }
  return false;
}
