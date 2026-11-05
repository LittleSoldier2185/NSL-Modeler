import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/app_info.dart';
import 'package:nsl_dev/core/changelog.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/diagram.dart';
import 'package:nsl_dev/main.dart';
import 'package:nsl_dev/state/app_settings.dart';
import 'package:nsl_dev/state/project_controller.dart';
import 'package:nsl_dev/ui/canvas/canvas_controller.dart';
import 'package:nsl_dev/ui/home_page.dart';
import 'package:nsl_dev/ui/palette/command_palette.dart';
import 'package:nsl_dev/ui/whats_new_dialog.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

void main() {
  group('เลขรุ่นและชื่อรุ่น', () {
    test('pubspec.yaml ตรงกับ kAppVersion', () {
      final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
      expect(line.replaceFirst('version:', '').trim().split('+').first, kAppVersion);
    });

    test('เลขรุ่นเป็น SemVer และชื่อรุ่นเป็นคำในลำดับดาราศาสตร์ที่วางไว้', () {
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kAppVersion), true);
      expect(kCodenameRoadmap, contains(kAppCodename));
      // เรียงตามตัวอักษร (A, B, C, ...)
      for (var i = 1; i < kCodenameRoadmap.length; i++) {
        expect(kCodenameRoadmap[i].codeUnitAt(0), greaterThan(kCodenameRoadmap[i - 1].codeUnitAt(0)));
      }
      expect(appVersionLabel, '$kAppCodename $kAppVersion');
    });

    test('ชื่อรุ่นตรงกับเลขรอง: 0.5 = รุ่นที่ 1 ในลำดับ (Altair)', () {
      final minor = int.parse(kAppVersion.split('.')[1]);
      expect(kCodenameRoadmap[minor - 5], kAppCodename);
    });
  });

  group('patch note', () {
    test('รุ่นบนสุดตรงกับรุ่นปัจจุบัน; ทุกรุ่นมีเนื้อหาและวันที่ถูกรูปแบบ; เรียงใหม่สุดก่อน', () {
      expect(kReleaseNotes.first.version, kAppVersion);
      expect(kReleaseNotes.first.codename, kAppCodename);
      for (final r in kReleaseNotes) {
        expect(r.isEmpty, false);
        expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r.date), true, reason: r.version);
      }
      for (var i = 1; i < kReleaseNotes.length; i++) {
        expect(kReleaseNotes[i - 1].date.compareTo(kReleaseNotes[i].date), greaterThanOrEqualTo(0));
      }
    });

    test('ทุกบรรทัดมีคำแปลอังกฤษ (ไม่หลุดเป็นไทยในหน้าอังกฤษ)', () {
      final old = currentLang;
      currentLang = Lang.en;
      for (final r in kReleaseNotes) {
        for (final k in NoteKind.values) {
          for (final line in r.of(k)) {
            expect(RegExp(r'[฀-๿]').hasMatch(tr(line)), false, reason: line);
          }
        }
      }
      currentLang = old;
    });

    test('CHANGELOG.md มีหัวข้อรุ่นปัจจุบัน และทุกบรรทัดใน changelog.dart อยู่ในไฟล์นั้นด้วย', () {
      final md = File('CHANGELOG.md').readAsStringSync();
      final top = kReleaseNotes.first;
      expect(md, contains('## ${top.codename} ${top.version} — ${top.date}'));
      for (final k in NoteKind.values) {
        for (final line in top.of(k)) {
          // ใน markdown ใช้ ` ครอบตัวนำหน้า — เทียบแบบตัดเครื่องหมายนี้
          expect(md.replaceAll('`', ''), contains(line.replaceAll('`', '')), reason: line);
        }
      }
    });
  });

  group('แถบสถานะ', () {
    late ProjectController c;
    late AppSettings settings;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, Size size = const Size(1440, 900), String? lastSeen}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      settings = AppSettings(lang: lang, lastSeenVersion: lastSeen);
      await tester.pumpWidget(NslDevApp(settings: settings));
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(base(), null);
      await tester.pump();
    }

    testWidgets('อยู่ล่างสุดทั้งความกว้าง สูง 24 แสดงรุ่น/สรุป/ซูม; ไม่ทับพื้นที่ทำงาน', (tester) async {
      await boot(tester);
      final version = find.byKey(const ValueKey('status-version'));
      expect(tester.widget<Text>(version).data, appVersionLabel);
      final r = tester.getRect(version);
      expect(r.bottom, closeTo(900, 12));
      expect(find.textContaining('ตาราง · '), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-zoom'))).data, '100%');
      expect(tester.takeException(), isNull);
    });

    testWidgets('จุดแจ้ง "มีอะไรใหม่": ยังไม่เคยดู = มีจุด; เปิดดูแล้วจุดหาย และจำไว้ในการตั้งค่า', (tester) async {
      await boot(tester);
      expect(find.byKey(const ValueKey('status-unseen-dot')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-whats-new')));
      await tester.pumpAndSettle();
      expect(find.byType(WhatsNewDialog), findsOneWidget);
      expect(find.text('$kAppCodename $kAppVersion'), findsWidgets);
      expect(settings.lastSeenVersion, kAppVersion);
      await tester.tap(find.text('ปิด'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-unseen-dot')), findsNothing);
    });

    testWidgets('เคยดูรุ่นนี้แล้ว = ไม่มีจุดตั้งแต่เปิดแอป', (tester) async {
      await boot(tester, lastSeen: kAppVersion);
      expect(find.byKey(const ValueKey('status-unseen-dot')), findsNothing);
    });

    testWidgets('หน้า patch note แสดงทุกหมวด ทุกบรรทัดของรุ่นล่าสุด และเลื่อนดูได้', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('status-whats-new')));
      await tester.pumpAndSettle();
      Finder inDialog(String t) => find.descendant(of: find.byType(WhatsNewDialog), matching: find.text(t));
      expect(inDialog('เพิ่มใหม่'), findsOneWidget);
      expect(inDialog('ปรับปรุง'), findsOneWidget);
      expect(inDialog('แก้ไข'), findsOneWidget);
      expect(find.text(kReleaseNotes.first.added.first), findsOneWidget);
      // บรรทัดท้าย ๆ ต้องเลื่อนถึง
      await tester.drag(find.byKey(const ValueKey('whats-new-scroll')), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text(kReleaseNotes.first.fixed.last), findsOneWidget);
    });

    testWidgets('เมนูช่วยเหลือ: มีอะไรใหม่ / เกี่ยวกับ (แสดงรุ่น)', (tester) async {
      await boot(tester);
      await tester.tap(find.text('ช่วยเหลือ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เกี่ยวกับ NSL Dev…'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutAppDialog), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('about-version'))).data, appVersionLabel);
      await tester.tap(find.descendant(of: find.byType(AboutAppDialog), matching: find.text('มีอะไรใหม่')));
      await tester.pumpAndSettle();
      expect(find.byType(WhatsNewDialog), findsOneWidget);
    });

    testWidgets('ค้นจาก palette: "patch note" เปิดหน้ามีอะไรใหม่', (tester) async {
      await boot(tester);
      final ctx = tester.element(find.byType(HomePage));
      final entries = buildPaletteEntries(ctx);
      final hit = paletteResults(entries, 'patch note').first;
      expect(hit.title, 'มีอะไรใหม่ (Patch note)');
      hit.run();
      await tester.pumpAndSettle();
      expect(find.byType(WhatsNewDialog), findsOneWidget);
    });

    testWidgets('สถานะ: ยังไม่ได้บันทึก/ปัญหา/ซูม เปลี่ยนตามงาน; บนแท็บ DFD แสดงวัตถุและเส้นข้อมูล', (tester) async {
      await boot(tester);
      expect(find.byKey(const ValueKey('status-dirty')), findsNothing);
      c.addTable(name: 'solo');
      await tester.pump();
      expect(find.byKey(const ValueKey('status-dirty')), findsOneWidget);
      expect(find.text('● ยังไม่ได้บันทึก'), findsOneWidget);
      // ตัวบอกปัญหาตรงกับผลตรวจจริง
      final badge = find.descendant(of: find.byKey(const ValueKey('status-issues')), matching: find.byType(Text));
      final errs = c.issues.where((i) => i.severity.name == 'error').length;
      final warns = c.issues.where((i) => i.severity.name == 'warning').length;
      expect(tester.widget<Text>(badge).data, c.issues.where((i) => i.severity.name != 'info').isEmpty ? 'ไม่พบปัญหา' : '$errs ข้อผิดพลาด · $warns คำเตือน');
      final cv = tester.element(find.byType(HomePage)).read<CanvasController>();
      cv.zoomAt(const Offset(500, 400), 1.25);
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-zoom'))).data, '${(cv.scale * 100).round()}%');

      c.addDiagram(DiagramKind.dfd, name: 'L1');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-summary'))).data, contains('0 วัตถุ · 0 เส้นข้อมูล'));
      expect(find.textContaining('L1'), findsWidgets);
    });

    testWidgets('คลิกตัวบอกปัญหา (ER) เปิดแท็บปัญหาของแผง SQL', (tester) async {
      await boot(tester);
      c.addTable(name: 'solo');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('status-issues')));
      await tester.pumpAndSettle();
      final cv = tester.element(find.byType(HomePage)).read<CanvasController>();
      expect(cv.dockTab, DockTab.issues);
    });

    testWidgets('ชื่อไฟล์ย้ายมาอยู่ที่แถบสถานะ (ยังไม่บันทึก = ชื่อโปรเจกต์.nsld)', (tester) async {
      await boot(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-summary'))).data, startsWith('${c.project.name}.nsld · '));
    });

    testWidgets('หน้าต่างแคบ: แถบสถานะไม่ overflow', (tester) async {
      await boot(tester, size: const Size(1000, 700));
      c.addDiagram(DiagramKind.dfd, name: 'A very long diagram name for the status bar test');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ภาษาอังกฤษ: แถบสถานะและหน้า patch note แปลครบ', (tester) async {
      await boot(tester, lang: Lang.en);
      expect(find.text("What's new"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-whats-new')));
      await tester.pumpAndSettle();
      expect(find.text('Added'), findsOneWidget);
      expect(find.textContaining('DFD diagrams:'), findsOneWidget);
      currentLang = Lang.th;
    });
  });
}
