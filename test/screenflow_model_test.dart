import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/clipboard/screenflow_clipboard.dart';
import 'package:nsl_dev/core/export/screenflow_svg.dart';
import 'package:nsl_dev/core/layout/screenflow_geometry.dart';
import 'package:nsl_dev/core/models/doc_ref.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/screenflow_model.dart';
import 'package:nsl_dev/core/models/wireframe_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/core/validate/screenflow_validator.dart';

ScreenFlowDiagram sample() => ScreenFlowDiagram(nodes: [
      SfNode(id: 's', kind: SfKind.start, title: 'Open app', x: 0, y: 0),
      SfNode(id: 'login', kind: SfKind.screen, title: 'Login', x: 250, y: 0, wireframeId: 'w1'),
      SfNode(id: 'home', kind: SfKind.screen, title: 'Home', x: 550, y: 0, color: 0xFF0D9488),
      SfNode(id: 'x', kind: SfKind.end, title: 'Logout', x: 850, y: 0),
    ], edges: [
      SfEdge(id: 'e1', fromId: 's', toId: 'login'),
      SfEdge(id: 'e2', fromId: 'login', toId: 'home', label: 'click Login', condition: 'valid'),
      SfEdge(id: 'e3', fromId: 'home', toId: 'x', label: 'Logout'),
    ]);

Map<String, dynamic> roundTrip(Object o) => jsonDecode(jsonEncode(o)) as Map<String, dynamic>;

Workspace ws({ScreenFlowDiagram? sf, bool withWireframe = true}) => Workspace(name: 'P', documents: [
      ProjectDocument.er(id: 'er', name: 'ER', content: Project(name: 'P')),
      if (withWireframe)
        ProjectDocument.wireframe(
            id: 'w1',
            name: 'Login',
            content: WireframeDiagram(components: [WfComponent(id: 'b', kind: WfKind.button, text: 'Go', x: 10, y: 10)])),
      ProjectDocument.screenflow(id: 'f1', name: 'App flow', content: sf ?? sample()),
    ]);

