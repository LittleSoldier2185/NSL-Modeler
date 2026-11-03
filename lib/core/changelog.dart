import 'app_info.dart';
import 'l10n/l10n.dart';

/// หมวดของรายการ patch note
enum NoteKind { added, improved, fixed }

class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.codename,
    required this.date,
    this.added = const [],
    this.improved = const [],
    this.fixed = const [],
  });

  final String version;
  final String codename;

  /// วันที่ปล่อย (ISO: 2026-11-04)
  final String date;

  /// ข้อความไทยต้นฉบับ (ใช้เป็นคีย์ [tr] — มีคำแปลอังกฤษใน l10n_en.dart)
  final List<String> added;
  final List<String> improved;
  final List<String> fixed;

  List<String> of(NoteKind k) => switch (k) {
        NoteKind.added => added,
        NoteKind.improved => improved,
        NoteKind.fixed => fixed,
      };

  bool get isEmpty => added.isEmpty && improved.isEmpty && fixed.isEmpty;
}

String noteKindTitle(NoteKind k) => switch (k) {
      NoteKind.added => tr('เพิ่มใหม่'),
      NoteKind.improved => tr('ปรับปรุง'),
      NoteKind.fixed => tr('แก้ไข'),
    };

/// patch note ทุกรุ่น เรียงใหม่สุดก่อน — รุ่นแรกต้องตรงกับ [kAppVersion] (มีเทสต์ตรวจ)
/// เพิ่มรุ่นใหม่ไว้บนสุดทุกครั้งที่ขึ้นเลขรอง/เลขแก้ไข และอัปเดต CHANGELOG.md ให้ตรงกัน
const List<ReleaseNote> kReleaseNotes = [
  ReleaseNote(
    version: kAppVersion,
    codename: kAppCodename,
    date: '2026-11-04',
    added: [
      'แผนภาพ DFD: ผู้ใช้ภายนอก กระบวนการ ที่เก็บข้อมูล และเส้นข้อมูลพร้อมป้ายชื่อ ตรวจกฎของ DFD ให้อัตโนมัติ และ Export เป็นภาพ',
      'แท็บแผนภาพแบบแท็บเบราว์เซอร์ สร้างได้หลายแผนภาพในโปรเจกต์เดียว',
      'เชื่อมต่อฐานข้อมูล MySQL / MariaDB แบบอ่านอย่างเดียว นำโครงสร้างเข้ามาเป็นแผนภาพ หรือเปรียบเทียบเพื่อสร้างสคริปต์ migration',
      'ช่องค้นหากลางแถบชื่อหน้าต่าง ค้นได้ทั้งคำสั่ง ตาราง คอลัมน์ วัตถุ DFD โน้ต กลุ่ม และปัญหา (ตัวนำหน้า @ # : ! > ~)',
      'แถบสถานะด้านล่าง แสดงรุ่นของโปรแกรม จำนวนตาราง ปัญหาที่ตรวจพบ และปุ่มเปิด patch note',
      'เครื่องหมายทิศทางข้อมูลกลางเส้น FK และเส้นประที่วิ่งตามทิศทางข้อมูล (ปิดได้ในเมนูมุมมอง)',
      'ฟอนต์ Noto Sans Thai ฝังในโปรแกรม และเลือกฟอนต์ที่ติดตั้งในเครื่องให้แต่ละตารางได้',
      'สีตาราง สีกลุ่ม และสีเส้น FK เลือกได้อิสระ ด้วยตัวเลือกสีแบบพื้นที่ลาก',
      'Export ภาพ PNG/SVG แบบธีมมืด และเมื่อ crop เฉพาะที่เลือก กรอบกลุ่มติดไปด้วย',
      'ลากกรอบเลือกครอบกลุ่มทั้งกลุ่ม กลุ่มและโน้ตข้างในจะเลื่อนตามตารางที่ลาก',
      'คลิกที่เส้น FK เพื่อเลือก คลิกขวาเพื่อเปลี่ยนสีหรือลบ',
      'แถบชื่อหน้าต่างแบบกำหนดเอง และไอคอนโปรแกรมใหม่',
    ],
    improved: [
      'เส้น FK เลี่ยงขอบกลุ่ม เว้นระยะเลนให้ห่างขึ้น และเส้นที่เลือกเด่นขึ้น',
      'Undo/Redo แยกต่อแท็บ และใช้ Ctrl+Shift+Z เป็น Redo แบบ Adobe',
    ],
    fixed: [
      'แก้หน้าต่างค้างหลังย่อแล้วคืนขนาด',
    ],
  ),
];
