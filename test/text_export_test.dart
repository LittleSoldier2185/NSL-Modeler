import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/ddl/ddl_generator.dart';
import 'package:nsl_modeler/core/export/diagram_text_export.dart';
import 'package:nsl_modeler/core/export/markdown_export.dart';
import 'package:nsl_modeler/core/export/sample_data.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/index_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:sqlite3/sqlite3.dart';

import 'migration_fixtures.dart';

/// โปรเจกต์ที่ครอบคลุมชนิดข้อมูลและรูปแบบ FK หลายแบบ
Project wide([Dialect d = Dialect.mysql]) => Project(name: 'ร้านค้า', dialect: d, tables: [
      TableModel(id: 'tu', name: 'users', comment: "ผู้ใช้ | ระบบ's", columns: [
        col('u1', 'id', pk: true, ai: true),
        col('u2', 'email', type: DataType.varchar, len: 255, nn: true, uq: true),
        col('u3', 'full_name', type: DataType.varchar, len: 30),
        col('u4', 'age', nn: false),
        col('u5', 'active', type: DataType.boolean, nn: true),
        col('u6', 'joined', type: DataType.date),
        col('u7', 'bio', type: DataType.text, comment: 'ประวัติ\nหลายบรรทัด | มีท่อ'),
      ]),
      TableModel(id: 'tp', name: 'products', columns: [
        col('p1', 'id', type: DataType.uuid, pk: true),
        col('p2', 'sku', type: DataType.varchar, len: 12, uq: true, nn: true),
        col('p3', 'price', type: DataType.decimal, len: 8, scale: 2, nn: true, def: '0'),
        col('p4', 'weight', type: DataType.float),
        col('p5', 'thumb', type: DataType.blob, nn: true),
        col('p6', 'meta', type: DataType.json),
        col('p7', 'created', type: DataType.datetime, nn: true, def: 'CURRENT_TIMESTAMP'),
      ], indexes: [
        IndexModel(id: 'ip', name: 'idx_products_price', columnIds: ['p3']),
      ]),
      TableModel(id: 'to', name: 'orders', columns: [
        col('o1', 'id', type: DataType.bigint, pk: true, ai: true),
        col('o2', 'user_id', nn: true),
        col('o3', 'status', type: DataType.varchar, len: 20, nn: true),
        col('o4', 'coupon_id'),
      ]),
      // ตารางเชื่อม: PK หลายคอลัมน์ที่เป็น FK ทั้งคู่
      TableModel(id: 'ti', name: 'order_items', columns: [
        col('i1', 'order_id', type: DataType.bigint, pk: true),
        col('i2', 'product_id', type: DataType.uuid, pk: true),
        col('i3', 'qty', nn: true),
      ]),
      // 1:1 (FK เป็น PK)
      TableModel(id: 'tf', name: 'profiles', columns: [
        col('f1', 'user_id', pk: true),
        col('f2', 'nickname', type: DataType.varchar, len: 20),
      ]),
    ], relations: [
      RelationModel(id: 'r1', fromTableId: 'to', fromColumnId: 'o2', toTableId: 'tu', toColumnId: 'u1', onDelete: RefAction.cascade, onUpdate: RefAction.restrict),
      RelationModel(id: 'r2', fromTableId: 'ti', fromColumnId: 'i1', toTableId: 'to', toColumnId: 'o1', onDelete: RefAction.cascade),
      RelationModel(id: 'r3', fromTableId: 'ti', fromColumnId: 'i2', toTableId: 'tp', toColumnId: 'p1'),
      RelationModel(id: 'r4', fromTableId: 'tf', fromColumnId: 'f1', toTableId: 'tu', toColumnId: 'u1', onDelete: RefAction.setNull),
    ]);

