import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/ddl/ddl_generator.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/index_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';

Project shop(Dialect d) => Project(
      name: 'shop',
      dialect: d,
      tables: [
        TableModel(id: 'tu', name: 'users', columns: [
          ColumnModel(id: 'u1', name: 'id', isPrimaryKey: true, autoIncrement: true),
          ColumnModel(id: 'u2', name: 'email', type: DataType.varchar, length: 255, notNull: true, unique: true),
          ColumnModel(
              id: 'u3',
              name: 'created_at',
              type: DataType.datetime,
              notNull: true,
              defaultValue: 'CURRENT_TIMESTAMP'),
        ]),
        TableModel(id: 'to', name: 'orders', columns: [
          ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true, autoIncrement: true),
          ColumnModel(id: 'o2', name: 'user_id', notNull: true),
          ColumnModel(
              id: 'o3',
              name: 'status',
              type: DataType.varchar,
              length: 20,
              notNull: true,
              defaultValue: 'pending'),
          ColumnModel(id: 'o4', name: 'total', type: DataType.decimal, length: 10, scale: 2, notNull: true),
        ], indexes: [
          IndexModel(id: 'i1', name: 'idx_orders_user_id', columnIds: ['o2']),
        ]),
      ],
      relations: [
        RelationModel(
            id: 'r1',
            fromTableId: 'to',
            fromColumnId: 'o2',
            toTableId: 'tu',
            toColumnId: 'u1',
            onDelete: RefAction.cascade),
      ],
    );

String gen(Project p) => DdlGenerator.forDialect(p.dialect).generate(p);

