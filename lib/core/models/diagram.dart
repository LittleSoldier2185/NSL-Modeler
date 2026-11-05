/// id ของเอกสาร ER ในโปรเจกต์ที่แปลงจากไฟล์รูปแบบเก่า (v1/v2) และของโปรเจกต์ใหม่
const String kErDiagramId = 'er';

/// ความยาวสูงสุดของชื่อเอกสาร (แท็บ)
const int kDiagramNameMax = 40;

/// ตัดช่องว่างหัวท้าย/ย่อให้ไม่เกิน [kDiagramNameMax]
String cleanDiagramName(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length > kDiagramNameMax ? t.substring(0, kDiagramNameMax).trimRight() : t;
}
