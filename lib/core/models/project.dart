import 'color_utils.dart';
import 'dfd_model.dart';
import 'diagram.dart';
import 'enums.dart';
import 'group_model.dart';
import 'note_model.dart';
import 'relation_model.dart';
import 'table_model.dart';
import 'workspace.dart';

/// ขนาดกระดานเริ่มต้นและช่วงที่อนุญาตตอนกำหนดเอง (px ในพิกัดโปรเจกต์)
const double kDefaultBoardWidth = 2400;
const double kDefaultBoardHeight = 1500;
const double kMinBoardSide = 800;
const double kMaxBoardSide = 20000;

/// เนื้อหาของเอกสาร ER หนึ่งชิ้น (ไฟล์ v1/v2 เดิม: ทั้งโปรเจกต์ รวมแท็บ [diagrams] และเนื้อหา DFD [dfd])
class Project implements DocContent {
  Project({
    this.name = 'untitled',
    this.dialect = Dialect.mysql,
    this.boardWidth = kDefaultBoardWidth,
    this.boardHeight = kDefaultBoardHeight,
    this.lineColor,
    List<TableModel>? tables,
    List<RelationModel>? relations,
    List<NoteModel>? notes,
    List<GroupModel>? groups,
    List<DiagramTab>? diagrams,
    Map<String, DfdDiagram>? dfd,
  })  : diagrams = normalizeDiagrams(diagrams),
        tables = tables ?? [],
        relations = relations ?? [],
        notes = notes ?? [],
        groups = groups ?? [] {
    // เนื้อหา DFD: มีรายการสำหรับทุกแท็บ DFD เสมอ และไม่มีรายการของแท็บที่ไม่มีอยู่
    this.dfd = {
      for (final t in this.diagrams)
        if (t.kind == DiagramKind.dfd) t.id: dfd?[t.id] ?? DfdDiagram(),
    };
  }

  String name;
  Dialect dialect;

  /// แท็บแผนภาพตามลำดับที่แสดง (มีแท็บ ER เสมอ) — เนื้อหาของ ER คือฟิลด์ tables/relations/notes/groups ด้านล่าง
  List<DiagramTab> diagrams;

  /// เนื้อหาของแท็บ DFD (key = id ของแท็บ)
  late Map<String, DfdDiagram> dfd;

  /// เนื้อหา DFD ของแท็บ [id] (สร้างให้ถ้ายังไม่มี)
  DfdDiagram dfdOf(String id) => dfd.putIfAbsent(id, DfdDiagram.new);

  DiagramTab? diagramById(String id) {
    for (final d in diagrams) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// ชื่อแท็บที่ยังไม่มีใครใช้ ([base], [base] 2, ...)
  String uniqueDiagramName(String base, {String? except}) {
    final used = {for (final d in diagrams) if (d.id != except) d.name.toLowerCase()};
    var name = base;
    for (var n = 2; used.contains(name.toLowerCase()); n++) {
      name = '$base $n';
    }
    return name;
  }

  /// สีเส้นความสัมพันธ์เริ่มต้นของทั้งโปรเจกต์ (ARGB) — null = สีตามธีม
  int? lineColor;

  /// ขนาดกระดานขั้นต่ำ — กรอบจะขยายเกินนี้เองเมื่อมีของวางนอกกรอบ
  double boardWidth;
  double boardHeight;
  List<TableModel> tables;
  List<RelationModel> relations;
  List<NoteModel> notes;

  /// กลุ่มตาราง (กรอบเส้นประมีชื่อ)
  List<GroupModel> groups;

  GroupModel? groupById(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  TableModel? tableById(String id) {
    for (final t in tables) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// เวอร์ชันสูงสุดที่อ่านได้ — เวอร์ชัน 2 = มีแผนภาพ DFD (ไฟล์ที่มีแต่ ER ยังเขียนเป็นเวอร์ชัน 1 เปิดด้วยโปรแกรมรุ่นเก่าได้)
  static const formatVersion = 2;

  bool get _hasExtraDiagrams => diagrams.any((d) => d.kind != DiagramKind.er);

  /// [withDfd] = false ตอนทำ snapshot undo ของ ER (เนื้อหา DFD มีประวัติแยกต่อแท็บ)
  Map<String, dynamic> toJson({bool withDfd = true}) => {
        'format': 'nsl-erd',
        'version': _hasExtraDiagrams ? 2 : 1,
        'name': name,
        'dialect': dialect.name,
        'board': {'width': boardWidth, 'height': boardHeight},
        if (lineColor != null) 'lineColor': lineColor,
        // แท็บ: เขียนเมื่อมีอะไรมากกว่าแท็บ ER ชื่อเริ่มต้น (ไฟล์ ER ล้วนเหมือนเดิมทุกไบต์)
        if (_hasExtraDiagrams || diagrams.single.name != 'ER') 'diagrams': diagrams.map((d) => d.toJson()).toList(),
        'tables': tables.map((t) => t.toJson()).toList(),
        'relations': relations.map((r) => r.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
        if (groups.isNotEmpty) 'groups': groups.map((g) => g.toJson()).toList(),
        if (withDfd && dfd.isNotEmpty) 'dfd': {for (final e in dfd.entries) e.key: e.value.toJson()},
      };

  /// เนื้อหา ER สำหรับเอกสารในไฟล์ v3 (คีย์เดียวกับ [toJson] แต่ไม่มีหัวไฟล์ แท็บ และ DFD)
  @override
  Map<String, dynamic> toContentJson() => {
        'name': name,
        'dialect': dialect.name,
        'board': {'width': boardWidth, 'height': boardHeight},
        if (lineColor != null) 'lineColor': lineColor,
        'tables': tables.map((t) => t.toJson()).toList(),
        'relations': relations.map((r) => r.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
        if (groups.isNotEmpty) 'groups': groups.map((g) => g.toJson()).toList(),
      };

  /// อ่านเนื้อหา ER ของเอกสาร v3 (ไม่สนคีย์แท็บ/DFD ถ้ามีหลงมา)
  factory Project.fromContentJson(Map<String, dynamic> j) =>
      Project.fromJson({...j}..remove('diagrams')..remove('dfd'));

  /// ค่าขนาดจากไฟล์: ไม่ใช่ตัวเลข/นอกช่วง -> ใช้ค่าเริ่มต้น (ไฟล์เก่าไม่มีฟิลด์นี้)
  static double _side(Object? v, double fallback) =>
      v is num && v >= kMinBoardSide && v <= kMaxBoardSide ? v.toDouble() : fallback;

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: j['name'] as String? ?? 'untitled',
        dialect: Dialect.values.byName(j['dialect'] as String? ?? 'mysql'),
        lineColor: parseArgb(j['lineColor']),
        diagrams: (j['diagrams'] as List? ?? []).map(DiagramTab.tryFromJson).whereType<DiagramTab>().toList(),
        dfd: {
          if (j['dfd'] is Map) for (final e in (j['dfd'] as Map).entries) if (e.key is String) e.key as String: DfdDiagram.fromJson(e.value),
        },
        boardWidth: _side((j['board'] as Map?)?['width'], kDefaultBoardWidth),
        boardHeight: _side((j['board'] as Map?)?['height'], kDefaultBoardHeight),
        tables: (j['tables'] as List? ?? [])
            .map((e) => TableModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        relations: (j['relations'] as List? ?? [])
            .map((e) => RelationModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: (j['notes'] as List? ?? [])
            .map((e) => NoteModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        groups: (j['groups'] as List? ?? [])
            .map((e) => GroupModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
