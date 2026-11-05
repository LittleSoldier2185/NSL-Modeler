/// ไฟล์/ข้อมูลโปรเจกต์อ่านไม่ได้ (ไม่ใช่ไฟล์โปรเจกต์, เวอร์ชันใหม่กว่าที่รองรับ, โครงสร้างเสีย) — [message] แสดงให้ผู้ใช้ได้
class ProjectFormatException implements Exception {
  ProjectFormatException(this.message);
  final String message;
  @override
  String toString() => 'ProjectFormatException: $message';
}
