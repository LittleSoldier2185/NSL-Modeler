import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/db/db_session.dart';
import 'package:nsl_modeler/core/db/saved_connections.dart';
import 'package:nsl_modeler/core/db/secret_codec.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/ui/db_connect_dialog.dart';

/// ตัวเข้ารหัสปลอมที่ทำงานได้ทุกแพลตฟอร์ม (กลับตัวอักษร) — ของจริง (DPAPI) ทดสอบใน secret_codec_test
class _FakeCodec implements SecretCodec {
  @override
  bool get available => true;
  @override
  String? encrypt(String plain) => 'enc:${plain.split('').reversed.join()}';
  @override
  String? decrypt(String e) => e.startsWith('enc:') ? e.substring(4).split('').reversed.join() : null;
}

class _OkSession implements DbSession {
  @override
  Future<List<Map<String, String?>>> query(String sql) async => sql.startsWith('SHOW FULL')
      ? [
          {'Tables_in_shop': 't', 'Table_type': 'BASE TABLE'}
        ]
      : [
          {'Table': 't', 'Create Table': 'CREATE TABLE `t` (`id` int NOT NULL, PRIMARY KEY (`id`))'}
        ];
  @override
  Future<void> close() async {}
}

class _OkConnector implements DbConnector {
  @override
  Future<DbSession> connect(DbConfig config) async => _OkSession();
}

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nsl_saved');
    file = File('${dir.path}/connections.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('SavedConnectionStore', () {
    const shop = SavedConnection(name: 'ร้านค้า', host: 'db.local', port: 3307, user: 'app', database: 'shop', secure: true);

    test('บันทึก-โหลดกลับ ; รหัสผ่านไม่อยู่ในไฟล์เป็นข้อความเปล่า แต่ถอดกลับได้', () {
      final s = SavedConnectionStore(file, _FakeCodec());
      expect(s.upsert(shop, password: 'S3cret!pw'), true);
      final text = file.readAsStringSync();
      expect(text, isNot(contains('S3cret!pw')));
      expect(text, contains('"pw":"enc:')); // เก็บเฉพาะผลจากตัวเข้ารหัส (ความแข็งแรงจริงดู secret_codec_test)
      final back = s.load().single;
      expect((back.name, back.host, back.port, back.user, back.database, back.secure), ('ร้านค้า', 'db.local', 3307, 'app', 'shop', true));
      expect(s.passwordOf(back), 'S3cret!pw');
    });

    test('ไม่ส่งรหัสผ่าน / เข้ารหัสไม่ได้ = ไม่เก็บรหัสผ่านเลย (ไม่ถอยไปเก็บข้อความเปล่า)', () {
      final a = SavedConnectionStore(file, _FakeCodec());
      expect(a.upsert(shop), false);
      expect(a.passwordOf(a.load().single), isNull);

      final b = SavedConnectionStore(file, const NoSecretCodec());
      expect(b.canRememberPassword, false);
      expect(b.upsert(shop, password: 'plain-pw'), false);
      expect(file.readAsStringSync(), isNot(contains('plain-pw')));
      expect(b.passwordOf(b.load().single), isNull);
    });

    test('ชื่อซ้ำ (ไม่สนตัวพิมพ์) = แทนที่ ; เรียงตามชื่อ ; ลบได้ ; บันทึกซ้ำโดยไม่ติ๊กจำ = ล้างรหัสผ่านเดิม', () {
      final s = SavedConnectionStore(file, _FakeCodec());
      s.upsert(const SavedConnection(name: 'b', database: 'x'), password: 'pw');
      s.upsert(const SavedConnection(name: 'A', database: 'y'));
      s.upsert(const SavedConnection(name: 'B', database: 'z')); // แทน b และไม่มีรหัสผ่าน
      final l = s.load();
      expect(l.map((e) => e.name), ['A', 'B']);
      expect(l.last.database, 'z');
      expect(s.passwordOf(l.last), isNull);
      s.remove('a');
      expect(s.load().map((e) => e.name), ['B']);
    });

    test('ไฟล์ไม่มี / เสีย / รายการผิดรูป = รายการว่างหรือข้ามรายการเสีย ไม่ทำให้ล้ม', () {
      final s = SavedConnectionStore(file, _FakeCodec());
      expect(s.load(), isEmpty);
      file.writeAsStringSync('{not json');
      expect(s.load(), isEmpty);
      file.writeAsStringSync('{"connections": [5, {"name": ""}, {"nope": 1}, {"name": "ok", "port": 99999, "kind": "zzz"}]}');
      final l = s.load();
      expect(l.single.name, 'ok');
      expect(l.single.port, 3306); // พอร์ตผิดช่วง -> ค่าเริ่มต้น
      expect(l.single.kind, DbKind.mysql);
    });

    test('SQLite เก็บเฉพาะที่อยู่ไฟล์ (ไม่มีข้อมูลเซิร์ฟเวอร์/รหัสผ่าน)', () {
      final s = SavedConnectionStore(file, _FakeCodec());
      s.upsert(const SavedConnection(name: 'local', kind: DbKind.sqlite, database: r'C:\data\shop.db'), password: 'ignored');
      final text = file.readAsStringSync();
      expect(text, isNot(contains('host')));
      expect(text, contains('shop.db'));
      expect(s.load().single.kind, DbKind.sqlite);
    });

    test('ไม่ทิ้งไฟล์ .tmp', () {
      SavedConnectionStore(file, _FakeCodec()).upsert(shop);
      expect(File('${file.path}.tmp').existsSync(), false);
    });
  });

  group('กล่องเชื่อมต่อ + รายการที่บันทึก', () {
    Future<void> openDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      currentLang = Lang.th;
      await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: Lang.th)));
      await tester.pump();
      await tester.tap(find.text('ไฟล์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เชื่อมต่อฐานข้อมูล…'));
      await tester.pumpAndSettle();
    }

    setUp(() {
      DbConnectDialog.connector = _OkConnector();
      DbConnectDialog.last = const DbConfig();
      DbConnectDialog.lastKind = DbKind.mysql;
    });
    tearDown(() => DbConnectDialog.store = null);

    testWidgets('ไม่มีที่เก็บ = ไม่แสดงตัวเลือกบันทึก', (tester) async {
      DbConnectDialog.store = null;
      await openDialog(tester);
      expect(find.byKey(const ValueKey('db-save')), findsNothing);
      expect(find.byKey(const ValueKey('db-saved')), findsNothing);
    });

    testWidgets('ติ๊กบันทึก+จำรหัสผ่าน แล้วเชื่อมสำเร็จ = เก็บรายการ (รหัสผ่านเข้ารหัส) ; เปิดใหม่เลือกรายการแล้วกรอกให้ครบ ; ลบได้', (tester) async {
      final store = DbConnectDialog.store = SavedConnectionStore(file, _FakeCodec());
      await openDialog(tester);
      await tester.enterText(find.byKey(const ValueKey('db-host')), 'db.local');
      await tester.enterText(find.byKey(const ValueKey('db-user')), 'app');
      await tester.enterText(find.byKey(const ValueKey('db-pass')), 'topsecret');
      await tester.enterText(find.byKey(const ValueKey('db-name')), 'shop');
      // ยังไม่ติ๊ก = ไม่แสดงช่องชื่อ/จำรหัสผ่าน
      expect(find.byKey(const ValueKey('db-remember')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('db-save')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('db-save-name')), 'ร้านค้า');
      await tester.tap(find.byKey(const ValueKey('db-remember')));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('db-import')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(file.readAsStringSync(), isNot(contains('topsecret')));
      final saved = store.load().single;
      expect((saved.name, saved.host, saved.user, saved.database), ('ร้านค้า', 'db.local', 'app', 'shop'));
      expect(store.passwordOf(saved), 'topsecret');
    });

    testWidgets('ไม่ติ๊กจำรหัสผ่าน = รายการถูกเก็บแต่ไม่มีรหัสผ่าน ; เลือกรายการแล้วช่องรหัสผ่านว่าง', (tester) async {
      final store = DbConnectDialog.store = SavedConnectionStore(file, _FakeCodec());
      store.upsert(const SavedConnection(name: 'dev', host: 'h1', port: 3310, user: 'u1', database: 'd1'));
      await openDialog(tester);
      expect(find.byKey(const ValueKey('db-saved')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('db-saved')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('dev').last);
      await tester.pumpAndSettle();
      String t(String k) => tester.widget<TextField>(find.byKey(ValueKey(k))).controller!.text;
      expect((t('db-host'), t('db-port'), t('db-user'), t('db-name'), t('db-pass')), ('h1', '3310', 'u1', 'd1', ''));

      // ลบรายการ
      await tester.tap(find.byKey(const ValueKey('db-saved-delete')));
      await tester.pumpAndSettle();
      expect(store.load(), isEmpty);
      expect(find.byKey(const ValueKey('db-saved')), findsNothing);
    });

    testWidgets('รายการที่จำรหัสผ่านไว้ = เลือกแล้วช่องรหัสผ่านถูกเติมและติ๊กจำให้', (tester) async {
      final store = DbConnectDialog.store = SavedConnectionStore(file, _FakeCodec());
      store.upsert(const SavedConnection(name: 'prod', host: 'h', user: 'u', database: 'd'), password: 'pw-9');
      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('db-saved')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('prod').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('db-pass'))).controller!.text, 'pw-9');
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('db-remember'))).value, true);
    });

    testWidgets('เครื่องที่เข้ารหัสไม่ได้ = ไม่เสนอ "จำรหัสผ่าน"', (tester) async {
      DbConnectDialog.store = SavedConnectionStore(file, const NoSecretCodec());
      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('db-save')));
      await tester.pump();
      expect(find.byKey(const ValueKey('db-save-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('db-remember')), findsNothing);
    });
  });
}
