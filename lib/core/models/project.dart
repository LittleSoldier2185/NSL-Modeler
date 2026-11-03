import 'color_utils.dart';
import 'enums.dart';
import 'group_model.dart';
import 'note_model.dart';
import 'relation_model.dart';
import 'table_model.dart';

/// ขนาดกระดานเริ่มต้นและช่วงที่อนุญาตตอนกำหนดเอง (px ในพิกัดโปรเจกต์)
const double kDefaultBoardWidth = 2400;
const double kDefaultBoardHeight = 1500;
const double kMinBoardSide = 800;
const double kMaxBoardSide = 20000;

class Project {
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
  })  : tables = tables ?? [],
        relations = relations ?? [],
        notes = notes ?? [],
        groups = groups ?? [];

  String name;
  Dialect dialect;

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

  static const formatVersion = 1;

  Map<String, dynamic> toJson() => {
        'format': 'nsl-erd',
        'version': formatVersion,
        'name': name,
        'dialect': dialect.name,
        'board': {'width': boardWidth, 'height': boardHeight},
        if (lineColor != null) 'lineColor': lineColor,
        'tables': tables.map((t) => t.toJson()).toList(),
        'relations': relations.map((r) => r.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
        if (groups.isNotEmpty) 'groups': groups.map((g) => g.toJson()).toList(),
      };

  /// ค่าขนาดจากไฟล์: ไม่ใช่ตัวเลข/นอกช่วง -> ใช้ค่าเริ่มต้น (ไฟล์เก่าไม่มีฟิลด์นี้)
  static double _side(Object? v, double fallback) =>
      v is num && v >= kMinBoardSide && v <= kMaxBoardSide ? v.toDouble() : fallback;

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: j['name'] as String? ?? 'untitled',
        dialect: Dialect.values.byName(j['dialect'] as String? ?? 'mysql'),
        lineColor: parseArgb(j['lineColor']),
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
