import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_dev/core/clipboard/wireframe_clipboard.dart';
import 'package:nsl_dev/core/export/wireframe_svg.dart';
import 'package:nsl_dev/core/layout/wireframe_render.dart';
import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/doc_ref.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/table_model.dart';
import 'package:nsl_dev/core/models/wireframe_model.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_codec.dart';
import 'package:nsl_dev/core/validate/wireframe_validator.dart';
import 'package:nsl_dev/core/validate/workspace_validator.dart';

WireframeDiagram sample() => WireframeDiagram(device: WfDevice.mobile, style: WfStyle.clean, accent: 0xFF16A34A, components: [
      WfComponent(id: 'box', kind: WfKind.card, text: 'Login', x: 20, y: 100, w: 350, h: 300),
      WfComponent(id: 'user', kind: WfKind.input, text: 'Email', x: 40, y: 160, w: 300, h: 40,
          ref: const WfDataRef(docId: 'er', tableId: 'users', columnId: 'email')),
      WfComponent(id: 'go', kind: WfKind.button, text: 'Sign in', x: 40, y: 320, w: 300, h: 44, align: WfAlign.center),
      WfComponent(id: 'tbl', kind: WfKind.table, x: 20, y: 450, w: 350, h: 200, columns: ['Name', 'Role'], rows: 4, disabled: true),
      WfComponent(id: 'chk', kind: WfKind.checkbox, text: 'Remember', x: 40, y: 220, checked: true, fill: 0xFFFFEEAA, bold: true),
    ]);

Map<String, dynamic> roundTrip(Object o) => jsonDecode(jsonEncode(o)) as Map<String, dynamic>;

Project erWithUsers() => Project(name: 'P', tables: [
      TableModel(id: 'users', name: 'users', columns: [ColumnModel(id: 'email', name: 'email')]),
    ]);

Workspace ws([WireframeDiagram? wf]) => Workspace(name: 'P', documents: [
      ProjectDocument.er(id: 'er', name: 'ER', content: erWithUsers()),
      ProjectDocument.wireframe(id: 'w1', name: 'Login screen', content: wf ?? sample()),
    ]);

