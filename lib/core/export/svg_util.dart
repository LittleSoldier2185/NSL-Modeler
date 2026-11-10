import 'dart:math' as math;

import '../layout/ortho_route.dart' show RoutePoint;

/// ตัวช่วยเขียน SVG ที่ใช้ร่วมกันระหว่างตัว export ของ Wireframe / Screen Flow (ฟังก์ชันล้วน)

const String kSvgSans = "'Noto Sans Thai','Leelawadee UI',Tahoma,'Segoe UI',sans-serif";

String svgEsc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// ตัวเลขสั้นที่สุด (ทศนิยมไม่เกิน 2 ตำแหน่ง ไม่มีศูนย์ท้าย)
String svgNum(num v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// ค่า d ของ path จากคำสั่ง 'M' / 'L' / 'C' / 'Q' / 'Z'
String svgPathData(List<(String, List<RoutePoint>)> cmds) {
  final b = StringBuffer();
  for (final (op, pts) in cmds) {
    if (op == 'Z') {
      b.write('Z ');
      continue;
    }
    b.write(op);
    b.write(pts.map((p) => '${svgNum(p.$1)} ${svgNum(p.$2)}').join(' '));
    b.write(' ');
  }
  return b.toString().trim();
}

/// สี ARGB -> (rgb แบบ #RRGGBB, ความทึบ 0..1)
(String, double) svgColor(int argb) =>
    ('#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}', ((argb >> 24) & 0xFF) / 255);

/// attribute ของสี: `fill="#..."` (+ `fill-opacity` เมื่อไม่ทึบ)
String svgPaint(String attr, int argb) {
  final (c, a) = svgColor(argb);
  return a >= 0.999 ? '$attr="$c"' : '$attr="$c" $attr-opacity="${svgNum(a)}"';
}

/// แบ่งข้อความเป็นบรรทัดให้พอดีความกว้าง (ประมาณ — SVG ไม่มีตัววัดฟอนต์จริง) ; เกิน [maxLines] ตัดด้วย …
List<String> svgWrap(String text, double width, double perChar, int maxLines) {
  final max = math.max(1, (width / perChar).floor());
  final out = <String>[];
  for (final para in text.split('\n')) {
    var rest = para;
    while (rest.length > max) {
      var cut = rest.lastIndexOf(' ', max);
      if (cut <= 0) cut = max;
      out.add(rest.substring(0, cut).trimRight());
      rest = rest.substring(cut).trimLeft();
    }
    out.add(rest);
  }
  if (out.length > maxLines) {
    final kept = out.sublist(0, math.max(1, maxLines));
    final last = kept.length - 1;
    kept[last] = '${kept[last].substring(0, math.max(0, kept[last].length - 1))}…';
    return kept;
  }
  return out;
}
