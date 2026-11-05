import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/ddl/sql_highlight.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/file_actions.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/ui/sql_dock.dart';
import 'package:provider/provider.dart';

List<String> kinds(String line) =>
    tokenizeSqlLine(line).where((t) => t.kind != SqlTokenKind.space).map((t) => '${t.kind.name}:${t.text}').toList();

void main() {
  group('tokenizeSqlLine', () {
    test('ต่อ token ทั้งหมดได้ข้อความเดิมเป๊ะ', () {
      const lines = [
        "  `id` INT NOT NULL AUTO_INCREMENT,",
        "  [x] NVARCHAR(MAX) DEFAULT N'it''s' -- หมายเหตุ",
        'ALTER TABLE "a" ADD CONSTRAINT "fk" FOREIGN KEY ("b") REFERENCES "c" ("d") ON DELETE CASCADE;',
        '',
        '   ',
        '-- ภาษาไทย 😀 ตัวอักษรแปลก ~ ^ ¿',
      ];
      for (final l in lines) {
        expect(tokenizeSqlLine(l).map((t) => t.text).join(), l);
      }
    });

    test('จัดประเภท token', () {
      expect(kinds('`id` INT NOT NULL,'), [
        'identifier:`id`',
        'type:INT',
        'keyword:NOT',
        'keyword:NULL',
        'punct:,',
      ]);
      expect(kinds("DEFAULT 'pending'"), ['keyword:DEFAULT', "string:'pending'"]);
      expect(kinds('DECIMAL(10,2)'),
          ['type:DECIMAL', 'punct:(', 'number:10', 'punct:,', 'number:2', 'punct:)']);
    });

    test('-- ในสตริงหรือชื่อที่ quote ไม่ใช่คอมเมนต์', () {
      expect(kinds("'a--b'"), ["string:'a--b'"]);
      expect(kinds('"x--y"'), ['identifier:"x--y"']);
    });

    test('คอมเมนต์ท้ายบรรทัด', () {
      final k = kinds('INT -- เลข');
      expect(k.last, 'comment:-- เลข');
    });

    test("'' ในสตริงไม่ตัดสตริงกลางคัน", () {
      expect(kinds("'it''s'"), ["string:'it''s'"]);
    });

    test('keyword ไม่สนตัวพิมพ์เล็กใหญ่ และชื่อทั่วไปเป็น plain', () {
      expect(kinds('create foo'), ['keyword:create', 'plain:foo']);
    });
  });

  group('sqlFileName', () {
    test('ต่อท้าย dialect', () {
      expect(FileActions.sqlFileName('shop', Dialect.postgres), 'shop_postgres.sql');
    });
    test('ตัดอักขระที่ Windows ห้าม', () {
      expect(FileActions.sqlFileName(r'a/b:c*d?"e<f>g|h\i', Dialect.mysql), 'a_b_c_d__e_f_g_h_i_mysql.sql');
    });
    test('ชื่อว่างใช้ schema', () {
      expect(FileActions.sqlFileName('  ', Dialect.sqlite), 'schema_sqlite.sql');
    });
  });

  group('SqlDock widget', () {
    Future<ProjectController> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NslDevApp());
      return tester.element(find.byType(HomePage)).read<ProjectController>();
    }

    Finder rich(String s) => find.textContaining(s, findRichText: true);

    testWidgets('แสดง SQL สดตามแผนภาพ และสลับ dialect แล้วเปลี่ยนตาม', (tester) async {
      final c = await pump(tester);
      expect(rich('SQL Preview'), findsOneWidget);

      c.addTable(name: 'users');
      await tester.pump();
      expect(rich('CREATE TABLE'), findsOneWidget);
      expect(rich('AUTO_INCREMENT'), findsOneWidget);

      await tester.tap(find.text('PostgreSQL'));
      await tester.pump();
      expect(c.project.dialect, Dialect.postgres);
      expect(rich('SERIAL'), findsOneWidget);
      expect(rich('AUTO_INCREMENT'), findsNothing);

      await tester.tap(find.text('SQL Server'));
      await tester.pump();
      expect(rich('IDENTITY'), findsOneWidget);
    });

    testWidgets('ปุ่มคัดลอกส่ง SQL ทั้งหมดไป clipboard', (tester) async {
      final c = await pump(tester);
      c.addTable(name: 'users');
      await tester.pump();

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.tap(find.text('คัดลอก'));
      await tester.pump();
      expect(copied, contains('CREATE TABLE `users`'));
      expect(find.text('คัดลอกแล้ว ✓'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2)); // ข้อความกลับเป็นเดิม
      expect(find.text('คัดลอก'), findsOneWidget);
    });

    testWidgets('ย่อ/ขยาย dock', (tester) async {
      await pump(tester);
      double h() => tester.getSize(find.byType(SqlDock)).height;
      expect(h(), 248);
      await tester.tap(find.byTooltip('ย่อแผง SQL'));
      await tester.pump();
      expect(h(), 44);
      await tester.tap(find.byTooltip('ขยายแผง SQL'));
      await tester.pump();
      expect(h(), 248);
    });

    testWidgets('Alt+2 สลับเป็น PostgreSQL', (tester) async {
      final c = await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(c.project.dialect, Dialect.postgres);
    });
  });
}