void main() {
  group('Data dictionary (Markdown)', () {
    test('โปรเจกต์ว่าง', () {
      final s = exportDataDictionary(Project(name: 'x'));
      expect(s, contains('# x — Data Dictionary'));
      expect(s, contains('_ยังไม่มีตาราง_'));
    });

    test('โครงสร้าง: สารบัญ, ตารางต่อคอลัมน์, FK ขาออก/ขาเข้า, INDEX', () {
      final s = exportDataDictionary(wide());
      expect(s, contains('# ร้านค้า — Data Dictionary'));
      expect(s, contains('- 5 ตาราง · 4 ความสัมพันธ์'));
      expect(s, contains('- [users](#users) — ผู้ใช้ | ระบบ\'s'));
      expect(s, contains('## orders'));
      expect(s, contains('| 2 | user_id | INT | FK |  |'));
      expect(s, contains('| 1 | id | INT | PK AI |  |'));
      expect(s, contains('| 2 | email | VARCHAR(255) | UQ |  |'));
      expect(s, contains('**อ้างถึง (FK)**'));
      expect(s, contains('- orders.user_id → users.id (ON DELETE CASCADE, ON UPDATE RESTRICT)'));
      expect(s, contains('**ถูกอ้างถึงโดย**'));
      expect(s, contains('- order_items.order_id'));
      expect(s, contains('- `idx_products_price` (price)'));
    });

    test('escape | และขึ้นบรรทัดใหม่ในช่องตาราง ไม่ทำให้ตารางพัง', () {
      final s = exportDataDictionary(wide());
      expect(s, contains('ประวัติ<br>หลายบรรทัด \\| มีท่อ'));
      // ทุกแถวของตาราง users มีจำนวนช่อง (|) เท่าหัวตาราง
      final rows = s.split('\n').where((l) => RegExp(r'^\| \d+ \|').hasMatch(l)).toList();
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect(RegExp(r'(?<!\\)\|').allMatches(r).length, 8, reason: r);
      }
    });

    test('Null และ default', () {
      final s = exportDataDictionary(wide());
      expect(s, contains('| 4 | age | INT |  | ✓ |')); // อนุญาต NULL
      expect(s, contains('| 5 | active | BOOLEAN |  |  |')); // NOT NULL
      expect(s, contains('| 3 | price | DECIMAL(8,2) |  |  | 0 |'));
    });

    test('ผลลัพธ์คงที่', () {
      expect(exportDataDictionary(wide()), exportDataDictionary(wide()));
    });
  });

  group('Mermaid', () {
    test('ชนิดและ key', () {
      final s = exportMermaid(wide());
      expect(s, contains('        int id PK'));
      expect(s, contains('        varchar email UK'));
      expect(s, contains('        int user_id FK'));
      expect(s, contains('        uuid id PK'));
      expect(s, isNot(contains('varchar(255)')));
    });

    test('cardinality: หลาย:1 (NOT NULL) / หลาย:0..1 (nullable) / 1:1', () {
      final p = wide();
      cl(p, 'to', 'o2').notNull = true;
      cl(p, 'to', 'o4').notNull = false;
      p.relations.add(RelationModel(id: 'r5', fromTableId: 'to', fromColumnId: 'o4', toTableId: 'tu', toColumnId: 'u1'));
      final s = exportMermaid(p);
      expect(s, contains('orders }o--|| users : "user_id"')); // NOT NULL -> แม่ 1 แถวเสมอ
      expect(s, contains('orders }o--o| users : "coupon_id"')); // nullable -> แม่ 0..1
      expect(s, contains('profiles |o--|| users : "user_id"')); // FK เป็น PK เดี่ยว -> 1:1 และ NOT NULL -> แม่ 1 แถวเสมอ
      expect(s, contains('order_items }o--|| orders : "order_id"')); // PK คู่ ไม่ใช่ 1:1
    });

    test('ชื่อภาษาไทย/ช่องว่าง: แปลงเป็นชื่อที่ใช้ได้ ไม่ซ้ำกัน และเก็บชื่อเดิมไว้ในคำอธิบาย', () {
      final p = Project(tables: [
        TableModel(id: 'a', name: 'ลูกค้า', columns: [col('a1', 'รหัส ลูกค้า', pk: true)]),
        TableModel(id: 'b', name: 'สินค้า', columns: [col('b1', 'id', pk: true)]),
        TableModel(id: 'c', name: '2fast', columns: [col('c1', 'id', pk: true)]),
      ]);
      final s = exportMermaid(p);
      final entities = RegExp(r'^    (\S+) \{$', multiLine: true).allMatches(s).map((m) => m.group(1)).toList();
      expect(entities.toSet().length, 3, reason: s);
      for (final e in entities) {
        expect(RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(e!), true, reason: e);
      }
      expect(s, contains('"รหัส ลูกค้า"'));
    });

    test('ความเห็นคอลัมน์ในเครื่องหมายคำพูด และ " ในข้อความถูกแทนที่', () {
      final p = Project(tables: [
        TableModel(id: 'a', name: 'a', columns: [col('a1', 'id', pk: true, comment: 'บอก "ค่า"\nสอง')]),
      ]);
      expect(exportMermaid(p), contains('int id PK "บอก \'ค่า\' สอง"'));
    });

    test('FK ที่ชี้ผิดถูกข้าม และตารางไม่มีคอลัมน์ไม่ทำให้ไดอะแกรมว่างเปล่า', () {
      final p = wide();
      p.relations.first.toTableId = 'ghost';
      p.tables.add(TableModel(id: 'e', name: 'empty'));
      final s = exportMermaid(p);
      expect(s, isNot(contains('ghost')));
      expect(s, contains('    empty {\n        string _empty\n    }'));
    });
  });

  group('DBML', () {
    test('Table, คุณสมบัติคอลัมน์, Note, indexes', () {
      final s = exportDbml(wide());
      expect(s, contains('Table users {'));
      expect(s, contains('  id int [pk, increment]'));
      expect(s, contains('  email varchar(255) [not null, unique]'));
      expect(s, contains('  active boolean [not null]'));
      expect(s, contains("  Note: 'ผู้ใช้ | ระบบ\\'s'"));
      expect(s, contains("[note: 'ประวัติ\\nหลายบรรทัด | มีท่อ']"));
      expect(s, contains('  price decimal(8,2) [not null, default: 0]'));
      expect(s, contains('  created datetime [not null, default: `CURRENT_TIMESTAMP`]'));
      expect(s, contains("    price [name: 'idx_products_price']"));
    });

    test('PK หลายคอลัมน์เป็น indexes ไม่ใช่ [pk] ต่อคอลัมน์', () {
      final s = exportDbml(wide());
      expect(s, contains('    (order_id, product_id) [pk]'));
      expect(s, isNot(contains('order_id bigint [pk')));
    });

    test('Ref: ทิศทาง ชนิดความสัมพันธ์ และ action', () {
      final s = exportDbml(wide());
      expect(s, contains('Ref: orders.user_id > users.id [delete: cascade, update: restrict]'));
      expect(s, contains('Ref: order_items.product_id > products.id\n'));
      expect(s, contains('Ref: profiles.user_id - users.id [delete: set null]')); // 1:1
    });

    test('ชื่อพิเศษถูกใส่ "..." และ escape', () {
      final p = Project(tables: [
        TableModel(id: 'a', name: 'ลูกค้า "VIP"', columns: [col('a1', 'my col', pk: true)]),
      ]);
      final s = exportDbml(p);
      expect(s, contains('Table "ลูกค้า \\"VIP\\"" {'));
      expect(s, contains('  "my col" int [pk]'));
    });

    test('ค่าเริ่มต้นหลายแบบ', () {
      String d(DataType t, String v) {
        final p = Project(tables: [
          TableModel(id: 'a', name: 'a', columns: [col('a1', 'c', type: t, def: v)]),
        ]);
        return RegExp(r'default: ([^\],]+)').firstMatch(exportDbml(p))!.group(1)!;
      }

      expect(d(DataType.integer, '5'), '5');
      expect(d(DataType.varchar, '5'), "'5'"); // คอลัมน์ข้อความ ต้องเป็นสตริง
      expect(d(DataType.varchar, "it's"), "'it\\'s'");
      expect(d(DataType.boolean, 'TRUE'), 'true');
      expect(d(DataType.uuid, 'uuid()'), '`uuid()`');
      expect(d(DataType.datetime, 'now()'), '`now()`');
    });
  });

  group('ข้อมูลตัวอย่าง', () {
    test('ผลลัพธ์คงที่ตาม seed และต่างกันเมื่อ seed ต่าง', () {
      final p = wide();
      expect(exportSampleData(p, seed: 7), exportSampleData(p, seed: 7));
      expect(exportSampleData(p, seed: 7), isNot(exportSampleData(p, seed: 8)));
    });

    test('ตารางแม่มาก่อนตารางลูก', () {
      final s = exportSampleData(wide());
      int at(String t) => s.indexOf('INSERT INTO `$t`');
      expect(at('users'), lessThan(at('orders')));
      expect(at('orders'), lessThan(at('order_items')));
      expect(at('products'), lessThan(at('order_items')));
      expect(at('users'), lessThan(at('profiles')));
    });

    test('คอลัมน์ AUTO INCREMENT ไม่ถูกใส่ใน INSERT', () {
      final s = exportSampleData(wide());
      expect(s, contains('INSERT INTO `users` (`email`,'));
      expect(s, isNot(contains('INSERT INTO `users` (`id`')));
    });

    test('จำนวนแถวตามที่ขอ (จำกัด 1–1000)', () {
      int count(String s, String t) {
        final block = RegExp('INSERT INTO `$t`[^;]*;').firstMatch(s)!.group(0)!;
        return '\n  ('.allMatches(block).length;
      }

      expect(count(exportSampleData(wide(), rows: 3), 'users'), 3);
      expect(count(exportSampleData(wide(), rows: 0), 'users'), 1);
      expect(count(exportSampleData(wide(), rows: 5000), 'users'), 1000);
    });

    test('รูปแบบค่าตาม dialect: boolean, blob, ภาษาไทยใน SQL Server ต้องมี N', () {
      expect(exportSampleData(wide(Dialect.postgres)), contains('TRUE'));
      expect(exportSampleData(wide(Dialect.mysql)), contains("X'00'"));
      expect(exportSampleData(wide(Dialect.postgres)), contains(r"'\x00'"));
      final ms = exportSampleData(wide(Dialect.mssql));
      expect(ms, contains('0x00'));
      expect(ms, matches(RegExp(r"N'[^']*[ก-๙]")));
      expect(exportSampleData(wide(Dialect.mysql)), isNot(contains("N'")));
    });

    test('ชื่อ/อีเมลตามชื่อคอลัมน์ และความยาวไม่เกินที่กำหนด', () {
      final s = exportSampleData(wide(), rows: 12);
      expect(s, contains('user1@example.com'));
      expect(s, contains('user12@example.com'));
      // sku varchar(12) + unique: ถูกตัดแต่ยังไม่ซ้ำ
      final skus = RegExp(r"'(CODE-\d+)'").allMatches(s).map((m) => m.group(1)!).toList();
      expect(skus.toSet().length, skus.length);
      expect(skus.every((x) => x.length <= 12), true);
    });

    test('ทุกตารางที่ทุกคอลัมน์เป็น AUTO INCREMENT ใช้ค่าเริ่มต้นล้วน', () {
      final p = Project(tables: [
        TableModel(id: 't', name: 't', columns: [col('c', 'id', pk: true, ai: true)]),
      ]);
      expect(exportSampleData(p, rows: 2), contains('INSERT INTO `t` () VALUES ();\nINSERT INTO `t` () VALUES ();'));
      p.dialect = Dialect.postgres;
      expect(exportSampleData(p, rows: 1), contains('INSERT INTO "t" DEFAULT VALUES;'));
    });

    test('FK เป็น NOT NULL แต่ตารางแม่ว่าง ก็ยังไม่พัง', () {
      final p = Project(tables: [
        TableModel(id: 'a', name: 'a', columns: [col('a1', 'id', pk: true)]),
        TableModel(id: 'b', name: 'b', columns: [col('b1', 'id', pk: true, ai: true), col('b2', 'a_id', nn: true)]),
      ], relations: [
        RelationModel(id: 'r', fromTableId: 'b', fromColumnId: 'b2', toTableId: 'a', toColumnId: 'a1'),
      ]);
      expect(exportSampleData(p, rows: 2), contains('INSERT INTO `b`'));
    });

    test('FK วนกันไม่ค้าง', () {
      final p = Project(tables: [
        TableModel(id: 'a', name: 'a', columns: [col('a1', 'id', pk: true), col('a2', 'b_id')]),
        TableModel(id: 'b', name: 'b', columns: [col('b1', 'id', pk: true), col('b2', 'a_id')]),
      ], relations: [
        RelationModel(id: 'r1', fromTableId: 'a', fromColumnId: 'a2', toTableId: 'b', toColumnId: 'b1'),
        RelationModel(id: 'r2', fromTableId: 'b', fromColumnId: 'b2', toTableId: 'a', toColumnId: 'a1'),
      ]);
      expect(exportSampleData(p, rows: 3), allOf(contains('INSERT INTO `a`'), contains('INSERT INTO `b`')));
    });

    test('โปรเจกต์ว่าง = มีแต่หัว', () {
      expect(exportSampleData(Project()).trim().split('\n').length, 1);
    });
  });

  group('ข้อมูลตัวอย่างบน SQLite จริง: ไม่ละเมิด FK / UNIQUE / PK', () {
    for (final rows in [1, 5, 25]) {
      test('$rows แถวต่อตาราง', () {
        final p = wide(Dialect.sqlite);
        final db = sqlite3.openInMemory();
        db.execute(DdlGenerator.forDialect(Dialect.sqlite).generate(p));
        db.execute(exportSampleData(p, rows: rows));
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
        expect(db.select('SELECT COUNT(*) AS n FROM users').single['n'], rows);
        expect(db.select('SELECT COUNT(*) AS n FROM orders').single['n'], rows);
        // ตารางเชื่อม PK คู่: ได้สูงสุดเท่าที่ไม่ซ้ำ
        final items = db.select('SELECT COUNT(*) AS n FROM order_items').single['n'] as int;
        expect(items, inInclusiveRange(1, rows));
        // 1:1 (profiles.user_id เป็น PK ที่ FK ไป users) ต้องไม่เกินจำนวน users
        expect(db.select('SELECT COUNT(*) AS n FROM profiles').single['n'] as int, lessThanOrEqualTo(rows));
        // ค่า NOT NULL/UNIQUE ถูกต้อง
        expect(db.select('SELECT COUNT(DISTINCT email) AS n FROM users').single['n'], rows);
        db.close();
      });
    }

    test('seed ต่างกันก็ผ่าน (ไม่ใช่แค่ seed 1 ที่บังเอิญดี)', () {
      for (var seed = 1; seed <= 12; seed++) {
        final p = wide(Dialect.sqlite);
        final db = sqlite3.openInMemory();
        db.execute(DdlGenerator.forDialect(Dialect.sqlite).generate(p));
        db.execute(exportSampleData(p, rows: 15, seed: seed));
        expect(db.select('PRAGMA foreign_key_check'), isEmpty, reason: 'seed $seed');
        db.close();
      }
    });

    test('ค่าจำนวนเงินไม่ล้น precision ที่กำหนด', () {
      final p = wide(Dialect.sqlite);
      final db = sqlite3.openInMemory();
      db.execute(DdlGenerator.forDialect(Dialect.sqlite).generate(p));
      db.execute(exportSampleData(p, rows: 30));
      final max = db.select('SELECT MAX(price) AS m FROM products').single['m'] as num;
      expect(max, lessThan(1000000)); // DECIMAL(8,2) -> ส่วนจำนวนเต็มไม่เกิน 6 หลัก (ตัวสร้างจำกัด ≤ 4 หลัก)
      db.close();
    });
  });

  group('SQL Server: N prefix ใน DDL ด้วย', () {
    test('DEFAULT ภาษาไทยมี N, ภาษาอังกฤษไม่มี', () {
      final p = Project(dialect: Dialect.mssql, tables: [
        TableModel(id: 't', name: 't', columns: [
          col('a', 'a', type: DataType.varchar, len: 20, def: 'ปกติ'),
          col('b', 'b', type: DataType.varchar, len: 20, def: 'normal'),
        ]),
      ]);
      final s = DdlGenerator.forDialect(Dialect.mssql).generate(p);
      expect(s, contains("DEFAULT N'ปกติ'"));
      expect(s, contains("DEFAULT 'normal'"));
    });
  });
}
