import 'dart:math' as math;

import '../layout/diagram_geometry.dart' show roundedRoute;
import '../layout/flowchart_geometry.dart';
import '../layout/ortho_route.dart';
import '../models/color_utils.dart';
import '../models/flowchart_model.dart';

const _sans = "'Noto Sans Thai','Leelawadee UI',Tahoma,'Segoe UI',sans-serif";

class _Theme {
  const _Theme({required this.canvas, required this.surface, required this.text, required this.tint});
  final String canvas, surface, text, tint;
}

const _light = _Theme(canvas: '#F6F8FB', surface: '#FFFFFF', text: '#1B2430', tint: '0.10');
const _dark = _Theme(canvas: '#121820', surface: '#19212B', text: '#E6EBF2', tint: '0.18');

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _n(num v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _d(List<FcCmd> cmds) {
  final b = StringBuffer();
  for (final (op, pts) in cmds) {
    if (op == 'Z') {
      b.write('Z ');
      continue;
    }
    b.write(op);
    b.write(pts.map((p) => '${_n(p.$1)} ${_n(p.$2)}').join(' '));
    b.write(' ');
  }
  return b.toString().trim();
}

String _dash(FcDash d, double w) => switch (d) {
      FcDash.solid => '',
      FcDash.dashed => ' stroke-dasharray="8 5"',
      FcDash.dotted => ' stroke-dasharray="${_n(math.max(1.5, w))} 4"',
    };

/// แบ่งข้อความเป็นบรรทัดให้พอดีความกว้าง (ประมาณ — SVG ไม่มีตัววัดฟอนต์จริง)
List<String> _wrap(String text, double width, double perChar, int maxLines) {
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
    final kept = out.sublist(0, maxLines);
    kept[maxLines - 1] = '${kept[maxLines - 1].substring(0, math.max(0, kept[maxLines - 1].length - 1))}…';
    return kept;
  }
  return out;
}

/// ภาพ SVG ของ Flowchart (ตัดเฉพาะส่วนที่มีสัญลักษณ์) — null ถ้าว่าง ; [dark] = ธีมมืด ; [transparent] = ไม่มีพื้นหลัง
String? exportFlowchartSvg(FlowchartDiagram d, {bool dark = false, String title = 'Flowchart', bool transparent = false}) {
  final b = fcBounds(d, pad: 40);
  if (b == null) return null;
  final th = dark ? _dark : _light;
  final w = b.right - b.left, h = b.bottom - b.top;
  final out = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${_n(w)}" height="${_n(h)}" '
        'viewBox="${_n(b.left)} ${_n(b.top)} ${_n(w)} ${_n(h)}" font-family="$_sans" font-size="13">')
    ..writeln('<title>${_esc(title)}</title>');
  if (!transparent) {
    out.writeln('<rect x="${_n(b.left)}" y="${_n(b.top)}" width="${_n(w)}" height="${_n(h)}" fill="${th.canvas}"/>');
  }

  // ---- สัญลักษณ์ ----
  for (final n in d.nodes) {
    final g = fcShapeGeom(n);
    final stroke = hexRgb(n.stroke ?? kFcShapeColors[n.shape]!);
    final path = _d(g.outline);
    if (n.fill != null) {
      out.writeln('<path d="$path" fill="${hexRgb(n.fill!)}" stroke="$stroke" stroke-width="1.7" stroke-linejoin="round"${_dash(n.dash, 1.7)}/>');
    } else {
      out.writeln('<path d="$path" fill="${th.surface}"/>');
      out.writeln('<path d="$path" fill="$stroke" fill-opacity="${th.tint}" stroke="$stroke" stroke-width="1.7" stroke-linejoin="round"${_dash(n.dash, 1.7)}/>');
    }
    if (g.details.isNotEmpty) out.writeln('<path d="${_d(g.details)}" fill="none" stroke="$stroke" stroke-width="1.7"/>');
    if (n.text.trim().isEmpty) continue;
    final box = fcTextBox(n);
    final lineH = n.fontSize * 1.25;
    final lines = _wrap(n.text, box.width, n.fontSize * 0.58, math.max(1, (box.height / lineH).floor()));
    final (anchor, tx) = switch (n.align) {
      FcAlign.left => ('start', box.left),
      FcAlign.center => ('middle', box.left + box.width / 2),
      FcAlign.right => ('end', box.left + box.width),
    };
    final top = box.top + (box.height - lines.length * lineH) / 2;
    final fill = n.textColor != null ? hexRgb(n.textColor!) : th.text;
    out.write('<text text-anchor="$anchor" font-size="${_n(n.fontSize)}" font-weight="${n.bold ? 700 : 500}"'
        '${n.italic ? ' font-style="italic"' : ''} fill="$fill">');
    for (var i = 0; i < lines.length; i++) {
      out.write('<tspan x="${_n(tx)}" y="${_n(top + lineH * i + n.fontSize)}">${_esc(lines[i])}</tspan>');
    }
    out.writeln('</text>');
  }

  // ---- เส้น ----
  final routes = fcRoutes(d);
  for (final e in d.edges) {
    final r = routes[e.id];
    if (r == null) continue;
    final color = e.color != null ? hexRgb(e.color!) : th.text;
    final segs = roundedRoute(r, radius: 6);
    out.writeln('<path d="${_d(segs)}" fill="none" stroke="$color" stroke-width="${_n(e.width)}" '
        'stroke-linejoin="round" stroke-linecap="round"${_dash(e.dash, e.width)}${e.color == null ? ' stroke-opacity="0.75"' : ''}/>');
    out.write(_arrow(e.endArrow, r[r.length - 2], r.last, color, e.width));
    out.write(_arrow(e.startArrow, r[1], r.first, color, e.width));
  }

  // ---- ป้ายเส้น ----
  for (final e in d.edges) {
    final r = routes[e.id];
    if (r == null || e.label.trim().isEmpty) continue;
    final (ax, ay) = routeLabelAnchor(r);
    final label = _wrap(e.label, 200, 6.8, 1).first;
    final bw = label.length * 6.8 + 10;
    out.writeln('<rect x="${_n(ax - bw / 2)}" y="${_n(ay - 9)}" width="${_n(bw)}" height="18" rx="5" fill="${th.canvas}"/>');
    out.writeln('<text x="${_n(ax)}" y="${_n(ay + 4)}" text-anchor="middle" font-size="12" font-weight="500" '
        'fill="${e.color != null ? hexRgb(e.color!) : th.text}">${_esc(label)}</text>');
  }
  out.writeln('</svg>');
  return out.toString();
}

String _arrow(FcArrow a, RoutePoint from, RoutePoint to, String color, double width) {
  final (filled, pts) = fcArrowHead(a, from, to, size: 9 + width);
  if (pts.isEmpty) return '';
  final ps = pts.map((p) => '${_n(p.$1)},${_n(p.$2)}').join(' ');
  return filled
      ? '<polygon points="$ps" fill="$color"/>\n'
      : '<polyline points="$ps" fill="none" stroke="$color" stroke-width="${_n(width)}" stroke-linejoin="round" stroke-linecap="round"/>\n';
}
