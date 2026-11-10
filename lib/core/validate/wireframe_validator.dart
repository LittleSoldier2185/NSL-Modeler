import '../l10n/l10n.dart';
import '../layout/box_ops.dart';
import '../models/wireframe_model.dart';
import '../models/workspace.dart';
import 'issue.dart';

/// ตรวจ Wireframe ([Issue.tableId] = id ชิ้นส่วน)
///
/// - error: ชิ้นส่วนผูกกับเอกสาร ER / ตาราง / คอลัมน์ที่ไม่มีแล้ว (ต้องส่ง [workspace] มาด้วย)
/// - warning: ชิ้นส่วนล้นหรืออยู่นอกกรอบหน้าจอ, ชิ้นส่วนซ้อนทับกันบางส่วน (ไม่นับชิ้นที่อยู่ในภาชนะ/ชิ้นอื่นทั้งใบ)
/// - info: ปุ่ม/ป้าย/หัวข้อที่ไม่มีข้อความ
List<Issue> validateWireframe(WireframeDiagram d, {Workspace? workspace}) {
  final out = <Issue>[];
  final frame = WfComponent(id: '', kind: WfKind.container, x: 0, y: 0, w: d.width, h: d.height);
  for (final c in d.components) {
    if (!boxesOverlap(c, frame)) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'wf_out_of_frame',
        title: tr('ชิ้นส่วนอยู่นอกกรอบหน้าจอ'),
        message: tr('{0} อยู่นอกกรอบหน้าจอทั้งชิ้น', [wfComponentTitle(c)]),
        tableId: c.id,
      ));
    } else if (!boxInside(c, frame)) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'wf_out_of_frame',
        title: tr('ชิ้นส่วนล้นกรอบหน้าจอ'),
        message: tr('{0} ล้นออกนอกกรอบหน้าจอ', [wfComponentTitle(c)]),
        tableId: c.id,
      ));
    }
  }

  // ซ้อนทับกันบางส่วน (ชิ้นหนึ่งอยู่ในอีกชิ้นทั้งใบ = ตั้งใจวางซ้อน ไม่เตือน)
  final list = d.components;
  for (var j = 1; j < list.length; j++) {
    for (var i = 0; i < j; i++) {
      final a = list[i], b = list[j];
      if (!boxesOverlap(a, b) || boxInside(a, b) || boxInside(b, a)) continue;
      if (a.kind == WfKind.divider || b.kind == WfKind.divider) continue;
      out.add(Issue(
        severity: Severity.warning,
        code: 'wf_overlap',
        title: tr('ชิ้นส่วนซ้อนทับกัน'),
        message: tr('{0} ทับกับ {1} บางส่วน', [wfComponentTitle(b), wfComponentTitle(a)]),
        tableId: b.id,
      ));
      break; // เตือนครั้งเดียวต่อชิ้น
    }
  }

  for (final c in d.components) {
    if ((c.kind == WfKind.button || c.kind == WfKind.label || c.kind == WfKind.heading) && c.text.trim().isEmpty) {
      out.add(Issue(
        severity: Severity.info,
        code: 'wf_empty_text',
        title: tr('ไม่มีข้อความ'),
        message: tr('{0} ยังไม่มีข้อความ', [wfKindLabel(c.kind)]),
        tableId: c.id,
      ));
    }
    final r = c.ref;
    if (r != null && workspace != null && wfRefProblem(workspace, r) != null) {
      out.add(Issue(
        severity: Severity.error,
        code: 'wf_ref_missing',
        title: tr('ผูกกับข้อมูล ER ที่ไม่มีแล้ว'),
        message: tr('{0}: {1} — เลือกใหม่หรือเลิกผูก', [wfComponentTitle(c), wfRefProblem(workspace, r)!]),
        tableId: c.id,
      ));
    }
  }
  out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return out;
}

/// ปัญหาของการผูก [r] (null = ใช้ได้)
String? wfRefProblem(Workspace w, WfDataRef r) {
  final er = w.documentById(r.docId)?.er;
  if (er == null) return tr('ไม่พบเอกสาร ER');
  final t = er.tableById(r.tableId);
  if (t == null) return tr('ไม่พบตาราง');
  if (r.columnId != null && t.columnById(r.columnId!) == null) return tr('ไม่พบคอลัมน์');
  return null;
}

