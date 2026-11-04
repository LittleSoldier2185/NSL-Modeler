import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/db/db_session.dart';
import 'package:nsl_modeler/core/db/mysql_reader.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/db_connect_dialog.dart';
import 'package:nsl_modeler/ui/data_browser_dialog.dart';
import 'package:nsl_modeler/ui/import_dialog.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:nsl_modeler/ui/shortcuts.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

const _users = '''CREATE TABLE `users` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `email` varchar(255) NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4''';

const _orders = '''CREATE TABLE `orders` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `total` decimal(12,2) NOT NULL DEFAULT '0.00',
  PRIMARY KEY (`id`),
  KEY `fk_orders_user` (`user_id`),
  CONSTRAINT `fk_orders_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4''';

/// ฐานข้อมูลปลอม: ตอบ SHOW FULL TABLES / SHOW CREATE TABLE และจดทุกคำสั่งที่ได้รับ
class _FakeSession implements DbSession {
  final seen = <String>[];
  bool closed = false;

  @override
  Future<List<Map<String, String?>>> query(String sql) async {
    seen.add(sql);
    if (sql.startsWith('SHOW FULL TABLES')) {
      return [
        {'Tables_in_shop': 'orders', 'Table_type': 'BASE TABLE'},
        {'Tables_in_shop': 'users', 'Table_type': 'BASE TABLE'},
      ];
    }
    if (sql.startsWith('SHOW CREATE TABLE `users`')) return [{'Table': 'users', 'Create Table': _users}];
    if (sql.startsWith('SHOW CREATE TABLE `orders`')) return [{'Table': 'orders', 'Create Table': _orders}];
    return [];
  }

  @override
  Future<void> close() async => closed = true;
}

class _FakeConnector implements DbConnector {
  _FakeConnector({this.error});
  final DbException? error;
  final configs = <DbConfig>[];
  final sessions = <_FakeSession>[];

  @override
  Future<DbSession> connect(DbConfig config) async {
    configs.add(config);
    if (error != null) throw error!;
    final s = _FakeSession();
    sessions.add(s);
    return s;
  }
}

