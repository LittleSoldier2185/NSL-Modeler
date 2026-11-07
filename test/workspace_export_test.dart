import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/html_doc_export.dart';
import 'package:nsl_dev/core/export/markdown_export.dart';
import 'package:nsl_dev/core/export/sql_export.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/ui/export/text_export_dialog.dart';

final _thai = RegExp(r'[฀-๿]');

Project _er(String name, Dialect d, {String tableName = 'users'}) => Project(name: name, dialect: d, tables: [
      TableModel(id: 't1', name: tableName, comment: 'a|b <x> & "q"', x: 20, y: 20, columns: [
        ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'c2', name: 'note', type: DataType.varchar, length: 50, comment: 'p|q\nline2 <b>'),
      ]),
      TableModel(id: 't2', name: 'orders', x: 300, y: 20, columns: [
        ColumnModel(id: 'c3', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'c4', name: 'user_id'),
      ]),
    ], relations: [
      RelationModel(id: 'r1', fromTableId: 't2', fromColumnId: 'c4', toTableId: 't1', toColumnId: 'c1', onDelete: RefAction.cascade),
    ]);

/// ER 2 อัน (MySQL + PostgreSQL) + DFD 2 อัน (หนึ่งมีวัตถุ+เส้น+ error, หนึ่งว่าง)
Workspace _ws() => Workspace(name: 'โปรเจกต์ <A&B>', documents: [
      ProjectDocument.er(id: 'er', name: 'ER หลัก', content: _er('main', Dialect.mysql)),
      ProjectDocument.dfd(
        id: 'd1',
        name: 'Level 0 | <ระบบ>',
        content: DfdDiagram(nodes: [
          DfdNode(id: 'n1', kind: DfdKind.entity, name: 'ลูกค้า', x: 0, y: 0),
          DfdNode(id: 'n2', kind: DfdKind.process, name: 'ชำระ <เงิน>', number: '1.0', x: 300, y: 0, childId: 'd2'),
          DfdNode(id: 'n3', kind: DfdKind.store, name: 'ผู้ใช้', number: 'D1', x: 600, y: 0, tableId: 't1', tableDocId: 'er2'),
        ], flows: [
          DfdFlow(id: 'f1', fromId: 'n1', toId: 'n2', label: 'คำสั่ง|ซื้อ'),
          DfdFlow(id: 'f2', fromId: 'n2', toId: 'n3', label: 'บันทึก', bidirectional: true),
          DfdFlow(id: 'f3', fromId: 'n1', toId: 'n3', label: 'ตรง'), // entity -> store = error
        ]),
      ),
      ProjectDocument.er(id: 'er2', name: 'ER ที่สอง', content: _er('second', Dialect.postgres, tableName: 'customers')),
      ProjectDocument.dfd(id: 'd2', name: 'ว่าง', content: DfdDiagram()),
    ]);

