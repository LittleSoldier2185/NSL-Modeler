import 'l10n_en.dart';

/// ภาษาของแอป
enum Lang {
  th('ไทย', 'th'),
  en('English', 'en');

  const Lang(this.label, this.code);
  final String label;
  final String code;

  static Lang? fromCode(String? c) {
    for (final l in values) {
      if (l.code == c) return l;
    }
    return null;
  }
}

String _stripCtx(String s) {
  final i = s.indexOf('@@');
  return i < 0 ? s : s.substring(0, i);
}

/// ภาษาที่ใช้อยู่ตอนนี้ — ตั้งโดย [AppSettings]; ค่าเริ่มต้นเป็นไทยซึ่งเป็นภาษาต้นฉบับของข้อความทั้งหมด
Lang currentLang = Lang.th;

/// แปลข้อความ: ข้อความไทยเป็น "คีย์" ถ้าเป็นภาษาอังกฤษจะหาคำแปลใน [kEn]
/// ใช้ `{0}`, `{1}` … แทนค่าที่แทรก เช่น `tr('คัดลอก {0} ตาราง', [n])`
///
/// คำไทยเดียวกันที่ความหมายต่างกัน แยกด้วยตัวบอกบริบทท้ายคีย์ `คำ@@ctx` (ภาษาไทยจะตัดส่วน `@@…` ทิ้ง)
String tr(String th, [List<Object?> args = const []]) {
  var s = currentLang == Lang.en ? (kEn[th] ?? _stripCtx(th)) : _stripCtx(th);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
