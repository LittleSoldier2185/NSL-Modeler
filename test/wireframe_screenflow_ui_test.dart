import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n_en.dart';
import 'package:nsl_dev/core/models/screenflow_model.dart';
import 'package:nsl_dev/core/models/wireframe_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/screenflow_controller.dart';
import 'package:nsl_dev/state/wireframe_controller.dart';
import 'package:nsl_dev/state/workspace_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('สร้าง Wireframe / Screen Flow ผ่านแอป: แคนวาส แผง วางชิ้นส่วน สลับรูปแบบ undo ผูกหน้าจอ', (tester) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(showExplorer: true)));
    await tester.pump();
    final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();

    final wfDoc = w.addDocument(DocType.wireframe)!;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-canvas')), findsOneWidget);
    final wf = tester.element(find.byType(HomePage)).read<WireframeController>();
    expect(wf.docId, wfDoc.id);
    final c = wf.addComponent(WfKind.button, 200, 200)!;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-delete')), findsOneWidget);
    wf.setStyle(WfStyle.clean);
    await tester.pump();
    expect(wf.diagram.style, WfStyle.clean);
    wf.undo();
    expect(wf.diagram.style, WfStyle.sketch);
    expect(wf.diagram.componentById(c.id), isNotNull);
    wf.clearSelection();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-panel-style')), findsOneWidget);

    w.addDocument(DocType.screenflow);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sf-canvas')), findsOneWidget);
    final sf = tester.element(find.byType(HomePage)).read<ScreenFlowController>();
    sf.addNode(SfKind.start, 0, 0);
    final screen = sf.addNode(SfKind.screen, 300, 0)!;
    sf.linkWireframe(screen.id, wfDoc.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sf-open-wireframe')), findsOneWidget);
    expect(w.backlinksOf(wfDoc.id).length, 1);

    w.showHome();
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('home-card-${wfDoc.id}')), findsOneWidget);
  });

  test('ข้อความไทยในโค้ด Wireframe / Screen Flow มีคำแปลอังกฤษ', () {
    final files = [
      ...Directory('lib/ui/wireframe').listSync().whereType<File>(),
      ...Directory('lib/ui/screenflow').listSync().whereType<File>(),
      File('lib/core/validate/wireframe_validator.dart'),
      File('lib/core/validate/screenflow_validator.dart'),
      File('lib/state/wireframe_controller.dart'),
      File('lib/state/screenflow_controller.dart'),
    ];
    final thai = RegExp(r'[฀-๿]');
    final call = RegExp(r"\btr\(\s*'([^'\n]*)'");
    final missing = <String>[];
    for (final f in files) {
      for (final m in call.allMatches(f.readAsStringSync())) {
        final k = m.group(1)!.replaceAll(r'\n', '\n');
        if (thai.hasMatch(k) && !kEn.containsKey(k)) missing.add('${f.path}: $k');
      }
    }
    expect(missing, isEmpty);
  });
}
