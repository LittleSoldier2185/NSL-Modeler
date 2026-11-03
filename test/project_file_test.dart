import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/models/column_model.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/core/models/index_model.dart';
import 'package:nsl_modeler/core/models/note_model.dart';
import 'package:nsl_modeler/core/models/project.dart';
import 'package:nsl_modeler/core/models/relation_model.dart';
import 'package:nsl_modeler/core/models/table_model.dart';
import 'package:nsl_modeler/core/storage/project_file.dart';

Project sample() => Project(
      name: 'ร้านค้าออนไลน์',
      dialect: Dialect.postgres,
      tables: [
        TableModel(id: 't1', name: 'users', x: 36, y: 96, comment: 'ผู้ใช้', columns: [
          ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true, notNull: true, autoIncrement: true),
          ColumnModel(id: 'c2', name: 'email', type: DataType.varchar, length: 255, unique: true),
        ], indexes: [
          IndexModel(id: 'i1', name: 'idx_email', columnIds: ['c2'], unique: true),
        ]),
        TableModel(id: 't2', name: 'orders', columns: [
          ColumnModel(id: 'c3', name: 'user_id'),
          ColumnModel(id: 'c4', name: 'total', type: DataType.decimal, length: 10, scale: 2, defaultValue: '0'),
        ]),
      ],
      relations: [
        RelationModel(
            id: 'r1', fromTableId: 't2', fromColumnId: 'c3', toTableId: 't1', toColumnId: 'c1',
            onDelete: RefAction.cascade),
      ],
      notes: [NoteModel(id: 'n1', text: 'แก้ price', x: 10, y: 20)],
    );

void main() {
  test('encode -> decode ได้ข้อมูลเท่าเดิม', () {
    final a = ProjectFile.encode(sample());
    final b = ProjectFile.encode(ProjectFile.decode(a));
    expect(b, a);
  });

  test('คงภาษาไทยและค่า optional', () {
    final p = ProjectFile.decode(ProjectFile.encode(sample()));
    expect(p.name, 'ร้านค้าออนไลน์');
    expect(p.tables[0].comment, 'ผู้ใช้');
    expect(p.tables[1].columns[1].scale, 2);
    expect(p.relations.single.onDelete, RefAction.cascade);
    expect(p.dialect, Dialect.postgres);
  });

  test('ปฏิเสธไฟล์ที่ไม่ใช่ .erd', () {
    expect(() => ProjectFile.decode('{"a":1}'), throwsA(isA<ProjectFormatException>()));
    expect(() => ProjectFile.decode('not json'), throwsA(isA<ProjectFormatException>()));
  });

  test('ปฏิเสธเวอร์ชันใหม่กว่า', () {
    final j = ProjectFile.encode(sample()).replaceFirst('"version": 1', '"version": 99');
    expect(() => ProjectFile.decode(j), throwsA(isA<ProjectFormatException>()));
  });

  test('save/load ผ่านไฟล์จริง', () async {
    final dir = await Directory.systemTemp.createTemp('nsl');
    final path = '${dir.path}/x.erd';
    await ProjectFile.save(sample(), path);
    expect(File('$path.tmp').existsSync(), false);
    final p = await ProjectFile.load(path);
    expect(p.tables.length, 2);
    await dir.delete(recursive: true);
  });
}
