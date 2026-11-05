import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/svg_export.dart';
import 'package:nsl_dev/core/layout/diagram_geometry.dart';
import 'package:nsl_dev/core/models/group_model.dart';
import 'package:nsl_dev/core/models/note_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

bool _axisAligned(List<RoutePoint> pts) {
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    if ((a.$1 - b.$1).abs() > 0.001 && (a.$2 - b.$2).abs() > 0.001) return false;
  }
  return true;
}

void main() {
  group('relationRoutes: เลี่ยงขอบกลุ่ม', () {
    Project placed() {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 600
        ..y = 300;
      return p;
    }

    test('ไม่มีกลุ่ม = แนวตั้งอยู่กลางช่อง; มีขอบกลุ่มตรงนั้น = ขยับออกห่างอย่างน้อย kGroupEdgeClear', () {
      final p = placed();
      final mid = relationRoutes(p)['r1']![1].$1;
      p.groups.add(GroupModel(id: 'g', name: 'g', x: 0, y: 0, width: mid, height: 600)); // ขอบขวาของกลุ่มอยู่กลางช่องพอดี
      final route = relationRoutes(p)['r1']!;
      expect(_axisAligned(route), true);
      for (var i = 1; i < route.length; i++) {
        if ((route[i - 1].$1 - route[i].$1).abs() < 0.001) {
          expect((route[i].$1 - mid).abs(), greaterThanOrEqualTo(kGroupEdgeClear));
        }
      }
    });

    test('เส้นที่ข้ามขอบกลุ่มตรง ๆ ไม่ต้องหลบ (ไม่เกาะขอบ)', () {
      final p = placed();
      p.groups.add(GroupModel(id: 'g', name: 'g', x: 0, y: 0, width: 300, height: 600));
      final mid = relationRoutes(placed())['r1']![1].$1;
      expect(relationRoutes(p)['r1']![1].$1, mid);
    });
  });

  group('relationRoutes: เส้น FK หักมุมฉาก', () {
    test('การ์ดอยู่คนละฝั่ง: ออกแนวนอน หักกลางช่องว่าง แล้วเข้าแนวนอน และทุกช่วงตรงแกน', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60; // users ซ้าย
      tb(p, 'to')
        ..x = 500
        ..y = 300; // orders ขวา-ล่าง
      final route = relationRoutes(p)['r1']!;
      expect(route.length, 4);
      expect(_axisAligned(route), true);
      final g = relationGeometry(p, p.relations.first)!;
      expect(route.first, (g.fx, g.fy));
      expect(route.last, (g.tx, g.ty));
      // แนวตั้งอยู่ระหว่างขอบการ์ดสองใบ
      final mx = route[1].$1;
      expect(mx, greaterThan(40 + tb(p, 'tu').width));
      expect(mx, lessThan(500));
    });

    test('คอลัมน์ระดับเดียวกัน = เส้นตรงล้วน', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 100;
      tb(p, 'to')
        ..x = 500
        ..y = 100 - 28.0 * 3 + 28.0 * 0; // ให้ orders.user_id (แถว 2) ตรงกับ users.id (แถว 1)
      // ปรับ y ให้ศูนย์กลางแถวตรงกันพอดี
      final g0 = relationGeometry(p, p.relations.first)!;
      tb(p, 'to').y += g0.ty - g0.fy;
      final route = relationRoutes(p)['r1']!;
      expect(route.length, 2);
    });

    test('การ์ดซ้อนกัน/ตารางเดียวกัน: อ้อมออกด้านข้างพ้นขอบการ์ด', () {
      final p = base();
      tb(p, 'tu')
        ..x = 100
        ..y = 100;
      tb(p, 'to')
        ..x = 150 // ซ้อนในแนวนอน
        ..y = 400;
      final route = relationRoutes(p)['r1']!;
      expect(_axisAligned(route), true);
      final right = [tb(p, 'tu'), tb(p, 'to')].map((t) => t.x + t.width).reduce((a, b) => a > b ? a : b);
      expect(route[1].$1, greaterThanOrEqualTo(right + kRouteStub - 0.001));
    });

    test('FK หลายเส้นผ่านช่องว่างเดียวกัน = แยกเป็นเลนขนาน ไม่ทับกัน', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 500
        ..y = 300;
      // เพิ่ม FK อีก 2 เส้นระหว่างสองตารางเดิม (ต่างคอลัมน์ต้นทาง)
      p.relations.add(RelationModel(
          id: 'r2', fromTableId: 'to', fromColumnId: 'o3', toTableId: 'tu', toColumnId: 'u2'));
      p.relations.add(RelationModel(
          id: 'r3', fromTableId: 'to', fromColumnId: 'o4', toTableId: 'tu', toColumnId: 'u3'));
      final routes = relationRoutes(p);
      final xs = [for (final id in ['r1', 'r2', 'r3']) routes[id]![1].$1];
      expect(xs.toSet().length, 3, reason: 'เลนต้องไม่ซ้ำกัน: $xs');
      xs.sort();
      expect(xs[1] - xs[0], closeTo(kRouteLaneGap, 0.001));
      expect(xs[2] - xs[1], closeTo(kRouteLaneGap, 0.001));
      for (final id in ['r1', 'r2', 'r3']) {
        expect(_axisAligned(routes[id]!), true);
      }
    });

    test('ความสัมพันธ์ที่อ้างถึงของที่ไม่มี ถูกข้าม', () {
      final p = base();
      p.relations.add(RelationModel(
          id: 'bad', fromTableId: 'to', fromColumnId: 'nope', toTableId: 'tu', toColumnId: 'u1'));
      expect(relationRoutes(p).containsKey('bad'), false);
    });
  });

  group('relationRoutes: เลี่ยงสิ่งกีดขวางและห่วง self-reference', () {
    /// มีส่วนใดของเส้นตัดผ่านภายในการ์ด [t] หรือไม่ (แตะขอบไม่นับ)
    bool crosses(List<RoutePoint> pts, double l, double t, double r, double b) {
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], c = pts[i];
        final horizontal = (a.$2 - c.$2).abs() < 0.001;
        if (horizontal) {
          if (a.$2 > t && a.$2 < b && (a.$1 < c.$1 ? a.$1 : c.$1) < r && (a.$1 > c.$1 ? a.$1 : c.$1) > l) return true;
        } else {
          if (a.$1 > l && a.$1 < r && (a.$2 < c.$2 ? a.$2 : c.$2) < b && (a.$2 > c.$2 ? a.$2 : c.$2) > t) return true;
        }
      }
      return false;
    }

    Project threeTables() {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 700
        ..y = 400;
      // ตารางที่ 3 วางขวางกลางช่องว่างระหว่าง users กับ orders
      p.tables.add(TableModel(id: 'tx', name: 'blocker', x: 330, y: 120, columns: [
        col('x1', 'id', pk: true),
        col('x2', 'v'),
      ]));
      return p;
    }

    test('ไม่มีสิ่งกีดขวาง = เส้น 4 จุดตามเลนปกติ', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 700
        ..y = 400;
      expect(relationRoutes(p)['r1']!.length, 4);
    });

    test('การ์ดวางขวางกลางช่อง: เส้นไม่ตัดผ่านการ์ดนั้น และยังเริ่ม/จบที่คอลัมน์เดิม', () {
      final p = threeTables();
      final blocker = tb(p, 'tx');
      final route = relationRoutes(p)['r1']!;
      expect(
        crosses(route, blocker.x, blocker.y, blocker.x + blocker.width, blocker.y + tableHeight(blocker)),
        false,
        reason: '$route',
      );
      expect(_axisAligned(route), true);
      final g = relationGeometry(p, p.relations.first)!;
      expect(route.first, (g.fx, g.fy));
      expect(route.last, (g.tx, g.ty));
    });

    test('ถ้าขวางทั้งช่อง (แนวตั้ง) จะอ้อมผ่านเหนือ/ใต้ ได้เส้น 6 จุด', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 700
        ..y = 100;
      // กำแพงการ์ดสูงที่กั้นช่องว่างตลอดแนวตั้งและกว้างเต็มช่อง
      p.tables.add(TableModel(id: 'wall', name: 'wall', x: 300, y: -400, width: 360, columns: [
        for (var i = 0; i < 40; i++) col('w$i', 'c$i'),
      ]));
      final wall = tb(p, 'wall');
      final route = relationRoutes(p)['r1']!;
      expect(route.length, 6);
      expect(_axisAligned(route), true);
      expect(
        crosses(route, wall.x, wall.y, wall.x + wall.width, wall.y + tableHeight(wall)),
        false,
        reason: '$route',
      );
    });

    test('โน้ตที่ขวางทางก็ถูกเลี่ยง', () {
      final p = threeTables()..tables.removeWhere((t) => t.id == 'tx');
      final n = NoteModel(id: 'n1', x: 330, y: 150, text: 'hello');
      p.notes.add(n);
      final route = relationRoutes(p)['r1']!;
      expect(crosses(route, n.x, n.y, n.x + n.width, n.y + noteHeight(n)), false, reason: '$route');
    });

    test('self-reference: ห่วงยื่นออกจากขอบการ์ดไกลกว่าเส้นทั่วไป (มองเห็นเป็นห่วง)', () {
      final p = base();
      final t = tb(p, 'tu')
        ..x = 100
        ..y = 100;
      t.columns.add(col('u5', 'parent_id'));
      p.relations.add(RelationModel(
          id: 'self', fromTableId: 'tu', fromColumnId: 'u5', toTableId: 'tu', toColumnId: 'u1'));
      final route = relationRoutes(p)['self']!;
      expect(_axisAligned(route), true);
      expect(route[1].$1 - (t.x + t.width), greaterThanOrEqualTo(kRouteSelfLoop));
      // ไม่ปนเลนกับเส้นที่ออกด้านเดียวกันจากตารางอื่น
      expect(route.length, 4);
    });

    test('self-reference หลายเส้นของตารางเดียวกัน: แยกเลน ไม่ทับกัน', () {
      final p = base();
      final t = tb(p, 'tu')
        ..x = 100
        ..y = 100;
      t.columns.addAll([col('u5', 'p1'), col('u6', 'p2')]);
      p.relations.add(RelationModel(
          id: 's1', fromTableId: 'tu', fromColumnId: 'u5', toTableId: 'tu', toColumnId: 'u1'));
      p.relations.add(RelationModel(
          id: 's2', fromTableId: 'tu', fromColumnId: 'u6', toTableId: 'tu', toColumnId: 'u1'));
      final routes = relationRoutes(p);
      expect(routes['s1']![1].$1, isNot(routes['s2']![1].$1));
    });
  });

  group('เส้นที่ไปหาตารางแม่ตัวเดียวกัน (ไม่รวมเป็นเส้นเดียว: วิ่งขนานแยกเลน)', () {
    /// users (แม่) ซ้าย, orders (ลูก) ขวา มี FK สองเส้นไป users.id คนละคอลัมน์ต้นทาง
    Project twoToOne() {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 500
        ..y = 300;
      p.relations.add(RelationModel(
          id: 'r2', fromTableId: 'to', fromColumnId: 'o3', toTableId: 'tu', toColumnId: 'u1'));
      return p;
    }

    test('สองเส้นไปคอลัมน์แม่เดียวกัน: แนวตั้งคนละเลน (ห่าง 10 px) ไม่ซ้อนกัน แต่ไปจบที่จุดแม่เดียวกัน', () {
      final routes = relationRoutes(twoToOne());
      final a = routes['r1']![1].$1, b = routes['r2']![1].$1;
      expect(a, isNot(b));
      expect((a - b).abs(), closeTo(kRouteLaneGap, 0.001));
    });

    test('เข้าตารางแม่คนละระดับ (ไม่ทับกัน): ที่ขอบการ์ดเดียวกัน แต่ห่างกัน kEndSpread และกระจายรอบกึ่งกลางแถวแม่', () {
      final p = twoToOne();
      final routes = relationRoutes(p);
      final e1 = routes['r1']!.last, e2 = routes['r2']!.last;
      expect(e1.$1, e2.$1); // ขอบการ์ดแม่ด้านเดียวกัน
      expect((e1.$2 - e2.$2).abs(), closeTo(kEndSpread, 0.001)); // แต่คนละระดับ
      expect(e1.$2, lessThan(e2.$2)); // ต้นทางสูงกว่า (o2) เข้าช่องสูงกว่า ไม่ไขว้กัน
      final g = relationGeometry(p, p.relations.first)!;
      expect((e1.$2 + e2.$2) / 2, closeTo(g.ty, 0.001));
      // ช่วงสุดท้ายที่เข้าแม่ (แนวนอน) ของทั้งสองเส้นไม่อยู่บนเส้นเดียวกัน
      expect(routes['r1']![routes['r1']!.length - 2].$2, e1.$2);
      expect(routes['r2']![routes['r2']!.length - 2].$2, e2.$2);
    });

    test('เส้นเดียวเข้าคอลัมน์แม่ = เข้าที่กึ่งกลางแถวพอดี (ไม่เลื่อน)', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 500
        ..y = 300;
      final g = relationGeometry(p, p.relations.first)!;
      expect(relationRoutes(p)['r1']!.last, (g.tx, g.ty));
    });

    test('สามเส้นเข้าคอลัมน์เดียวกัน: ระดับห่างเท่ากันและเรียงตามความสูงของต้นทาง', () {
      final p = twoToOne();
      p.relations.add(RelationModel(
          id: 'r3', fromTableId: 'to', fromColumnId: 'o4', toTableId: 'tu', toColumnId: 'u1'));
      final routes = relationRoutes(p);
      final ys = [for (final id in ['r1', 'r2', 'r3']) routes[id]!.last.$2]; // ต้นทาง o2,o3,o4 เรียงลงล่าง
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
      expect(ys[1] - ys[0], closeTo(kEndSpread, 0.001));
      expect(ys[2] - ys[1], closeTo(kEndSpread, 0.001));
      final slots = parentEndSlots(p);
      expect(slots.values.every((s) => s.count == 3), true);
    });

    test('จำนวนเส้นมากขึ้น: ผลรวมการกระจายไม่เกิน kEndSpreadMax (ไม่ล้นแถวสูง 28 px)', () {
      final p = twoToOne();
      for (var i = 0; i < 6; i++) {
        p.relations.add(RelationModel(
            id: 'x$i', fromTableId: 'to', fromColumnId: 'o4', toTableId: 'tu', toColumnId: 'u1'));
      }
      final dys = parentEndSlots(p).values.map((s) => s.dy).toList();
      expect(dys.reduce((a, b) => a > b ? a : b) - dys.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(kEndSpreadMax + 0.001));
    });

    test('แต่ละเส้นออกจากแถวต้นทางของตัวเอง และแนวตั้งของแต่ละเส้นไม่ทับกัน', () {
      final routes = relationRoutes(twoToOne());
      expect(routes['r1']!.first.$2, isNot(routes['r2']!.first.$2));
      // ช่วงแนวตั้ง (จุดที่ 2-3) ของสองเส้นอยู่คนละ x จึงไม่เป็นเส้นเดียวกัน
      expect(routes['r1']![1].$1, isNot(routes['r2']![1].$1));
      expect(routes['r1']![2].$1, isNot(routes['r2']![2].$1));
    });

    test('เส้นที่ไปคอลัมน์แม่คนละคอลัมน์ ก็แยกเลนไม่ทับกันเช่นกัน', () {
      final p = twoToOne();
      p.relations.last.toColumnId = 'u2'; // r2 ไป users.email แทน
      final routes = relationRoutes(p);
      expect(routes['r1']![1].$1, isNot(routes['r2']![1].$1));
    });

    test('เส้นสามเส้นไปแม่เดียวกันจากลูกสองตาราง ไม่ทำให้พัง และทุกช่วงยังตรงแกน', () {
      final p = twoToOne();
      p.tables.add(TableModel(id: 'tz', name: 'z', x: 500, y: 700, columns: [col('z1', 'user_id')]));
      p.relations.add(RelationModel(
          id: 'r3', fromTableId: 'tz', fromColumnId: 'z1', toTableId: 'tu', toColumnId: 'u1'));
      for (final r in relationRoutes(p).values) {
        expect(_axisAligned(r), true);
      }
    });
  });

  group('ปลายฝั่งแม่: หนึ่งเดียว (ขีดคู่) / ศูนย์หรือหนึ่ง (ขีด + วงกลม)', () {
    test('mandatory ตามคอลัมน์ FK: NOT NULL/PK = true, NULL ได้ = false', () {
      final p = base();
      expect(relationGeometry(p, p.relations.first)!.mandatory, true); // orders.user_id NOT NULL
      cl(p, 'to', 'o2').notNull = false;
      expect(relationGeometry(p, p.relations.first)!.mandatory, false);
    });

    int bars(String svg) => RegExp(r'<path d="M[\d.]+ [\d.-]+ L[\d.]+ [\d.-]+"/>').allMatches(svg).length;

    test('SVG: FK NOT NULL = ขีดคู่ไม่มีวงกลม ; FK NULL ได้ = ขีดเดียวกับวงกลม', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 500
        ..y = 300;
      final mandatory = exportSvg(p)!;
      expect(mandatory, isNot(contains('<circle')));
      final barsMandatory = bars(mandatory);

      cl(p, 'to', 'o2').notNull = false;
      final optional = exportSvg(p)!;
      expect(optional, contains('<circle'));
      expect(bars(optional), barsMandatory - 1); // ขีดคู่ -> ขีดเดียว
    });

    test('SVG: เส้นหลายเส้นเข้าคอลัมน์แม่เดียวกัน ต่างเส้นต่างมีสัญลักษณ์ปลายแม่ของตัวเอง', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 500
        ..y = 300;
      p.relations.add(RelationModel(
          id: 'r2', fromTableId: 'to', fromColumnId: 'o3', toTableId: 'tu', toColumnId: 'u1'));
      cl(p, 'to', 'o2').notNull = false;
      cl(p, 'to', 'o3').notNull = false;
      expect(RegExp('<circle').allMatches(exportSvg(p)!).length, 2); // NULL ได้ทั้งสองเส้น = วงกลมสองวง
    });

    test('FK NULL ได้ปนกับ NOT NULL ที่คอลัมน์แม่เดียวกัน: แต่ละเส้นแสดงตามของตัวเอง (วงกลมเฉพาะเส้นที่ NULL ได้)', () {
      final p = base();
      tb(p, 'tu')
        ..x = 40
        ..y = 60;
      tb(p, 'to')
        ..x = 500
        ..y = 300;
      p.relations.add(RelationModel(
          id: 'r2', fromTableId: 'to', fromColumnId: 'o3', toTableId: 'tu', toColumnId: 'u1'));
      cl(p, 'to', 'o3').notNull = false; // o2 ยัง NOT NULL
      expect(RegExp('<circle').allMatches(exportSvg(p)!).length, 1);
    });
  });

  group('roundedRoute', () {
    test('เริ่มด้วย M จบด้วย L และมุมเป็น Q', () {
      final cmds = roundedRoute([(0, 0), (50, 0), (50, 80), (120, 80)]);
      expect(cmds.first.$1, 'M');
      expect(cmds.last.$1, 'L');
      expect(cmds.where((c) => c.$1 == 'Q').length, 2);
      expect(cmds.last.$2.single, (120.0, 80.0));
    });

    test('ช่วงสั้นกว่ารัศมี: ลดรัศมีลงครึ่งหนึ่งของช่วง ไม่ล้ำจุดถัดไป', () {
      final cmds = roundedRoute([(0, 0), (6, 0), (6, 100)], radius: 20);
      final firstCut = cmds[1].$2.single; // L ก่อนมุม
      expect(firstCut.$1, closeTo(3, 0.001));
    });

    test('จุดซ้ำกัน/ช่วงยาว 0 ไม่ทำให้พัง', () {
      expect(() => roundedRoute([(0, 0), (0, 0), (10, 0)]), returnsNormally);
    });
  });

  test('SVG ใช้เส้นหักมุมฉากโค้งมน (Q) ไม่ใช่เบซิเยร์ C เดิม และ well-formed', () {
    final p = base();
    tb(p, 'tu')
      ..x = 40
      ..y = 60;
    tb(p, 'to')
      ..x = 500
      ..y = 300;
    final svg = exportSvg(p)!;
    expect(svg, contains(RegExp(r'<path d="M[^"]* L[^"]* Q[^"]*"/>')));
    expect(svg, isNot(contains(RegExp(r'<path d="M[\d. -]+ C'))));
  });

  group('โน้ต: พิมพ์บนโน้ตโดยตรง', () {
    late ProjectController c;
    late CanvasController cv;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      final ctx = tester.element(find.byType(HomePage));
      c = ctx.read<ProjectController>();
      cv = ctx.read<CanvasController>();
      c.loadProject(Project(name: 'n', notes: [NoteModel(id: 'n1', text: 'เดิม', x: 300, y: 200)]), null);
      await tester.pump();
    }

    Finder noteCard() => find.byKey(const ValueKey('note-n1'));
    Finder field() => find.byKey(const ValueKey('note-field-n1'));

    Future<void> dbl(WidgetTester tester, Finder f) async {
      final at = tester.getCenter(f);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
    }

    testWidgets('ดับเบิลคลิก = ช่องพิมพ์โผล่บนโน้ตเลย ไม่มี dialog', (tester) async {
      await boot(tester);
      expect(field(), findsNothing);
      await dbl(tester, noteCard());
      expect(field(), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.widget<TextField>(field()).controller!.text, 'เดิม');
    });

    testWidgets('พิมพ์แล้ว Ctrl+Enter = บันทึก (undo ได้ขั้นเดียว)', (tester) async {
      await boot(tester);
      await dbl(tester, noteCard());
      await tester.enterText(field(), 'แก้ราคา สินค้า');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(field(), findsNothing);
      expect(c.project.notes.first.text, 'แก้ราคา สินค้า');
      expect(find.text('แก้ราคา สินค้า'), findsOneWidget);
      c.undo();
      expect(c.project.notes.first.text, 'เดิม');
    });

    testWidgets('คลิกที่อื่น (เสียโฟกัส) = บันทึกให้', (tester) async {
      await boot(tester);
      await dbl(tester, noteCard());
      await tester.enterText(field(), 'จดไว้');
      await tester.tapAt(const Offset(700, 450)); // พื้นว่าง
      await tester.pumpAndSettle();
      expect(field(), findsNothing);
      expect(c.project.notes.first.text, 'จดไว้');
    });

    testWidgets('Esc = ยกเลิกสิ่งที่พิมพ์ ข้อความเดิมอยู่ครบ และไม่ล้างการเลือกอื่น', (tester) async {
      await boot(tester);
      await dbl(tester, noteCard());
      await tester.enterText(field(), 'ทิ้งนะ');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(field(), findsNothing);
      expect(c.project.notes.first.text, 'เดิม');
      expect(c.canUndo, false);
    });

    testWidgets('พิมพ์ตัวอักษร T/F/N/Delete ในโน้ตไม่ไปสั่งคีย์ลัดของแอป', (tester) async {
      await boot(tester);
      await dbl(tester, noteCard());
      await tester.enterText(field(), '');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(cv.tool, CanvasTool.select);
      expect(c.project.notes.length, 1);
    });

    testWidgets('วางโน้ตใหม่ด้วยเครื่องมือโน้ต = เข้าโหมดพิมพ์ทันที', (tester) async {
      await boot(tester);
      cv.setTool(CanvasTool.note);
      await tester.pump();
      await tester.tapAt(const Offset(800, 500));
      await tester.pumpAndSettle();
      expect(c.project.notes.length, 2);
      final newId = c.project.notes.last.id;
      final f = find.byKey(ValueKey('note-field-$newId'));
      expect(f, findsOneWidget);
      expect(tester.widget<TextField>(f).focusNode!.hasFocus, true);
      await tester.enterText(f, 'โน้ตใหม่');
      await tester.tapAt(const Offset(1000, 700));
      await tester.pumpAndSettle();
      expect(c.project.notes.last.text, 'โน้ตใหม่');
    });

    testWidgets('ปุ่มลบบนโน้ตลบโน้ต (undo กู้คืนได้)', (tester) async {
      await boot(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(noteCard()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-delete-n1')));
      await tester.pumpAndSettle();
      expect(c.project.notes, isEmpty);
      c.undo();
      expect(c.project.notes.length, 1);
    });

    testWidgets('ระหว่างพิมพ์ลากในโน้ตไม่ย้ายโน้ต แต่ตอนไม่พิมพ์ลากย้ายได้', (tester) async {
      await boot(tester);
      final x0 = c.project.notes.first.x;
      await tester.dragFrom(tester.getTopLeft(noteCard()) + const Offset(40, 14), const Offset(60, 0));
      await tester.pump();
      expect(c.project.notes.first.x, greaterThan(x0 + 30));

      final x1 = c.project.notes.first.x;
      await dbl(tester, noteCard());
      expect(field(), findsOneWidget);
      await tester.dragFrom(tester.getCenter(field()), const Offset(60, 0));
      await tester.pump();
      expect(c.project.notes.first.x, x1);
    });
  });
}
