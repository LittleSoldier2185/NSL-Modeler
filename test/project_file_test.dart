import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/index_model.dart';
import 'package:nsl_dev/core/models/note_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/core/storage/project_file.dart';

import 'support/project_helpers.dart';

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
  extensionTests();
  test('encode -> decode ได้ข้อมูลเท่าเดิม', () {
    final a = ProjectFile.encode(Workspace.single(sample()));
    final b = ProjectFile.encode(ProjectFile.decode(a));
    expect(b, a);
  });

  test('คงภาษาไทยและค่า optional', () {
    final p = roundTripEr(sample());
    expect(p.name, 'ร้านค้าออนไลน์');
    expect(p.tables[0].comment, 'ผู้ใช้');
    expect(p.tables[1].columns[1].scale, 2);
    expect(p.relations.single.onDelete, RefAction.cascade);
    expect(p.dialect, Dialect.postgres);
  });

  test('ปฏิเสธไฟล์ที่ไม่ใช่ไฟล์โปรเจกต์', () {
    expect(() => ProjectFile.decode('{"a":1}'), throwsA(isA<ProjectFormatException>()));
    expect(() => ProjectFile.decode('not json'), throwsA(isA<ProjectFormatException>()));
  });

  test('ปฏิเสธเวอร์ชันใหม่กว่า', () {
    final j = ProjectFile.encode(Workspace.single(sample())).replaceFirst('"version": 3', '"version": 99');
    expect(j, contains('"version": 99'));
    expect(() => ProjectFile.decode(j), throwsA(isA<ProjectFormatException>()));
  });

  test('save/load ผ่านไฟล์จริง', () async {
    final dir = await Directory.systemTemp.createTemp('nsl');
    final path = '${dir.path}/x.nsld';
    await ProjectFile.save(Workspace.single(sample()), path);
    expect(File('$path.tmp').existsSync(), false);
    final p = await ProjectFile.load(path);
    expect(erOf(p).tables.length, 2);
    await dir.delete(recursive: true);
  });
}

void extensionTests() {
  group('สกุลไฟล์ .nsld', () {
    test('withProjectExt: ต่อ .nsld , เปลี่ยน .erd เป็น .nsld , ของเดิมคงไว้ , ไม่สนตัวพิมพ์', () {
      expect(withProjectExt(r'C:\งาน\shop'), r'C:\งาน\shop.nsld');
      expect(withProjectExt(r'C:\งาน\shop.nsld'), r'C:\งาน\shop.nsld');
      expect(withProjectExt(r'C:\งาน\shop.NSLD'), r'C:\งาน\shop.NSLD');
      expect(withProjectExt(r'C:\งาน\shop.erd'), r'C:\งาน\shop.nsld');
      expect(withProjectExt(r'C:\งาน\shop.nslm'), r'C:\งาน\shop.nsld');
      expect(withProjectExt(r'C:\งาน\shop.ERD'), r'C:\งาน\shop.nsld');
      expect(withProjectExt(r'C:\งาน\shop.sql'), r'C:\งาน\shop.sql.nsld');
    });

    test('isLegacyProjectPath และสกุลที่เปิดได้', () {
      expect(isLegacyProjectPath('a.erd'), true);
      expect(isLegacyProjectPath('a.nslm'), true);
      expect(isLegacyProjectPath('a.nsld'), false);
      expect(kOpenableExts, ['nsld', 'nslm', 'erd']);
    });

    test('ไฟล์ .nslm/.erd เก่า (v1/v2) เปิดได้ แล้ว "บันทึกเป็น" ได้ .nsld v3 (ไฟล์เดิมไม่ถูกแตะ)', () async {
      final dir = await Directory.systemTemp.createTemp('nsl');
      addTearDown(() => dir.delete(recursive: true));
      for (final (src, ext) in [('v1_er_only.nslm', 'nslm'), ('v2_er_dfd.nsld', 'erd')]) {
        final old = '${dir.path}/old_$ext.$ext';
        final original = File('test/fixtures/$src').readAsStringSync();
        await File(old).writeAsString(original);
        expect(isLegacyProjectPath(old), true);
        final w = await ProjectFile.load(old);
        final out = withProjectExt(old);
        await ProjectFile.save(w, out);
        expect(out.endsWith('old_$ext.nsld'), true);
        expect(File(old).readAsStringSync(), original); // ไฟล์เดิมไม่ถูกแตะ
        final text = File(out).readAsStringSync();
        expect((jsonDecode(text) as Map)['version'], 3);
        final back = await ProjectFile.load(out);
        expect(encodeProjectMap(back), encodeProjectMap(w));
        expect(erOf(back).tables.length, 2);
      }
    });
  });
}
