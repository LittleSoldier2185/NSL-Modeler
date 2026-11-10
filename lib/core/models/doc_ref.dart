import 'dfd_model.dart';
import 'workspace.dart';

/// ชนิดของการอ้างอิงข้ามเอกสาร
enum DocRefKind {
  /// กระบวนการใน DFD ชี้ไปแผนภาพย่อย (เอกสาร DFD)
  dfdChild,

  /// ที่เก็บข้อมูลใน DFD ผูกกับตารางในเอกสาร ER
  storeTable,

  /// ชิ้นส่วนใน Wireframe ผูกกับตาราง (และคอลัมน์) ในเอกสาร ER
  wireframeTable,

  /// หน้าจอใน Screen Flow ผูกกับเอกสาร Wireframe
  screenWireframe,
}

/// การอ้างอิงไปยังเอกสาร [docId] (และวัตถุ [elementId] ในเอกสารนั้น ถ้ามี)
class DocRef {
  const DocRef({required this.docId, this.elementId, required this.kind, this.subElementId});

  final String docId;
  final String? elementId;

  /// วัตถุย่อยใน [elementId] (เช่น คอลัมน์ของตาราง) — null = ไม่มี
  final String? subElementId;
  final DocRefKind kind;

  @override
  bool operator ==(Object other) =>
      other is DocRef &&
      other.docId == docId &&
      other.elementId == elementId &&
      other.subElementId == subElementId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(docId, elementId, subElementId, kind);

  @override
  String toString() => 'DocRef($kind → $docId${elementId == null ? '' : '/$elementId'}${subElementId == null ? '' : '/$subElementId'})';
}

/// ดัชนีการอ้างอิงข้ามเอกสารของ workspace (โครงเริ่มต้น — คำนวณใหม่ทุกครั้งที่สร้าง)
class WorkspaceIndex {
  WorkspaceIndex(Workspace w) {
    for (final d in w.documents) {
      for (final n in d.dfd?.nodes ?? const <DfdNode>[]) {
        final child = n.childId;
        if (n.kind == DfdKind.process && child != null) {
          _add(d.id, n.id, DocRef(docId: child, kind: DocRefKind.dfdChild));
        }
        final table = n.tableId, tableDoc = n.tableDocId;
        if (n.kind == DfdKind.store && table != null && tableDoc != null) {
          _add(d.id, n.id, DocRef(docId: tableDoc, elementId: table, kind: DocRefKind.storeTable));
        }
      }
      for (final c in d.wireframe?.components ?? const []) {
        final r = c.ref;
        if (r != null) {
          _add(d.id, c.id, DocRef(docId: r.docId, elementId: r.tableId, subElementId: r.columnId, kind: DocRefKind.wireframeTable));
        }
      }
      for (final n in d.screenflow?.nodes ?? const []) {
        final wf = n.wireframeId;
        if (wf != null) _add(d.id, n.id, DocRef(docId: wf, kind: DocRefKind.screenWireframe));
      }
    }
  }

  /// เอกสารที่อ้างอิงถึงแต่ละเอกสาร: docId ปลายทาง -> [(เอกสารต้นทาง, วัตถุต้นทาง, ref)]
  final Map<String, List<(String fromDoc, String fromElement, DocRef ref)>> _incoming = {};

  void _add(String fromDoc, String fromElement, DocRef ref) =>
      _incoming.putIfAbsent(ref.docId, () => []).add((fromDoc, fromElement, ref));

  /// การอ้างอิงที่ชี้มาที่เอกสาร [docId] จากเอกสารอื่น (ใช้แสดงจำนวนตอนยืนยันการลบ)
  List<(String fromDoc, String fromElement, DocRef ref)> backlinks(String docId) =>
      [for (final e in _incoming[docId] ?? const <(String, String, DocRef)>[]) if (e.$1 != docId) e];

  int backlinkCount(String docId) => backlinks(docId).length;
}
