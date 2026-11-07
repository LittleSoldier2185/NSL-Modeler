import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';
import 'support/project_helpers.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/validate/issue.dart';
import 'package:nsl_dev/core/validate/workspace_validator.dart';

void main() {
  test('ตรวจรวมทุกเอกสาร: ปัญหาของ DFD ทุกแท็บถูกระบุเอกสารต้นทาง', () {
    final w = Workspace.single(Project());
    final a = DfdDiagram()..nodes.add(DfdNode(id: 'n1', kind: DfdKind.process, name: '', number: '1.0', x: 0, y: 0));
    final b = DfdDiagram();
    w.documents
      ..add(ProjectDocument.dfd(id: 'd1', name: 'Level 0', content: a))
      ..add(ProjectDocument.dfd(id: 'd2', name: 'Level 1', content: b));

    final all = validateWorkspace(w);
    final fromA = all.where((x) => x.docId == 'd1').toList();
    expect(fromA, isNotEmpty);
    expect(fromA.every((x) => x.docName == 'Level 0' && x.docType == DocType.dfd), isTrue);
    expect(all.where((x) => x.docId == 'd2'), isEmpty);
    final n = countIssues(all.map((x) => x.issue));
    expect(n.errors + n.warnings + n.infos, all.length);
  });

  test('เอกสารว่างทั้งโปรเจกต์ = ไม่มีปัญหา และชนิดที่ไม่รู้จักถูกข้าม', () {
    final w = Workspace.single(Project());
    w.documents.add(ProjectDocument(id: 'x', typeName: 'flowchart', name: 'F', content: RawDocContent({'a': 1})));
    expect(validateWorkspace(w).where((x) => x.issue.severity != Severity.info), isEmpty);
    expect(validateWorkspace(w).any((x) => x.docId == 'x'), isFalse);
  });

  testWidgets('หน้าต่างปัญหาทั้งโปรเจกต์: เปิดจากแถบสถานะ แสดงเอกสารต้นทาง คลิกแล้วไปที่แท็บนั้น', (tester) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
    final ctx = tester.element(find.byType(HomePage));
    final c = ctx.read<ProjectController>();
    final w = ctx.read<WorkspaceController>();
    final tab = c.addDiagram(DocType.dfd, name: 'Level 0')!;
    setDfd(c, tab.id, DfdDiagram()..nodes.add(DfdNode(id: 'n1', kind: DfdKind.process, name: '', number: '1.0')));
    await tester.pump();
    w.openDocument(w.documents.first.id); // กลับ ER
    await tester.pump();
    w.openDocument(tab.id);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('status-issues')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-issues')), findsOneWidget);
    expect(find.text('Level 0'), findsWidgets);

    w.openDocument(w.documents.first.id);
    await tester.pump();
    await tester.tap(find.text('กระบวนการไม่ได้เชื่อมกับอะไร'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-issues')), findsNothing);
    expect(w.activeId, tab.id);
    expect(tester.takeException(), isNull);
  });
}
