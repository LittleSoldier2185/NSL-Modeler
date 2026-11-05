import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/db/secret_codec.dart';

void main() {
  test('NoSecretCodec : ไม่เก็บอะไรเลย', () {
    const c = NoSecretCodec();
    expect(c.available, false);
    expect(c.encrypt('pw'), isNull);
    expect(c.decrypt('x'), isNull);
  });

  group('Windows DPAPI จริง', () {
    final codec = WindowsDpapiCodec.forPlatform();

    test('เข้ารหัส-ถอดรหัสกลับได้ (รวมภาษาไทย/อักขระพิเศษ/ว่าง) และข้อความเข้ารหัสไม่มีรหัสเดิม', () {
      for (final pw in ['p@ss w0rd!', 'รหัสผ่านไทย ๑๒๓', '', 'a' * 5000, r"quote'" '"' r'back\slash']) {
        final enc = codec.encrypt(pw)!;
        expect(enc.startsWith('dpapi:'), true);
        if (pw.length > 3) expect(enc, isNot(contains(pw)));
        expect(codec.decrypt(enc), pw);
      }
    });

    test('เข้ารหัสสองครั้งได้ข้อความต่างกัน (มี salt) แต่ถอดได้เหมือนกัน', () {
      final a = codec.encrypt('same')!, b = codec.encrypt('same')!;
      expect(a, isNot(b));
      expect(codec.decrypt(a), codec.decrypt(b));
    });

    test('ข้อมูลเสีย/ถูกแก้/ไม่ใช่ของเรา = ถอดไม่ได้ (null) ไม่ throw', () {
      final enc = codec.encrypt('secret')!;
      expect(codec.decrypt('plain text'), isNull);
      expect(codec.decrypt('dpapi:!!!notbase64'), isNull);
      expect(codec.decrypt('dpapi:AAAA'), isNull);
      final tampered = '${enc.substring(0, enc.length - 6)}AAAAAA';
      expect(codec.decrypt(tampered), isNull);
    });
  }, skip: Platform.isWindows ? false : 'ต้องรันบน Windows');
}
