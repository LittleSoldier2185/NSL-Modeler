import 'project.dart';

/// ขนาดกระดานสำเร็จรูปตอนสร้างโปรเจกต์ (px ในพิกัดโปรเจกต์)
class BoardPreset {
  const BoardPreset(this.id, this.label, this.hint, this.width, this.height);

  final String id;

  /// ข้อความไทยต้นฉบับ (ใช้เป็นคีย์ `tr()` ตอนแสดง)
  final String label;
  final String hint;
  final double width;
  final double height;

  bool matches(double w, double h) => w == width && h == height;
}

const kBoardPresets = <BoardPreset>[
  BoardPreset('small', 'เล็ก', 'ประมาณ 5–10 ตาราง', 1600, 1000),
  BoardPreset('medium', 'กลาง', 'ประมาณ 10–25 ตาราง (ค่าเริ่มต้น)', kDefaultBoardWidth, kDefaultBoardHeight),
  BoardPreset('large', 'ใหญ่', 'ประมาณ 25–60 ตาราง', 4000, 2500),
  BoardPreset('xlarge', 'ใหญ่มาก', 'ระบบขนาดใหญ่ 60 ตารางขึ้นไป', 8000, 5000),
];

/// ตรวจขนาดที่ผู้ใช้กรอกเอง — คืนข้อความไทยต้นฉบับของปัญหา หรือ null ถ้าใช้ได้
String? validateBoardSide(String text) {
  final v = double.tryParse(text.trim());
  if (v == null) return 'กรอกเป็นตัวเลข';
  if (v < kMinBoardSide || v > kMaxBoardSide) return 'ต้องอยู่ระหว่าง {0} ถึง {1}';
  return null;
}
