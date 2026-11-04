import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/l10n/l10n.dart';
import 'package:nsl_modeler/core/models/enums.dart';
import 'package:nsl_modeler/main.dart';
import 'package:nsl_modeler/state/app_settings.dart';
import 'package:nsl_modeler/state/project_controller.dart';
import 'package:nsl_modeler/ui/create_table_dialog.dart';
import 'package:nsl_modeler/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  late ProjectController c;

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslModelerApp(settings: AppSettings(lang: Lang.th)));
    c = tester.element(find.byType(HomePage)).read<ProjectController>();
    c.loadProject(base(), null);
    await tester.pump();
  }

  Future<void> openEdit(WidgetTester tester, String tableId) async {
    c.selectTable(tableId);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  testWidgets('Ctrl+Shift+M เปิดฟอร์มแก้ไข: เติมค่าเดิมครบทุกคอลัมน์', (tester) async {
    await boot(tester);
    await openEdit(tester, 'tu');
    expect(find.byType(CreateTableDialog), findsOneWidget);
    expect(find.text('แก้ไขโครงสร้างตาราง'), findsOneWidget);
    expect(text(tester, 'ct-table-name'), 'users');
    expect(text(tester, 'ct-name-0'), 'id');
    expect(text(tester, 'ct-name-1'), 'email');
    expect(text(tester, 'ct-len-1'), '255');
    expect(find.byKey(const ValueKey('ct-name-4')), findsNothing);
  });

  testWidgets('แก้ชื่อ/ความยาวแล้วบันทึก: id คอลัมน์เดิมคงอยู่, FK ไม่หลุด, undo ขั้นเดียว', (tester) async {
    await boot(tester);
    final relsBefore = c.project.relations.length;
    final colIds = c.project.tableById('tu')!.columns.map((x) => x.id).toList();
    await openEdit(tester, 'tu');
    await tester.enterText(find.byKey(const ValueKey('ct-name-2')), 'full_name');
    await tester.enterText(find.byKey(const ValueKey('ct-len-2')), '150');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ct-save')));
    await tester.pumpAndSettle();

    final t = c.project.tableById('tu')!;
    expect(find.byType(CreateTableDialog), findsNothing);
    expect(t.columns.map((x) => x.id), colIds);
    expect(t.columns[2].name, 'full_name');
    expect(t.columns[2].length, 150);
    expect(c.project.relations.length, relsBefore);

    c.undo();
    expect(c.project.tableById('tu')!.columns[2].name, 'name');
    expect(c.project.tableById('tu')!.columns[2].length, 100);
  });

  testWidgets('เพิ่มคอลัมน์ใหม่ในฟอร์มแก้ไข ได้ id ใหม่ และคอลัมน์เดิมไม่เปลี่ยน', (tester) async {
    await boot(tester);
    await openEdit(tester, 'tu');
    await tester.tap(find.byKey(const ValueKey('ct-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ct-name-4')), 'phone');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ct-save')));
    await tester.pumpAndSettle();

    final t = c.project.tableById('tu')!;
    expect(t.columns.map((x) => x.name), ['id', 'email', 'name', 'age', 'phone']);
    expect(t.columns.take(4).map((x) => x.id), ['u1', 'u2', 'u3', 'u4']);
    expect(t.columns.last.id, isNot(anyOf('u1', 'u2', 'u3', 'u4')));
  });

  testWidgets('ลบคอลัมน์ที่มี FK ผูกอยู่: ถามยืนยัน แล้วลบความสัมพันธ์ตาม', (tester) async {
    await boot(tester);
    final rel = c.project.relations.first;
    final tableId = rel.fromTableId;
    final colId = rel.fromColumnId;
    final t0 = c.project.tableById(tableId)!;
    final idx = t0.columns.indexWhere((x) => x.id == colId);
    await openEdit(tester, tableId);
    await tester.tap(find.byKey(ValueKey('ct-remove-$idx')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ct-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ความสัมพันธ์ FK'), findsOneWidget);

    // ยกเลิก = ไม่เปลี่ยนอะไร
    await tester.tap(find.text('ยกเลิก').last);
    await tester.pumpAndSettle();
    expect(c.project.tableById(tableId)!.columns.any((x) => x.id == colId), true);

    await tester.tap(find.byKey(const ValueKey('ct-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบและบันทึก'));
    await tester.pumpAndSettle();
    expect(c.project.tableById(tableId)!.columns.any((x) => x.id == colId), false);
    expect(c.project.relations.any((r) => r.fromColumnId == colId || r.toColumnId == colId), false);

    c.undo();
    expect(c.project.tableById(tableId)!.columns.any((x) => x.id == colId), true);
    expect(c.project.relations.any((r) => r.fromColumnId == colId), true);
  });

  testWidgets('ชื่อตารางซ้ำกับตารางอื่น = บันทึกไม่ได้ แต่ชื่อเดิมของตัวเองใช้ได้', (tester) async {
    await boot(tester);
    await openEdit(tester, 'tu');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ct-save'))).onPressed, isNotNull);
    await tester.enterText(find.byKey(const ValueKey('ct-table-name')), 'Orders');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ct-save'))).onPressed, isNull);
  });

  test('ดัชนีหลายคอลัมน์เดิมคงอยู่หลังแก้ (ตัดเฉพาะคอลัมน์ที่ถูกลบ)', () {
    final p = base();
    final t = p.tableById('to')!;
    final before = t.indexes.length;
    final drafts = [for (final col in t.columns) ColumnDraft.fromColumn(t, col)];
    final built = buildTableFromDrafts(
      newId: (_) => 'new',
      name: t.name,
      comment: t.comment,
      drafts: drafts,
      existing: t,
    );
    expect(built.id, t.id);
    expect(built.columns.map((x) => x.id), t.columns.map((x) => x.id));
    expect(built.indexes.length, before);
    expect(built.columns.map((x) => x.type), t.columns.map((x) => x.type));
    expect(built.columns[2].type, DataType.decimal);
    expect((built.columns[2].length, built.columns[2].scale), (10, 2));
  });
}
