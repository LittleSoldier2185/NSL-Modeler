import 'dart:math' as math;

import '../layout/diagram_geometry.dart' show roundedRoute;
import '../models/color_utils.dart';
import '../models/dfd_model.dart';

const _sans = "'Noto Sans Thai','Leelawadee UI',Tahoma,'Segoe UI',sans-serif";

class _Theme {
  const _Theme({required this.canvas, required this.surface, required this.text, required this.line, required this.tintOpacity});
  final String canvas, surface, text, line, tintOpacity;
}

const _light = _Theme(canvas: '#F6F8FB', surface: '#FFFFFF', text: '#1B2430', line: '#0F766E', tintOpacity: '0.10');
const _dark = _Theme(canvas: '#121820', surface: '#19212B', text: '#E6EBF2', line: '#14958B', tintOpacity: '0.18');

const _kindColors = {DfdKind.entity: 0xFF3B82F6, DfdKind.process: 0xFF9333EA, DfdKind.store: 0xFFF59E0B};

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _n(num v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// ตัดข้อความให้พอดีความกว้าง (ประมาณ — SVG ไม่มีตัววัดฟอนต์จริง)
String _fit(String s, double width, double perChar) {
  final max = math.max(1, (width / perChar).floor());
  return s.length <= max ? s : '${s.substring(0, math.max(1, max - 1))}…';
}

/// ภาพ SVG ของแผนภาพ DFD (ตัดเฉพาะส่วนที่มีวัตถุ) — null ถ้าไม่มีวัตถุ; [dark] = ธีมมืด
String? exportDfdSvg(DfdDiagram d, {bool dark = false, String title = 'DFD'}) {
  final b = dfdBounds(d, pad: 48);
  if (b == null) return null;
  final th = dark ? _dark : _light;
  final w = b.right - b.left, h = b.bottom - b.top;
  final out = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${_n(w)}" height="${_n(h)}" '
        'viewBox="${_n(b.left)} ${_n(b.top)} ${_n(w)} ${_n(h)}" font-family="$_sans" font-size="13">')
    ..writeln('<title>${_esc(title)}</title>')
    ..writeln('<rect x="${_n(b.left)}" y="${_n(b.top)}" width="${_n(w)}" height="${_n(h)}" fill="${th.canvas}"/>');

  final routes = dfdRoutes(d);

  // ---- ขอบเขตระบบ ----
  for (final k in d.boundaries) {
    final c = k.color != null ? hexRgb(k.color!) : th.line;
    out.writeln('<rect x="${_n(k.x)}" y="${_n(k.y)}" width="${_n(k.w)}" height="${_n(k.h)}" rx="14" '
        'fill="$c" fill-opacity="0.06" stroke="$c" stroke-opacity="0.75" stroke-width="1.5" stroke-dasharray="8 6"/>');
    if (k.name.trim().isNotEmpty) {
      out.writeln('<text x="${_n(k.x + 12)}" y="${_n(k.y + 18)}" fill="${th.text}" font-weight="600" opacity="0.8">'
          '${_esc(_fit(k.name, k.w - 24, 8))}</text>');
    }
  }

  // ---- เส้น ----
  for (final f in d.flows) {
    final r = routes[f.id];
    if (r == null) continue;
    final color = f.color != null ? hexRgb(f.color!) : th.line;
    final path = StringBuffer();
    for (final (op, pts) in roundedRoute(r, radius: 8)) {
      switch (op) {
        case 'M':
          path.write('M${_n(pts[0].$1)} ${_n(pts[0].$2)} ');
        case 'L':
          path.write('L${_n(pts[0].$1)} ${_n(pts[0].$2)} ');
        case 'Q':
          path.write('Q${_n(pts[0].$1)} ${_n(pts[0].$2)} ${_n(pts[1].$1)} ${_n(pts[1].$2)} ');
      }
    }
    out.writeln('<path d="${path.toString().trim()}" fill="none" stroke="$color" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>');
    out.writeln(_arrow(r[r.length - 2], r.last, color));
    if (f.bidirectional) out.writeln(_arrow(r[1], r.first, color));
  }

  // ---- วัตถุ ----
  for (final n in d.nodes) {
    final accent = hexRgb(n.color ?? _kindColors[n.kind]!);
    final tint = th.tintOpacity;
    switch (n.kind) {
      case DfdKind.entity:
        out.writeln('<rect x="${_n(n.x)}" y="${_n(n.y)}" width="${_n(n.w)}" height="${_n(n.h)}" rx="6" fill="${th.surface}"/>');
        out.writeln('<rect x="${_n(n.x)}" y="${_n(n.y)}" width="${_n(n.w)}" height="${_n(n.h)}" rx="6" fill="$accent" fill-opacity="$tint" stroke="$accent" stroke-width="1.7"/>');
        out.writeln('<rect x="${_n(n.x + 12)}" y="${_n(n.cy - 7)}" width="16" height="14" rx="3" fill="$accent"/>');
        out.writeln(_text(n.name, n.x + 38, n.cy, n.w - 46, th.text));
      case DfdKind.process:
        out.writeln('<rect x="${_n(n.x)}" y="${_n(n.y)}" width="${_n(n.w)}" height="${_n(n.h)}" rx="16" fill="${th.surface}"/>');
        out.writeln('<rect x="${_n(n.x)}" y="${_n(n.y)}" width="${_n(n.w)}" height="${_n(n.h)}" rx="16" fill="$accent" fill-opacity="$tint" stroke="$accent" stroke-width="1.7"/>');
        final num = n.number.isEmpty ? '·' : n.number;
        final bw = math.max(30.0, num.length * 7.2 + 14);
        out.writeln('<rect x="${_n(n.x + 10)}" y="${_n(n.cy - 11)}" width="${_n(bw)}" height="22" rx="11" fill="$accent"/>');
        out.writeln('<text x="${_n(n.x + 10 + bw / 2)}" y="${_n(n.cy + 4)}" text-anchor="middle" font-size="11.5" font-weight="700" fill="${hexRgb(onColor(n.color ?? _kindColors[n.kind]!))}">${_esc(num)}</text>');
        out.writeln(_text(n.name, n.x + 10 + bw + 8, n.cy, n.w - bw - 28, th.text));
      case DfdKind.store:
        out.writeln('<rect x="${_n(n.x)}" y="${_n(n.y)}" width="${_n(n.w)}" height="${_n(n.h)}" fill="${th.surface}"/>');
        out.writeln('<rect x="${_n(n.x)}" y="${_n(n.y)}" width="${_n(n.w)}" height="${_n(n.h)}" fill="$accent" fill-opacity="$tint"/>');
        out.writeln('<path d="M${_n(n.right)} ${_n(n.y)} H${_n(n.x)} V${_n(n.bottom)} H${_n(n.right)}" fill="none" stroke="$accent" stroke-width="1.7"/>');
        out.writeln('<rect x="${_n(n.x)}" y="${_n(n.y)}" width="44" height="${_n(n.h)}" fill="$accent" fill-opacity="0.2"/>');
        out.writeln('<line x1="${_n(n.x + 44)}" y1="${_n(n.y)}" x2="${_n(n.x + 44)}" y2="${_n(n.bottom)}" stroke="$accent" stroke-width="1.7"/>');
        if (n.number.isNotEmpty) {
          out.writeln('<text x="${_n(n.x + 22)}" y="${_n(n.cy + 4)}" text-anchor="middle" font-size="12" font-weight="700" fill="$accent">${_esc(n.number)}</text>');
        }
        out.writeln(_text(n.name, n.x + 54, n.cy, n.w - 62, th.text));
    }
  }

  // ---- ป้ายชื่อเส้น ----
  for (final f in d.flows) {
    final r = routes[f.id];
    if (r == null || f.label.trim().isEmpty) continue;
    final (ax, ay) = dfdLabelAnchor(r);
    final label = _fit(f.label, 220, 6.8);
    final bw = label.length * 6.8 + 8;
    out.writeln('<rect x="${_n(ax - bw / 2)}" y="${_n(ay - 9)}" width="${_n(bw)}" height="18" rx="5" fill="${th.canvas}"/>');
    out.writeln('<text x="${_n(ax)}" y="${_n(ay + 4)}" text-anchor="middle" font-size="12" font-weight="500" fill="${th.text}">${_esc(label)}</text>');
  }

  out.writeln('</svg>');
  return out.toString();
}

String _text(String s, double x, double cy, double width, String fill) =>
    s.isEmpty ? '' : '<text x="${_n(x)}" y="${_n(cy + 4.5)}" font-weight="600" fill="$fill">${_esc(_fit(s, width, 7.4))}</text>';

String _arrow(DfdPoint from, DfdPoint to, String color) {
  final dx = to.$1 - from.$1, dy = to.$2 - from.$2;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 0.001) return '';
  final ux = dx / len, uy = dy / len;
  const size = 10.0;
  final bx = to.$1 - ux * size, by = to.$2 - uy * size;
  final nx = -uy, ny = ux;
  return '<polygon points="${_n(to.$1)},${_n(to.$2)} ${_n(bx + nx * size * 0.45)},${_n(by + ny * size * 0.45)} '
      '${_n(bx - nx * size * 0.45)},${_n(by - ny * size * 0.45)}" fill="$color"/>';
}
