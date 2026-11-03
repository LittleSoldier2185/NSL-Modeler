import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/ddl/ddl_generator.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/parser/sql_importer.dart';
import 'package:nsl_modeler/core/validate/validator.dart';

/// ไฟล์ตัวอย่างใน samples/ ต้อง import ได้ครบและ export กลับเป็น SQL ของทุก dialect ได้
void main() {
  final cases = <({String file, Dialect dialect, int tables, int relations})>[
    (file: 'shop_mysql.sql', dialect: Dialect.mysql, tables: 7, relations: 8),
    (file: 'blog_postgres.sql', dialect: Dialect.postgres, tables: 5, relations: 6),
    (file: 'school_sqlite.sql', dialect: Dialect.sqlite, tables: 4, relations: 3),
  ];

  for (final c in cases) {
    group(c.file, () {
      late String sql;
      late ImportResult r;

      setUpAll(() {
        sql = File('samples/${c.file}').readAsStringSync();
        r = importSql(sql, name: 'sample');
      });

      test('ตรวจ dialect ถูก', () => expect(r.detected, c.dialect));

      test('อ่านครบ ${c.tables} ตาราง ${c.relations} ความสัมพันธ์ และเตือนเฉพาะคำสั่ง SET/PRAGMA ที่ถูกข้าม', () {
        expect(r.project.tables.length, c.tables);
        expect(r.project.relations.length, c.relations);
        // SET NAMES / PRAGMA ไม่ใช่โครงสร้างตาราง จึงถูกข้ามพร้อมแจ้งเตือน (ใช้ดูแผง "สิ่งที่ควรตรวจ")
        final other = r.notes.where((n) => !RegExp(r'SET|PRAGMA').hasMatch(n.message));
        expect(other, isEmpty, reason: other.map((n) => n.message).join('\n'));
        expect(r.notes.length, c.file == 'blog_postgres.sql' ? 0 : 1);
      });

      test('ทุกตารางมี PK และตัวตรวจ schema ไม่พบ error', () {
        for (final t in r.project.tables) {
          expect(t.columns.any((x) => x.isPrimaryKey), true, reason: t.name);
        }
        final errors = validateProject(r.project).where((i) => i.severity.name == 'error');
        expect(errors, isEmpty, reason: errors.map((i) => '${i.title}: ${i.message}').join('\n'));
      });

      test('export ได้ทั้ง 4 dialect และ import กลับได้จำนวนเท่าเดิม', () {
        for (final d in Dialect.values) {
          final out = DdlGenerator.forDialect(d).generate(r.project..dialect = d);
          final back = importSql(out, name: 'back', dialect: d);
          expect(back.project.tables.length, c.tables, reason: '$d');
          expect(back.project.relations.length, c.relations, reason: '$d');
        }
      });
    });
  }

  test('shop_mysql.sql: รายละเอียดสำคัญถูกอ่านครบ', () {
    final p = importSql(File('samples/shop_mysql.sql').readAsStringSync()).project;
    final cat = p.tables.firstWhere((t) => t.name == 'categories');
    expect(p.relations.any((r) => r.fromTableId == cat.id && r.toTableId == cat.id), true); // self-reference
    final items = p.tables.firstWhere((t) => t.name == 'order_items');
    expect(items.columns.where((x) => x.isPrimaryKey).length, 2); // PK ผสม
    final users = p.tables.firstWhere((t) => t.name == 'users');
    expect(users.comment, 'ผู้ใช้งานระบบ');
    expect(users.columns.firstWhere((x) => x.name == 'email').unique, true);
    final addr = p.tables.firstWhere((t) => t.name == 'addresses');
    expect(p.relations.any((r) => r.fromTableId == addr.id), true); // FK จาก ALTER TABLE
  });
}
