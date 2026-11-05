import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/ui/right_panel.dart';
import 'package:nsl_dev/ui/widgets.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  late ProjectController c;
  late AppSettings settings;

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
    tester.view.physicalSize = const Size(1440, 936); // +36 = แถบแท็บแผนภาพ
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = AppSettings(lang: lang);
    await tester.pumpWidget(NslDevApp(settings: settings));
    c = tester.element(find.byType(HomePage)).read<ProjectController>();
    c.loadProject(base(), null);
    c.selectTable('to', columnId: 'o2'); // orders.user_id = คอลัมน์ FK
    await tester.pumpAndSettle();
  }

  Finder inPanel(Finder f) => find.descendant(of: find.byType(RightPanel), matching: f);

  /// ป้ายของช่องติ๊ก (ไม่ใช่ป้าย PK ตัวเล็กในรายการคอลัมน์): ข้อความขนาด 13 ในฟอนต์ปกติ
  Finder checkLabel(String text) => inPanel(find.byWidgetPredicate(
      (w) => w is Text && w.data == text && w.style?.fontSize == 13 && w.style?.fontFamily != 'JetBrains Mono'));

  group('ตัวแก้คอลัมน์ในแผงขวา: สัดส่วนเรียบร้อย', () {
    testWidgets('ช่องชนิดข้อมูลกับช่องค่าเริ่มต้นสูงเท่ากัน (ความสูงมาตรฐานเดียวกัน)', (tester) async {
      await boot(tester);
      final type = tester.getSize(inPanel(find.byType(Dropdown<DataType>)));
      final def = tester.getSize(find.byKey(const ValueKey('cd-o2-null')));
      // กรอบของ TextField ที่ถูก decorate อยู่ภายใน CommitField
      final defField = tester.getSize(find.descendant(of: find.byKey(const ValueKey('cd-o2-null')), matching: find.byType(TextField)));
      expect(type.height, kFieldHeight);
      expect(defField.height, kFieldHeight);
      expect(def.height, greaterThanOrEqualTo(kFieldHeight)); // รวมป้ายกำกับ
    });

    testWidgets('ON DELETE / ON UPDATE สูงเท่ากับช่องอื่น และ "NO ACTION" ไม่ตัดขึ้นบรรทัดใหม่', (tester) async {
      await boot(tester);
      await tester.ensureVisible(inPanel(find.byType(Dropdown<RefAction>)).first);
      await tester.pump();
      final boxes = tester.widgetList<Dropdown<RefAction>>(inPanel(find.byType(Dropdown<RefAction>))).length;
      expect(boxes, 2);
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(inPanel(find.byType(Dropdown<RefAction>)).at(i));
        expect(size.height, kFieldHeight, reason: 'ดรอปดาวน์ที่ $i');
      }
      // ข้อความในดรอปดาวน์เป็นบรรทัดเดียว
      final texts = tester.widgetList<Text>(find.descendant(
        of: inPanel(find.byType(Dropdown<RefAction>)).last,
        matching: find.byType(Text),
      ));
      for (final t in texts) {
        expect(t.maxLines, 1);
        expect(t.softWrap, false);
      }
    });

    testWidgets('ช่องติ๊กเรียงเป็นตาราง 2 คอลัมน์ตรงกัน (PK/UNIQUE ซ้าย-ขวา, NOT NULL/AUTO INCREMENT ซ้าย-ขวา)', (tester) async {
      await boot(tester);
      double x(String label) => tester.getTopLeft(checkLabel(label)).dx;
      double y(String label) => tester.getCenter(checkLabel(label)).dy;
      // แถวเดียวกัน: PK กับ NOT NULL ; UNIQUE กับ AUTO INCREMENT (ซ้าย→ขวา)
      expect(x('PK'), lessThan(x('NOT NULL')));
      expect(y('PK'), closeTo(y('NOT NULL'), 1));
      expect(y('UNIQUE'), closeTo(y('AUTO INCREMENT'), 1));
      expect(y('UNIQUE'), greaterThan(y('PK')));
      // คอลัมน์เดียวกันตรงกันทุกแถว
      expect(x('UNIQUE'), closeTo(x('PK'), 1));
      expect(x('AUTO INCREMENT'), closeTo(x('NOT NULL'), 1));
    });

    for (final w in [PanelLayout.kRightMin, PanelLayout.kRightMax]) {
      testWidgets('แผงขวากว้าง ${w.toInt()} px: ไม่ overflow และช่องกรอก/ดรอปดาวน์ไม่ล้นแผง', (tester) async {
        await boot(tester);
        settings.layout.setRight(w);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final panel = tester.getRect(find.byType(RightPanel));
        for (final f in [
          inPanel(find.byType(Dropdown<DataType>)),
          inPanel(find.byType(Dropdown<RefAction>)).first,
          inPanel(find.byType(Dropdown<RefAction>)).last,
        ]) {
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(panel.left));
          expect(r.right, lessThanOrEqualTo(panel.right));
        }
      });
    }

    testWidgets('ภาษาอังกฤษ + แผงแคบสุด: ไม่ overflow', (tester) async {
      await boot(tester, lang: Lang.en);
      settings.layout.setRight(PanelLayout.kRightMin);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      currentLang = Lang.th;
    });

    testWidgets('รายการคอลัมน์: ขอบซ้ายของชื่อ ขอบขวาของป้ายและชนิดข้อมูลตรงกันทุกแถว (ไม่เหลื่อม)', (tester) async {
      await boot(tester);
      // orders: id (PK NN AI), user_id (FK NN), total, note — ป้ายต่างกันและชนิดข้อมูลยาวสั้นต่างกัน
      final ids = tb(c.project, 'to').columns.map((x) => x.id).toList();
      Rect rect(String key) => tester.getRect(inPanel(find.byKey(ValueKey(key))));
      for (final w in [PanelLayout.kRightMin, PanelLayout.kRightDefault, PanelLayout.kRightMax]) {
        settings.layout.setRight(w);
        await tester.pumpAndSettle();
        final names = [for (final id in ids) rect('col-name-$id')];
        final badges = [for (final id in ids) rect('col-badges-$id')];
        final types = [for (final id in ids) rect('col-type-$id')];
        for (var i = 1; i < ids.length; i++) {
          expect(names[i].left, closeTo(names[0].left, 0.5), reason: 'ชื่อ แผง $w');
          expect(badges[i].right, closeTo(badges[0].right, 0.5), reason: 'ป้าย แผง $w');
          expect(types[i].right, closeTo(types[0].right, 0.5), reason: 'ชนิด แผง $w');
          expect(types[i].width, closeTo(types[0].width, 0.5), reason: 'ความกว้างช่องชนิด แผง $w');
        }
        // ป้ายกับชนิดไม่ซ้อนกัน และชื่อไม่ล้นไปทับป้าย
        for (var i = 0; i < ids.length; i++) {
          expect(badges[i].right, lessThanOrEqualTo(types[i].left + 0.5));
          expect(names[i].right, lessThanOrEqualTo(badges[i].left + 0.5));
        }
        expect(tester.takeException(), isNull, reason: 'แผง $w');
      }
    });

    testWidgets('รายการคอลัมน์: ป้ายและชนิดข้อมูลชิดขวา (ข้อความอยู่ชิดขอบขวาของช่อง)', (tester) async {
      await boot(tester);
      final ids = tb(c.project, 'to').columns.map((x) => x.id).toList();
      for (final id in ids) {
        final slot = tester.getRect(inPanel(find.byKey(ValueKey('col-type-$id'))));
        final text = tester.getRect(find.descendant(of: inPanel(find.byKey(ValueKey('col-type-$id'))), matching: find.byType(Text)));
        expect(text.right, closeTo(slot.right, 0.5));
      }
    });

    testWidgets('แผงกว้าง (>= 440px เนื้อหา): ช่องติ๊กเรียงแถวเดียว 4 คอลัมน์', (tester) async {
      await boot(tester);
      settings.layout.setRight(PanelLayout.kRightMax);
      await tester.pumpAndSettle();
      double y(String label) => tester.getCenter(checkLabel(label)).dy;
      expect(y('PK'), closeTo(y('AUTO INCREMENT'), 1));
    });
  });
}