/// ข้อความแสดงการผูก "ER › ตาราง.คอลัมน์" (ไม่พบ = id ดิบ) ; [withDoc] = ใส่ชื่อเอกสาร ER นำหน้า
String wfRefLabel(Workspace? w, WfDataRef r, {bool withDoc = false}) {
  final doc = w?.documentById(r.docId);
  final t = doc?.er?.tableById(r.tableId);
  final col = r.columnId == null ? null : t?.columnById(r.columnId!);
  final table = t?.name ?? r.tableId;
  final column = r.columnId == null ? '' : '.${col?.name ?? r.columnId}';
  final pre = withDoc ? '${doc?.name ?? r.docId} › ' : '';
  return '$pre$table$column';
}

/// ชื่อแสดงของชิ้นส่วน (บรรทัดเดียว): ข้อความบรรทัดแรก หรือชื่อชนิด
String wfComponentTitle(WfComponent c) {
  final t = c.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return wfKindLabel(c.kind);
  final one = t.length > 40 ? '${t.substring(0, 39)}…' : t;
  return '${wfKindLabel(c.kind)} "$one"';
}

/// ชื่อชนิดชิ้นส่วน (แสดงในคลัง/แผง/รายงาน)
String wfKindLabel(WfKind k) => switch (k) {
      WfKind.container => tr('กล่อง / ภาชนะ'),
      WfKind.heading => tr('หัวข้อ'),
      WfKind.label => tr('ป้ายข้อความ'),
      WfKind.paragraph => tr('ย่อหน้า'),
      WfKind.button => tr('ปุ่ม'),
      WfKind.input => tr('ช่องกรอกข้อความ'),
      WfKind.textarea => tr('ช่องกรอกหลายบรรทัด'),
      WfKind.checkbox => tr('ช่องทำเครื่องหมาย'),
      WfKind.radio => tr('ปุ่มตัวเลือก (radio)'),
      WfKind.toggle => tr('สวิตช์'),
      WfKind.select => tr('ดรอปดาวน์'),
      WfKind.slider => tr('แถบเลื่อน'),
      WfKind.search => tr('ช่องค้นหา'),
      WfKind.image => tr('รูปภาพ'),
      WfKind.icon => tr('ไอคอน'),
      WfKind.avatar => tr('รูปโปรไฟล์'),
      WfKind.table => tr('ตาราง@@wf'),
      WfKind.list => tr('รายการ'),
      WfKind.card => tr('การ์ด'),
      WfKind.tabs => tr('แถบแท็บ'),
      WfKind.navbar => tr('แถบนำทางบน'),
      WfKind.sidebar => tr('แถบข้าง'),
      WfKind.modal => tr('หน้าต่างโต้ตอบ (modal)'),
      WfKind.divider => tr('เส้นคั่น'),
      WfKind.badge => tr('ป้ายสถานะ'),
      WfKind.pagination => tr('ตัวแบ่งหน้า'),
      WfKind.breadcrumb => tr('เส้นทางนำทาง (breadcrumb)'),
      WfKind.map => tr('แผนที่'),
      WfKind.chart => tr('กราฟ'),
    };

/// ชื่อรูปแบบการแสดงผล
String wfStyleLabel(WfStyle s) => switch (s) {
      WfStyle.sketch => tr('ร่าง (low-fidelity)'),
      WfStyle.clean => tr('เรียบร้อย (medium-fidelity)'),
    };

/// ชื่อขนาดหน้าจอสำเร็จรูป
String wfDeviceLabel(WfDevice d) => switch (d) {
      WfDevice.desktop => tr('เดสก์ท็อป 1440×900'),
      WfDevice.laptop => tr('แล็ปท็อป 1280×800'),
      WfDevice.tablet => tr('แท็บเล็ต แนวตั้ง 768×1024'),
      WfDevice.tabletLandscape => tr('แท็บเล็ต แนวนอน 1024×768'),
      WfDevice.mobile => tr('มือถือ 390×844'),
      WfDevice.mobileSmall => tr('มือถือ 360×800'),
      WfDevice.custom => tr('กำหนดเอง'),
    };
