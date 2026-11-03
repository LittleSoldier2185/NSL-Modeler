import 'dart:convert';

import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';

const _marker = 'nsl-modeler-tables';

class ClipboardPayload {
  const ClipboardPayload(this.tables, this.relations);
  final List<TableModel> tables;

  /// เฉพาะความสัมพันธ์ที่ปลายทั้งสองข้างอยู่ในตารางที่คัดลอก
  final List<RelationModel> relations;
}

/// ข้อความสำหรับใส่คลิปบอร์ดของระบบ: ตารางที่เลือก + FK ระหว่างกันเอง
/// เป็น JSON ที่มีเครื่องหมายระบุ จึงวางข้ามโปรเจกต์/ข้ามหน้าต่างได้ และแยกออกจากข้อความทั่วไปได้
String encodeTableClipboard(Project p, Set<String> ids) {
  final tables = [for (final t in p.tables) if (ids.contains(t.id)) t];
  final inside = tables.map((t) => t.id).toSet();
  return jsonEncode({
    'format': _marker,
    'version': 1,
    'tables': [for (final t in tables) t.toJson()],
    'relations': [
      for (final r in p.relations)
        if (inside.contains(r.fromTableId) && inside.contains(r.toTableId)) r.toJson()
    ],
  });
}

/// อ่านข้อความจากคลิปบอร์ด — null ถ้าไม่ใช่ข้อมูลตารางของโปรแกรมนี้ (หรือเสียหาย)
ClipboardPayload? decodeTableClipboard(String? text) {
  if (text == null || !text.trimLeft().startsWith('{')) return null;
  try {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> || j['format'] != _marker) return null;
    final tables = [
      for (final t in (j['tables'] as List)) TableModel.fromJson(t as Map<String, dynamic>),
    ];
    if (tables.isEmpty) return null;
    final ids = tables.map((t) => t.id).toSet();
    final rels = [
      for (final r in (j['relations'] as List? ?? []))
        RelationModel.fromJson(r as Map<String, dynamic>),
    ].where((r) => ids.contains(r.fromTableId) && ids.contains(r.toTableId)).toList();
    return ClipboardPayload(tables, rels);
  } catch (_) {
    return null;
  }
}
