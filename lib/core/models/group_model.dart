import 'color_utils.dart';

/// กลุ่มตาราง: กรอบเส้นประมีชื่อบน canvas ครอบตาราง/โน้ตที่อยู่ข้างใน
/// ลากกลุ่มแล้วของข้างในเลื่อนตาม (สมาชิกคือของที่จุดกึ่งกลางอยู่ในกรอบ ณ ตอนนั้น ไม่ได้ผูกถาวร)
class GroupModel {
  GroupModel({
    required this.id,
    required this.name,
    this.x = 0,
    this.y = 0,
    this.width = kGroupDefaultWidth,
    this.height = kGroupDefaultHeight,
    this.colorIndex = 0,
    this.customColor,
  });

  String id;
  String name;
  double x;
  double y;
  double width;
  double height;

  /// ลำดับสีใน [kGroupColors]
  int colorIndex;

  /// สีที่ผู้ใช้กำหนดเอง (ARGB) — มีค่าเมื่อไหร่ใช้แทน [colorIndex]
  int? customColor;

  /// สีที่ใช้จริง (ARGB)
  int get colorValue => customColor ?? kGroupColors[colorIndex % kGroupColors.length];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'color': colorIndex,
        if (customColor != null) 'fill': customColor,
      };

  factory GroupModel.fromJson(Map<String, dynamic> j) {
    double size(Object? v, double min, double fallback) => v is num && v >= min ? v.toDouble() : fallback;
    final c = j['color'];
    return GroupModel(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      x: (j['x'] as num?)?.toDouble() ?? 0,
      y: (j['y'] as num?)?.toDouble() ?? 0,
      width: size(j['width'], kGroupMinWidth, kGroupDefaultWidth),
      height: size(j['height'], kGroupMinHeight, kGroupDefaultHeight),
      colorIndex: c is int && c >= 0 && c < kGroupColors.length ? c : 0,
      customColor: parseArgb(j['fill']),
    );
  }
}

const double kGroupDefaultWidth = 480;
const double kGroupDefaultHeight = 320;
const double kGroupMinWidth = 200;
const double kGroupMinHeight = 120;

/// ความสูงแถบชื่อของกลุ่ม
const double kGroupHeader = 34;

/// สีของกลุ่ม (ARGB) — UI ใช้เป็นสีขอบ/พื้นจาง ๆ ส่วน export ใช้เป็นสีเส้นประ
const List<int> kGroupColors = [
  0xFF14B8A6, // เขียวน้ำทะเล
  0xFF9333EA, // ม่วง
  0xFF3B82F6, // น้ำเงิน
  0xFFF59E0B, // ส้ม
  0xFFF43F5E, // ชมพู
  0xFF22C55E, // เขียว
];