void main() {
  group('โมเดล / ไฟล์', () {
    test('JSON ไป-กลับ ; ป้าย + เงื่อนไข ; ค่าเริ่มต้นไม่ถูกเขียน', () {
      final d = sample();
      final back = ScreenFlowDiagram.fromJson(roundTrip(d.toJson()));
      expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
      expect(back.edgeById('e2')!.caption, 'click Login [valid]');
      expect(back.edgeById('e1')!.caption, '');
      expect(SfEdge(id: 'z', fromId: 'a', toId: 'b', condition: 'c').caption, '[c]');
      final e1 = (roundTrip(d.toJson())['edges'] as List).first as Map;
      expect(e1.keys.toSet(), {'id', 'from', 'to', 'label'});
    });

    test('ซ่อมข้อมูลผิดปกติ: ชนิดแปลก/id ซ้ำ/เส้นชี้ไปโหนดที่ไม่มี', () {
      final d = ScreenFlowDiagram.fromJson({
        'nodes': [
          {'id': 'a', 'kind': 'screen', 'w': 2, 'wireframe': ''},
          {'id': 'a', 'kind': 'end'},
          {'id': 'b', 'kind': 'portal'},
          {'id': 'c', 'kind': 'end', 'h': 99999},
        ],
        'edges': [
          {'id': 'e', 'from': 'a', 'to': 'c'},
          {'id': 'e', 'from': 'c', 'to': 'a'},
          {'id': 'f', 'from': 'a', 'to': 'b'},
        ],
      });
      expect(d.nodes.map((n) => n.id), ['a', 'c']);
      expect(d.nodeById('a')!.w, sfDefaultSize(SfKind.screen).$1);
      expect(d.nodeById('a')!.wireframeId, isNull);
      expect(d.nodeById('c')!.h, kSfMaxSide);
      expect(d.edges.map((e) => e.id), ['e']);
    });

    test('บันทึกเป็นชนิด "screenflow" ; เปิดกลับครบ ; ชื่อว่าง = "Screen Flow"', () {
      final j = roundTrip(encodeProjectMap(ws()));
      final doc = (j['documents'] as List).firstWhere((d) => d['id'] == 'f1') as Map;
      expect(doc['type'], 'screenflow');
      final back = decodeProjectMap(j);
      expect(back.documentById('f1')!.type, DocType.screenflow);
      expect(jsonEncode(encodeProjectMap(back)), jsonEncode(j));
      final named = decodeProjectMap({
        'format': 'nsl-erd',
        'version': 3,
        'documents': [
          {'id': 'f', 'type': 'screenflow', 'name': ' ', 'content': null},
        ],
      });
      expect(named.documentById('f')!.name, 'Screen Flow');
    });

    test('จำลองรุ่นที่ไม่รู้จัก screenflow: เก็บดิบและเขียนกลับไม่เปลี่ยน', () {
      final j = roundTrip(encodeProjectMap(ws()));
      final raw = jsonEncode(j).replaceAll('"type":"screenflow"', '"type":"screenflow-x"');
      final old = decodeProjectMap(jsonDecode(raw) as Map<String, dynamic>);
      expect(old.documentById('f1')!.type, isNull);
      final saved = jsonEncode(encodeProjectMap(old)).replaceAll('"type":"screenflow-x"', '"type":"screenflow"');
      expect(saved, jsonEncode(j));
      expect(decodeProjectMap(jsonDecode(saved) as Map<String, dynamic>).documentById('f1')!.screenflow!.edges.length, 3);
    });
  });

  group('ตัวตรวจ', () {
    test('แผนผังครบ: ไม่มีปัญหาระดับ error/warning', () {
      final issues = validateScreenFlow(sample(), workspace: ws());
      expect(issues.map((i) => i.code), ['sf_no_wireframe']); // Home ยังไม่ผูก (info)
    });

    test('ไม่มีจุดเริ่ม (error) ; ว่าง = ไม่มีปัญหา', () {
      expect(validateScreenFlow(ScreenFlowDiagram()), isEmpty);
      final d = ScreenFlowDiagram(nodes: [SfNode(id: 'a', kind: SfKind.screen, wireframeId: 'w1')]);
      expect(validateScreenFlow(d, workspace: ws()).map((i) => i.code), ['sf_no_start', 'sf_dead_end']);
    });

    test('ไปไม่ถึง / ทางตัน / Wireframe ที่ผูกหายไป (error)', () {
      final d = sample()
        ..nodes.add(SfNode(id: 'lost', kind: SfKind.screen, title: 'Lost', wireframeId: 'w1'))
        ..edges.removeWhere((e) => e.id == 'e3');
      final issues = validateScreenFlow(d, workspace: ws(withWireframe: false));
      String codes(String id) => issues.where((i) => i.tableId == id).map((i) => i.code).join(',');
      expect(codes('lost'), contains('sf_unreachable'));
      expect(codes('lost'), contains('sf_dead_end'));
      expect(codes('lost'), contains('sf_wireframe_missing'));
      expect(codes('home'), contains('sf_dead_end'));
      expect(codes('x'), contains('sf_unreachable'));
      expect(codes('login'), 'sf_wireframe_missing');
      expect(issues.first.severity.name, 'error');
    });

    test('ลิงก์ข้ามเอกสาร: หน้าจอที่ผูก Wireframe = backlink ของเอกสาร Wireframe', () {
      final b = WorkspaceIndex(ws()).backlinks('w1');
      expect(b.single.$1, 'f1');
      expect(b.single.$3, const DocRef(docId: 'w1', kind: DocRefKind.screenWireframe));
    });
  });

  group('เรขาคณิต / export / คลิปบอร์ด', () {
    test('เส้นหักมุมฉาก ซ้ายไปขวา ; เส้นวนเข้าตัวเอง ; คลิกโดน', () {
      final d = sample()..edges.add(SfEdge(id: 'loop', fromId: 'home', toId: 'home'));
      final r = sfRoutes(d);
      expect(r.keys.toSet(), {'e1', 'e2', 'e3', 'loop'});
      expect(r['e2']!.first.$1, 250 + 190);
      expect(r['e2']!.last.$1, 550);
      expect(r['loop']!.first.$1, 550 + 190);
      expect(sfNodeAt(d, 260, 20)?.id, 'login');
      expect(sfEdgeAt(d, r['e2']!.first.$1 + 20, r['e2']!.first.$2), 'e2');
    });

    test('จัดวางอัตโนมัติ: ซ้ายไปขวาตามทิศเส้น ผลคงที่', () {
      final d = sample();
      for (final n in d.nodes) {
        n.x = 0;
        n.y = 0;
      }
      final p = sfAutoLayout(d);
      expect(p['s']!.x, lessThan(p['login']!.x));
      expect(p['login']!.x, lessThan(p['home']!.x));
      expect(p['home']!.x, lessThan(p['x']!.x));
      expect(jsonEncode(sfAutoLayout(d).map((k, v) => MapEntry(k, [v.x, v.y]))), jsonEncode(p.map((k, v) => MapEntry(k, [v.x, v.y]))));
    });

    test('SVG: ภาพย่อ Wireframe ในหน้าจอที่ผูก ; ป้าย [เงื่อนไข] ; ว่าง = null', () {
      final w = ws();
      final svg = exportScreenFlowSvg(sample(), wireframeOf: (id) => w.documentById(id)?.wireframe, title: 'A<B')!;
      expect(svg, contains('<title>A&lt;B</title>'));
      expect(svg, contains('viewBox="0 0 1440 900"')); // ภาพย่อหน้าจอ desktop
      expect(svg, contains('click Login [valid]'));
      expect(svg, contains('>Go<'));
      expect(exportScreenFlowSvg(ScreenFlowDiagram()), isNull);
      expect(exportScreenFlowSvg(sample(), dark: true), contains('#121820'));
    });

    test('คลิปบอร์ด: เฉพาะโหนดที่เลือก + เส้นระหว่างกัน', () {
      final back = decodeScreenFlowClipboard(encodeScreenFlowClipboard(sample(), {'login', 'home'}))!;
      expect(back.nodes.map((n) => n.id), ['login', 'home']);
      expect(back.edges.map((e) => e.id), ['e2']);
      expect(decodeScreenFlowClipboard('{"format":"nsl-dev-wireframe"}'), isNull);
    });
  });
}
