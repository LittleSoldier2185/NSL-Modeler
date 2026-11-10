import 'dart:math' as math;

import '../models/color_utils.dart';
import '../models/wireframe_model.dart';
import 'ortho_route.dart' show RoutePoint;

/// ภาพของ Wireframe เป็นรายการ "ชิ้นวาด" กลาง (ฟังก์ชันล้วน ไม่พึ่ง Flutter) — ตัววาดบนจอ/PNG และตัวเขียน SVG
/// แปลงรายการเดียวกันนี้ จึงได้ภาพตรงกันทั้งสองรูปแบบการแสดงผล ([WfStyle.sketch] / [WfStyle.clean])

/// คำสั่งเส้น: 'M' (1 จุด), 'L' (1 จุด), 'C' (3 จุด), 'Z' — โครงเดียวกับ FcCmd ของ Flowchart
typedef WfCmd = (String op, List<RoutePoint> pts);

/// ชิ้นวาดหนึ่งชิ้น
sealed class WfPrim {
  const WfPrim();
}

/// รูปทรง/เส้น: [fill] null = ไม่เติม, [stroke] null = ไม่มีเส้น
class WfPathPrim extends WfPrim {
  const WfPathPrim(this.cmds, {this.fill, this.stroke, this.width = 1, this.dashed = false});
  final List<WfCmd> cmds;
  final int? fill;
  final int? stroke;
  final double width;
  final bool dashed;
}

/// ข้อความในกรอบ ([x],[y],[w],[h]) — ตัดคำ/ตัดบรรทัดเกินกรอบด้วย … ; [align] 0 ซ้าย 1 กลาง 2 ขวา ; [top] = ชิดบน (ไม่งั้นกึ่งกลางแนวตั้ง)
class WfTextPrim extends WfPrim {
  const WfTextPrim(this.text, this.x, this.y, this.w, this.h,
      {required this.size, required this.color, this.bold = false, this.align = 0, this.top = false, this.maxLines});
  final String text;
  final double x, y, w, h;
  final double size;
  final int color;
  final bool bold;
  final int align;
  final bool top;
  final int? maxLines;
}

/// ชุดสีของการแสดงผล
class WfPalette {
  const WfPalette({
    required this.frame,
    required this.surface,
    required this.subtle,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentTint,
    required this.sketch,
  });

  final int frame, surface, subtle, border, text, muted, accent, onAccent, accentTint;
  final bool sketch;
}

int _alpha(int argb, double a) => ((a * 255).round().clamp(0, 255) << 24) | (argb & 0xFFFFFF);

/// สีเทาที่ความสว่างเท่ากัน (ใช้กับรูปแบบร่างซึ่งเป็นขาวดำ)
int wfGray(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  final v = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
  return (argb & 0xFF000000) | (v << 16) | (v << 8) | v;
}