void main() {
  group('ReadOnlySession: อ่านอย่างเดียวเท่านั้น', () {
    test('อนุญาต SELECT/SHOW/DESCRIBE/EXPLAIN คำสั่งเดียว', () {
      for (final ok in [
        'SELECT 1',
        '  select * from `t` where a = \'x;y\'',
        'SHOW FULL TABLES',
        'SHOW CREATE TABLE `a`',
        'DESCRIBE users',
        'EXPLAIN SELECT 1',
      ]) {
        expect(ReadOnlySession.isSafe(ok), true, reason: ok);
      }
    });

    test('ปฏิเสธทุกคำสั่งเขียน/หลายคำสั่ง/ซ่อนคำสั่ง', () {
      for (final bad in [
        'DROP TABLE users',
        'DELETE FROM users',
        'INSERT INTO t VALUES (1)',
        'UPDATE t SET a = 1',
        'ALTER TABLE t ADD c INT',
        'CREATE TABLE x (a INT)',
        'TRUNCATE t',
        'SET SESSION TRANSACTION READ WRITE',
        'GRANT ALL ON *.* TO a',
        'SELECT 1; DROP TABLE users',
        'SELECT 1;',
        'SELECT 1 -- ; DROP',
        'SELECT 1 /* x */',
        'SELECT 1 # x',
        "SELECT * INTO OUTFILE '/tmp/x' FROM t",
        "SELECT 1 INTO DUMPFILE '/tmp/x'",
        '',
        '   ',
        'selectx',
      ]) {
        expect(ReadOnlySession.isSafe(bad), false, reason: bad);
      }
    });

    test('query ที่ไม่ปลอดภัยไม่ถูกส่งต่อไปยังฐานข้อมูลเลย', () async {
      final inner = _FakeSession();
      final s = ReadOnlySession(inner);
      await expectLater(s.query('DROP TABLE users'), throwsA(isA<DbException>()));
      expect(inner.seen, isEmpty);
      await s.query('SHOW FULL TABLES');
      expect(inner.seen, hasLength(1));
    });
  });

  group('readMysqlSchema', () {
    test('อ่านรายชื่อตาราง + SHOW CREATE TABLE แล้วนำเข้าเป็นโปรเจกต์ครบ (คอลัมน์/คีย์/FK)', () async {
      final fake = _FakeSession();
      final r = await readMysqlSchema(fake, database: 'shop');
      expect(r.tableCount, 2);
      final p = r.import.project;
      expect(p.name, 'shop');
      expect(p.dialect, Dialect.mysql);
      expect(p.tables.map((t) => t.name).toSet(), {'users', 'orders'});
      final users = p.tables.firstWhere((t) => t.name == 'users');
      expect(users.columns.map((c) => c.name), ['id', 'email', 'name']);
      expect(users.columns.first.isPrimaryKey, true);
      expect(users.columns.first.autoIncrement, true);
      expect(users.columns[1].unique, true);
      expect(p.relations, hasLength(1));
      expect(p.relations.single.onDelete, RefAction.cascade);
    });

    test('ส่งเฉพาะคำสั่งอ่านอย่างเดียว และไม่เอา VIEW', () async {
      final fake = _FakeSession();
      await readMysqlSchema(fake, database: 'shop');
      expect(fake.seen.every(ReadOnlySession.isSafe), true);
      expect(fake.seen.first, contains("Table_type = 'BASE TABLE'"));
    });

    test('ชื่อตารางที่มี backtick ถูก escape; รายงานความคืบหน้า', () async {
      expect(quoteMysqlIdent('we`ird'), '`we``ird`');
      final progress = <(int, int)>[];
      await readMysqlSchema(_FakeSession(), database: 'shop', onProgress: (d, t) => progress.add((d, t)));
      expect(progress, [(1, 2), (2, 2)]);
    });

    test('ตารางที่อ่านโครงสร้างไม่ได้ = ข้อผิดพลาดที่อ่านเข้าใจ', () async {
      final s = _FakeSession();
      final bad = _BadSession(s);
      await expectLater(readMysqlSchema(bad, database: 'shop'), throwsA(isA<DbException>()));
    });
  });

  group('DbConfig', () {
    test('label และ toString ไม่มีรหัสผ่าน', () {
      const c = DbConfig(host: 'h', port: 3307, user: 'u', password: 'secret!', database: 'd');
      expect(c.label, 'u@h:3307/d');
      expect(c.toString(), isNot(contains('secret')));
    });
  });

  group('กล่องเชื่อมต่อ', () {
    late ProjectController c;
    late _FakeConnector fake;

    Future<void> boot(WidgetTester tester, {_FakeConnector? connector, Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      fake = connector ?? _FakeConnector();
      DbConnectDialog.connector = fake;
      DbConnectDialog.last = const DbConfig();
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: lang)));
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
      await tester.pump();
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('ไฟล์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เชื่อมต่อฐานข้อมูล…'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, {String pass = 'pw123'}) async {
      await tester.enterText(find.byKey(const ValueKey('db-host')), 'db.local');
      await tester.enterText(find.byKey(const ValueKey('db-user')), 'app');
      await tester.enterText(find.byKey(const ValueKey('db-pass')), pass);
      await tester.enterText(find.byKey(const ValueKey('db-name')), 'shop');
    }

    testWidgets('เมนูไฟล์เปิดกล่อง; รหัสผ่านถูกซ่อน; กรอกไม่ครบ = แจ้งและไม่เชื่อมต่อ', (tester) async {
      await boot(tester);
      await open(tester);
      expect(find.text('เชื่อมต่อฐานข้อมูล'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('db-pass'))).obscureText, true);
      await tester.tap(find.byKey(const ValueKey('db-test')));
      await tester.pump();
      expect(find.text('กรอกชื่อฐานข้อมูล'), findsOneWidget);
      expect(fake.configs, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('db-port')), '99999');
      await tester.tap(find.byKey(const ValueKey('db-test')));
      await tester.pump();
      expect(find.textContaining('พอร์ต (1-65535)'), findsOneWidget);
      expect(fake.configs, isEmpty);
    });

    testWidgets('ทดสอบการเชื่อมต่อ: ส่งค่าที่กรอก ปิด session แล้ว และกล่องยังอยู่', (tester) async {
      await boot(tester);
      await open(tester);
      await fill(tester);
      await tester.tap(find.byKey(const ValueKey('db-test')));
      await tester.pumpAndSettle();
      expect(find.text('เชื่อมต่อสำเร็จ'), findsOneWidget);
      final cfg = fake.configs.single;
      expect((cfg.host, cfg.port, cfg.user, cfg.password, cfg.database, cfg.secure), ('db.local', 3306, 'app', 'pw123', 'shop', false));
      expect(fake.sessions.single.closed, true);
      expect(find.byKey(const ValueKey('db-import')), findsOneWidget);
    });

    testWidgets('เชื่อมต่อไม่ได้: แสดงข้อผิดพลาดในกล่อง ไม่ปิดกล่อง ไม่แสดงรหัสผ่าน', (tester) async {
      await boot(tester, connector: _FakeConnector(error: DbException('เซิร์ฟเวอร์ปฏิเสธ: Access denied')));
      await open(tester);
      await fill(tester, pass: 'topsecret');
      await tester.tap(find.byKey(const ValueKey('db-import')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('db-error')), findsOneWidget);
      expect(find.textContaining('Access denied'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('db-error')), matching: find.textContaining('topsecret')), findsNothing);
      expect(c.project.tables, isEmpty);
    });

    testWidgets('นำเข้าเป็นแผนภาพ: พรีวิว > นำเข้า = โปรเจกต์ใหม่จากฐานข้อมูล ยังไม่บันทึก; จำค่าเดิมแต่ไม่จำรหัสผ่าน', (tester) async {
      await boot(tester);
      await open(tester);
      await fill(tester);
      await tester.tap(find.byKey(const ValueKey('db-import')));
      await tester.pumpAndSettle();
      expect(find.textContaining('พบ 2 ตาราง'), findsOneWidget);
      await tester.tap(find.text('นำเข้า'));
      await tester.pumpAndSettle();
      expect(c.project.tables.map((t) => t.name).toSet(), {'users', 'orders'});
      expect(c.project.relations, hasLength(1));
      expect(c.dirty, true);
      expect(c.filePath, isNull);
      expect(DbConnectDialog.last.host, 'db.local');
      expect(DbConnectDialog.last.password, '');
      expect(fake.sessions.single.closed, true);
    });

    testWidgets('เปรียบเทียบ: ปุ่มใช้ได้เมื่อโปรเจกต์เป็น MySQL แล้วเปิดหน้า migration; dialect อื่นปุ่มถูกปิด', (tester) async {
      await boot(tester);
      c.loadProject(base(), null); // base() = MySQL
      await open(tester);
      await fill(tester);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('db-compare'))).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('db-compare')));
      await tester.pumpAndSettle();
      expect(find.textContaining('shop'), findsWidgets); // oldLabel = ชื่อการเชื่อมต่อ
      expect(find.text('เชื่อมต่อฐานข้อมูล'), findsNothing);
    });

    testWidgets('โปรเจกต์ไม่ใช่ MySQL: ปุ่มเปรียบเทียบปิดอยู่พร้อมคำอธิบาย', (tester) async {
      await boot(tester);
      c.setDialect(Dialect.postgres);
      await tester.pump();
      await open(tester);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('db-compare'))).onPressed, isNull);
      expect(find.textContaining('dialect ของโปรเจกต์เป็น MySQL'), findsOneWidget);
    });

    testWidgets('โหมด SQLite: ซ่อนช่องเซิร์ฟเวอร์ ใช้ไฟล์จริง นำเข้าได้ ; ไฟล์ไม่มี = แจ้งข้อผิดพลาด ; เปรียบเทียบปิด (โปรเจกต์เป็น MySQL)', (tester) async {
      await boot(tester);
      DbConnectDialog.lastKind = DbKind.mysql;
      DbConnectDialog.lastSqlitePath = '';
      final dir = Directory.systemTemp.createTempSync('nsl_dlg');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = '${dir.path}/shop.db';
      final db = sqlite3.open(file)..execute('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)');
      db.close();

      await open(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('db-kind')), matching: find.text('SQLite')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('db-host')), findsNothing);
      expect(find.byKey(const ValueKey('db-pass')), findsNothing);
      expect(find.byKey(const ValueKey('db-file')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('db-compare'))).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('db-import')));
      await tester.pump();
      expect(find.text('กรอกที่อยู่ไฟล์ SQLite'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('db-file')), '${dir.path}/missing.db');
      await tester.tap(find.byKey(const ValueKey('db-import')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('db-error')), findsOneWidget);
      expect(fake.configs, isEmpty); // ไม่ได้แตะตัวเชื่อมต่อ MySQL

      await tester.enterText(find.byKey(const ValueKey('db-file')), file);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('db-import')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.byType(ImportPreviewDialog), findsOneWidget);
      expect(DbConnectDialog.lastKind, DbKind.sqlite);
      expect(DbConnectDialog.lastSqlitePath, file);
      DbConnectDialog.lastKind = DbKind.mysql;
    });

    testWidgets('เปิดดู/แก้ข้อมูล : ไฟล์ SQLite จริง > เปิดหน้าข้อมูล เห็นตารางและแถว ; เชื่อมไม่ได้ = อยู่ในกล่องเดิมพร้อมข้อผิดพลาด', (tester) async {
      await boot(tester);
      DbConnectDialog.lastKind = DbKind.mysql;
      final dir = Directory.systemTemp.createTempSync('nsl_dlg2');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = '${dir.path}/shop.db';
      final db = sqlite3.open(file)..execute("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT); INSERT INTO people (name) VALUES ('Zed')");
      db.close();

      await open(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('db-kind')), matching: find.text('SQLite')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('db-file')), '${dir.path}/none.db');
      await tester.tap(find.byKey(const ValueKey('db-browse-data')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('db-error')), findsOneWidget);
      expect(find.byType(DataBrowserDialog), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('db-file')), file);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('db-browse-data')));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(find.byType(DataBrowserDialog), findsOneWidget);
      expect(find.text('Zed'), findsOneWidget);
      DbConnectDialog.lastKind = DbKind.mysql;
    });

    testWidgets('คีย์ลัด Ctrl+Shift+O และภาษาอังกฤษ', (tester) async {
      await boot(tester, lang: Lang.en);
      expect(shortcutText(Cmd.connectDb), 'Ctrl+Shift+O');
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect to database…'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to database'), findsOneWidget);
      expect(find.text('Test connection'), findsOneWidget);
      expect(find.textContaining('Reads the structure only'), findsOneWidget);
      currentLang = Lang.th;
    });
  });
}

class _BadSession implements DbSession {
  _BadSession(this._inner);
  final _FakeSession _inner;
  @override
  Future<List<Map<String, String?>>> query(String sql) async {
    if (sql.startsWith('SHOW CREATE TABLE')) return [];
    return _inner.query(sql);
  }

  @override
  Future<void> close() async {}
}
