import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/export/flowchart_svg.dart';
import 'package:nsl_dev/core/export/html_doc_export.dart';
import 'package:nsl_dev/core/export/markdown_export.dart';
import 'package:nsl_dev/core/export/workspace_summary.dart';
import 'package:nsl_dev/core/l10n/l10n.dart';
import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/flowchart_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/ui/export/flowchart_png.dart';

FlowchartDiagram flow() => FlowchartDiagram(nodes: [
      FcNode(id: 's', shape: FcShape.start, text: 'Start', x: 0, y: 0),
      FcNode(id: 'd', shape: FcShape.decision, text: 'A & <B>?', x: 0, y: 120, fill: 0xFFAA33CC),
      FcNode(id: 'e', shape: FcShape.end, text: 'End', x: 0, y: 300, align: FcAlign.left),
      FcNode(id: 'n', shape: FcShape.note, text: 'line 1\nline 2', x: 300, y: 0),
    ], edges: [
      FcEdge(id: 'k1', fromId: 's', toId: 'd'),
      FcEdge(id: 'k2', fromId: 'd', toId: 'e', label: 'Yes', dash: FcDash.dashed, startArrow: FcArrow.open),
    ]);

Workspace ws({bool withFlow = true}) => Workspace(name: 'Shop', documents: [
      ProjectDocument.er(id: 'er', name: 'ER', content: Project(name: 'Shop')),
      ProjectDocument.dfd(id: 'd1', name: 'Level 0', content: DfdDiagram()),
      if (withFlow) ProjectDocument.flowchart(id: 'f1', name: 'Checkout', content: flow()),
      if (withFlow) ProjectDocument.flowchart(id: 'f2', name: 'Empty flow', content: FlowchartDiagram()),
    ]);

