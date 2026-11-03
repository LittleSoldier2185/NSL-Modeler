/// ข้อมูลเวอร์ชันของแอป (แหล่งเดียว — pubspec.yaml ต้องตรงกับค่านี้ มีเทสต์ตรวจ)
///
/// ชื่อรุ่น = คำดาราศาสตร์ (ดาว/กลุ่มดาว) เรียงตามตัวอักษรทีละรุ่นที่เลขรอง (ตัวกลาง) เพิ่ม
/// เช่น 0.5 Altair → 0.6 Betelgeuse → 0.7 Capella → 0.8 Deneb → 0.9 Elnath → 1.0 Fomalhaut
/// รุ่นแก้บั๊กเล็ก (0.5.1) ใช้ชื่อเดิม
const String kAppName = 'NSL Modeler';
const String kAppVersion = '0.5.0';
const String kAppCodename = 'Altair';

/// ข้อความสำหรับแสดง เช่น "Altair 0.5.0"
String get appVersionLabel => '$kAppCodename $kAppVersion';

/// ลำดับชื่อรุ่นที่วางแผนไว้ (ใช้ตั้งชื่อรุ่นถัดไป)
const List<String> kCodenameRoadmap = [
  'Altair',
  'Betelgeuse',
  'Capella',
  'Deneb',
  'Elnath',
  'Fomalhaut',
];
