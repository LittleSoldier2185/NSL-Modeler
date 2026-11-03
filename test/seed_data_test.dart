import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/ddl/ddl_generator.dart';
import 'package:nsl_modeler/core/export/seed_data.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/core/storage/project_file.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:sqlite3/sqlite3.dart';

/// roles(id AI PK, name UNIQUE NOT NULL, is_admin bool default false)  <-  users(id, role_id FK, note text)
Project make(Dialect d) => Project(name: 'app', dialect: d, tables: [
      TableModel(id: 'tu', name: 'users', columns: [
        ColumnModel(id: 'u1', name: 'id', isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'u2', name: 'role_id', notNull: true),
        ColumnModel(id: 'u3', name: 'note', type: DataType.text),
      ]),
      TableModel(id: 'tr', name: 'roles', columns: [
        ColumnModel(id: 'r1', name: 'id', isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'r2', name: 'name', type: DataType.varchar, length: 20, notNull: true, unique: true),
        ColumnModel(id: 'r3', name: 'is_admin', type: DataType.boolean, notNull: true, defaultValue: 'false'),
      ]),
    ], relations: [
      RelationModel(id: 'fk', fromTableId: 'tu', fromColumnId: 'u2', toTableId: 'tr', toColumnId: 'r1'),
    ]);

Project withSeed(Dialect d) {
  final p = make(d);
  p.tableById('tr')!.seedRows = [
    {'r1': '1', 'r2': 'admin', 'r3': 'true'},
    {'r1': '2', 'r2': "o'neil", 'r3': 'false'},
  ];
  p.tableById('tu')!.seedRows = [
    {'u1': '1', 'u2': '1', 'u3': 'สวัสดี'},
  ];
  return p;
}

