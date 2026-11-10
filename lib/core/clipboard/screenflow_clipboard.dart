import 'dart:convert';

import '../models/screenflow_model.dart';

const _marker = 'nsl-dev-screenflow';

/// ข้อความสำหรับคลิปบอร์ดของระบบ: โหนด Screen Flow ที่เลือก + เส้นระหว่างกันเอง
String encodeScreenFlowClipboard(ScreenFlowDiagram d, Set<String> nodeIds) {
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

/// อ่านข้อความจากคลิปบอร์ด — null ถ้าไม่ใช่ข้อมูล Screen Flow ของโปรแกรมนี้ (หรือเสียหาย/ว่าง)
ScreenFlowDiagram? decodeScreenFlowClipboard(String? text) {
  if (text == null || !text.trimLeft().startsWith('{')) return null;
  try {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> || j['format'] != _marker) return null;
    final d = ScreenFlowDiagram.fromJson(j);
    return d.nodes.isEmpty ? null : d;
  } catch (_) {
    return null;
  }
}
