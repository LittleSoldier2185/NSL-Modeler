import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/html_doc_export.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/diagram.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/index_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';

Project sample() => Project(name: 'ร้าน <A&B>', dialect: Dialect.mysql, tables: [
      TableModel(id: 't1', name: 'users', comment: 'ผู้ใช้\nระบบ', x: 20, y: 20, columns: [
        ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'c2', name: 'email', type: DataType.varchar, length: 120, unique: true, comment: 'a<b>'),
      ], indexes: [
        IndexModel(id: 'i1', name: 'idx_email', columnIds: ['c2'], unique: true),
      ]),
      TableModel(id: 't2', name: 'orders', x: 400, y: 20, columns: [
        ColumnModel(id: 'c3', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'c4', name: 'user_id'),
      ]),
    ], relations: [
      RelationModel(id: 'r1', fromTableId: 't2', fromColumnId: 'c4', toTableId: 't1', toColumnId: 'c1', onDelete: RefAction.cascade),
    ]);

void main() {
  test('เอกสาร HTML: โครง สารบัญ ตาราง FK และ SVG ฝัง', () {
    final h = exportHtmlDocument(Workspace.fromLegacy(sample()));
    expect(h, startsWith('<!DOCTYPE html>'));
    expect(h, contains('<meta charset="utf-8">'));
    expect(h, contains('id="er-diagram"'));
    expect(h, contains('<svg'));
    expect(h, isNot(contains('<?xml')));
    expect(h, contains('viewBox'));
    expect(h, contains('href="#t-t1"'));
    expect(h, contains('id="t-t2"'));
    expect(h, contains('ON DELETE CASCADE'));
    expect(h, contains('idx_email'));
    expect(h, contains('<span class="tag pk">PK</span>'));
    expect(h, contains('<span class="tag fk">FK</span>'));
    expect(h, contains('@media print'));
    expect(h, isNot(contains('<script')));
  });

  test('ข้อความของผู้ใช้ถูก escape (ชื่อโปรเจกต์ หมายเหตุ)', () {
    final h = exportHtmlDocument(Workspace.fromLegacy(sample()));
    expect(h, contains('ร้าน &lt;A&amp;B&gt;'));
    expect(h, contains('a&lt;b&gt;'));
    expect(h, isNot(contains('<A&B>')));
    expect(h, contains('ผู้ใช้<br>ระบบ'));
  });

  test('includeDiagrams=false ไม่ฝังภาพ ; ผลลัพธ์คงที่', () {
    final p = sample();
    final h = exportHtmlDocument(Workspace.fromLegacy(p), includeDiagrams: false);
    expect(h, isNot(contains('<svg')));
    expect(h, isNot(contains('er-diagram')));
    expect(exportHtmlDocument(Workspace.fromLegacy(p)), exportHtmlDocument(Workspace.fromLegacy(p)));
  });

  test('โปรเจกต์ว่างไม่ล้ม', () {
    final h = exportHtmlDocument(Workspace.fromLegacy(Project()));
    expect(h, contains('</html>'));
  });

  test('มีแท็บ DFD ที่มีวัตถุ → ฝังภาพ DFD ด้วย', () {
    final p = sample();
    final tab = DiagramTab(id: 'd1', name: 'Level 0', kind: DiagramKind.dfd);
    p.diagrams.add(tab);
    p.dfd[tab.id] = DfdDiagram(nodes: [
      DfdNode(id: 'n1', kind: DfdKind.process, name: 'ชำระเงิน', x: 100, y: 100),
    ]);
    final h = exportHtmlDocument(Workspace.fromLegacy(p));
    expect(h, contains('id="dfd-d1"'));
    expect(h, contains('DFD: Level 0'));
    expect(RegExp('<svg').allMatches(h).length, 2);
  });
}
