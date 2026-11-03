/// ชนิดของแผนภาพในโปรเจกต์ (แท็บเหนือแคนวาส)
enum DiagramKind {
  /// แผนภาพ ER (ตาราง/ความสัมพันธ์) — เนื้อหาอยู่ที่ฟิลด์หลักของ Project; มีอันเดียวและลบไม่ได้
  er,

  /// Data Flow Diagram — ไม่เกี่ยวกับ SQL
  dfd,
}

/// id ตายตัวของแท็บ ER
const String kErDiagramId = 'er';

const int kDiagramNameMax = 40;

/// แท็บหนึ่งแท็บ: ข้อมูลที่ใช้แสดงและเรียงลำดับ (เนื้อหาของ DFD จะเพิ่มในรอบถัดไป)
class DiagramTab {
  DiagramTab({required this.id, required this.name, required this.kind});

  final String id;
  String name;
  final DiagramKind kind;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind.name};

  /// ค่าผิดปกติ (ไม่ใช่ map / ไม่มี id / ชนิดไม่รู้จัก) = null
  static DiagramTab? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = DiagramKind.values.where((k) => k.name == j['kind']).firstOrNull;
    if (id is! String || id.isEmpty || kind == null) return null;
    final name = j['name'];
    return DiagramTab(id: id, name: name is String ? cleanDiagramName(name) : '', kind: kind);
  }
}

/// ตัดช่องว่างหัวท้าย/ย่อให้ไม่เกิน [kDiagramNameMax]
String cleanDiagramName(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length > kDiagramNameMax ? t.substring(0, kDiagramNameMax).trimRight() : t;
}

/// จัดรายการแท็บให้ถูกต้องเสมอ: มี ER อันเดียว (id = [kErDiagramId]), id ไม่ซ้ำ, ชื่อไม่ว่างและไม่ซ้ำ (ไม่สนตัวพิมพ์)
List<DiagramTab> normalizeDiagrams(Iterable<DiagramTab>? input) {
  final out = <DiagramTab>[];
  final ids = <String>{};
  var haveEr = false;
  for (final t in input ?? const <DiagramTab>[]) {
    if (t.kind == DiagramKind.er) {
      if (haveEr) continue;
      haveEr = true;
      out.add(DiagramTab(id: kErDiagramId, name: t.name, kind: DiagramKind.er));
      ids.add(kErDiagramId);
    } else {
      if (t.id == kErDiagramId || !ids.add(t.id)) continue;
      out.add(DiagramTab(id: t.id, name: t.name, kind: t.kind));
    }
  }
  if (!haveEr) out.insert(0, DiagramTab(id: kErDiagramId, name: '', kind: DiagramKind.er));

  final used = <String>{};
  for (final t in out) {
    var base = cleanDiagramName(t.name);
    if (base.isEmpty) base = t.kind == DiagramKind.er ? 'ER' : 'DFD';
    var name = base;
    for (var n = 2; used.contains(name.toLowerCase()); n++) {
      name = '$base $n';
    }
    used.add(name.toLowerCase());
    t.name = name;
  }
  return out;
}
