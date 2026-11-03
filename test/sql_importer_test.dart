import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/ddl/ddl_generator.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/index_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/core/parser/sql_importer.dart';
import 'package:nsl_modeler/core/parser/sql_lexer.dart';

TableModel tableOf(ImportResult r, String name) =>
    r.project.tables.firstWhere((t) => t.name.toLowerCase() == name.toLowerCase());

ColumnModel colOf(ImportResult r, String t, String c) =>
    tableOf(r, t).columns.firstWhere((x) => x.name.toLowerCase() == c.toLowerCase());

String fkText(Project p, RelationModel r) {
  final ft = p.tableById(r.fromTableId)!, tt = p.tableById(r.toTableId)!;
  return '${ft.name}.${ft.columnById(r.fromColumnId)!.name}->${tt.name}.${tt.columnById(r.toColumnId)!.name}'
      ' del=${r.onDelete.name} upd=${r.onUpdate.name}';
}

/// รูปร่างของ schema แบบไม่ผูกกับ id — ใช้เทียบก่อน/หลัง roundtrip
String shape(Project p, {bool types = true}) {
  final b = StringBuffer();
  for (final t in p.tables) {
    b.writeln('T ${t.name} "${t.comment}"');
    for (final c in t.columns) {
      var def = c.defaultValue;
      if (def != null) {
        final u = def.toUpperCase();
        if (c.type == DataType.boolean) {
          def = (u == 'TRUE' || u == '1') ? 'true' : 'false';
        } else {
          def = u == 'NOW()' ? 'CURRENT_TIMESTAMP' : def;
        }
      }
      // SQLite ไม่มีชนิด boolean: true/false กลับมาเป็น 1/0 (เทียบเฉพาะโหมดไม่เช็กชนิด)
      if (!types && def == 'true') def = '1';
      if (!types && def == 'false') def = '0';
      b.writeln('  C ${c.name} ${types ? '${c.type.name}(${c.length},${c.scale})' : ''} '
          'pk=${c.isPrimaryKey} nn=${c.notNull || c.isPrimaryKey} uq=${c.unique && !c.isPrimaryKey} '
          'ai=${c.autoIncrement} def=$def "${c.comment}"');
    }
    final idx = [
      for (final i in t.indexes)
        '${i.name}(${i.columnIds.map((id) => t.columnById(id)!.name).join(',')})${i.unique ? ' unique' : ''}'
    ]..sort();
    for (final i in idx) {
      b.writeln('  I $i');
    }
  }
  final fks = [for (final r in p.relations) fkText(p, r)]..sort();
  for (final f in fks) {
    b.writeln('F $f');
  }
  return b.toString();
}

