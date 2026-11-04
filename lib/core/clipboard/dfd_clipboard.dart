import 'dart:convert';

import '../models/dfd_model.dart';

const _marker = 'nsl-modeler-dfd';

class DfdClipboardPayload {
  const DfdClipboardPayload(this.nodes, this.flows, this.boundaries);
  final List<DfdNode> nodes;

  /// เฉพาะเส้นที่ปลายทั้งสองข้างอยู่ในวัตถุที่คัดลอก
  final List<DfdFlow> flows;
  final List<DfdBoundary> boundaries;

  bool get isEmpty => nodes.isEmpty && boundaries.isEmpty;
}

/// ข้อความสำหรับคลิปบอร์ดของระบบ : วัตถุ DFD ที่เลือก + เส้นข้อมูลระหว่างกันเอง (+ ขอบเขตระบบที่เลือก)
/// เป็น JSON ที่มีเครื่องหมายระบุ จึงวางข้ามแท็บ/ข้ามโปรเจกต์ได้ และแยกจากข้อความทั่วไป/ตาราง ER ได้
String encodeDfdClipboard(DfdDiagram d, {required Set<String> nodeIds, String? boundaryId}) {
  final nodes = [for (final n in d.nodes) if (nodeIds.contains(n.id)) n];
  final inside = nodes.map((n) => n.id).toSet();
  final b = boundaryId == null ? null : d.boundaryById(boundaryId);
  return jsonEncode({
    'format': _marker,
    'version': 1,
    'nodes': [for (final n in nodes) n.toJson()],
    'flows': [
      for (final f in d.flows)
        if (inside.contains(f.fromId) && inside.contains(f.toId)) f.toJson(),
    ],
    if (b != null) 'boundaries': [b.toJson()],
  });
}

/// อ่านข้อความจากคลิปบอร์ด — null ถ้าไม่ใช่ข้อมูล DFD ของโปรแกรมนี้ (หรือเสียหาย/ว่าง)
DfdClipboardPayload? decodeDfdClipboard(String? text) {
  if (text == null || !text.trimLeft().startsWith('{')) return null;
  try {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> || j['format'] != _marker) return null;
    final d = DfdDiagram.fromJson(j); // ซ่อมข้อมูลผิดปกติ/ตัดเส้นที่ชี้ไปวัตถุที่ไม่มี ให้เหมือนตอนเปิดไฟล์
    final p = DfdClipboardPayload(d.nodes, d.flows, d.boundaries);
    return p.isEmpty ? null : p;
  } catch (_) {
    return null;
  }
}
