import 'dart:convert';
import 'dart:typed_data';

/// ถอดรหัสไฟล์ .sql เป็นข้อความ: UTF-8 (มี/ไม่มี BOM), UTF-16 LE/BE (มี BOM — SSMS มักบันทึกแบบนี้)
/// ไบต์ที่ไม่ใช่ UTF-8 ที่ถูกต้องจะถูกแทนด้วย U+FFFD แทนที่จะ error ทั้งไฟล์
String decodeSqlBytes(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return _utf16(b, 2, littleEndian: true);
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return _utf16(b, 2, littleEndian: false);
  var start = 0;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) start = 3;
  return utf8.decode(start == 0 ? b : b.sublist(start), allowMalformed: true);
}

String _utf16(Uint8List b, int start, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = start; i + 1 < b.length; i += 2) {
    units.add(littleEndian ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}
