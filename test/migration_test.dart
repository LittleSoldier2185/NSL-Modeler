import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/diff/migration.dart';
import 'package:nsl_dev/core/diff/schema_diff.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/index_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'migration_fixtures.dart';

String mig(Project a, Project b) => generateMigration(a, b);

void main() {
  group('diffProjects', () {
    test('เหมือนกัน = ว่าง', () {
      final d = diffProjects(base(), clone(base()));
      expect(d.isEmpty, true);
      expect(d.summary(base(), base()), isEmpty);
    });

    test('เพิ่ม/ลบตาราง', () {
      final b = clone(base());
      b.tables.removeWhere((t) => t.id == 'to');
      b.relations.clear();
      b.tables.add(TableModel(id: 'tn', name: 'logs', columns: [col('n1', 'id', pk: true)]));
      final d = diffProjects(base(), b);
      expect(d.droppedTables.map((t) => t.name), ['orders']);
      expect(d.addedTables.map((t) => t.name), ['logs']);
      expect(d.droppedRelations.length, 1);
    });

    test('เปลี่ยนชื่อ (id เดิม) ไม่ใช่ลบ+สร้างใหม่', () {
      final b = clone(base());
      tb(b, 'tu').name = 'members';
      cl(b, 'tu', 'u3').name = 'full_name';
      final d = diffProjects(base(), b);
      expect(d.droppedTables, isEmpty);
      expect(d.addedTables, isEmpty);
      final td = d.modified.single;
      expect(td.renamed, true);
      expect(td.changedColumns.single.renamed, true);
      expect(td.droppedColumns, isEmpty);
      expect(td.addedColumns, isEmpty);
    });

    test('จับคู่ด้วยชื่อเมื่อ id ไม่ตรง (เช่น เทียบกับโปรเจกต์ที่ import มา)', () {
      final a = base();
      final b = Project.fromJson(a.toJson());
      // เปลี่ยน id ทุกตัวใน b
      var n = 0;
      for (final t in b.tables) {
        final oldTid = t.id;
        t.id = 'new_t${n++}';
        for (final r in b.relations) {
          if (r.fromTableId == oldTid) r.fromTableId = t.id;
          if (r.toTableId == oldTid) r.toTableId = t.id;
        }
        for (final c in t.columns) {
          final oldCid = c.id;
          c.id = 'new_c${n++}';
          for (final r in b.relations) {
            if (r.fromColumnId == oldCid) r.fromColumnId = c.id;
            if (r.toColumnId == oldCid) r.toColumnId = c.id;
          }
          for (final i in t.indexes) {
            i.columnIds = [for (final x in i.columnIds) x == oldCid ? c.id : x];
          }
        }
      }
      expect(diffProjects(a, b).isEmpty, true);
      cl(b, b.tables[1].id, b.tables[1].columns[2].id).notNull = false;
      expect(diffProjects(a, b).modified.single.changedColumns.single.nullChanged, true);
    });

    test('VARCHAR ไม่ระบุความยาว = 255 ไม่นับว่าเปลี่ยน', () {
      final a = base();
      final b = clone(base());
      cl(a, 'tu', 'u2').length = null;
      expect(diffProjects(a, b).isEmpty, true);
    });

    test('ชนิด/null/default/AI/unique/comment แยกกันเห็น', () {
      final b = clone(base());
      final c = cl(b, 'to', 'o3');
      c.length = 12;
      c.notNull = false;
      c.defaultValue = '1';
      final ch = diffProjects(base(), b).modified.single.changedColumns.single;
      expect([ch.typeChanged, ch.nullChanged, ch.defaultChanged, ch.autoIncrementChanged, ch.uniqueChanged],
          [true, true, true, false, false]);
    });

    test('unique บนคอลัมน์ PK เดี่ยวไม่นับ', () {
      final b = clone(base());
      cl(b, 'tu', 'u1').unique = true;
      expect(diffProjects(base(), b).isEmpty, true);
    });

    test('PK เปลี่ยน', () {
      final b = clone(base());
      cl(b, 'to', 'o2').isPrimaryKey = true;
      expect(diffProjects(base(), b).modified.single.pkChanged, true);
    });

    test('INDEX เพิ่ม/ลบ/เปลี่ยน', () {
      final b = clone(base());
      tb(b, 'to').indexes.clear();
      tb(b, 'to').indexes.add(IndexModel(id: 'i9', name: 'idx_total', columnIds: ['o3']));
      final td = diffProjects(base(), b).modified.single;
      expect(td.droppedIndexes.map((i) => i.name), ['idx_orders_user']);
      expect(td.addedIndexes.map((i) => i.name), ['idx_total']);
    });

    test('FK: action เปลี่ยน = ลบแล้วเพิ่ม, ชื่อ/id เปลี่ยนอย่างเดียวไม่นับ', () {
      final b = clone(base());
      b.relations.single.onDelete = RefAction.setNull;
      var d = diffProjects(base(), b);
      expect(d.droppedRelations.length, 1);
      expect(d.addedRelations.length, 1);

      final c = clone(base());
      c.relations.single.id = 'other';
      c.relations.single.name = 'renamed_fk';
      d = diffProjects(base(), c);
      expect(d.isEmpty, true);
    });

    test('summary: ข้อความและธงอันตราย', () {
      final b = clone(base());
      tb(b, 'tu').columns.removeWhere((c) => c.id == 'u4');
      cl(b, 'to', 'o3').length = 12;
      final lines = diffProjects(base(), b).summary(base(), b);
      expect(lines.any((l) => l.kind == ChangeKind.drop && l.destructive && l.text.contains('age')), true);
      expect(lines.any((l) => l.text.contains('DECIMAL(10,2) → DECIMAL(12,2)') && l.destructive), true);
    });
  });

  group('migration: ไม่มีอะไรเปลี่ยน', () {
    for (final d in Dialect.values) {
      test(d.label, () {
        final s = mig(base(d), clone(base(d)));
        expect(s, contains('ไม่มีความแตกต่าง'));
        expect(s, isNot(contains('ALTER')));
      });
    }
  });

  group('migration: MySQL', () {
    Project b0() => clone(base());

    test('เพิ่มคอลัมน์ / เปลี่ยนชื่อ / แก้นิยาม', () {
      final b = b0();
      tb(b, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
      cl(b, 'tu', 'u3').name = 'full_name';
      final t = cl(b, 'to', 'o3');
      t.length = 12;
      final s = mig(base(), b);
      expect(s, contains('ALTER TABLE `users` ADD COLUMN `phone` VARCHAR(20);'));
      expect(s, contains('ALTER TABLE `users` RENAME COLUMN `name` TO `full_name`;'));
      expect(s, contains('ALTER TABLE `orders` MODIFY COLUMN `total` DECIMAL(12,2) NOT NULL DEFAULT 0;'));
      expect(s, contains('-- ⚠ เปลี่ยนชนิด'));
    });

    test('NOT NULL ไม่มี DEFAULT ที่เพิ่มเข้าตารางเดิมมีคำเตือน', () {
      final b = b0();
      tb(b, 'tu').columns.add(col('u9', 'code', nn: true));
      expect(mig(base(), b), contains('-- ⚠ code เป็น NOT NULL ไม่มี DEFAULT'));
    });

    test('ลบคอลัมน์/ตารางมี ⚠ และหัวสรุป', () {
      final b = b0();
      tb(b, 'tu').columns.removeWhere((c) => c.id == 'u4');
      b.tables.removeWhere((t) => t.id == 'to');
      b.relations.clear();
      final s = mig(base(), b);
      expect(s, contains('ALTER TABLE `users` DROP COLUMN `age`;'));
      expect(s, contains('DROP TABLE `orders`;'));
      expect(s, contains('-- ⚠ ลบตาราง orders'));
      expect(s, contains('-- ⚠ 2 รายการอาจทำให้ข้อมูลหาย'));
    });

    test('เปลี่ยนชื่อตาราง', () {
      final b = b0();
      tb(b, 'tu').name = 'members';
      expect(mig(base(), b), contains('RENAME TABLE `users` TO `members`;'));
    });

    test('UNIQUE เพิ่ม/ลบ', () {
      final b = b0();
      cl(b, 'tu', 'u3').unique = true;
      cl(b, 'tu', 'u2').unique = false;
      final s = mig(base(), b);
      expect(s, contains('ALTER TABLE `users` ADD CONSTRAINT `name` UNIQUE (`name`);'));
      expect(s, contains('ALTER TABLE `users` DROP INDEX `email`;'));
    });

    test('PK เปลี่ยน', () {
      final b = b0();
      cl(b, 'to', 'o1').isPrimaryKey = false;
      cl(b, 'to', 'o1').autoIncrement = false;
      cl(b, 'to', 'o2').isPrimaryKey = true;
      final s = mig(base(), b);
      expect(s, contains('ALTER TABLE `orders` DROP PRIMARY KEY;'));
      expect(s, contains('ALTER TABLE `orders` ADD PRIMARY KEY (`user_id`);'));
    });

    test('INDEX / FK เพิ่มลบ และลำดับ: ลบ FK -> ลบตาราง -> สร้างตาราง -> เพิ่ม FK', () {
      final b = b0();
      tb(b, 'to').indexes.clear();
      tb(b, 'to').indexes.add(IndexModel(id: 'i9', name: 'idx_total', columnIds: ['o3'], unique: true));
      b.relations.clear(); // ลบ FK เดิม
      b.tables.add(TableModel(id: 'tn', name: 'logs', columns: [col('n1', 'id', pk: true), col('n2', 'user_id')]));
      b.relations.add(RelationModel(
          id: 'rn', fromTableId: 'tn', fromColumnId: 'n2', toTableId: 'tu', toColumnId: 'u1'));
      final s = mig(base(), b);
      expect(s, contains('ALTER TABLE `orders` DROP FOREIGN KEY `fk_orders_user_id`;'));
      expect(s, contains('DROP INDEX `idx_orders_user` ON `orders`;'));
      expect(s, contains('CREATE UNIQUE INDEX `idx_total` ON `orders` (`total`);'));
      expect(s, contains('ALTER TABLE `logs` ADD CONSTRAINT `fk_logs_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`);'));
      expect(s.indexOf('DROP FOREIGN KEY'), lessThan(s.indexOf('CREATE TABLE `logs`')));
      expect(s.indexOf('CREATE TABLE `logs`'), lessThan(s.indexOf('ADD CONSTRAINT `fk_logs_user_id`')));
    });

    test('FK เปลี่ยน action = DROP แล้ว ADD', () {
      final b = b0();
      b.relations.single.onDelete = RefAction.setNull;
      cl(b, 'to', 'o2').notNull = false;
      final s = mig(base(), b);
      expect(s, contains('DROP FOREIGN KEY `fk_orders_user_id`'));
      expect(s, contains('ADD CONSTRAINT `fk_orders_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;'));
    });

    test('หมายเหตุตาราง', () {
      final b = b0();
      tb(b, 'tu').comment = "ผู้ใช้'s";
      expect(mig(base(), b), contains("ALTER TABLE `users` COMMENT = 'ผู้ใช้''s';"));
    });
  });

  group('migration: PostgreSQL', () {
    Project a0() => base(Dialect.postgres);
    Project b0() => clone(a0());

    test('แยกคำสั่งตามสิ่งที่เปลี่ยน', () {
      final b = b0();
      final t = cl(b, 'to', 'o3');
      t.length = 12;
      t.notNull = false;
      t.defaultValue = null;
      cl(b, 'tu', 'u3').defaultValue = 'anon';
      cl(b, 'tu', 'u3').comment = 'ชื่อ';
      final s = mig(a0(), b);
      expect(s, contains('ALTER TABLE "orders" ALTER COLUMN "total" TYPE NUMERIC(12,2) USING "total"::NUMERIC(12,2);'));
      expect(s, contains('ALTER TABLE "orders" ALTER COLUMN "total" DROP NOT NULL;'));
      expect(s, contains('ALTER TABLE "orders" ALTER COLUMN "total" DROP DEFAULT;'));
      expect(s, contains('''ALTER TABLE "users" ALTER COLUMN "name" SET DEFAULT 'anon';'''));
      expect(s, contains('''COMMENT ON COLUMN "users"."name" IS 'ชื่อ';'''));
    });

    test('เพิ่มคอลัมน์ AUTO INCREMENT ใช้ SERIAL, ชนิดตอนแก้ไม่ใช้ SERIAL', () {
      final b = b0();
      tb(b, 'tu').columns.add(col('u9', 'seq', ai: true, nn: true));
      cl(b, 'tu', 'u1').type = DataType.bigint;
      final s = mig(a0(), b);
      expect(s, contains('ALTER TABLE "users" ADD COLUMN "seq" SERIAL NOT NULL;'));
      expect(s, contains('ALTER COLUMN "id" TYPE BIGINT USING "id"::BIGINT;'));
      expect(s, isNot(contains('TYPE BIGSERIAL')));
    });

    test('UNIQUE ลบ/เพิ่ม ใช้ชื่อ constraint มาตรฐานของ PostgreSQL', () {
      final b = b0();
      cl(b, 'tu', 'u2').unique = false;
      cl(b, 'tu', 'u3').unique = true;
      final s = mig(a0(), b);
      expect(s, contains('ALTER TABLE "users" DROP CONSTRAINT "users_email_key";'));
      expect(s, contains('ALTER TABLE "users" ADD CONSTRAINT "users_name_key" UNIQUE ("name");'));
    });

    test('เปลี่ยนชื่อตาราง/คอลัมน์ และ DROP INDEX ไม่มี ON', () {
      final b = b0();
      tb(b, 'to').name = 'purchases';
      cl(b, 'to', 'o4').name = 'memo';
      tb(b, 'to').indexes.clear();
      final s = mig(a0(), b);
      expect(s, contains('ALTER TABLE "orders" RENAME TO "purchases";'));
      expect(s, contains('ALTER TABLE "purchases" RENAME COLUMN "note" TO "memo";'));
      expect(s, contains('DROP INDEX "idx_orders_user";'));
      // DROP INDEX ใช้ชื่อตารางเก่า/ไม่มีชื่อตาราง; rename เกิดหลัง
      expect(s.indexOf('DROP INDEX'), lessThan(s.indexOf('RENAME TO')));
    });

    test('ตารางใหม่ + หมายเหตุ ได้ COMMENT ON', () {
      final b = b0();
      b.tables.add(TableModel(id: 'tn', name: 'logs', comment: 'บันทึก', columns: [
        col('n1', 'id', pk: true, comment: 'รหัส'),
      ]));
      final s = mig(a0(), b);
      expect(s, contains('CREATE TABLE "logs"'));
      expect(s, contains('''COMMENT ON TABLE "logs" IS 'บันทึก';'''));
      expect(s, contains('''COMMENT ON COLUMN "logs"."id" IS 'รหัส';'''));
    });

    test('ลบ FK ก่อนลบตารางแม่', () {
      final b = b0();
      b.tables.removeWhere((t) => t.id == 'tu');
      b.relations.clear();
      final s = mig(a0(), b);
      expect(s.indexOf('DROP CONSTRAINT "fk_orders_user_id"'), lessThan(s.indexOf('DROP TABLE "users"')));
    });
  });

  group('migration: SQL Server', () {
    Project a0() => base(Dialect.mssql);
    Project b0() => clone(a0());

    test('เพิ่ม/แก้คอลัมน์ ใช้ ADD ไม่มีคำว่า COLUMN และ ALTER COLUMN', () {
      final b = b0();
      tb(b, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
      cl(b, 'to', 'o3').length = 12;
      final s = mig(a0(), b);
      expect(s, contains('ALTER TABLE [users] ADD [phone] NVARCHAR(20);'));
      expect(s, contains('ALTER TABLE [orders] ALTER COLUMN [total] DECIMAL(12,2) NOT NULL;'));
    });

    test('เปลี่ยนชื่อด้วย sp_rename', () {
      final b = b0();
      tb(b, 'tu').name = 'members';
      cl(b, 'tu', 'u3').name = 'full_name';
      final s = mig(a0(), b);
      expect(s, contains("EXEC sp_rename N'users', N'members';"));
      expect(s, contains("EXEC sp_rename N'members.name', N'full_name', N'COLUMN';"));
    });

    test('DEFAULT / IDENTITY / UNIQUE ที่ทำอัตโนมัติไม่ได้ ได้คำเตือนให้ทำเอง', () {
      final b = b0();
      cl(b, 'to', 'o3').defaultValue = '5';
      cl(b, 'tu', 'u2').unique = false;
      cl(b, 'tu', 'u4').autoIncrement = true;
      final s = mig(a0(), b);
      expect(s, contains('-- ⚠ เปลี่ยนค่าเริ่มต้น'));
      expect(s, contains('-- ⚠ ต้องลบ UNIQUE ของ users.email เอง'));
      expect(s, contains('-- ⚠ SQL Server เปลี่ยน IDENTITY'));
    });

    test('INDEX, PK constraint, หมายเหตุ', () {
      final b = b0();
      tb(b, 'to').indexes.clear();
      cl(b, 'to', 'o1').isPrimaryKey = false;
      cl(b, 'to', 'o1').autoIncrement = false;
      cl(b, 'to', 'o2').isPrimaryKey = true;
      tb(b, 'tu').comment = 'ผู้ใช้';
      final s = mig(a0(), b);
      expect(s, contains('DROP INDEX [idx_orders_user] ON [orders];'));
      expect(s, contains('ALTER TABLE [orders] DROP CONSTRAINT [PK_orders];'));
      expect(s, contains('ALTER TABLE [orders] ADD CONSTRAINT [PK_orders] PRIMARY KEY ([user_id]);'));
      expect(s, contains("EXEC sp_addextendedproperty N'MS_Description', N'ผู้ใช้', N'SCHEMA', N'dbo', N'TABLE', N'users';"));
    });

    test('หมายเหตุ: แก้ = update, ลบ = drop', () {
      final a = a0();
      tb(a, 'tu').comment = 'เดิม';
      final b = clone(a);
      tb(b, 'tu').comment = 'ใหม่';
      expect(mig(a, b), contains("sp_updateextendedproperty N'MS_Description', N'ใหม่'"));
      tb(b, 'tu').comment = '';
      expect(mig(a, b), contains("sp_dropextendedproperty N'MS_Description'"));
    });
  });

  test('SQLite: สร้างตารางใหม่ห่อด้วย PRAGMA/ทรานแซกชัน; ถ้าไม่ต้องสร้างใหม่ ไม่ห่อ', () {
    final a = base(Dialect.sqlite);
    final b = clone(a);
    tb(b, 'tu').columns.add(col('u9', 'phone', type: DataType.varchar, len: 20));
    final simple = mig(a, b);
    expect(simple, contains('ALTER TABLE "users" ADD COLUMN "phone" TEXT;'));
    expect(simple, isNot(contains('PRAGMA')));
    expect(simple, isNot(contains('__new')));

    cl(b, 'to', 'o3').notNull = false;
    final rebuilt = mig(a, b);
    expect(rebuilt, startsWith('PRAGMA foreign_keys = OFF;\nBEGIN TRANSACTION;'));
    expect(rebuilt, contains('CREATE TABLE "orders__new"'));
    expect(rebuilt, contains('DROP TABLE "orders";'));
    expect(rebuilt, contains('ALTER TABLE "orders__new" RENAME TO "orders";'));
    expect(rebuilt.trimRight(), endsWith('PRAGMA foreign_keys = ON;'));
  });
}
