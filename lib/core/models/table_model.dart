import 'color_utils.dart';
import 'column_model.dart';
import 'index_model.dart';

/// สีที่เลือกให้ตารางได้ (ARGB) — เข้มพอให้ตัวอักษรขาวบนหัวตารางอ่านชัดทั้งธีมสว่าง/มืด
/// ลำดับ: เขียวน้ำทะเล, ม่วง, น้ำเงิน, ส้ม, ชมพู, เขียว, เทา
const List<int> kTableColors = [
  0xFF0F766E,
  0xFF7E22CE,
  0xFF1D4ED8,
  0xFFC2410C,
  0xFFBE123C,
  0xFF15803D,
  0xFF475569,
];

class TableModel {
  TableModel({
    required this.id,
    required this.name,
    this.comment = '',
    this.x = 0,
    this.y = 0,
    this.width = 220,
    this.colorIndex,
    this.customColor,
    this.fontFamily,
    List<ColumnModel>? columns,
    List<Map<String, String?>>? seedRows,
    List<IndexModel>? indexes,
  })  : seedRows = seedRows ?? [],
        columns = columns ?? [],
        indexes = indexes ?? [];

  String id;
  String name;
  String comment;
  double x;
  double y;
  double width;

  /// สีของตาราง (ลำดับใน [kTableColors]) — null = สีเริ่มต้น (เทาเข้ม)
  int? colorIndex;

  /// สีที่ผู้ใช้กำหนดเอง (ARGB) — มีค่าเมื่อไหร่ใช้แทน [colorIndex]
  int? customColor;

  /// สีที่ใช้จริง (ARGB): สีกำหนดเอง ก่อน สีสำเร็จรูป ; null = สีเริ่มต้น
  int? get colorValue => customColor ?? (colorIndex == null ? null : kTableColors[colorIndex!]);

  /// ฟอนต์ของตาราง (ชื่อ family ที่ติดตั้งในเครื่อง) — null = ฟอนต์หลักของแอป (Noto Sans Thai)
  String? fontFamily;

  /// ข้อมูลตั้งต้น (seed data): แต่ละแถวเป็น id คอลัมน์ -> ข้อความที่กรอก (ว่าง = NULL)
  /// คอลัมน์ที่ไม่มี key ในแถว = ให้ฐานข้อมูลใส่ DEFAULT/AUTO INCREMENT เอง ดู `seed_data.dart`
  List<Map<String, String?>> seedRows;
  List<ColumnModel> columns;

  /// เปลี่ยน id คอลัมน์ในข้อมูลตั้งต้นตามแผนที่ [idMap] (เก่า -> ใหม่) ตอนทำสำเนาตาราง
  void remapSeedColumns(Map<String, String> idMap) {
    seedRows = [
      for (final r in seedRows) {for (final e in r.entries) idMap[e.key] ?? e.key: e.value},
    ];
  }

  /// ลบค่าของคอลัมน์ [columnId] ออกจากข้อมูลตั้งต้น (ตอนลบคอลัมน์)
  void dropSeedColumn(String columnId) {
    for (final r in seedRows) {
      r.remove(columnId);
    }
    // แถวที่ไม่เหลือค่าอะไรเลยหลังลบคอลัมน์ ไม่มีความหมาย
    seedRows.removeWhere((r) => r.isEmpty);
  }
  List<IndexModel> indexes;

  ColumnModel? columnById(String id) {
    for (final c in columns) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (comment.isNotEmpty) 'comment': comment,
        'x': x,
        'y': y,
        'width': width,
        if (colorIndex != null) 'color': colorIndex,
        if (customColor != null) 'fill': customColor,
        if (fontFamily != null) 'font': fontFamily,
        if (seedRows.isNotEmpty) 'seed': [for (final r in seedRows) Map<String, String?>.of(r)],
        'columns': columns.map((c) => c.toJson()).toList(),
        'indexes': indexes.map((i) => i.toJson()).toList(),
      };

  factory TableModel.fromJson(Map<String, dynamic> j) => TableModel(
        id: j['id'] as String,
        name: j['name'] as String,
        comment: j['comment'] as String? ?? '',
        x: (j['x'] as num? ?? 0).toDouble(),
        y: (j['y'] as num? ?? 0).toDouble(),
        width: (j['width'] as num? ?? 220).toDouble(),
        colorIndex: j['color'] is int && (j['color'] as int) >= 0 && (j['color'] as int) < kTableColors.length
            ? j['color'] as int
            : null,
        customColor: parseArgb(j['fill']),
        fontFamily: j['font'] is String && (j['font'] as String).trim().isNotEmpty ? (j['font'] as String).trim() : null,
        seedRows: [
          for (final r in (j['seed'] as List? ?? []))
            if (r is Map)
              {
                for (final e in r.entries)
                  if (e.key is String && (e.value == null || e.value is String || e.value is num || e.value is bool))
                    e.key as String: e.value == null ? null : '${e.value}',
              },
        ],
        columns: (j['columns'] as List? ?? [])
            .map((e) => ColumnModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        indexes: (j['indexes'] as List? ?? [])
            .map((e) => IndexModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
