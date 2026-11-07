import 'dart:convert';

import '../models/flowchart_model.dart';

const _marker = 'nsl-dev-flowchart';

/// ข้อความสำหรับคลิปบอร์ดของระบบ : สัญลักษณ์ Flowchart ที่เลือก + เส้นระหว่างกันเอง
/// เป็น JSON ที่มีเครื่องหมายระบุ จึงวางข้ามแท็บ/ข้ามโปรเจกต์ได้ และแยกจากข้อมูล DFD/ER/ข้อความทั่วไปได้
String encodeFlowchartClipboard(FlowchartDiagram d, Set<String> nodeIds) {
  final nodes = [for (final n in d.nodes) if (nodeIds.contains(n.id)) n];
  final inside = nodes.map((n) => n.id).toSet();
  return jsonEncode({
    'format': _marker,
    'version': 1,
    'nodes': [for (final n in nodes) n.toJson()],
    'edges': [
      for (final e in d.edges)
        if (inside.contains(e.fromId) && inside.contains(e.toId)) e.toJson(),
    ],
  });
}

/// อ่านข้อความจากคลิปบอร์ด — null ถ้าไม่ใช่ข้อมูล Flowchart ของโปรแกรมนี้ (หรือเสียหาย/ว่าง)
FlowchartDiagram? decodeFlowchartClipboard(String? text) {
  if (text == null || !text.trimLeft().startsWith('{')) return null;
  try {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> || j['format'] != _marker) return null;
    final d = FlowchartDiagram.fromJson(j);
    return d.nodes.isEmpty ? null : d;
  } catch (_) {
    return null;
  }
}
