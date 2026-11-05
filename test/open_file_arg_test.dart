import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  testWidgets('เปิดแอปพร้อมไฟล์ที่ส่งมาทางบรรทัดคำสั่ง = โหลดโปรเจกต์และจำ path (ยังไม่ถือว่าแก้ไข)', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(
      settings: AppSettings(lang: Lang.th),
      initialProject: Workspace.single(base()),
      initialPath: r'C:\งาน\shop.nsld',
    ));
    final c = tester.element(find.byType(HomePage)).read<ProjectController>();
    expect(c.project.tables.length, 2);
    expect(c.filePath, r'C:\งาน\shop.nsld');
    expect(c.dirty, false);
  });
}