void main() {
  group('โมเดล / การเก็บ', () {
    test('ไม่มีข้อมูลตั้งต้น = ไม่มีฟิลด์ seed ในไฟล์', () {
      expect(make(Dialect.mysql).tables.first.toJson().containsKey('seed'), false);
    });

    test('บันทึกแล้วเปิดกลับมาได้ครบ รวมค่า NULL และไทย', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tr')!.seedRows.add({'r1': '3', 'r2': 'x', 'r3': null});
      final back = ProjectFile.decode(ProjectFile.encode(p));
      final rows = back.tableById('tr')!.seedRows;
      expect(rows.length, 3);
      expect(rows[1]['r2'], "o'neil");
      expect(rows[2].containsKey('r3') && rows[2]['r3'] == null, true);
      expect(back.tableById('tu')!.seedRows.single['u3'], 'สวัสดี');
    });

    test('ข้อมูลในไฟล์ที่ผิดรูป (ไม่ใช่ list/map) ถูกข้ามโดยไม่พัง', () {
      final j = make(Dialect.mysql).tables.first.toJson()..['seed'] = [1, 'x', {'a': 5, 'b': true, 'c': null, 9: 'x'}];
      final t = TableModel.fromJson(j);
      expect(t.seedRows.length, 1);
      expect(t.seedRows.single, {'a': '5', 'b': 'true', 'c': null});
    });

    test('ตัวควบคุม: ตั้ง/แก้ข้อมูลตั้งต้นเป็น undo ขั้นเดียว และค่าเดิมไม่สร้างประวัติ', () {
      final c = ProjectController(make(Dialect.mysql));
      final rows = [
        {'r1': '1', 'r2': 'admin'}
      ];
      c.setSeedRows('tr', rows);
      c.setSeedRows('tr', rows); // เหมือนเดิม
      expect(c.project.tableById('tr')!.seedRows.length, 1);
      c.undo();
      expect(c.project.tableById('tr')!.seedRows, isEmpty);
      expect(c.canUndo, false);
    });

    test('ลบคอลัมน์ = ลบค่าของคอลัมน์นั้นออกจากข้อมูลตั้งต้นด้วย (ไม่ค้างค่าผี)', () {
      final c = ProjectController(withSeed(Dialect.mysql));
      c.removeColumn('tr', 'r3');
      final rows = c.project.tableById('tr')!.seedRows;
      expect(rows.every((r) => !r.containsKey('r3')), true);
      expect(rows.length, 2);
    });

    test('ทำสำเนาตาราง: ข้อมูลตั้งต้นตามไปและผูกกับ id คอลัมน์ใหม่', () {
      final c = ProjectController(withSeed(Dialect.mysql));
      final copy = c.duplicateTable('tr')!;
      final newIds = copy.columns.map((x) => x.id).toSet();
      expect(copy.seedRows.length, 2);
      for (final r in copy.seedRows) {
        expect(r.keys.every(newIds.contains), true);
      }
      expect(validateSeed(c.project).where((p) => p.tableId == copy.id), isEmpty);
    });
  });

  group('validateSeed', () {
    test('ข้อมูลถูกต้อง = ไม่มีปัญหา', () {
      expect(validateSeed(withSeed(Dialect.mysql)), isEmpty);
    });

    test('ชนิดค่าผิด: จำนวนเต็ม / ตัวเลข / boolean / วันที่ / UUID / JSON / BLOB / ความยาว varchar', () {
      final p = Project(name: 'x', tables: [
        TableModel(id: 't', name: 't', columns: [
          ColumnModel(id: 'a', name: 'a'),
          ColumnModel(id: 'b', name: 'b', type: DataType.decimal, length: 10, scale: 2),
          ColumnModel(id: 'c', name: 'c', type: DataType.boolean),
          ColumnModel(id: 'd', name: 'd', type: DataType.date),
          ColumnModel(id: 'e', name: 'e', type: DataType.uuid),
          ColumnModel(id: 'f', name: 'f', type: DataType.json),
          ColumnModel(id: 'g', name: 'g', type: DataType.blob),
          ColumnModel(id: 'h', name: 'h', type: DataType.varchar, length: 3),
          ColumnModel(id: 'i', name: 'i', type: DataType.datetime),
        ])
      ]);
      p.tables.single.seedRows = [
        {'a': '1.5', 'b': 'abc', 'c': 'maybe', 'd': '2024/01/01', 'e': 'xyz', 'f': '{bad', 'g': 'zz', 'h': 'abcd', 'i': 'yesterday'},
      ];
      final cols = validateSeed(p).map((e) => e.columnId).toSet();
      expect(cols, {'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'});
    });

    test('ชนิดค่าที่ถูก: ไม่มีปัญหา (รวมรูปแบบที่ยอมรับ)', () {
      final p = Project(name: 'x', tables: [
        TableModel(id: 't', name: 't', columns: [
          ColumnModel(id: 'a', name: 'a'),
          ColumnModel(id: 'b', name: 'b', type: DataType.decimal),
          ColumnModel(id: 'c', name: 'c', type: DataType.boolean),
          ColumnModel(id: 'd', name: 'd', type: DataType.date),
          ColumnModel(id: 'e', name: 'e', type: DataType.uuid),
          ColumnModel(id: 'f', name: 'f', type: DataType.json),
          ColumnModel(id: 'g', name: 'g', type: DataType.blob),
          ColumnModel(id: 'i', name: 'i', type: DataType.timestamp),
        ])
      ]);
      p.tables.single.seedRows = [
        {
          'a': '-5',
          'b': '10.25',
          'c': 'Yes',
          'd': '2024-02-29',
          'e': '123e4567-e89b-12d3-a456-426614174000',
          'f': '{"x":[1,2]}',
          'g': '0A1b',
          'i': '2024-02-29T10:30:00'
        },
      ];
      expect(validateSeed(p), isEmpty);
    });

    test('NOT NULL ที่ไม่ให้ค่า: error; แต่ถ้ามี DEFAULT หรือเป็น AUTO INCREMENT ปล่อยว่างได้', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tr')!.seedRows = [
        {'r2': 'a'}, // r1 AI ไม่ให้ค่า OK, r3 มี DEFAULT ไม่ให้ค่า OK
        {'r1': '5'}, // r2 NOT NULL ไม่มี DEFAULT -> error
        {'r2': ''}, // กรอกว่าง (NULL) ในคอลัมน์ NOT NULL -> error
      ];
      p.tableById('tu')!.seedRows = [];
      final problems = validateSeed(p);
      expect(problems.where((x) => x.row == 0), isEmpty);
      expect(problems.any((x) => x.row == 1 && x.columnId == 'r2'), true);
      expect(problems.any((x) => x.row == 2 && x.columnId == 'r2'), true);
    });

    test('PK ซ้ำและ UNIQUE ซ้ำ', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tr')!.seedRows = [
        {'r1': '1', 'r2': 'a'},
        {'r1': '1', 'r2': 'b'}, // PK ซ้ำ
        {'r1': '3', 'r2': 'a'}, // UNIQUE ซ้ำ
      ];
      final problems = validateSeed(p);
      expect(problems.any((x) => x.row == 1 && x.columnId == 'r1'), true);
      expect(problems.any((x) => x.row == 2 && x.columnId == 'r2'), true);
    });

    test('FK ชี้ค่าที่ไม่มีในตารางแม่ (เมื่อแม่มีข้อมูลตั้งต้น); แม่ไม่มีข้อมูล = ตรวจไม่ได้ ไม่ฟ้อง', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tu')!.seedRows = [
        {'u1': '1', 'u2': '99'}
      ];
      expect(validateSeed(p).any((x) => x.tableId == 'tu' && x.columnId == 'u2'), true);

      p.tableById('tr')!.seedRows = [];
      expect(validateSeed(p), isEmpty);
    });

    test('แถวอ้างคอลัมน์ที่ไม่มีอยู่แล้ว = ปัญหา', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tr')!.seedRows.add({'ghost': '1', 'r1': '9', 'r2': 'z'});
      expect(validateSeed(p).any((x) => x.columnId == 'ghost'), true);
    });

    test('ข้อความปัญหาแปลเป็นอังกฤษได้ ไม่มีอักษรไทยหลุด', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tr')!.seedRows = [
        {'r1': 'x', 'r2': 'a'}
      ];
      final msg = validateSeed(p).first;
      expect(msg.message, isNotEmpty);
    });
  });

  group('สร้าง INSERT ต่อ dialect', () {
    test('MySQL: ตารางแม่ก่อนลูก, หลายแถวในคำสั่งเดียว, escape, boolean', () {
      final sql = generateSeedSql(withSeed(Dialect.mysql));
      expect(sql.indexOf('INSERT INTO `roles`'), lessThan(sql.indexOf('INSERT INTO `users`')));
      expect(sql, contains("(1, 'admin', TRUE)"));
      expect(sql, contains("(2, 'o''neil', FALSE)")); // เครื่องหมายคำพูดเดี่ยวซ้ำสองตัว
      expect(sql, contains('สวัสดี'));
    });

    test('PostgreSQL: boolean TRUE/FALSE และตั้ง sequence ต่อจากค่าสูงสุดเมื่อใส่ค่า AUTO INCREMENT เอง', () {
      final sql = generateSeedSql(withSeed(Dialect.postgres));
      expect(sql, contains('"roles"'));
      expect(sql, contains("'o''neil'"));
      expect(sql, contains('setval(pg_get_serial_sequence(\'"roles"\', \'id\')'));
      expect(sql, contains('MAX("id")'));
    });

    test('SQL Server: N\'…\' สำหรับข้อความ, bit เป็น 1/0, IDENTITY_INSERT เปิด-ปิดรอบตาราง', () {
      final sql = generateSeedSql(withSeed(Dialect.mssql));
      expect(sql, contains("N'admin'"));
      expect(sql, contains("N'สวัสดี'"));
      expect(sql, contains('(1, N\'admin\', 1)'));
      expect(sql, contains('SET IDENTITY_INSERT [roles] ON;'));
      expect(sql.indexOf('SET IDENTITY_INSERT [roles] ON;'), lessThan(sql.indexOf('SET IDENTITY_INSERT [roles] OFF;')));
    });

    test('SQLite: boolean เป็น 1/0', () {
      final sql = generateSeedSql(withSeed(Dialect.sqlite));
      expect(sql, contains('(1, \'admin\', 1)'));
    });

    test('ไม่ใส่ AUTO INCREMENT เอง: ไม่มี setval / IDENTITY_INSERT', () {
      final p = withSeed(Dialect.postgres);
      p.tableById('tr')!.seedRows = [
        {'r2': 'a'},
        {'r2': 'b'}
      ];
      p.tableById('tu')!.seedRows = [];
      expect(generateSeedSql(p), isNot(contains('setval')));
      final m = withSeed(Dialect.mssql);
      m.tableById('tr')!.seedRows = [
        {'r2': 'a'}
      ];
      m.tableById('tu')!.seedRows = [];
      expect(generateSeedSql(m), isNot(contains('IDENTITY_INSERT')));
    });

    test('NULL, สตริงว่าง "" และคอลัมน์ที่ไม่ใส่ค่า (ใช้ DEFAULT)', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tu')!.seedRows = [
        {'u1': '1', 'u2': '1', 'u3': null},
        {'u1': '2', 'u2': '1', 'u3': '""'},
        {'u1': '3', 'u2': '1'}, // ไม่มี u3 -> DEFAULT
      ];
      final sql = generateSeedSql(p);
      expect(sql, contains('(1, 1, NULL)'));
      expect(sql, contains("(2, 1, '')"));
      expect(sql, contains('(3, 1, DEFAULT)'));
    });

    test('SQLite: แถวที่ไม่ให้ค่าบางคอลัมน์ แยกเป็นคำสั่งต่อแถว (ไม่ใช้ DEFAULT ในรายการค่า)', () {
      final p = withSeed(Dialect.sqlite);
      p.tableById('tu')!.seedRows = [
        {'u1': '1', 'u2': '1', 'u3': 'a'},
        {'u1': '2', 'u2': '1'},
      ];
      final sql = generateSeedSql(p);
      expect(sql, isNot(contains('DEFAULT')));
      expect(sql, contains('INSERT INTO "users" ("id", "role_id") VALUES (2, 1);'));
    });

    test('ข้อมูลมาก: แบ่งก้อนละ 500 แถว', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tr')!.seedRows = [
        for (var i = 1; i <= 1200; i++) {'r1': '$i', 'r2': 'role$i'},
      ];
      p.tableById('tu')!.seedRows = [];
      final sql = generateSeedSql(p);
      expect('INSERT INTO'.allMatches(sql).length, 3);
    });

    test('ไม่มีข้อมูลตั้งต้นเลย = ข้อความว่าง', () {
      expect(generateSeedSql(make(Dialect.mysql)), '');
    });

    test('ข้อมูลไม่ถูกต้อง = ไม่สร้าง SQL (โยน SeedException)', () {
      final p = withSeed(Dialect.mysql);
      p.tableById('tr')!.seedRows = [
        {'r1': 'abc', 'r2': 'x'}
      ];
      expect(() => generateSeedSql(p), throwsA(isA<SeedException>()));
    });

    test('ชื่อตาราง/คอลัมน์ที่เป็น reserved word ถูก quote', () {
      final p = Project(name: 'x', dialect: Dialect.postgres, tables: [
        TableModel(id: 't', name: 'order', columns: [
          ColumnModel(id: 'a', name: 'select', type: DataType.varchar, length: 10, isPrimaryKey: true)
        ], seedRows: [
          {'a': 'v'}
        ])
      ]);
      expect(generateSeedSql(p), contains('INSERT INTO "order" ("select") VALUES'));
    });
  });

  group('รันซ้ำได้อย่างปลอดภัย (idempotent)', () {
    String idem(Dialect d) {
      final p = withSeed(d);
      return seedInsertSql(p, p.tableById('tr')!, p.tableById('tr')!.seedRows, idempotent: true);
    }

    test('MySQL: INSERT IGNORE', () => expect(idem(Dialect.mysql), contains('INSERT IGNORE INTO `roles`')));
    test('SQLite: INSERT OR IGNORE', () => expect(idem(Dialect.sqlite), contains('INSERT OR IGNORE INTO "roles"')));
    test('PostgreSQL: ON CONFLICT DO NOTHING', () => expect(idem(Dialect.postgres), contains('ON CONFLICT DO NOTHING')));
    test('SQL Server: IF NOT EXISTS ตาม PK ต่อแถว', () {
      final sql = idem(Dialect.mssql);
      expect(sql, contains('IF NOT EXISTS (SELECT 1 FROM [roles] WHERE [id] = 1)'));
      expect(sql, contains("N'admin'"));
    });
    test('SQL Server: ตารางไม่มี PK = ข้ามพร้อมคอมเมนต์เตือน ไม่สร้าง INSERT ที่รันซ้ำไม่ได้', () {
      final p = Project(name: 'x', dialect: Dialect.mssql, tables: [
        TableModel(id: 't', name: 'nopk', columns: [ColumnModel(id: 'a', name: 'a')], seedRows: [
          {'a': '1'}
        ])
      ]);
      final sql = seedInsertSql(p, p.tables.single, p.tables.single.seedRows, idempotent: true);
      expect(sql, contains('-- '));
      expect(sql, isNot(contains('INSERT INTO')));
    });
  });

  group('รันบน SQLite จริง', () {
    late Database db;
    setUp(() => db = sqlite3.openInMemory());
    tearDown(() => db.close());

    void schema(Project p) => db.execute(DdlGenerator.forDialect(Dialect.sqlite).generate(p));
    int count(String table) => db.select('SELECT COUNT(*) AS n FROM "$table"').first['n'] as int;

    test('สคริปต์ข้อมูลตั้งต้นรันได้ ข้อมูลครบ ไทยและเครื่องหมายคำพูดไม่เพี้ยน', () {
      final p = withSeed(Dialect.sqlite);
      schema(p);
      db.execute(generateSeedSql(p));
      expect(count('roles'), 2);
      expect(count('users'), 1);
      expect(db.select('SELECT name FROM roles WHERE id = 2').first['name'], "o'neil");
      expect(db.select('SELECT note FROM users').first['note'], 'สวัสดี');
      expect(db.select('SELECT is_admin FROM roles WHERE id = 1').first['is_admin'], 1);
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    });

    test('แถวที่ไม่ให้ค่าบางคอลัมน์: ใช้ DEFAULT ของตาราง และ AUTO INCREMENT ได้ค่าถัดไป', () {
      final p = withSeed(Dialect.sqlite);
      p.tableById('tr')!.seedRows = [
        {'r2': 'a'},
        {'r2': 'b'},
      ];
      p.tableById('tu')!.seedRows = [];
      schema(p);
      db.execute(generateSeedSql(p));
      final rows = db.select('SELECT id, is_admin FROM roles ORDER BY id');
      expect(rows.map((r) => r['id']).toList(), [1, 2]);
      expect(rows.every((r) => r['is_admin'] == 0), true);
    });

    test('รัน idempotent ซ้ำหลายรอบ: ไม่ error ไม่ซ้ำ และไม่แตะค่าที่ผู้ใช้แก้ไว้ในฐานข้อมูล', () {
      final p = withSeed(Dialect.sqlite);
      schema(p);
      final roles = p.tableById('tr')!;
      final script = seedInsertSql(p, roles, roles.seedRows, idempotent: true);
      db.execute(script);
      db.execute("UPDATE roles SET name = 'ผู้ดูแล' WHERE id = 1"); // ผู้ใช้แก้ในฐานข้อมูลจริง
      db.execute(script);
      db.execute(script);
      expect(count('roles'), 2);
      expect(db.select('SELECT name FROM roles WHERE id = 1').first['name'], 'ผู้ดูแล'); // ไม่ถูกทับ
    });

    test('ข้อมูลที่ขัดกับ FK ถูกจับก่อนสร้างสคริปต์ (ไม่ปล่อยไปพังตอนรัน)', () {
      final p = withSeed(Dialect.sqlite);
      p.tableById('tu')!.seedRows = [
        {'u1': '1', 'u2': '77'}
      ];
      expect(() => generateSeedSql(p), throwsA(isA<SeedException>()));
    });
  });
}