void main() {
  setUp(() => currentLang = Lang.th);

  group('SVG', () {
    test('มีรูปทรง ข้อความ (escape) ป้ายเส้น เส้นประ หัวลูกศร ; ว่าง = null', () {
      final svg = exportFlowchartSvg(flow(), title: 'T & U')!;
      expect(svg, startsWith('<svg'));
      expect(svg, contains('<title>T &amp; U</title>'));
      expect(svg, contains('A &amp; &lt;B&gt;?'));
      expect(svg, contains('#AA33CC'));
      expect(svg, contains('>Yes<'));
      expect(svg, contains('stroke-dasharray="8 5"'));
      expect('<polygon'.allMatches(svg).length, 2); // หัวลูกศรทึบปลายเส้นทั้งสอง
      expect('<polyline'.allMatches(svg).length, 1); // หัวลูกศรโปร่งต้นเส้น k2
      expect(svg, contains('<tspan'));
      expect(svg.trim(), endsWith('</svg>'));
      expect(exportFlowchartSvg(FlowchartDiagram()), isNull);
    });

    test('ธีมมืด/สว่าง และพื้นหลังโปร่งใส', () {
      final light = exportFlowchartSvg(flow())!;
      final dark = exportFlowchartSvg(flow(), dark: true)!;
      expect(light, contains('#F6F8FB'));
      expect(dark, contains('#121820'));
      final clear = exportFlowchartSvg(flow(), transparent: true)!;
      // ไม่มีสี่เหลี่ยมพื้นหลังเต็มภาพ (เหลือแค่พื้นหลังป้ายเส้น)
      expect('#F6F8FB'.allMatches(clear).length, '#F6F8FB'.allMatches(light).length - 1);
    });
  });

  testWidgets('PNG: พื้นตามธีม, โปร่งใสได้ ; ว่าง = null', (tester) async {
    Future<int> cornerAlpha({bool dark = false, bool transparent = false}) async => (await tester.runAsync(() async {
          final out = await exportFlowchartPng(flow(), scale: 1, dark: dark, transparent: transparent);
          final codec = await ui.instantiateImageCodec(out!.bytes);
          final img = (await codec.getNextFrame()).image;
          final data = (await img.toByteData())!;
          return dark ? data.getUint8(0) + data.getUint8(1) + data.getUint8(2) : data.getUint8(3);
        }))!;
    expect(await cornerAlpha(), 255);
    expect(await cornerAlpha(transparent: true), 0);
    expect(await cornerAlpha(dark: true), lessThan(200));
    expect(await tester.runAsync(() => exportFlowchartPng(FlowchartDiagram())), isNull);
  });

  group('เอกสารทั้งโปรเจกต์', () {
    test('ตัวเลขสรุปนับ Flowchart', () {
      final c = workspaceCounts(ws());
      expect((c.docs, c.fcs, c.symbols, c.fcEdges), (4, 2, 4, 2));
      expect(docCountLine(c), '4 เอกสาร (1 ER · 1 DFD · 2 Flowchart)');
      expect(docCountLine(workspaceCounts(ws(withFlow: false))), '2 เอกสาร (1 ER · 1 DFD)');
    });

    test('Markdown: ภาพรวม + หัวข้อ Flowchart ทุกอัน + ตารางสัญลักษณ์/เส้น + ปัญหา', () {
      final md = exportWorkspaceDictionary(ws());
      expect(md, contains('- 4 เอกสาร (1 ER · 1 DFD · 2 Flowchart)'));
      expect(md, contains('- 4 สัญลักษณ์ Flowchart · 2 เส้นเชื่อม'));
      expect(md, contains('- Flowchart: Checkout — 4 สัญลักษณ์ · 2 เส้นเชื่อม'));
      expect(md, contains('## Flowchart: Checkout'));
      expect(md, contains('| การตัดสินใจ | A & <B>? |'));
      expect(md, contains('| โน้ต | line 1<br>line 2 |'));
      expect(md, contains('| A & <B>? | End | Yes |'));
      expect(md, contains('## Flowchart: Empty flow'));
      expect(md, contains('_ไม่มีสัญลักษณ์_'));
      // ปัญหาของ Checkout: การตัดสินใจมีทางออกเดียว
      expect(md, contains('การตัดสินใจมีทางออกไม่ครบ'));
      // ลำดับ: ER -> DFD -> Flowchart
      expect(md.indexOf('## ER: ER'), lessThan(md.indexOf('## DFD: Level 0')));
      expect(md.indexOf('## DFD: Level 0'), lessThan(md.indexOf('## Flowchart: Checkout')));
    });

    test('Markdown/HTML ไม่มี Flowchart = ข้อความภาพรวมเดิม', () {
      final md = exportWorkspaceDictionary(ws(withFlow: false));
      expect(md, contains('- 2 เอกสาร (1 ER · 1 DFD)'));
      expect(md, isNot(contains('Flowchart')));
      expect(exportHtmlDocument(ws(withFlow: false)), isNot(contains('Flowchart')));
    });

    test('HTML: สารบัญ ภาพรวม ภาพ SVG ฝัง ตาราง และ escape', () {
      final html = exportHtmlDocument(ws());
      expect(html, contains('<a href="#fc-f1">Flowchart: Checkout</a>'));
      expect(html, contains('<section id="fc-f1">'));
      expect(html, contains('<section id="fc-f2">'));
      expect(html, contains('4 เอกสาร (1 ER · 1 DFD · 2 Flowchart)'));
      expect(html, contains('4 สัญลักษณ์ Flowchart · 2 เส้นเชื่อม'));
      expect(html, contains('<div class="diagram"><svg'));
      expect(html, contains('<td>A &amp; &lt;B&gt;?</td>'));
      expect(html, contains('line 1<br>line 2'));
      expect(html, contains('ไม่มีสัญลักษณ์'));
      expect(exportHtmlDocument(ws(), includeDiagrams: false), isNot(contains('<title>Checkout</title>')));
    });

    test('ภาษาอังกฤษ: ไม่มีอักษรไทยในโครงเอกสาร', () {
      currentLang = Lang.en;
      final thai = RegExp(r'[฀-๿]');
      final md = exportWorkspaceDictionary(ws());
      expect(thai.hasMatch(md), isFalse, reason: thai.firstMatch(md)?.group(0));
      expect(md, contains('Flowchart: Checkout'));
      final html = exportHtmlDocument(ws());
      expect(thai.hasMatch(html), isFalse);
      currentLang = Lang.th;
    });
  });
}
