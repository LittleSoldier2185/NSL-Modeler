enum NameStyle { snake, upperSnake, camel, pascal, kebab, spaced, other }

final _snake = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');
final _upperSnake = RegExp(r'^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$');
final _camel = RegExp(r'^[a-z][a-z0-9]*([A-Z][a-z0-9]*)+$');
final _pascal = RegExp(r'^([A-Z][a-z0-9]*)+$');

/// ชื่อที่มีตัวอักษรนอก ASCII (เช่น ภาษาไทย) — แปลงเป็น snake_case ไม่ได้ จึงไม่ตรวจรูปแบบ
bool hasNonAscii(String s) => s.codeUnits.any((c) => c > 127);

NameStyle styleOf(String s) {
  if (_snake.hasMatch(s)) return NameStyle.snake;
  if (_upperSnake.hasMatch(s) && s.contains('_')) return NameStyle.upperSnake;
  if (_camel.hasMatch(s)) return NameStyle.camel;
  if (_pascal.hasMatch(s)) return NameStyle.pascal;
  if (s.contains('-')) return NameStyle.kebab;
  if (s.contains(' ')) return NameStyle.spaced;
  return NameStyle.other;
}

/// แปลงเป็น snake_case เช่น `UserID` -> `user_id`, `orderItems` -> `order_items`, `my col` -> `my_col`
String toSnakeCase(String s) {
  var t = s.trim();
  t = t.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}'); // orderItems -> order_Items
  t = t.replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}'); // UserID/HTTPServer
  t = t.replaceAll(RegExp(r'[\s\-.]+'), '_').replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  t = t.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '').toLowerCase();
  return t;
}

/// ชื่อตารางเป็นพหูพจน์ (เดาจากคำลงท้าย; ยกเว้นคำที่ลงท้าย s อยู่แล้วแต่เป็นเอกพจน์ เช่น status, address)
bool looksPlural(String name) {
  final n = name.toLowerCase().split('_').last; // ดูคำสุดท้ายของ order_items
  if (n.length < 3 || !n.endsWith('s')) return false;
  const singularEndings = ['ss', 'us', 'is', 'ics', 'ous'];
  if (singularEndings.any(n.endsWith)) return false;
  const singularWords = {'news', 'series', 'species', 'bus', 'gas', 'lens', 'canvas', 'alias', 'access'};
  return !singularWords.contains(n);
}