void main() {
  tearDown(() => currentLang = Lang.th);

  group('Markdown ทั้งโปรเจกต์', () {
    test('ER เดียวไม่มีเอกสารอื่น = เหมือน exportDataDictionary ทุกตัวอักษร', () {
      final p = _er('shop', Dialect.mysql);
      expect(exportWorkspaceDictionary(Workspace.single(p)), exportDataDictionary(p));
    });

    test('ภาพรวม + ER ทุกอันพร้อม dialect + DFD ทุกอัน ตามลำดับ', () {
      final m = exportWorkspaceDictionary(_ws());
      expect(m, startsWith('# โปรเจกต์ <A&B> — Data Dictionary'));
      final iOverview = m.indexOf('## ภาพรวมโปรเจกต์');
      final iEr1 = m.indexOf('## ER: ER หลัก');
      final iEr2 = m.indexOf('## ER: ER ที่สอง');
      final iD1 = m.indexOf('## DFD: Level 0');
      final iD2 = m.indexOf('## DFD: ว่าง');
      expect([iOverview, iEr1, iEr2, iD1, iD2].every((i) => i >= 0), isTrue);
      expect(iOverview < iEr1 && iEr1 < iEr2 && iEr2 < iD1 && iD1 < iD2, isTrue, reason: m);
      expect(m, contains('- 4 เอกสาร (2 ER · 2 DFD)'));
      expect(m, contains('- 4 ตาราง · 2 ความสัมพันธ์'));
      expect(m, contains('- 3 วัตถุ DFD · 3 เส้นข้อมูล'));
      expect(m, contains('- Dialect: MySQL / MariaDB'));
      expect(m, contains('- Dialect: PostgreSQL'));
      expect(m, contains('### users'));
      expect(m, contains('### customers'));
      expect(m, contains('ON DELETE CASCADE'));
    });

    test('ปัญหาทั้งโปรเจกต์อยู่ในภาพรวมและใต้ DFD ที่เป็นต้นเหตุ', () {
      final m = exportWorkspaceDictionary(_ws());
      final overview = m.substring(m.indexOf('## ภาพรวมโปรเจกต์'), m.indexOf('## ER: ER หลัก'));
      expect(overview, contains('ข้อผิดพลาด'));
      expect(overview, contains('Level 0'));
      final d1 = m.substring(m.indexOf('## DFD: Level 0'), m.indexOf('## DFD: ว่าง'));
      expect(d1, contains('**ปัญหาที่ตรวจพบ**'));
    });

    test('DFD: วัตถุ เส้น ทิศทาง ป้ายชื่อ ตารางที่ผูก (ชื่อ ER › ตาราง) แผนภาพย่อย', () {
      final m = exportWorkspaceDictionary(_ws());
      expect(m, contains('| กระบวนการ | 1.0 | ชำระ <เงิน> |'));
      expect(m, contains('| ที่เก็บข้อมูล | D1 | ผู้ใช้ | ER ที่สอง › customers |'));
      expect(m, contains('ว่าง |')); // แผนภาพย่อย
      expect(m, contains('| ลูกค้า | → | 1.0 ชำระ <เงิน> | คำสั่ง\\|ซื้อ |'));
      expect(m, contains('| 1.0 ชำระ <เงิน> | ↔ | D1 ผู้ใช้ | บันทึก |'));
    });

    test('อักขระพิเศษ: ท่อ/ขึ้นบรรทัดใหม่ในช่องตารางถูก escape ; ชื่อเอกสารที่มีท่อไม่ทำตารางพัง', () {
      final m = exportWorkspaceDictionary(_ws());
      expect(m, contains('p\\|q<br>line2 <b>'));
      // ชื่อเอกสารขึ้นหัวข้อบรรทัดเดียว
      expect(m, contains('## DFD: Level 0 | <ระบบ>'));
      for (final line in m.split('\n').where((l) => l.startsWith('| ') && l.contains('Level 0'))) {
        // ท่อในเซลล์ต้องมี \ นำหน้า
        expect(line.replaceAll('\\|', '').contains('Level 0 | <'), isFalse, reason: line);
      }
    });

    test('DFD ว่าง: ขึ้นหัวข้อและ _ไม่มีวัตถุ_ ไม่มีตาราง', () {
      final m = exportWorkspaceDictionary(_ws());
      final d2 = m.substring(m.indexOf('## DFD: ว่าง'));
      expect(d2, contains('_ไม่มีวัตถุ_'));
      expect(d2, isNot(contains('| ชนิด |')));
    });

    test('ผลลัพธ์คงที่ และไม่ล้มเมื่อมี ER ว่าง/ไม่มี DFD', () {
      expect(exportWorkspaceDictionary(_ws()), exportWorkspaceDictionary(_ws()));
      final w = Workspace(name: 'x', documents: [
        ProjectDocument.er(id: 'a', name: 'A', content: Project(name: 'A')),
        ProjectDocument.er(id: 'b', name: 'B', content: Project(name: 'B')),
      ]);
      final m = exportWorkspaceDictionary(w);
      expect(m, contains('## ER: A'));
      expect(m, contains('## ER: B'));
      expect(m, contains('_ยังไม่มีตาราง_'));
    });

    test('ภาษาอังกฤษไม่มีอักษรไทยในโครงเอกสาร (ข้อมูลผู้ใช้ภาษาอังกฤษ)', () {
      currentLang = Lang.en;
      final w = Workspace(name: 'Shop', documents: [
        ProjectDocument.er(id: 'a', name: 'Main', content: _er('m', Dialect.sqlite)),
        ProjectDocument.dfd(id: 'd', name: 'L0', content: DfdDiagram(nodes: [
          DfdNode(id: 'n', kind: DfdKind.process, name: 'Pay', number: '1.0'),
        ])),
        ProjectDocument.dfd(id: 'e', name: 'Empty', content: DfdDiagram()),
      ]);
      final m = exportWorkspaceDictionary(w).replaceAll(RegExp(r'a\|b[^\n]*'), '');
      expect(_thai.hasMatch(m), isFalse, reason: m);
      expect(m, contains('## Project overview'));
      expect(m, contains('_No objects_'));
    });
  });

  group('HTML ทั้งโปรเจกต์', () {
    test('ER เดียวไม่มีเอกสารอื่น = รูปแบบเดิม (ไม่มีภาพรวม anchor เดิม)', () {
      final h = exportHtmlDocument(Workspace.single(_er('shop', Dialect.mysql)));
      expect(h, isNot(contains('id="overview"')));
      expect(h, contains('id="er-diagram"'));
      expect(h, contains('id="t-t1"'));
      expect(h, contains('href="#t-t1"'));
    });

    test('ภาพรวม ER ทุกอัน DFD ทุกอัน (รวมที่ว่าง) และภาพ SVG ต่อแผนภาพที่มีเนื้อหา', () {
      final h = exportHtmlDocument(_ws());
      expect(h, contains('<title>โปรเจกต์ &lt;A&amp;B&gt; — Data Dictionary</title>'));
      expect(h, contains('id="overview"'));
      expect(h, contains('id="erdoc-er"'));
      expect(h, contains('id="erdoc-er2"'));
      expect(h, contains('id="dfd-d1"'));
      expect(h, contains('id="dfd-d2"'));
      expect(h, contains('PostgreSQL'));
      expect(h, contains('MySQL / MariaDB'));
      // ER 2 อัน + DFD 1 อัน (อันว่างไม่มีภาพ)
      expect(RegExp('<svg').allMatches(h).length, 3);
      expect(h, contains('ไม่มีวัตถุ'));
      expect(h, isNot(contains('<script')));
    });

    test('anchor ตารางไม่ชนข้าม ER (id ตารางซ้ำกันในสอง ER)', () {
      final h = exportHtmlDocument(_ws());
      expect(h, contains('id="t-er-t1"'));
      expect(h, contains('id="t-er2-t1"'));
      expect(RegExp('id="t-er-t1"').allMatches(h).length, 1);
      expect(h, contains('href="#t-er2-t1"'));
    });

    test('DFD: ตารางวัตถุ/เส้น/ทิศทาง/ตารางที่ผูก/แผนภาพย่อย และปัญหา', () {
      final h = exportHtmlDocument(_ws());
      expect(h, contains('ER ที่สอง › customers'));
      expect(h, contains('<a href="#dfd-d2">ว่าง</a>'));
      expect(h, contains('<td class="c">↔</td>'));
      expect(h, contains('<td class="c">→</td>'));
      expect(h, contains('class="tag sev-error"'));
      final overview = h.substring(h.indexOf('id="overview"'), h.indexOf('id="erdoc-er"'));
      expect(overview, contains('Level 0'));
    });

    test('ข้อความของผู้ใช้ถูก escape ทั้งหมด', () {
      final h = exportHtmlDocument(_ws());
      expect(h, contains('Level 0 | &lt;ระบบ&gt;'));
      expect(h, contains('ชำระ &lt;เงิน&gt;'));
      expect(h, contains('a|b &lt;x&gt; &amp; &quot;q&quot;'));
      expect(h, contains('p|q<br>line2 &lt;b&gt;'));
      expect(h, isNot(contains('<เงิน>')));
      expect(h, isNot(contains('<b>')));
    });

    test('includeDiagrams=false ไม่มี SVG แต่ยังมีตารางข้อมูลของ DFD ; ผลลัพธ์คงที่', () {
      final h = exportHtmlDocument(_ws(), includeDiagrams: false);
      expect(h, isNot(contains('<svg')));
      expect(h, contains('ชำระ &lt;เงิน&gt;'));
      expect(exportHtmlDocument(_ws()), exportHtmlDocument(_ws()));
    });

    test('มีแต่ DFD (ไม่มี ER) ไม่ล้ม', () {
      final w = Workspace(name: 'x', documents: [
        ProjectDocument.dfd(id: 'd', name: 'L0', content: DfdDiagram()),
      ]);
      expect(exportHtmlDocument(w), contains('id="dfd-d"'));
    });

    test('ภาษาอังกฤษ: โครงเอกสารไม่มีอักษรไทย', () {
      currentLang = Lang.en;
      final w = Workspace(name: 'Shop', documents: [
        ProjectDocument.er(id: 'a', name: 'Main', content: _er('m', Dialect.sqlite).._plain()),
        ProjectDocument.dfd(id: 'e', name: 'Empty', content: DfdDiagram()),
      ]);
      final h = exportHtmlDocument(w);
      expect(h, contains('Project overview'));
      expect(h, contains('<html lang="en">'));
      expect(_thai.hasMatch(h.replaceAll(RegExp(r'<td>[^<]*</td>|<code>[^<]*</code>|<p class="comment">[^<]*</p>'), '')), isFalse);
    });
  });

  group('SQL ทุก ER', () {
    test('หัวคอมเมนต์ต่อ ER + dialect ของแต่ละ ER + เรียงตามเอกสาร', () {
      final s = buildWorkspaceSql(_ws());
      final i1 = s.indexOf('-- ===== ER 1/2: ER หลัก (MySQL / MariaDB) =====');
      final i2 = s.indexOf('-- ===== ER 2/2: ER ที่สอง (PostgreSQL) =====');
      expect(i1, 0);
      expect(i2, greaterThan(i1));
      expect(s.substring(i1, i2), contains('`users`')); // quote แบบ MySQL
      expect(s.substring(i2), contains('"customers"')); // quote แบบ PostgreSQL
      expect(s.substring(i2), isNot(contains('`')));
    });

    test('ER เดียว: ขึ้นต้นด้วยหัว 1/1 แล้วตามด้วย SQL ของ ER นั้น ; ไม่มี ER = ว่าง', () {
      final p = _er('shop', Dialect.sqlite);
      final s = buildWorkspaceSql(Workspace.single(p));
      expect(s, startsWith('-- ===== ER 1/1: ER (SQLite) =====\n'));
      expect(s, endsWith(buildExportSql(p)));
      expect(buildWorkspaceSql(Workspace(name: 'x')), '');
    });

    test('ชื่อเอกสารหลายบรรทัดไม่ทำให้คอมเมนต์หลุด', () {
      final w = Workspace(name: 'x', documents: [
        ProjectDocument.er(id: 'a', name: 'A\nDROP TABLE x;', content: _er('a', Dialect.mysql)),
      ]);
      expect(buildWorkspaceSql(w).split('\n').first, contains('A DROP TABLE x;'));
    });
  });

  group('กล่อง Export', () {
    testWidgets('มี HTML และ SQL ทั้งโปรเจกต์ ; ER หลายอัน: บอกว่า Mermaid ใช้ ER ไหน', (tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = _ws();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => TextExportDialog(
                project: w.documentById('er2')!.er!,
                workspace: w,
                erName: 'ER ที่สอง',
                initial: TextExportKind.mermaid,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ใช้เฉพาะ ER: ER ที่สอง'), findsOneWidget);

      await tester.tap(find.text('SQL ทั้งโปรเจกต์'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ใช้เฉพาะ ER'), findsNothing);
      expect(find.textContaining('===== ER 1/2', findRichText: true), findsOneWidget);

      await tester.tap(find.text('HTML'));
      await tester.pumpAndSettle();
      expect(find.textContaining('<!DOCTYPE html>', findRichText: true), findsOneWidget);
    });
  });
}

extension on Project {
  /// ทำให้ข้อความในตารางเป็นอังกฤษล้วน
  void _plain() {
    for (final t in tables) {
      t.comment = 'comment';
      for (final c in t.columns) {
        c.comment = '';
      }
    }
  }
}