/// ผสมสี [a] กับ [b] ด้วยสัดส่วน [t] (0 = a, 1 = b) — ทึบ
int _mix(int a, int b, double t) {
  int ch(int s) => (((a >> s) & 0xFF) * (1 - t) + ((b >> s) & 0xFF) * t).round().clamp(0, 255);
  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// ชุดสีของเอกสาร [d] ตามรูปแบบที่เลือก (ไม่ขึ้นกับธีมของแอป)
WfPalette wfPalette(WireframeDiagram d) {
  if (d.style == WfStyle.sketch) {
    return const WfPalette(
      frame: 0xFFFFFFFF,
      surface: 0xFFFFFFFF,
      subtle: 0xFFF0F0F0,
      border: 0xFF3A3A3A,
      text: 0xFF2B2B2B,
      muted: 0xFF8A8A8A,
      accent: 0xFF4A4A4A,
      onAccent: 0xFFFFFFFF,
      accentTint: 0xFFE2E2E2,
      sketch: true,
    );
  }
  final a = d.accent | 0xFF000000;
  return WfPalette(
    frame: 0xFFFFFFFF,
    surface: 0xFFFFFFFF,
    subtle: 0xFFF2F4F7,
    border: 0xFFD0D5DD,
    text: 0xFF1D2939,
    muted: 0xFF667085,
    accent: a,
    onAccent: onColor(a),
    accentTint: _mix(a, 0xFFFFFFFF, 0.86),
    sketch: false,
  );
}

/// รายการชิ้นวาดของทั้งหน้าจอ (กรอบหน้าจอ + ชิ้นส่วนตามลำดับการซ้อน) ที่พิกัดหน้าจอ (กรอบเริ่ม 0,0)
List<WfPrim> wireframePrims(WireframeDiagram d, {bool frame = true}) {
  final p = wfPalette(d);
  final b = _Builder(p);
  if (frame) {
    b.rect(0, 0, d.width, d.height, fill: p.frame, stroke: p.sketch ? p.border : 0xFF98A2B3, width: p.sketch ? 1.6 : 1, seed: 7);
  }
  for (final c in d.components) {
    _component(b, d, c);
  }
  return b.out;
}

int _seedOf(String s) {
  var h = 0x811C9DC5;
  for (final u in s.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// ตัวสร้างชิ้นวาด: รูปแบบร่างวาดเส้นแบบสั่นเล็กน้อยเหมือนวาดมือ (สุ่มแบบคงที่ตาม id ชิ้น)
class _Builder {
  _Builder(this.p);
  final WfPalette p;
  final out = <WfPrim>[];
  math.Random _rng = math.Random(1);

  void seed(String id) => _rng = math.Random(_seedOf(id));

  double _j(double amp) => (_rng.nextDouble() * 2 - 1) * amp;

  /// เส้นตรงแบบวาดมือ (แบ่งช่วง สั่นตั้งฉากกับเส้น และเลยปลายเล็กน้อย)
  List<WfCmd> _wobbly(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1, dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.01) return [];
    final ux = dx / len, uy = dy / len, nx = -uy, ny = ux;
    final over = math.min(2.0, len * 0.04);
    final steps = math.max(1, (len / 36).ceil());
    final amp = math.min(1.1, len * 0.02);
    final pts = <RoutePoint>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final along = -over + (len + 2 * over) * t;
      final off = (i == 0 || i == steps) ? _j(amp * 0.5) : _j(amp);
      pts.add((x1 + ux * along + nx * off, y1 + uy * along + ny * off));
    }
    return [('M', [pts.first]), for (final q in pts.skip(1)) ('L', [q])];
  }

  void line(double x1, double y1, double x2, double y2, {required int stroke, double width = 1, bool dashed = false}) {
    if (p.sketch && !dashed) {
      out.add(WfPathPrim(_wobbly(x1, y1, x2, y2), stroke: stroke, width: width * 1.15));
    } else {
      out.add(WfPathPrim([('M', [(x1, y1)]), ('L', [(x2, y2)])], stroke: stroke, width: width, dashed: dashed));
    }
  }

  List<WfCmd> _roundRect(double x, double y, double w, double h, double r) {
    r = math.max(0, math.min(r, math.min(w, h) / 2));
    if (r < 0.5) return [('M', [(x, y)]), ('L', [(x + w, y)]), ('L', [(x + w, y + h)]), ('L', [(x, y + h)]), ('Z', const [])];
    const k = 0.5522847498;
    final rr = r * (1 - k);
    return [
      ('M', [(x + r, y)]),
      ('L', [(x + w - r, y)]),
      ('C', [(x + w - rr, y), (x + w, y + rr), (x + w, y + r)]),
      ('L', [(x + w, y + h - r)]),
      ('C', [(x + w, y + h - rr), (x + w - rr, y + h), (x + w - r, y + h)]),
      ('L', [(x + r, y + h)]),
      ('C', [(x + rr, y + h), (x, y + h - rr), (x, y + h - r)]),
      ('L', [(x, y + r)]),
      ('C', [(x, y + rr), (x + rr, y), (x + r, y)]),
      ('Z', const []),
    ];
  }

  void rect(double x, double y, double w, double h,
      {int? fill, int? stroke, double width = 1, double r = 0, bool dashed = false, int? seed}) {
    if (seed != null) _rng = math.Random(seed);
    if (p.sketch) {
      if (fill != null) out.add(WfPathPrim(_roundRect(x, y, w, h, math.min(r, 3)), fill: fill));
      if (stroke != null) {
        if (dashed) {
          out.add(WfPathPrim(_roundRect(x, y, w, h, math.min(r, 3)), stroke: stroke, width: width, dashed: true));
        } else {
          final cmds = [
            ..._wobbly(x, y, x + w, y),
            ..._wobbly(x + w, y, x + w, y + h),
            ..._wobbly(x + w, y + h, x, y + h),
            ..._wobbly(x, y + h, x, y),
          ];
          out.add(WfPathPrim(cmds, stroke: stroke, width: width * 1.15));
        }
      }
      return;
    }
    out.add(WfPathPrim(_roundRect(x, y, w, h, r), fill: fill, stroke: stroke, width: width, dashed: dashed));
  }

  List<WfCmd> _ellipseCmds(double cx, double cy, double rx, double ry) {
    if (p.sketch) {
      final n = math.max(12, ((rx + ry) / 3).round());
      final start = _rng.nextDouble() * math.pi * 2;
      final pts = <RoutePoint>[];
      for (var i = 0; i <= n; i++) {
        final a = start + i / n * math.pi * 2 * 1.04;
        final jr = 1 + _j(0.035);
        pts.add((cx + math.cos(a) * rx * jr, cy + math.sin(a) * ry * jr));
      }
      return [('M', [pts.first]), for (final q in pts.skip(1)) ('L', [q])];
    }
    const k = 0.5522847498;
    return [
      ('M', [(cx + rx, cy)]),
      ('C', [(cx + rx, cy + ry * k), (cx + rx * k, cy + ry), (cx, cy + ry)]),
      ('C', [(cx - rx * k, cy + ry), (cx - rx, cy + ry * k), (cx - rx, cy)]),
      ('C', [(cx - rx, cy - ry * k), (cx - rx * k, cy - ry), (cx, cy - ry)]),
      ('C', [(cx + rx * k, cy - ry), (cx + rx, cy - ry * k), (cx + rx, cy)]),
      ('Z', const []),
    ];
  }

  void ellipse(double cx, double cy, double rx, double ry, {int? fill, int? stroke, double width = 1}) {
    if (fill != null) {
      final cmds = p.sketch ? [..._ellipseCmds(cx, cy, rx, ry), ('Z', const <RoutePoint>[])] : _ellipseCmds(cx, cy, rx, ry);
      out.add(WfPathPrim(cmds, fill: fill));
    }
    if (stroke != null) out.add(WfPathPrim(_ellipseCmds(cx, cy, rx, ry), stroke: stroke, width: p.sketch ? width * 1.15 : width));
  }

  void poly(List<RoutePoint> pts, {int? fill, int? stroke, double width = 1, bool close = false}) {
    out.add(WfPathPrim([
      ('M', [pts.first]),
      for (final q in pts.skip(1)) ('L', [q]),
      if (close) ('Z', const []),
    ], fill: fill, stroke: stroke, width: width));
  }

  void text(String t, double x, double y, double w, double h,
      {required double size, required int color, bool bold = false, int align = 0, bool top = false, int? maxLines}) {
    if (t.trim().isEmpty || w < 2 || h < 2) return;
    out.add(WfTextPrim(t, x, y, w, h, size: size, color: color, bold: bold, align: align, top: top, maxLines: maxLines));
  }

  /// แถบเทาแทนข้อความ (placeholder)
  void bar(double x, double y, double w, double h, int color) {
    if (w <= 1 || h <= 0) return;
    if (p.sketch) {
      line(x, y + h / 2, x + w, y + h / 2, stroke: color, width: math.max(1, h * 0.6));
    } else {
      out.add(WfPathPrim(_roundRect(x, y, w, h, h / 2), fill: color));
    }
  }
}

int _align(WfAlign a) => switch (a) { WfAlign.left => 0, WfAlign.center => 1, WfAlign.right => 2 };

void _component(_Builder b, WireframeDiagram d, WfComponent c) {
  final p = b.p;
  b.seed(c.id);
  final x = c.x, y = c.y, w = c.w, h = c.h;
  // สีของชิ้น: ค่าที่ผู้ใช้กำหนด (รูปแบบร่าง = แปลงเป็นเทา) ; ใช้งานไม่ได้ = จางลง
  int col(int? custom, int fallback) {
    var v = custom ?? fallback;
    if (p.sketch && custom != null) v = wfGray(v);
    return c.disabled ? _alpha(v, 0.45) : v;
  }

  final border = col(c.stroke, p.border);
  final surface = col(c.fill, p.surface);
  final ink = col(c.textColor, p.text);
  final muted = c.disabled ? _alpha(p.muted, 0.45) : p.muted;
  final accent = c.disabled ? _alpha(p.accent, 0.45) : p.accent;
  final fs = c.effectiveFontSize;
  final sw = p.sketch ? 1.4 : 1.0;
  final al = _align(c.align);
  final lineH = fs * 1.3;
  int lines(double hh) => math.max(1, (hh / lineH).floor());

  switch (c.kind) {
    case WfKind.container:
      b.rect(x, y, w, h, fill: c.fill == null ? null : surface, stroke: border, width: sw, r: 6, dashed: !p.sketch && c.fill == null);
      b.text(c.text, x + 8, y + 4, w - 16, math.min(h - 8, lineH), size: fs * 0.85, color: muted, align: al, top: true, maxLines: 1);
    case WfKind.heading || WfKind.label || WfKind.paragraph:
      if (c.fill != null) b.rect(x, y, w, h, fill: surface);
      b.text(c.text, x, y, w, h,
          size: fs, color: ink, bold: c.kind == WfKind.heading || c.bold, align: al, top: c.kind == WfKind.paragraph, maxLines: lines(h));
    case WfKind.button:
      final primary = !c.secondary;
      final fill = c.fill != null ? surface : (primary ? (p.sketch ? 0xFFDADADA : accent) : p.surface);
      final stroke = c.stroke != null ? border : (primary ? (p.sketch ? p.border : accent) : (p.sketch ? p.border : accent));
      final txt = c.textColor != null ? ink : (primary ? (p.sketch ? p.text : p.onAccent) : (p.sketch ? p.text : accent));
      b.rect(x, y, w, h, fill: c.disabled ? _alpha(fill, 0.5) : fill, stroke: stroke, width: primary && p.sketch ? 2 : sw, r: 6);
      b.text(c.text, x + 6, y, w - 12, h, size: fs, color: c.disabled ? _alpha(txt, 0.6) : txt, bold: true, align: al, maxLines: 1);
    case WfKind.input || WfKind.select || WfKind.search || WfKind.textarea:
      b.rect(x, y, w, h, fill: c.disabled ? col(null, p.subtle) : surface, stroke: border, width: sw, r: 4);
      var tx = x + 10;
      if (c.kind == WfKind.search) {
        final r = math.min(6.0, h / 4);
        b.ellipse(x + 12 + r, y + h / 2 - 1, r, r, stroke: muted, width: 1.4);
        b.line(x + 12 + r * 1.7, y + h / 2 - 1 + r * 0.7, x + 12 + r * 2.5, y + h / 2 - 1 + r * 1.5, stroke: muted, width: 1.4);
        tx = x + 18 + r * 2.5;
      }
      var right = x + w - 10;
      if (c.kind == WfKind.select) {
        final cx = x + w - 16, cy = y + h / 2;
        b.poly([(cx - 5, cy - 2.5), (cx, cy + 2.5), (cx + 5, cy - 2.5)], stroke: ink, width: 1.5);
        right = x + w - 28;
      }
      final top = c.kind == WfKind.textarea;
      b.text(c.text, tx, top ? y + 8 : y, right - tx, top ? h - 16 : h,
          size: fs, color: c.kind == WfKind.select ? ink : muted, align: al, top: top, maxLines: top ? lines(h - 16) : 1);
    case WfKind.checkbox || WfKind.radio:
      final s = math.min(16.0, h);
      final bx = x, by = y + (h - s) / 2;
      if (c.kind == WfKind.checkbox) {
        b.rect(bx, by, s, s, fill: c.checked && !p.sketch ? accent : surface, stroke: c.checked && !p.sketch ? accent : border, width: sw, r: 3);
        if (c.checked) {
          b.poly([(bx + s * 0.22, by + s * 0.52), (bx + s * 0.42, by + s * 0.72), (bx + s * 0.8, by + s * 0.3)],
              stroke: p.sketch ? p.text : p.onAccent, width: 2);
        }
      } else {
        b.ellipse(bx + s / 2, by + s / 2, s / 2, s / 2, fill: surface, stroke: c.checked && !p.sketch ? accent : border, width: sw);
        if (c.checked) b.ellipse(bx + s / 2, by + s / 2, s * 0.25, s * 0.25, fill: p.sketch ? p.text : accent);
      }
      b.text(c.text, x + s + 8, y, w - s - 8, h, size: fs, color: ink, align: 0, maxLines: 1);
    case WfKind.toggle:
      final th = math.min(20.0, h), tw = th * 1.8;
      final ty = y + (h - th) / 2;
      final on = c.checked;
      b.rect(x, ty, tw, th, fill: on ? (p.sketch ? 0xFF9A9A9A : accent) : col(null, p.subtle), stroke: on && !p.sketch ? accent : border, width: sw, r: th / 2);
      final kx = on ? x + tw - th / 2 : x + th / 2;
      b.ellipse(kx, ty + th / 2, th / 2 - 3, th / 2 - 3, fill: 0xFFFFFFFF, stroke: p.sketch ? p.border : null, width: 1);
      b.text(c.text, x + tw + 8, y, w - tw - 8, h, size: fs, color: ink, maxLines: 1);
    case WfKind.slider:
      final cy = y + h / 2, k = x + w * 0.4;
      b.line(x + 6, cy, x + w - 6, cy, stroke: col(null, p.sketch ? p.muted : p.border), width: 3);
      b.line(x + 6, cy, k, cy, stroke: accent, width: 3);
      b.ellipse(k, cy, math.min(8, h / 2), math.min(8, h / 2), fill: 0xFFFFFFFF, stroke: accent, width: 1.6);
    case WfKind.image:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : col(null, p.sketch ? 0xFFFFFFFF : 0xFFE4E7EC), stroke: border, width: sw);
      if (p.sketch) {
        b.line(x, y, x + w, y + h, stroke: border, width: 1);
        b.line(x + w, y, x, y + h, stroke: border, width: 1);
      } else {
        final m = math.min(w, h);
        b.poly([(x + w * 0.15, y + h * 0.8), (x + w * 0.4, y + h * 0.45), (x + w * 0.58, y + h * 0.65), (x + w * 0.7, y + h * 0.52), (x + w * 0.88, y + h * 0.8)],
            fill: 0xFFC4CAD4, close: true);
        b.ellipse(x + w * 0.7, y + h * 0.3, m * 0.08, m * 0.08, fill: 0xFFC4CAD4);
      }
    case WfKind.icon:
      final m = math.min(w, h);
      b.rect(x, y, w, h, fill: c.fill != null ? surface : col(null, p.subtle), stroke: p.sketch ? border : null, width: sw, r: m * 0.2);
      if (p.sketch) {
        b.line(x + w * 0.25, y + h * 0.25, x + w * 0.75, y + h * 0.75, stroke: border);
        b.line(x + w * 0.75, y + h * 0.25, x + w * 0.25, y + h * 0.75, stroke: border);
      } else {
        b.ellipse(x + w / 2, y + h / 2, m * 0.22, m * 0.22, stroke: col(c.stroke, p.muted), width: 1.8);
      }
    case WfKind.avatar:
      final r = math.min(w, h) / 2;
      final cx = x + w / 2, cy = y + h / 2;
      b.ellipse(cx, cy, r, r, fill: c.fill != null ? surface : col(null, p.subtle), stroke: border, width: sw);
      b.ellipse(cx, cy - r * 0.18, r * 0.32, r * 0.32, fill: p.sketch ? null : 0xFFC4CAD4, stroke: p.sketch ? border : null);
      b.poly([(cx - r * 0.6, cy + r * 0.72), (cx - r * 0.45, cy + r * 0.3), (cx + r * 0.45, cy + r * 0.3), (cx + r * 0.6, cy + r * 0.72)],
          fill: p.sketch ? null : 0xFFC4CAD4, stroke: p.sketch ? border : null, close: !p.sketch);
    case WfKind.table:
      _table(b, c, x, y, w, h, surface, border, ink, muted, fs, sw);
    case WfKind.list:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 4);
      final items = c.items;
      final n = math.max(items.length, c.rows);
      if (n == 0) break;
      final rh = math.min(44.0, h / n);
      for (var i = 0; i < n && (i + 1) * rh <= h + 0.5; i++) {
        final ry = y + i * rh;
        b.ellipse(x + 14, ry + rh / 2, 3, 3, fill: muted);
        if (i < items.length) {
          b.text(items[i], x + 26, ry, w - 36, rh, size: fs, color: ink, maxLines: 1);
        } else {
          b.bar(x + 26, ry + rh / 2 - 3, math.min(w * 0.5, w - 40), 6, col(null, p.sketch ? 0xFFBDBDBD : 0xFFE4E7EC));
        }
        if (i < n - 1) b.line(x + 8, ry + rh, x + w - 8, ry + rh, stroke: col(null, p.sketch ? 0xFFBDBDBD : p.border), width: 0.8);
      }
    case WfKind.card:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 8);
      b.text(c.text, x + 12, y + 8, w - 24, lineH, size: fs, color: ink, bold: true, align: al, top: true, maxLines: 1);
    case WfKind.tabs:
      final items = c.items.isEmpty ? [''] : c.items;
      final tw = w / items.length;
      b.line(x, y + h - 1, x + w, y + h - 1, stroke: col(null, p.sketch ? p.border : p.border), width: 1);
      for (var i = 0; i < items.length; i++) {
        final on = i == 0;
        b.text(items[i], x + i * tw + 6, y, tw - 12, h - 2, size: fs, color: on ? (p.sketch ? p.text : accent) : muted, bold: on, align: 1, maxLines: 1);
        if (on) b.line(x + i * tw + 4, y + h - 2, x + (i + 1) * tw - 4, y + h - 2, stroke: p.sketch ? p.text : accent, width: 2.5);
      }
    case WfKind.navbar:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : p.surface), stroke: border, width: sw);
      b.text(c.text, x + 16, y, w * 0.5, h, size: fs, color: ink, bold: true, maxLines: 1);
      for (var i = 0; i < 3; i++) {
        b.bar(x + w - 16 - (i + 1) * 64 + 8, y + h / 2 - 3, 48, 6, col(null, p.sketch ? 0xFFBDBDBD : 0xFFD0D5DD));
      }
    case WfKind.sidebar:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : col(null, p.subtle), stroke: border, width: sw);
      final items = c.items;
      for (var i = 0; i < items.length && 12 + (i + 1) * 36 <= h; i++) {
        final iy = y + 12 + i * 36;
        if (i == 0) b.rect(x + 8, iy, w - 16, 30, fill: p.sketch ? 0xFFE0E0E0 : p.accentTint, r: 6);
        b.text(items[i], x + 18, iy, w - 30, 30, size: fs, color: i == 0 && !p.sketch ? accent : ink, bold: i == 0, maxLines: 1);
      }
    case WfKind.modal:
      b.rect(x + 3, y + 4, w, h, fill: _alpha(0xFF000000, 0.08), r: 10);
      b.rect(x, y, w, h, fill: surface, stroke: border, width: p.sketch ? 1.8 : 1.2, r: 10);
      final th = math.min(48.0, h * 0.3);
      b.text(c.text, x + 16, y, w - 56, th, size: fs, color: ink, bold: true, maxLines: 1);
      final cx = x + w - 22, cy = y + th / 2;
      b.line(cx - 5, cy - 5, cx + 5, cy + 5, stroke: muted, width: 1.6);
      b.line(cx + 5, cy - 5, cx - 5, cy + 5, stroke: muted, width: 1.6);
      b.line(x + 1, y + th, x + w - 1, y + th, stroke: col(null, p.sketch ? p.border : p.border), width: 0.8);
    case WfKind.divider:
      if (h > w) {
        b.line(x + w / 2, y, x + w / 2, y + h, stroke: border, width: 1);
      } else {
        b.line(x, y + h / 2, x + w, y + h / 2, stroke: border, width: 1);
      }
    case WfKind.badge:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : p.accentTint), stroke: p.sketch ? border : null, width: sw, r: h / 2);
      b.text(c.text, x + 4, y, w - 8, h, size: fs, color: c.textColor != null ? ink : (p.sketch ? p.text : accent), bold: true, align: 1, maxLines: 1);
    case WfKind.pagination:
      final labels = ['‹', '1', '2', '3', '›'];
      final s = math.min(h, w / labels.length - 4);
      for (var i = 0; i < labels.length; i++) {
        final bx = x + i * (s + 4);
        final on = i == 1;
        b.rect(bx, y + (h - s) / 2, s, s, fill: on ? (p.sketch ? 0xFFDADADA : accent) : surface, stroke: on && !p.sketch ? accent : border, width: sw, r: 4);
        b.text(labels[i], bx, y + (h - s) / 2, s, s, size: fs, color: on && !p.sketch ? p.onAccent : ink, align: 1, maxLines: 1);
      }
    case WfKind.breadcrumb:
      final items = c.items;
      b.text(items.join('  /  '), x, y, w, h, size: fs, color: muted, align: al, maxLines: 1);
    case WfKind.map:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : 0xFFE6EFE3), stroke: border, width: sw);
      final road = p.sketch ? 0xFFBDBDBD : 0xFFFFFFFF;
      b.line(x, y + h * 0.35, x + w, y + h * 0.55, stroke: road, width: p.sketch ? 1.2 : 5);
      b.line(x + w * 0.3, y, x + w * 0.45, y + h, stroke: road, width: p.sketch ? 1.2 : 5);
      final px = x + w * 0.62, py = y + h * 0.42, r = math.min(10.0, math.min(w, h) * 0.08);
      b.poly([(px - r * 0.8, py + r * 0.4), (px, py + r * 2.2), (px + r * 0.8, py + r * 0.4)], fill: p.sketch ? null : 0xFFE5484D, stroke: p.sketch ? border : null, close: true);
      b.ellipse(px, py, r, r, fill: p.sketch ? 0xFFFFFFFF : 0xFFE5484D, stroke: p.sketch ? border : null);
    case WfKind.chart:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 4);
      final l = x + 24, bt = y + h - 20, tp = y + 16, r = x + w - 16;
      b.line(l, tp, l, bt, stroke: muted, width: 1);
      b.line(l, bt, r, bt, stroke: muted, width: 1);
      const vals = [0.45, 0.75, 0.55, 0.9, 0.65];
      final bw = (r - l) / (vals.length * 1.6);
      for (var i = 0; i < vals.length; i++) {
        final bx = l + bw * 0.6 + i * bw * 1.6, bh = (bt - tp) * vals[i];
        b.rect(bx, bt - bh, bw, bh, fill: p.sketch ? null : _alpha(accent, i.isEven ? 0.85 : 0.55), stroke: p.sketch ? border : null, width: 1.2);
      }
  }
}