Project rich({bool timestamps = true, bool json = true}) {
  ColumnModel c(String id, String name,
          {DataType type = DataType.integer,
          bool pk = false,
          bool nn = false,
          bool uq = false,
          bool ai = false,
          int? len,
          int? scale,
          String? def,
          String comment = ''}) =>
      ColumnModel(
          id: id,
          name: name,
          type: type,
          isPrimaryKey: pk,
          notNull: nn,
          unique: uq,
          autoIncrement: ai,
          length: len,
          scale: scale,
          defaultValue: def,
          comment: comment);

  return Project(name: 'shop', tables: [
    TableModel(id: 'tu', name: 'users', comment: "ผู้ใช้ระบบ's", columns: [
      c('u1', 'id', pk: true, ai: true),
      c('u2', 'email', type: DataType.varchar, len: 255, nn: true, uq: true),
      c('u3', 'created_at', type: DataType.datetime, nn: true, def: 'CURRENT_TIMESTAMP'),
      c('u4', 'active', type: DataType.boolean, nn: true, def: 'true'),
      c('u5', 'bio', type: DataType.text, comment: 'ประวัติ'),
      if (timestamps) c('u6', 'updated_at', type: DataType.timestamp),
    ]),
    TableModel(id: 'tc', name: 'coupons', columns: [
      c('c1', 'id', pk: true, ai: true),
      c('c2', 'code', type: DataType.varchar, len: 50, uq: true),
    ]),
    TableModel(id: 'tp', name: 'products', columns: [
      c('p1', 'id', type: DataType.uuid, pk: true),
      c('p2', 'name', type: DataType.varchar, len: 120, nn: true),
      c('p3', 'price', type: DataType.decimal, len: 10, scale: 2, def: '0'),
      c('p4', 'weight', type: DataType.float),
      c('p5', 'thumb', type: DataType.blob),
      c('p6', 'stock', type: DataType.smallint, def: '0'),
      c('p7', 'released', type: DataType.date),
      if (json) c('p8', 'meta', type: DataType.json),
    ]),
    TableModel(id: 'to', name: 'orders', columns: [
      c('o1', 'id', type: DataType.bigint, pk: true, ai: true),
      c('o2', 'user_id', nn: true),
      c('o3', 'status', type: DataType.varchar, len: 20, nn: true, def: 'pending'),
      c('o4', 'total', type: DataType.decimal, len: 12, scale: 2, nn: true),
      c('o5', 'note', type: DataType.varchar, len: 200, def: "it's ok"),
      c('o6', 'coupon_id'),
    ], indexes: [
      IndexModel(id: 'i1', name: 'idx_orders_user', columnIds: ['o2']),
      IndexModel(id: 'i2', name: 'ux_orders_user_status', columnIds: ['o2', 'o3'], unique: true),
    ]),
    TableModel(id: 'ti', name: 'order_items', columns: [
      c('i1', 'order_id', type: DataType.bigint, pk: true),
      c('i2', 'product_id', type: DataType.uuid, pk: true),
      c('i3', 'qty', nn: true, def: '1'),
    ]),
  ], relations: [
    RelationModel(
        id: 'r1',
        fromTableId: 'to',
        fromColumnId: 'o2',
        toTableId: 'tu',
        toColumnId: 'u1',
        onDelete: RefAction.cascade,
        onUpdate: RefAction.restrict),
    RelationModel(
        id: 'r2',
        fromTableId: 'to',
        fromColumnId: 'o6',
        toTableId: 'tc',
        toColumnId: 'c1',
        onDelete: RefAction.setNull),
    RelationModel(
        id: 'r3', fromTableId: 'ti', fromColumnId: 'i1', toTableId: 'to', toColumnId: 'o1', onDelete: RefAction.cascade),
    RelationModel(id: 'r4', fromTableId: 'ti', fromColumnId: 'i2', toTableId: 'tp', toColumnId: 'p1'),
  ]);
}

