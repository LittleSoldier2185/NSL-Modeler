import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/validate/issue.dart';
import 'package:nsl_dev/core/validate/naming.dart';
import 'package:nsl_dev/core/validate/validator.dart';

import 'migration_fixtures.dart';

void main() {
  group('styleOf', () {
    test('จัดประเภทรูปแบบชื่อ', () {
      expect(styleOf('user_id'), NameStyle.snake);
      expect(styleOf('users'), NameStyle.snake);
      expect(styleOf('a1_b2'), NameStyle.snake);
      expect(styleOf('USER_ID'), NameStyle.upperSnake);
      expect(styleOf('userId'), NameStyle.camel);
      expect(styleOf('UserId'), NameStyle.pascal);
      expect(styleOf('Users'), NameStyle.pascal);
      expect(styleOf('user-id'), NameStyle.kebab);
      expect(styleOf('user id'), NameStyle.spaced);
      expect(styleOf('_x'), NameStyle.other);
      expect(styleOf('user__id'), NameStyle.other); // ขีดล่างซ้อน
      expect(styleOf('1abc'), NameStyle.other);
    });
  });

  group('toSnakeCase', () {
    test('แปลงรูปแบบต่าง ๆ', () {
      expect(toSnakeCase('orderItems'), 'order_items');
      expect(toSnakeCase('OrderItems'), 'order_items');
      expect(toSnakeCase('UserID'), 'user_id');
      expect(toSnakeCase('HTTPServer'), 'http_server');
      expect(toSnakeCase('my col'), 'my_col');
      expect(toSnakeCase('user-id'), 'user_id');
      expect(toSnakeCase('USER_ID'), 'user_id');
      expect(toSnakeCase('  Name  '), 'name');
      expect(toSnakeCase('a__b'), 'a_b');
      expect(toSnakeCase('user.id'), 'user_id');
    });

    test('ผลลัพธ์เป็น snake_case เสมอ (ถ้าไม่ว่าง)', () {
      for (final s in ['orderItems', 'OrderItems', 'USER_ID', 'My Col', 'a-b-c', 'HTTPServer2']) {
        expect(styleOf(toSnakeCase(s)), NameStyle.snake, reason: s);
      }
    });
  });

  group('looksPlural', () {
    test('พหูพจน์', () {
      for (final s in ['users', 'orders', 'order_items', 'categories', 'products']) {
        expect(looksPlural(s), true, reason: s);
      }
    });
    test('เอกพจน์ รวมคำที่ลงท้าย s แต่ไม่ใช่พหูพจน์', () {
      for (final s in ['user', 'order', 'status', 'address', 'news', 'series', 'bus', 'analysis', 'access', 'ab']) {
        expect(looksPlural(s), false, reason: s);
      }
    });
  });

  group('กฎใน validator', () {
    List<Issue> naming(Project p) => validateProject(p).where((i) => i.code.startsWith('naming')).toList();

    Project proj(List<String> tables, {List<String> cols = const ['id']}) => Project(tables: [
          for (var i = 0; i < tables.length; i++)
            TableModel(id: 't$i', name: tables[i], columns: [for (var j = 0; j < cols.length; j++) col('c$i$j', cols[j], pk: j == 0)]),
        ]);

    test('snake_case ล้วนไม่มีคำเตือน', () {
      expect(naming(proj(['users', 'order_items', 'products'], cols: ['id', 'user_id', 'created_at'])), isEmpty);
    });

    test('ตาราง/คอลัมน์แบบ camelCase และ Pascal: แนะนำชื่อใหม่ เป็นระดับ info', () {
      final r = naming(proj(['OrderItems'], cols: ['id', 'userId']));
      expect(r.length, 2);
      expect(r.every((i) => i.severity == Severity.info && i.code == 'naming_style'), true);
      expect(r[0].message, contains('แนะนำ "order_items"'));
      expect(r[0].message, contains('PascalCase'));
      expect(r[1].message, contains('แนะนำ "user_id"'));
      expect(r[1].message, contains('camelCase'));
      expect(r[1].columnId, isNotNull);
    });

    test('ชื่อภาษาไทยไม่ถูกตรวจ (แปลงเป็น snake_case ไม่ได้)', () {
      expect(naming(proj(['ลูกค้า'], cols: ['รหัส', 'ชื่อ ลูกค้า'])), isEmpty);
    });

    test('ไม่ซ้ำกับ error อื่น: ชื่อที่ถูกต้องตามรูปแบบแต่เป็น reserved word ได้เฉพาะ warning', () {
      final r = validateProject(proj(['order'], cols: ['id']));
      expect(r.map((i) => i.code), contains('reserved_word'));
      expect(r.map((i) => i.code), isNot(contains('naming_style')));
    });

    test('ตารางเอกพจน์ปนพหูพจน์: เตือนฝั่งน้อย', () {
      final r = naming(proj(['users', 'orders', 'products', 'invoice']));
      expect(r.length, 1);
      expect(r.single.code, 'naming_number');
      expect(r.single.message, contains('invoice'));
      expect(r.single.message, contains('เอกพจน์'));
    });

    test('ตารางส่วนใหญ่เอกพจน์ มีพหูพจน์ตัวเดียว: เตือนตัวนั้น', () {
      final r = naming(proj(['user', 'order', 'product', 'tags']));
      expect(r.single.message, contains('tags'));
      expect(r.single.message, contains('พหูพจน์'));
    });

    test('ครึ่งต่อครึ่ง หรือตารางน้อยกว่า 3 ไม่เตือน', () {
      expect(naming(proj(['users', 'orders', 'invoice', 'receipt'])), isEmpty);
      expect(naming(proj(['users', 'invoice'])), isEmpty);
    });

    test('คำเตือนระดับ info ไม่ถูกนับเป็นป้ายบนแท็บปัญหา และไม่กระทบ error/warning', () {
      final r = validateProject(proj(['OrderItems']));
      expect(r.where((i) => i.severity != Severity.info), isEmpty);
    });

    test('schema ที่สะอาดของชุดทดสอบเดิมยังสะอาดทุก dialect', () {
      for (final d in Dialect.values) {
        expect(validateProject(base(d)), isEmpty, reason: d.label);
      }
    });
  });
}