void _table(_Builder b, WfComponent c, double x, double y, double w, double h, int surface, int border, int ink, int muted,
    double fs, double sw) {
  final p = b.p;
  final cols = c.columns.isEmpty ? ['', '', ''] : c.columns;
  final rowsN = c.rows;
  final rh = math.min(40.0, h / (rowsN + 1));
  b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 4);
  b.rect(x, y, w, rh, fill: p.sketch ? 0xFFEDEDED : p.subtle);
  b.line(x, y + rh, x + w, y + rh, stroke: border, width: 1);
  final cw = w / cols.length;
  final placeholder = p.sketch ? 0xFFC8C8C8 : 0xFFE4E7EC;
  for (var i = 0; i < cols.length; i++) {
    b.text(cols[i], x + i * cw + 8, y, cw - 16, rh, size: fs, color: ink, bold: true, maxLines: 1);
    if (i > 0) b.line(x + i * cw, y, x + i * cw, y + math.min(h, rh * (rowsN + 1)), stroke: p.sketch ? 0xFFBDBDBD : p.border, width: 0.8);
  }
  for (var r = 1; r <= rowsN && (r + 1) * rh <= h + 0.5; r++) {
    final ry = y + r * rh;
    if (r > 1) b.line(x, ry, x + w, ry, stroke: p.sketch ? 0xFFBDBDBD : p.border, width: 0.8);
    for (var i = 0; i < cols.length; i++) {
      final len = (cw - 16) * (0.45 + 0.35 * (((r * 7 + i * 3) % 5) / 4));
      b.bar(x + i * cw + 8, ry + rh / 2 - 3, len, 6, placeholder);
    }
  }
}