void main() {
  group('lexer', () {
    test('quote ทั้งสี่แบบ + สตริง + คอมเมนต์', () {
      final r = lexSql("`a` \"b\" [c] 'd' N'e' -- x\n/* y */ f 12.5");
      expect(r.error, isNull);
      expect(r.tokens.map((t) => '${t.kind.name}:${t.text}').toList(),
          ['ident:a', 'ident:b', 'ident:c', 'string:d', 'string:e', 'word:f', 'number:12.5']);
    });

    test("escape: '' , \"\" , ]] และ backslash (เฉพาะ MySQL)", () {
      expect(lexSql("'it''s'").tokens.single.text, "it's");
      expect(lexSql('"a""b"').tokens.single.text, 'a"b');
      expect(lexSql('[a]]b]').tokens.single.text, 'a]b');
      expect(lexSql(r"'a\'b'", backslashEscapes: true).tokens.single.text, "a'b");
      expect(lexSql(r"'C:\'").tokens.single.text, r'C:\'); // มาตรฐาน: \ เป็นตัวอักษรธรรมดา
    });

    test('text[] ไม่ใช่ชื่อที่ quote', () {
      final k = lexSql('text[]').tokens.map((t) => t.kind).toList();
      expect(k, [Tk.word, Tk.symbol, Tk.symbol]);
    });

    test('นับบรรทัดและรายงาน error ของสตริง/คอมเมนต์ที่ไม่ปิด', () {
      final r = lexSql("a\nb 'oops\n c");
      expect(r.error, isNotNull);
      expect(r.errorLine, 2);
      expect(r.tokens.map((t) => t.text), ['a', 'b']);
      expect(lexSql('x /* ไม่ปิด').error, isNotNull);
    });

    test(':: เป็น token เดียว และภาษาไทยเป็นส่วนของคำได้', () {
      expect(lexSql("'x'::text").tokens.map((t) => t.text), ['x', '::', 'text']);
      expect(lexSql('ผู้ใช้').tokens.single.kind, Tk.word);
    });
  });

  group('detectDialect', () {
    test('เดาจากรูปแบบ', () {
      expect(detectDialect('CREATE TABLE `a` (`id` INT AUTO_INCREMENT) ENGINE=InnoDB;'), Dialect.mysql);
      expect(detectDialect('CREATE TABLE a (id SERIAL, n text, d x::int);'), Dialect.postgres);
      expect(detectDialect('CREATE TABLE a (id INTEGER PRIMARY KEY AUTOINCREMENT);'), Dialect.sqlite);
      expect(detectDialect('CREATE TABLE [a] ([id] INT IDENTITY(1,1))\nGO\n'), Dialect.mssql);
      expect(detectDialect('select 1'), Dialect.mysql); // ไม่มีเบาะแส
    });
  });

  group('roundtrip: สร้าง SQL แล้ว import กลับได้ schema เดิม', () {
    for (final d in [Dialect.mysql, Dialect.postgres, Dialect.mssql]) {
      test(d.label, () {
        final original = rich(timestamps: d != Dialect.mssql, json: d != Dialect.mssql)..dialect = d;
        final sql = DdlGenerator.forDialect(d).generate(original);
        final r = importSql(sql, name: 'shop', dialect: d);
        expect(r.notes.where((n) => n.warning), isEmpty, reason: r.notes.join('\n'));
        expect(shape(r.project), shape(original));
        expect(detectDialect(sql), d);
      });
    }

    test('SQLite (ชนิดข้อมูลสูญเสียได้ตามธรรมชาติของ SQLite — เทียบโครงสร้าง)', () {
      final original = rich(timestamps: false, json: false)..dialect = Dialect.sqlite;
      final sql = DdlGenerator.forDialect(Dialect.sqlite).generate(original);
      final r = importSql(sql, name: 'shop', dialect: Dialect.sqlite);
      expect(r.notes.where((n) => n.warning), isEmpty, reason: r.notes.join('\n'));
      expect(shape(r.project, types: false).replaceAll(RegExp(r' "[^"\n]*"$', multiLine: true), ''),
          shape(original, types: false).replaceAll(RegExp(r' "[^"\n]*"$', multiLine: true), ''));
    });

    test('import ซ้ำ -> export ซ้ำ ได้ SQL เดิม (เสถียร)', () {
      for (final d in [Dialect.mysql, Dialect.postgres, Dialect.mssql]) {
        final original = rich(timestamps: d != Dialect.mssql, json: d != Dialect.mssql)..dialect = d;
        final gen = DdlGenerator.forDialect(d);
        final sql1 = gen.generate(original);
        final back = importSql(sql1, name: 'shop', dialect: d).project;
        expect(gen.generate(back), sql1, reason: d.label);
      }
    });
  });

  group('ไฟล์ dump จริง', () {
    test('mysqldump', () {
      const sql = r'''
-- MySQL dump 10.13
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!50503 SET NAMES utf8mb4 */;

DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'อีเมล\'ผู้ใช้',
  `active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `balance` decimal(10,2) NOT NULL DEFAULT '0.00',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_email` (`email`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='ตารางผู้ใช้';

LOCK TABLES `users` WRITE;
INSERT INTO `users` VALUES (1,'a@x.com',1,NULL,'0.00'),(2,'b@x.com',0,NULL,'5.50');
UNLOCK TABLES;

CREATE TABLE `orders` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` int unsigned NOT NULL,
  `status` enum('new','paid') NOT NULL DEFAULT 'new',
  PRIMARY KEY (`id`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `orders_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB;
''';
      final r = importSql(sql, name: 'dump');
      expect(r.detected, Dialect.mysql);
      expect(r.project.tables.map((t) => t.name), ['users', 'orders']);

      final users = tableOf(r, 'users');
      expect(users.comment, 'ตารางผู้ใช้');
      final id = colOf(r, 'users', 'id');
      expect([id.type, id.isPrimaryKey, id.autoIncrement, id.notNull], [DataType.integer, true, true, true]);
      final email = colOf(r, 'users', 'email');
      expect([email.type, email.length, email.notNull], [DataType.varchar, 255, true]);
      expect(email.comment, "อีเมล'ผู้ใช้");
      expect(email.unique, true); // UNIQUE KEY คอลัมน์เดียว -> unique ที่คอลัมน์
      expect(colOf(r, 'users', 'active').type, DataType.boolean);
      expect(colOf(r, 'users', 'active').defaultValue, '1');
      expect(colOf(r, 'users', 'created_at').defaultValue, 'CURRENT_TIMESTAMP');
      expect(colOf(r, 'users', 'balance').scale, 2);
      expect(users.indexes.single.name, 'idx_created');

      expect(colOf(r, 'orders', 'id').type, DataType.bigint);
      expect(colOf(r, 'orders', 'status').type, DataType.text); // enum -> text (มีหมายเหตุ)
      expect(r.notes.any((n) => n.message.contains('ENUM') || n.message.contains('enum')), true);
      expect(fkText(r.project, r.project.relations.single), 'orders.user_id->users.id del=cascade upd=noAction');
      // INSERT/LOCK/DROP ถูกข้ามและรวมเป็นยอด ไม่ใช่เตือนทีละคำสั่ง
      expect(r.notes.any((n) => !n.warning && n.message.contains('INSERT')), true);
    });

    test('pg_dump', () {
      const sql = '''
SET statement_timeout = 0;
CREATE TABLE public.users (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone,
    tags text[]
);
CREATE SEQUENCE public.users_id_seq START WITH 1 INCREMENT BY 1;
ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);
CREATE TABLE public.orders (
    id integer NOT NULL,
    user_id integer NOT NULL
);
ALTER TABLE ONLY public.users ADD CONSTRAINT users_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.users ADD CONSTRAINT users_email_key UNIQUE (email);
ALTER TABLE ONLY public.orders ADD CONSTRAINT orders_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_fk FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
CREATE INDEX idx_orders_user ON public.orders USING btree (user_id);
CREATE INDEX idx_lower_email ON public.users USING btree (lower((email)::text));
COMMENT ON TABLE public.users IS 'ผู้ใช้';
COMMENT ON COLUMN public.users.email IS 'อีเมล';
''';
      final r = importSql(sql, name: 'pg');
      expect(r.detected, Dialect.postgres);
      expect(colOf(r, 'users', 'id').isPrimaryKey, true); // จาก ALTER ... ADD CONSTRAINT PRIMARY KEY
      expect(colOf(r, 'users', 'id').notNull, true);
      expect(colOf(r, 'users', 'email').unique, true);
      expect(colOf(r, 'users', 'status').defaultValue, 'pending'); // ตัด ::character varying
      expect(colOf(r, 'users', 'created').type, DataType.datetime); // timestamp without time zone
      expect(colOf(r, 'users', 'created').defaultValue, 'now()');
      expect(colOf(r, 'users', 'updated').type, DataType.timestamp); // with time zone
      expect(colOf(r, 'users', 'tags').type, DataType.text);
      expect(tableOf(r, 'users').comment, 'ผู้ใช้');
      expect(colOf(r, 'users', 'email').comment, 'อีเมล');
      expect(fkText(r.project, r.project.relations.single), 'orders.user_id->users.id del=setNull upd=noAction');
      expect(tableOf(r, 'orders').indexes.single.name, 'idx_orders_user');
      // index แบบ expression ถูกข้ามพร้อมแจ้ง ไม่ทำให้พัง
      expect(tableOf(r, 'users').indexes, isEmpty);
      expect(r.notes.any((n) => n.message.contains('idx_lower_email') || n.message.contains('expression')), true);
    });

    test('pg: nextval default กลายเป็น AUTO INCREMENT', () {
      const sql = "CREATE TABLE t (id integer DEFAULT nextval('t_id_seq'::regclass) NOT NULL, PRIMARY KEY (id));";
      final r = importSql(sql);
      final id = colOf(r, 't', 'id');
      expect([id.autoIncrement, id.defaultValue, id.isPrimaryKey], [true, null, true]);
    });

    test('SSMS script (WITH CHECK ADD, CLUSTERED, GO)', () {
      const sql = '''
/****** Object:  Table [dbo].[Users]    Script Date: 1/1/2026 ******/
SET ANSI_NULLS ON
GO
CREATE TABLE [dbo].[Users](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[Email] [nvarchar](255) NOT NULL,
	[Bio] [nvarchar](max) NULL,
	[Active] [bit] NOT NULL CONSTRAINT [DF_Users_Active] DEFAULT ((1)),
 CONSTRAINT [PK_Users] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
CREATE TABLE [dbo].[Orders](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[UserId] [int] NOT NULL,
 CONSTRAINT [PK_Orders] PRIMARY KEY CLUSTERED ([Id] ASC)
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[Orders]  WITH CHECK ADD  CONSTRAINT [FK_Orders_Users] FOREIGN KEY([UserId])
REFERENCES [dbo].[Users] ([Id])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[Orders] CHECK CONSTRAINT [FK_Orders_Users]
GO
CREATE NONCLUSTERED INDEX [IX_Orders_UserId] ON [dbo].[Orders] ([UserId] ASC)
GO
''';
      final r = importSql(sql, name: 'ms');
      expect(r.detected, Dialect.mssql);
      expect(r.project.tables.map((t) => t.name), ['Users', 'Orders']);
      final id = colOf(r, 'Users', 'Id');
      expect([id.autoIncrement, id.isPrimaryKey, id.type], [true, true, DataType.integer]);
      expect(colOf(r, 'Users', 'Bio').type, DataType.text); // nvarchar(max)
      expect(colOf(r, 'Users', 'Active').type, DataType.boolean);
      expect(colOf(r, 'Users', 'Active').defaultValue, '1'); // ((1)) ถอดวงเล็บ
      expect(fkText(r.project, r.project.relations.single), 'Orders.UserId->Users.Id del=cascade upd=noAction');
      expect(tableOf(r, 'Orders').indexes.single.name, 'IX_Orders_UserId');
    });

    test('SQLite', () {
      const sql = '''
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  score REAL DEFAULT 0
);
CREATE TABLE posts (
  id INTEGER NOT NULL,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (id AUTOINCREMENT)
);
''';
      final r = importSql(sql);
      expect(r.detected, Dialect.sqlite);
      expect(colOf(r, 'users', 'id').autoIncrement, true);
      expect(colOf(r, 'users', 'score').type, DataType.float);
      expect(colOf(r, 'posts', 'id').autoIncrement, true);
      expect(fkText(r.project, r.project.relations.single), 'posts.user_id->users.id del=cascade upd=noAction');
    });
  });

  group('ความทนทาน', () {
    test('คำสั่งเสียหนึ่งคำสั่งไม่ทำให้ตารางอื่นหาย', () {
      const sql = '''
CREATE TABLE a (id INT PRIMARY KEY);
CREATE TABLE broken (id INT, name VARCHAR(10;
CREATE TABLE b (id INT PRIMARY KEY);
''';
      final r = importSql(sql);
      expect(r.project.tables.map((t) => t.name).toSet().containsAll(['a']), true);
      expect(r.notes.where((n) => n.warning), isNotEmpty);
    });

    test('สตริงไม่ปิดท้ายไฟล์: เก็บตารางก่อนหน้าไว้ และแจ้งบรรทัด', () {
      final r = importSql("CREATE TABLE a (id INT);\nINSERT INTO a VALUES ('oops");
      expect(r.project.tables.single.name, 'a');
      final n = r.notes.firstWhere((n) => n.message.contains('สตริงไม่ปิด'));
      expect(n.line, 2);
    });

    test('ตารางซ้ำ ใช้ตัวแรกและแจ้ง', () {
      final r = importSql('CREATE TABLE a (x INT); CREATE TABLE A (y INT);');
      expect(r.project.tables.length, 1);
      expect(r.project.tables.single.columns.single.name, 'x');
      expect(r.notes.any((n) => n.message.contains('ซ้ำ')), true);
    });

    test('FK ชี้ตารางที่ไม่มีในไฟล์ถูกข้ามพร้อมแจ้ง', () {
      final r = importSql('CREATE TABLE a (id INT, b_id INT, FOREIGN KEY (b_id) REFERENCES missing(id));');
      expect(r.project.relations, isEmpty);
      expect(r.notes.any((n) => n.message.contains('missing')), true);
    });

    test('REFERENCES โดยไม่ระบุคอลัมน์ = ชี้ไปที่ PK', () {
      final r = importSql('CREATE TABLE p (id INT PRIMARY KEY); CREATE TABLE c (pid INT REFERENCES p);');
      expect(fkText(r.project, r.project.relations.single), 'c.pid->p.id del=noAction upd=noAction');
    });

    test('REFERENCES ตามด้วย NOT NULL ไม่ถูกกลืน', () {
      final r = importSql('CREATE TABLE p (id INT PRIMARY KEY); CREATE TABLE c (pid INT REFERENCES p(id) NOT NULL);');
      expect(colOf(r, 'c', 'pid').notNull, true);
    });

    test('FK หลายคอลัมน์ แยกเป็นทีละคู่และแจ้ง', () {
      final r = importSql('''
CREATE TABLE p (a INT, b INT, PRIMARY KEY (a, b));
CREATE TABLE c (x INT, y INT, FOREIGN KEY (x, y) REFERENCES p (a, b));
''');
      expect(r.project.relations.length, 2);
      expect(r.notes.any((n) => n.message.contains('หลายคอลัมน์')), true);
    });

    test('UNIQUE หลายคอลัมน์กลายเป็น unique index', () {
      final r = importSql('CREATE TABLE t (a INT, b INT, UNIQUE (a, b));');
      final i = tableOf(r, 't').indexes.single;
      expect([i.unique, i.columnIds.length], [true, 2]);
    });

    test('CREATE UNIQUE INDEX / index แบบ prefix length', () {
      final r = importSql('''
CREATE TABLE t (a VARCHAR(100), b INT);
CREATE UNIQUE INDEX ux_ab ON t (a(10), b DESC);
''');
      final i = tableOf(r, 't').indexes.single;
      expect([i.name, i.unique, i.columnIds.length], ['ux_ab', true, 2]);
    });

    test('ไม่มี ; ระหว่างคำสั่ง (แยกด้วยคำสั่งใหม่ต้นบรรทัด)', () {
      final r = importSql('CREATE TABLE a (id INT)\nCREATE TABLE b (id INT)\nCREATE INDEX ix ON a (id)');
      expect(r.project.tables.length, 2);
      expect(tableOf(r, 'a').indexes.single.name, 'ix');
    });

    test('ชื่อภาษาไทย ทั้ง quote และมีช่องว่าง', () {
      final r = importSql('CREATE TABLE `ลูกค้า` (`รหัส ลูกค้า` INT PRIMARY KEY, ชื่อ VARCHAR(50));');
      expect(r.project.tables.single.name, 'ลูกค้า');
      expect(r.project.tables.single.columns.map((c) => c.name), ['รหัส ลูกค้า', 'ชื่อ']);
    });

    test('ชนิดที่ไม่รู้จักเป็น TEXT พร้อมแจ้ง', () {
      final r = importSql('CREATE TABLE t (a GEOMETRY);');
      expect(colOf(r, 't', 'a').type, DataType.text);
      expect(r.notes.any((n) => n.message.contains('GEOMETRY')), true);
    });

    test('CREATE VIEW / TRIGGER / INSERT ถูกข้ามโดยไม่พัง', () {
      final r = importSql('''
CREATE TABLE a (id INT);
CREATE VIEW v AS SELECT * FROM a;
INSERT INTO a VALUES (1);
INSERT INTO a VALUES (2);
''');
      expect(r.project.tables.length, 1);
      expect(r.notes.firstWhere((n) => n.message.contains('INSERT')).message, contains('2'));
    });

    test('ไฟล์ว่าง / มีแต่คอมเมนต์', () {
      expect(importSql('').project.tables, isEmpty);
      expect(importSql('-- hello\n/* x */').project.tables, isEmpty);
    });

    test('ตารางที่ import ได้ตำแหน่งไม่ทับกัน (จัด layout ให้)', () {
      final r = importSql('''
CREATE TABLE a (id INT PRIMARY KEY);
CREATE TABLE b (id INT PRIMARY KEY, a_id INT REFERENCES a(id));
CREATE TABLE c (id INT PRIMARY KEY);
''');
      final pos = r.project.tables.map((t) => (t.x, t.y)).toSet();
      expect(pos.length, 3);
      expect(tableOf(r, 'a').x, lessThan(tableOf(r, 'b').x));
    });

    test('DEFAULT หลายแบบ', () {
      final r = importSql(r'''
CREATE TABLE t (
  a INT DEFAULT -5,
  b VARCHAR(10) DEFAULT 'x y',
  c VARCHAR(36) DEFAULT (uuid()),
  d INT DEFAULT NULL,
  e INT DEFAULT ((0)),
  f DATETIME DEFAULT CURRENT_TIMESTAMP(6),
  g BOOLEAN DEFAULT TRUE
);''');
      String? d(String c) => colOf(r, 't', c).defaultValue;
      expect(d('a'), '-5');
      expect(d('b'), 'x y');
      expect(d('c'), 'uuid()');
      expect(d('d'), isNull);
      expect(d('e'), '0');
      expect(d('f'), 'CURRENT_TIMESTAMP(6)');
      expect(d('g'), 'TRUE');
    });
  });
}