void main() {
  group('โมเดล', () {
    test('JSON ไป-กลับได้ค่าเดิมทุกช่อง ; ค่าเริ่มต้นไม่ถูกเขียน', () {
      final d = sample();
      final back = WireframeDiagram.fromJson(roundTrip(d.toJson()));
      expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
      expect(back.device, WfDevice.mobile);
      expect((back.width, back.height), (390.0, 844.0));
      expect(back.style, WfStyle.clean);
      expect(back.accent, 0xFF16A34A);
      expect(back.componentById('user')!.ref, const WfDataRef(docId: 'er', tableId: 'users', columnId: 'email'));
      expect(back.componentById('tbl')!.columns, ['Name', 'Role']);
      final go = (roundTrip(d.toJson())['components'] as List)[2] as Map;
      expect(go.keys.toSet(), {'id', 'kind', 'text', 'x', 'y', 'w', 'h', 'align'});
    });

    test('ซ่อมข้อมูลผิดปกติ: ชนิดแปลก/id ซ้ำ/ขนาดเพี้ยน/กรอบเพี้ยน/ref เสีย', () {
      final d = WireframeDiagram.fromJson({
        'device': 'phablet',
        'width': 5,
        'height': double.nan,
        'style': 'neon',
        'accent': 'red',
        'components': [
          {'id': 'a', 'kind': 'button', 'w': 1, 'h': 99999, 'rows': 500, 'fontSize': 1, 'ref': {'doc': '', 'table': 't'}},
          {'id': 'a', 'kind': 'label'},
          {'id': 'b', 'kind': 'hologram'},
          'junk',
          {'id': 'c', 'kind': 'table', 'columns': ['x', 3, 'y'], 'ref': {'doc': 'er', 'table': 't'}},
        ],
      });
      expect(d.device, WfDevice.desktop);
      expect((d.width, d.height), (1440.0, 900.0));
      expect(d.style, WfStyle.sketch);
      expect(d.accent, kWfDefaultAccent);
      expect(d.components.map((c) => c.id), ['a', 'c']);
      final a = d.componentById('a')!;
      expect(a.w, wfDefaultSize(WfKind.button).$1);
      expect(a.h, kWfMaxSide);
      expect(a.rows, 50);
      expect(a.fontSize, isNull);
      expect(a.ref, isNull);
      expect(d.componentById('c')!.columns, ['x', 'y']);
      expect(d.componentById('c')!.ref!.columnId, isNull);
      expect(WireframeDiagram.fromJson(null).components, isEmpty);
    });

    test('ภาชนะ: พ่อ = ภาชนะเล็กสุดที่อยู่ใต้และครอบทั้งใบ ; ลูกหลานไล่ได้หลายชั้น', () {
      final d = WireframeDiagram(components: [
        WfComponent(id: 'outer', kind: WfKind.container, x: 0, y: 0, w: 500, h: 500),
        WfComponent(id: 'card', kind: WfKind.card, x: 10, y: 10, w: 300, h: 300),
        WfComponent(id: 'btn', kind: WfKind.button, x: 20, y: 20),
        WfComponent(id: 'img', kind: WfKind.image, x: 400, y: 400, w: 200, h: 50), // ล้นภาชนะ = ไม่ใช่ลูก
        WfComponent(id: 'lbl', kind: WfKind.label, x: 30, y: 200), // อยู่ในการ์ดด้วย
      ]);
      final p = wfParentMap(d);
      expect(p, {'card': 'outer', 'btn': 'card', 'lbl': 'card'});
      expect(wfDescendants(d, {'outer'}), {'card', 'btn', 'lbl'});
      expect(wfDescendants(d, {'btn'}), isEmpty);
      // ภาชนะที่อยู่เหนือชิ้น (ลำดับการซ้อนหลังกว่า) ไม่นับเป็นพ่อ
      final d2 = WireframeDiagram(components: [
        WfComponent(id: 'btn', kind: WfKind.button, x: 20, y: 20),
        WfComponent(id: 'box', kind: WfKind.container, x: 0, y: 0, w: 300, h: 300),
      ]);
      expect(wfParentMap(d2), isEmpty);
    });
  });

  group('ไฟล์ v3', () {
    test('บันทึกเป็นชนิด "wireframe" และเปิดกลับได้เนื้อหาเดิม ; ชื่อว่าง = "Wireframe"', () {
      final j = roundTrip(encodeProjectMap(ws()));
      expect(j['version'], 3);
      final doc = (j['documents'] as List).firstWhere((d) => d['id'] == 'w1') as Map;
      expect(doc['type'], 'wireframe');
      final back = decodeProjectMap(j);
      expect(back.documentById('w1')!.type, DocType.wireframe);
      expect(jsonEncode(back.documentById('w1')!.wireframe!.toJson()), jsonEncode(sample().toJson()));
      expect(jsonEncode(encodeProjectMap(back)), jsonEncode(j));
      final named = decodeProjectMap({
        'format': 'nsl-erd',
        'version': 3,
        'documents': [
          {'id': 'er', 'type': 'er', 'name': 'wireframe', 'content': {}},
          {'id': 'w', 'type': 'wireframe', 'name': '', 'content': 7},
        ],
      });
      expect(named.documents.map((d) => d.name), ['wireframe', 'Wireframe 2']);
    });

    test('จำลองรุ่นที่ไม่รู้จัก wireframe: เก็บดิบและเขียนกลับไม่เปลี่ยน แล้วรุ่นนี้เปิดได้ครบ', () {
      final j = roundTrip(encodeProjectMap(ws()));
      final raw = jsonEncode(j).replaceAll('"type":"wireframe"', '"type":"wireframe-unknown"');
      final old = decodeProjectMap(jsonDecode(raw) as Map<String, dynamic>);
      expect(old.documentById('w1')!.type, isNull);
      expect(old.documentById('w1')!.content, isA<RawDocContent>());
      final saved = jsonEncode(encodeProjectMap(old)).replaceAll('"type":"wireframe-unknown"', '"type":"wireframe"');
      expect(saved, jsonEncode(j));
      final reopened = decodeProjectMap(jsonDecode(saved) as Map<String, dynamic>);
      expect(reopened.documentById('w1')!.wireframe!.components.length, 5);
    });
  });

  group('ตัวตรวจ', () {
    test('ไม่มีปัญหาเมื่อทุกอย่างอยู่ในกรอบและผูกถูก', () {
      final d = WireframeDiagram(components: [WfComponent(id: 'b', kind: WfKind.button, text: 'OK', x: 10, y: 10)]);
      expect(validateWireframe(d), isEmpty);
    });

    test('ล้นกรอบ/นอกกรอบ (warning) ; ซ้อนทับบางส่วน (warning) ; ปุ่มไม่มีข้อความ (info) ; ref ขาด (error)', () {
      final d = WireframeDiagram(device: WfDevice.mobile, components: [
        WfComponent(id: 'out', kind: WfKind.label, text: 'x', x: 1000, y: 10),
        WfComponent(id: 'edge', kind: WfKind.label, text: 'x', x: 300, y: 10, w: 200),
        WfComponent(id: 'a', kind: WfKind.image, x: 10, y: 100, w: 100, h: 100),
        WfComponent(id: 'b', kind: WfKind.image, x: 60, y: 150, w: 100, h: 100),
        WfComponent(id: 'inside', kind: WfKind.icon, x: 20, y: 110), // อยู่ใน a ทั้งชิ้น = ไม่เตือน
        WfComponent(id: 'empty', kind: WfKind.button, text: '  ', x: 10, y: 400),
        WfComponent(id: 'ref', kind: WfKind.input, x: 10, y: 500, ref: const WfDataRef(docId: 'er', tableId: 'users', columnId: 'gone')),
        WfComponent(id: 'ref2', kind: WfKind.input, x: 10, y: 600, ref: const WfDataRef(docId: 'nope', tableId: 'users')),
      ]);
      final w = ws(d);
      final issues = validateWireframe(d, workspace: w);
      String codes(String id) => issues.where((i) => i.tableId == id).map((i) => i.code).join(',');
      expect(codes('out'), 'wf_out_of_frame');
      expect(codes('edge'), 'wf_out_of_frame');
      expect(codes('b'), 'wf_overlap');
      expect(codes('a'), '');
      expect(codes('inside'), '');
      expect(codes('empty'), 'wf_empty_text');
      expect(codes('ref'), 'wf_ref_missing');
      expect(codes('ref2'), 'wf_ref_missing');
      expect(issues.first.severity.name, 'error');
      expect(issues.firstWhere((i) => i.code == 'wf_empty_text').severity.name, 'info');
      // ไม่ส่ง workspace = ไม่ตรวจการผูก
      expect(validateWireframe(d).where((i) => i.code == 'wf_ref_missing'), isEmpty);
      // validateWorkspace รวมปัญหาของ Wireframe ด้วย
      expect(validateWorkspace(w).where((i) => i.docType == DocType.wireframe && i.issue.code == 'wf_ref_missing').length, 2);
    });

    test('ลิงก์ข้ามเอกสาร: ชิ้นที่ผูกตาราง = backlink ของเอกสาร ER', () {
      final idx = WorkspaceIndex(ws());
      final b = idx.backlinks('er');
      expect(b.single.$1, 'w1');
      expect(b.single.$2, 'user');
      expect(b.single.$3, const DocRef(docId: 'er', elementId: 'users', subElementId: 'email', kind: DocRefKind.wireframeTable));
      expect(wfRefLabel(ws(), sample().componentById('user')!.ref!), 'users.email');
      expect(wfRefLabel(ws(), const WfDataRef(docId: 'er', tableId: 'zz'), withDoc: true), 'ER › zz');
    });
  });

  group('การแสดงผลและ export', () {
    test('ชิ้นวาดคงที่ทุกครั้ง ; สองรูปแบบได้ภาพต่างกัน ; รูปแบบร่างเป็นขาวดำ', () {
      final clean = sample();
      final sketch = sample()..style = WfStyle.sketch;
      expect(exportWireframeSvg(clean), exportWireframeSvg(sample()));
      expect(exportWireframeSvg(sketch), isNot(exportWireframeSvg(clean)));
      // สีที่ใช้ในรูปแบบร่างเป็นเทาทั้งหมด (r == g == b)
      for (final p in wireframePrims(sketch)) {
        final colors = switch (p) {
          WfPathPrim() => [?p.fill, ?p.stroke],
          WfTextPrim() => [p.color],
        };
        for (final c in colors) {
          final r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
          expect(r == g && g == b, isTrue, reason: c.toRadixString(16));
        }
      }
      // รูปแบบเรียบร้อยใช้สีเน้นของเอกสาร
      expect(exportWireframeSvg(clean), contains('#16A34A'));
      expect(exportWireframeSvg(sketch), isNot(contains('#16A34A')));
    });

    test('SVG: ข้อความ escape, ไม่โปร่งใส = มีพื้นหลัง, รูปภาพแบบร่างเป็นกากบาท', () {
      final d = WireframeDiagram(components: [
        WfComponent(id: 'l', kind: WfKind.label, text: 'a < b & "c"', x: 10, y: 10),
        WfComponent(id: 'i', kind: WfKind.image, x: 10, y: 60),
      ]);
      final svg = exportWireframeSvg(d, title: 'T&T');
      expect(svg, startsWith('<svg'));
      expect(svg, contains('a &lt; b &amp; &quot;c&quot;'));
      expect(svg, contains('<title>T&amp;T</title>'));
      expect(exportWireframeSvg(d, transparent: true).contains('fill="#F4F4F2"'), isFalse);
      expect(svg, contains('fill="#F4F4F2"'));
    });

    test('คลิปบอร์ด: เข้ารหัส/ถอดรหัส ; ข้อมูลอื่น = null', () {
      final text = encodeWireframeClipboard(sample(), {'go', 'user'});
      final back = decodeWireframeClipboard(text)!;
      expect(back.map((c) => c.id), ['user', 'go']);
      expect(decodeWireframeClipboard('{"format":"nsl-dev-flowchart","nodes":[]}'), isNull);
      expect(decodeWireframeClipboard('nope'), isNull);
      expect(decodeWireframeClipboard(encodeWireframeClipboard(sample(), {})), isNull);
    });
  });
}
