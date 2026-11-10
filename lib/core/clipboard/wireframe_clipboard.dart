import 'dart:convert';

import '../models/wireframe_model.dart';

const _marker = 'nsl-dev-wireframe';

/// ข้อความสำหรับคลิปบอร์ดของระบบ: ชิ้นส่วน Wireframe [ids] ตามลำดับการซ้อน (JSON มีเครื่องหมายระบุ วางข้ามแท็บ/โปรเจกต์ได้)
String encodeWireframeClipboard(WireframeDiagram d, Set<String> ids) => jsonEncode({
      'format': _marker,
      'version': 1,
      'components': [for (final c in d.components) if (ids.contains(c.id)) c.toJson()],
    });

/// อ่านข้อความจากคลิปบอร์ด — null ถ้าไม่ใช่ข้อมูล Wireframe ของโปรแกรมนี้ (หรือเสียหาย/ว่าง)
List<WfComponent>? decodeWireframeClipboard(String? text) {
  if (text == null || !text.trimLeft().startsWith('{')) return null;
  try {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> || j['format'] != _marker) return null;
    final d = WireframeDiagram.fromJson({'components': j['components']});
    return d.components.isEmpty ? null : d.components;
  } catch (_) {
    return null;
  }
}
