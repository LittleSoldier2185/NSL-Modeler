import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/codegen.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/index_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';

Project sample() => Project(name: 'shop', dialect: Dialect.postgres, tables: [
      TableModel(id: 't1', name: 'users', comment: 'ผู้ใช้', columns: [
        ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'c2', name: 'email', type: DataType.varchar, length: 120, unique: true, notNull: true),
        ColumnModel(id: 'c3', name: 'created_at', type: DataType.timestamp, defaultValue: 'CURRENT_TIMESTAMP'),
      ], indexes: [
        IndexModel(id: 'i1', name: 'idx_email', columnIds: ['c2'], unique: true),
      ]),
      TableModel(id: 't2', name: 'order_items', columns: [
        ColumnModel(id: 'c4', name: 'id', type: DataType.bigint, isPrimaryKey: true),
        ColumnModel(id: 'c5', name: 'user_id', notNull: true),
        ColumnModel(id: 'c6', name: 'price', type: DataType.decimal, length: 10, scale: 2, notNull: true, comment: 'ราคา'),
        ColumnModel(id: 'c7', name: 'active', type: DataType.boolean, defaultValue: 'true'),
      ]),
    ], relations: [
      RelationModel(
          id: 'r1', fromTableId: 't2', fromColumnId: 'c5', toTableId: 't1', toColumnId: 'c1', onDelete: RefAction.cascade),
    ]);

void main() {
  test('Dart: คลาสเอกพจน์ nullable และ fromJson/toJson', () {
    final s = generateCode(sample(), CodegenTarget.dart);
    expect(s, contains('class User {'));
    expect(s, contains('class OrderItem {'));
    expect(s, contains('required this.email,'));
    expect(s, contains('final DateTime? createdAt;'));
    expect(s, contains("email: json['email'] as String"));
    expect(s, contains("createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String)"));
    expect(s, contains("'created_at': createdAt?.toIso8601String(),"));
    expect(s, contains('final double price;'));
    expect(s, contains("price: (json['price'] as num).toDouble()"));
    expect(s, contains('/// ราคา'));
  });

  test('TypeScript: interface และ nullable', () {
    final s = generateCode(sample(), CodegenTarget.typescript);
    expect(s, contains('export interface User {'));
    expect(s, contains('email: string;'));
    expect(s, contains('createdAt?: Date | null;'));
    expect(s, contains('id: string;')); // bigint
    expect(s, contains('userId: number; // → users.id'));
  });

  test('Prisma: id/default/unique/relation/map', () {
    final s = generateCode(sample(), CodegenTarget.prisma);
    expect(s, contains('provider = "postgresql"'));
    expect(s, contains('model User {'));
    expect(s, contains('@id @default(autoincrement())'));
    expect(s, contains('@unique'));
    expect(s, contains('@default(now())'));
    expect(s, contains('@db.VarChar(120)'));
    expect(s, contains('@map("created_at")'));
    expect(s, contains('@relation(fields: [userId], references: [id], onDelete: Cascade)'));
    expect(s, contains('orderItems OrderItem[]'));
    expect(s, contains('@@unique([email], map: "idx_email")'));
    expect(s, contains('@@map("order_items")'));
    expect(s, contains('@default(true)'));
  });

  test('Prisma: FK สองเส้นไปตารางเดียวกันต้องตั้งชื่อ relation', () {
    final p = Project(tables: [
      TableModel(id: 'a', name: 'people', columns: [ColumnModel(id: 'a1', name: 'id', isPrimaryKey: true)]),
      TableModel(id: 'b', name: 'msgs', columns: [
        ColumnModel(id: 'b1', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'b2', name: 'sender_id', notNull: true),
        ColumnModel(id: 'b3', name: 'receiver_id', notNull: true),
      ]),
    ], relations: [
      RelationModel(id: 'r1', fromTableId: 'b', fromColumnId: 'b2', toTableId: 'a', toColumnId: 'a1'),
      RelationModel(id: 'r2', fromTableId: 'b', fromColumnId: 'b3', toTableId: 'a', toColumnId: 'a1'),
    ]);
    final s = generateCode(p, CodegenTarget.prisma);
    expect(s, contains('name: "Msg_senderId"'));
    expect(s, contains('name: "Msg_receiverId"'));
  });

  test('Prisma: คีย์หลักรวมใช้ @@id และตารางไม่มีคีย์ได้คำเตือน', () {
    final p = Project(tables: [
      TableModel(id: 'a', name: 'link', columns: [
        ColumnModel(id: 'a1', name: 'x', isPrimaryKey: true),
        ColumnModel(id: 'a2', name: 'y', isPrimaryKey: true),
      ]),
      TableModel(id: 'b', name: 'log', columns: [ColumnModel(id: 'b1', name: 'msg', type: DataType.text)]),
    ]);
    final s = generateCode(p, CodegenTarget.prisma);
    expect(s, contains('@@id([x, y])'));
    expect(s, contains('ยังไม่มีคีย์หลัก'));
  });

  test('Prisma: FK ชี้ตัวเอง (self-reference) ได้ชื่อ relation และ field ไม่ซ้ำ', () {
    final p = Project(tables: [
      TableModel(id: 'a', name: 'categories', columns: [
        ColumnModel(id: 'a1', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'a2', name: 'parent_id'),
      ]),
    ], relations: [
      RelationModel(id: 'r1', fromTableId: 'a', fromColumnId: 'a2', toTableId: 'a', toColumnId: 'a1'),
    ]);
    final s = generateCode(p, CodegenTarget.prisma);
    expect(s, contains('model Category {'));
    expect(s, contains('name: "Category_parentId"'));
    expect(s, contains('Category[] @relation("Category_parentId")'));
  });

  test('Java: Entity/Column/getter-setter และ keyword ไม่ชน', () {
    final p = sample();
    p.tables[0].columns.add(ColumnModel(id: 'c9', name: 'class'));
    final s = generateCode(p, CodegenTarget.java);
    expect(s, contains('@Entity'));
    expect(s, contains('@Table(name = "users")'));
    expect(s, contains('@GeneratedValue(strategy = GenerationType.IDENTITY)'));
    expect(s, contains('@Column(name = "email", nullable = false, unique = true, length = 120)'));
    expect(s, contains('private java.math.BigDecimal price;'));
    expect(s, contains('public int getId()'));
    expect(s, contains('class2'));
  });

  test('C#: attribute และชนิด nullable', () {
    final s = generateCode(sample(), CodegenTarget.csharp);
    expect(s, contains('[Table("users")]'));
    expect(s, contains('public class User'));
    expect(s, contains('[Key]'));
    expect(s, contains('[MaxLength(120)]'));
    expect(s, contains('public DateTime? CreatedAt { get; set; }'));
    expect(s, contains('[Column(TypeName = "decimal(10,2)")]'));
  });

  test('ชื่อไทยล้วนไม่ทำให้ล้ม และผลลัพธ์คงที่', () {
    final p = Project(tables: [
      TableModel(id: 'a', name: 'ลูกค้า', columns: [ColumnModel(id: 'a1', name: 'รหัส', isPrimaryKey: true)]),
    ]);
    for (final t in CodegenTarget.values) {
      final a = generateCode(p, t), b = generateCode(p, t);
      expect(a, b);
      expect(a, isNotEmpty);
    }
    expect(generateCode(p, CodegenTarget.dart), contains('class Entity'));
  });

  test('โปรเจกต์ว่างไม่ล้ม', () {
    for (final t in CodegenTarget.values) {
      expect(() => generateCode(Project(), t), returnsNormally);
    }
  });
}