void main() {
  test('MySQL', () {
    expect(gen(shop(Dialect.mysql)), '''
-- shop (MySQL / MariaDB) — สร้างโดย NSL Dev

CREATE TABLE `users` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `email` VARCHAR(255) NOT NULL UNIQUE,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `orders` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `user_id` INT NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
  `total` DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX `idx_orders_user_id` ON `orders` (`user_id`);

ALTER TABLE `orders` ADD CONSTRAINT `fk_orders_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;
''');
  });

  test('PostgreSQL', () {
    expect(gen(shop(Dialect.postgres)), '''
-- shop (PostgreSQL) — สร้างโดย NSL Dev

CREATE TABLE "users" (
  "id" SERIAL NOT NULL,
  "email" VARCHAR(255) NOT NULL UNIQUE,
  "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY ("id")
);

CREATE TABLE "orders" (
  "id" SERIAL NOT NULL,
  "user_id" INTEGER NOT NULL,
  "status" VARCHAR(20) NOT NULL DEFAULT 'pending',
  "total" NUMERIC(10,2) NOT NULL,
  PRIMARY KEY ("id")
);

CREATE INDEX "idx_orders_user_id" ON "orders" ("user_id");

ALTER TABLE "orders" ADD CONSTRAINT "fk_orders_user_id" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE;
''');
  });

  test('SQLite: FK อยู่ใน CREATE TABLE และ AUTOINCREMENT', () {
    expect(gen(shop(Dialect.sqlite)), '''
-- shop (SQLite) — สร้างโดย NSL Dev

PRAGMA foreign_keys = ON;

CREATE TABLE "users" (
  "id" INTEGER NOT NULL,
  "email" TEXT NOT NULL UNIQUE,
  "created_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY ("id" AUTOINCREMENT)
);

CREATE TABLE "orders" (
  "id" INTEGER NOT NULL,
  "user_id" INTEGER NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "total" NUMERIC NOT NULL,
  PRIMARY KEY ("id" AUTOINCREMENT),
  CONSTRAINT "fk_orders_user_id" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE
);

CREATE INDEX "idx_orders_user_id" ON "orders" ("user_id");
''');
  });

  test('SQL Server: IDENTITY, PK constraint, GO', () {
    expect(gen(shop(Dialect.mssql)), '''
-- shop (SQL Server) — สร้างโดย NSL Dev

CREATE TABLE [users] (
  [id] INT IDENTITY(1,1) NOT NULL,
  [email] NVARCHAR(255) NOT NULL UNIQUE,
  [created_at] DATETIME2 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT [PK_users] PRIMARY KEY ([id])
);

CREATE TABLE [orders] (
  [id] INT IDENTITY(1,1) NOT NULL,
  [user_id] INT NOT NULL,
  [status] NVARCHAR(20) NOT NULL DEFAULT 'pending',
  [total] DECIMAL(10,2) NOT NULL,
  CONSTRAINT [PK_orders] PRIMARY KEY ([id])
);

GO

CREATE INDEX [idx_orders_user_id] ON [orders] ([user_id]);

ALTER TABLE [orders] ADD CONSTRAINT [fk_orders_user_id] FOREIGN KEY ([user_id]) REFERENCES [users] ([id]) ON DELETE CASCADE;
''');
  });

  test('ผลลัพธ์คงที่ (เรียกซ้ำได้ค่าเดิม)', () {
    final p = shop(Dialect.mysql);
    expect(gen(p), gen(p));
  });

  group('quote / escape', () {
    Project one(Dialect d, String table, String col) => Project(dialect: d, tables: [
          TableModel(id: 't', name: table, columns: [ColumnModel(id: 'c', name: col)]),
        ]);

    test('ชื่อที่มีอักขระปิดอยู่ในตัว', () {
      expect(gen(one(Dialect.mysql, 'a`b', 'c')), contains('`a``b`'));
      expect(gen(one(Dialect.postgres, 'a"b', 'c')), contains('"a""b"'));
      expect(gen(one(Dialect.mssql, 'a]b', 'c')), contains('[a]]b]'));
    });

    test('reserved word ถูก quote ทุก dialect', () {
      expect(gen(one(Dialect.mysql, 'order', 'select')), contains('CREATE TABLE `order` (\n  `select`'));
      expect(gen(one(Dialect.postgres, 'order', 'select')), contains('"order"'));
      expect(gen(one(Dialect.mssql, 'order', 'select')), contains('[order]'));
    });
  });

  group('ค่าเริ่มต้น', () {
    String def(Dialect d, DataType t, String v) {
      final p = Project(dialect: d, tables: [
        TableModel(id: 't', name: 't', columns: [ColumnModel(id: 'c', name: 'c', type: t, defaultValue: v)]),
      ]);
      return RegExp(r'DEFAULT (.*?)\n').firstMatch(gen(p))!.group(1)!;
    }

    test('ตัวเลข / ข้อความ / NULL', () {
      expect(def(Dialect.mysql, DataType.integer, '0'), '0');
      expect(def(Dialect.mysql, DataType.decimal, '-1.5'), '-1.5');
      expect(def(Dialect.mysql, DataType.varchar, '123'), "'123'"); // ชนิดข้อความ ต้อง quote
      expect(def(Dialect.mysql, DataType.varchar, "it's"), "'it''s'");
      expect(def(Dialect.mysql, DataType.integer, 'null'), 'NULL');
    });

    test('MySQL escape backslash', () {
      expect(def(Dialect.mysql, DataType.varchar, r'a\b'), r"'a\\b'");
      expect(def(Dialect.postgres, DataType.varchar, r'a\b'), r"'a\b'");
    });

    test('boolean: TRUE/FALSE ตาม dialect', () {
      expect(def(Dialect.postgres, DataType.boolean, 'true'), 'TRUE');
      expect(def(Dialect.mssql, DataType.boolean, 'true'), '1');
      expect(def(Dialect.sqlite, DataType.boolean, 'false'), '0');
    });

    test('boolean: DEFAULT 1/0 แปลงเป็น TRUE/FALSE (PostgreSQL ไม่รับ 1/0)', () {
      expect(def(Dialect.postgres, DataType.boolean, '1'), 'TRUE');
      expect(def(Dialect.postgres, DataType.boolean, '0'), 'FALSE');
      expect(def(Dialect.mysql, DataType.boolean, '1'), 'TRUE');
      expect(def(Dialect.mssql, DataType.boolean, '1'), '1');
      expect(def(Dialect.sqlite, DataType.boolean, '0'), '0');
    });

    test('ฟังก์ชันครอบวงเล็บ, NOW() -> CURRENT_TIMESTAMP', () {
      expect(def(Dialect.mysql, DataType.uuid, 'uuid()'), '(uuid())');
      expect(def(Dialect.postgres, DataType.timestamp, 'now()'), 'CURRENT_TIMESTAMP');
      expect(def(Dialect.mysql, DataType.datetime, 'CURRENT_TIMESTAMP'), 'CURRENT_TIMESTAMP');
    });

    test('สตริงที่ผู้ใช้ใส่ quote มาแล้ว ไม่ถูกครอบซ้ำ', () {
      expect(def(Dialect.mysql, DataType.varchar, "'x'"), "'x'");
    });

    test('คอลัมน์ AUTO INCREMENT ไม่ใส่ DEFAULT', () {
      final p = Project(tables: [
        TableModel(id: 't', name: 't', columns: [
          ColumnModel(id: 'c', name: 'id', isPrimaryKey: true, autoIncrement: true, defaultValue: '5'),
        ]),
      ]);
      expect(gen(p), isNot(contains('DEFAULT 5')));
    });
  });

  group('ชนิดข้อมูลต่อ dialect', () {
    String type(Dialect d, DataType t, {int? len, int? scale, bool ai = false}) {
      final p = Project(dialect: d, tables: [
        TableModel(id: 't', name: 't', columns: [
          ColumnModel(id: 'c', name: 'c', type: t, length: len, scale: scale, autoIncrement: ai),
        ]),
      ]);
      // บรรทัดคอลัมน์: "  <quote>c<quote> <TYPE>[ ...]" ; ตัด NOT NULL / PRIMARY ฯลฯ ท้ายออก
      final line = gen(p).split('\n').firstWhere((l) => RegExp(r'^  \S?c\S? ').hasMatch(l));
      return line.replaceFirst(RegExp(r'^  \S?c\S? '), '').replaceFirst(RegExp(r',$'), '');
    }

    test('ตารางแมป', () {
      expect(type(Dialect.mysql, DataType.uuid), 'CHAR(36)');
      expect(type(Dialect.postgres, DataType.uuid), 'UUID');
      expect(type(Dialect.mssql, DataType.uuid), 'UNIQUEIDENTIFIER');
      expect(type(Dialect.postgres, DataType.blob), 'BYTEA');
      expect(type(Dialect.mssql, DataType.text), 'NVARCHAR(MAX)');
      expect(type(Dialect.mssql, DataType.timestamp), 'DATETIME2');
      expect(type(Dialect.sqlite, DataType.bigint), 'INTEGER');
      expect(type(Dialect.postgres, DataType.bigint, ai: true), 'BIGSERIAL');
      expect(type(Dialect.postgres, DataType.smallint, ai: true), 'SMALLSERIAL');
      expect(type(Dialect.mysql, DataType.varchar), 'VARCHAR(255)'); // ไม่ระบุความยาว
      expect(type(Dialect.mysql, DataType.decimal), 'DECIMAL(10,2)');
    });
  });

  group('ความเห็น (COMMENT)', () {
    Project commented(Dialect d) => Project(dialect: d, tables: [
          TableModel(id: 't', name: 'orders', comment: "คำสั่งซื้อ's", columns: [
            ColumnModel(id: 'c', name: 'id', isPrimaryKey: true, comment: 'รหัส'),
          ]),
        ]);

    test('MySQL: inline', () {
      final s = gen(commented(Dialect.mysql));
      expect(s, contains("`id` INT NOT NULL COMMENT 'รหัส'"));
      expect(s, contains("COMMENT='คำสั่งซื้อ''s';"));
    });

    test('PostgreSQL: COMMENT ON', () {
      final s = gen(commented(Dialect.postgres));
      expect(s, contains('''COMMENT ON TABLE "orders" IS 'คำสั่งซื้อ''s';'''));
      expect(s, contains('''COMMENT ON COLUMN "orders"."id" IS 'รหัส';'''));
    });

    test('SQL Server: sp_addextendedproperty', () {
      final s = gen(commented(Dialect.mssql));
      expect(s, contains("N'TABLE', N'orders', N'COLUMN', N'id';"));
      expect(s, contains("N'คำสั่งซื้อ''s'"));
    });

    test('SQLite: แปลงเป็นคอมเมนต์ และบรรทัดใหม่ในความเห็นไม่ทำให้ SQL พัง', () {
      final p = commented(Dialect.sqlite);
      p.tables.first.comment = 'บรรทัด1\nบรรทัด2';
      final s = gen(p);
      expect(s, contains('-- บรรทัด1 บรรทัด2\nCREATE TABLE'));
      expect(s, contains('-- รหัส\n  "id" INTEGER NOT NULL'));
    });
  });

  group('คีย์และความสัมพันธ์', () {
    test('PK หลายคอลัมน์', () {
      final p = Project(tables: [
        TableModel(id: 't', name: 'oi', columns: [
          ColumnModel(id: 'a', name: 'order_id', isPrimaryKey: true),
          ColumnModel(id: 'b', name: 'product_id', isPrimaryKey: true),
        ]),
      ]);
      expect(gen(p), contains('PRIMARY KEY (`order_id`, `product_id`)'));
    });

    test('UNIQUE ของ PK คอลัมน์เดียวไม่ซ้ำซ้อน', () {
      final p = Project(tables: [
        TableModel(id: 't', name: 't', columns: [
          ColumnModel(id: 'a', name: 'id', isPrimaryKey: true, unique: true),
        ]),
      ]);
      expect(gen(p), isNot(contains('UNIQUE')));
    });

    test('SQLite: PK หลายคอลัมน์ไม่ใส่ AUTOINCREMENT', () {
      final p = Project(dialect: Dialect.sqlite, tables: [
        TableModel(id: 't', name: 't', columns: [
          ColumnModel(id: 'a', name: 'a', isPrimaryKey: true, autoIncrement: true),
          ColumnModel(id: 'b', name: 'b', isPrimaryKey: true),
        ]),
      ]);
      expect(gen(p), contains('PRIMARY KEY ("a", "b")'));
      expect(gen(p), isNot(contains('AUTOINCREMENT')));
    });

    test('ON UPDATE และชื่อ FK ที่ซ้ำถูกเติมเลขต่อท้าย', () {
      final p = shop(Dialect.postgres);
      p.relations.add(RelationModel(
          id: 'r2',
          fromTableId: 'to',
          fromColumnId: 'o2',
          toTableId: 'tu',
          toColumnId: 'u2',
          onUpdate: RefAction.setNull));
      final s = gen(p);
      expect(s, contains('"fk_orders_user_id_2" FOREIGN KEY ("user_id") REFERENCES "users" ("email") ON UPDATE SET NULL;'));
    });

    test('ชื่อ FK ที่ผู้ใช้ตั้งเองถูกใช้', () {
      final p = shop(Dialect.mysql);
      p.relations.single.name = 'my_fk';
      expect(gen(p), contains('CONSTRAINT `my_fk` FOREIGN KEY'));
    });

    test('FK ชี้ไปตารางที่ถูกลบ -> ข้ามพร้อมคอมเมนต์ ไม่ทำให้ SQL พัง', () {
      final p = shop(Dialect.mysql);
      p.tables.removeWhere((t) => t.id == 'tu');
      final s = gen(p);
      expect(s, contains('-- ข้าม FK'));
      expect(s, isNot(contains('ALTER TABLE')));
    });

    test('ตารางวนอ้างกัน: FK ไปท้ายไฟล์จึงไม่ติดลำดับ CREATE', () {
      final p = Project(tables: [
        TableModel(id: 'a', name: 'a', columns: [
          ColumnModel(id: 'a1', name: 'id', isPrimaryKey: true),
          ColumnModel(id: 'a2', name: 'b_id'),
        ]),
        TableModel(id: 'b', name: 'b', columns: [
          ColumnModel(id: 'b1', name: 'id', isPrimaryKey: true),
          ColumnModel(id: 'b2', name: 'a_id'),
        ]),
      ], relations: [
        RelationModel(id: 'r1', fromTableId: 'a', fromColumnId: 'a2', toTableId: 'b', toColumnId: 'b1'),
        RelationModel(id: 'r2', fromTableId: 'b', fromColumnId: 'b2', toTableId: 'a', toColumnId: 'a1'),
      ]);
      final s = gen(p);
      final lastCreate = s.lastIndexOf('CREATE TABLE');
      final firstAlter = s.indexOf('ALTER TABLE');
      expect(firstAlter, greaterThan(lastCreate));
    });
  });

  group('ขอบเขต', () {
    test('โปรเจกต์ว่างยังได้ header', () {
      expect(gen(Project(name: 'x')), '-- x (MySQL / MariaDB) — สร้างโดย NSL Dev\n');
    });

    test('ตารางไม่มีคอลัมน์ถูกข้าม', () {
      final p = Project(tables: [TableModel(id: 't', name: 'empty')]);
      expect(gen(p), contains('-- ข้ามตาราง empty'));
      expect(gen(p), isNot(contains('CREATE TABLE')));
    });

    test('INDEX หลายคอลัมน์ + UNIQUE', () {
      final p = Project(tables: [
        TableModel(id: 't', name: 't', columns: [
          ColumnModel(id: 'a', name: 'a'),
          ColumnModel(id: 'b', name: 'b'),
        ], indexes: [
          IndexModel(id: 'i', name: 'ux', columnIds: ['a', 'b'], unique: true),
        ]),
      ]);
      expect(gen(p), contains('CREATE UNIQUE INDEX `ux` ON `t` (`a`, `b`);'));
    });

    test('INDEX ที่คอลัมน์หายไปถูกข้าม', () {
      final p = Project(tables: [
        TableModel(id: 't', name: 't', columns: [
          ColumnModel(id: 'a', name: 'a'),
        ], indexes: [
          IndexModel(id: 'i', name: 'bad', columnIds: ['zzz']),
        ]),
      ]);
      expect(gen(p), contains('-- ข้าม INDEX bad'));
    });
  });
}
