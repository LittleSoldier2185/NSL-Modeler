import 'dart:math' as math;

/// เครื่องมือเกี่ยวกับสีแบบ ARGB (int) ที่ไม่พึ่ง Flutter — ใช้ร่วมกันทั้ง UI, PNG และ SVG

/// ตรวจค่าสีจากไฟล์: ต้องเป็นจำนวนเต็ม 32 บิต ไม่งั้นถือว่าไม่มีสี
int? parseArgb(Object? v) => v is int && v >= 0 && v <= 0xFFFFFFFF ? v : null;

/// ความสว่างเชิงการรับรู้ 0..1 (WCAG relative luminance)
double luminance(int argb) {
  double ch(int c) {
    final s = c / 255;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch((argb >> 16) & 0xFF) + 0.7152 * ch((argb >> 8) & 0xFF) + 0.0722 * ch(argb & 0xFF);
}

/// สีตัวอักษรที่อ่านชัดบนพื้น [argb]: ขาว หรือเกือบดำ (เลือกตามอัตราส่วนความต่างที่สูงกว่า)
int onColor(int argb) {
  final l = luminance(argb);
  final white = 1.05 / (l + 0.05);
  final dark = (l + 0.05) / (luminance(0xFF111827) + 0.05);
  return white >= dark ? 0xFFFFFFFF : 0xFF111827;
}

/// `#RRGGBB` (พิมพ์ใหญ่) จากสี ARGB — ทิ้งช่องโปร่งใส
String hexRgb(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// อ่านรหัสสีที่ผู้ใช้พิมพ์: `#RGB`, `#RRGGBB`, `RRGGBB` (มี/ไม่มี #) -> ARGB ทึบ; ผิดรูป = null
int? parseHexColor(String text) {
  var s = text.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return 0xFF000000 | int.parse(s, radix: 16);
}

/// HSV (h 0..360, s/v 0..1) -> ARGB ทึบ
int hsvToArgb(double h, double s, double v) {
  final c = v * s;
  final hp = (h % 360) / 60;
  final x = c * (1 - (hp % 2 - 1).abs());
  final (r1, g1, b1) = switch (hp.floor()) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  final m = v - c;
  int to8(double d) => ((d + m) * 255).round().clamp(0, 255);
  return 0xFF000000 | (to8(r1) << 16) | (to8(g1) << 8) | to8(b1);
}

/// ARGB -> (h 0..360, s 0..1, v 0..1)
(double, double, double) argbToHsv(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final d = mx - mn;
  double h;
  if (d == 0) {
    h = 0;
  } else if (mx == r) {
    h = 60 * (((g - b) / d) % 6);
  } else if (mx == g) {
    h = 60 * ((b - r) / d + 2);
  } else {
    h = 60 * ((r - g) / d + 4);
  }
  return (h < 0 ? h + 360 : h, mx == 0 ? 0 : d / mx, mx);
}
