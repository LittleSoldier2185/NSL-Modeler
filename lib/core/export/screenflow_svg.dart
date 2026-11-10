import '../layout/diagram_geometry.dart' show roundedRoute;
import '../layout/flowchart_geometry.dart' show fcArrowHead;
import '../layout/ortho_route.dart';
import '../layout/screenflow_geometry.dart';
import '../layout/wireframe_render.dart';
import '../models/flowchart_model.dart' show FcArrow;
import '../models/screenflow_model.dart';
import '../models/wireframe_model.dart';
import 'svg_util.dart';
import 'wireframe_svg.dart';

class _Theme {
  const _Theme({required this.canvas, required this.surface, required this.text, required this.muted, required this.tint});
  final String canvas, surface, text, muted, tint;
}

const _light = _Theme(canvas: '#F6F8FB', surface: '#FFFFFF', text: '#1B2430', muted: '#64748B', tint: '0.10');
const _dark = _Theme(canvas: '#121820', surface: '#19212B', text: '#E6EBF2', muted: '#94A3B8', tint: '0.18');

/// ภาพ SVG ของ Screen Flow (ตัดเฉพาะส่วนที่มีโหนด) — null ถ้าว่าง
/// [wireframeOf] = หาเนื้อหา Wireframe ที่หน้าจอผูกไว้ (มี = วาดภาพย่อในหน้าจอนั้น) ; [dark] = ธีมมืด ; [transparent] = ไม่มีพื้นหลัง
String? exportScreenFlowSvg(ScreenFlowDiagram d,
    {WireframeDiagram? Function(String id)? wireframeOf, bool dark = false, String title = 'Screen Flow', bool transparent = false}) {
  final b = sfBounds(d, pad: 40);
  if (b == null) return null;
  final th = dark ? _dark : _light;
  final w = b.right - b.left, h = b.bottom - b.top;
  final out = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${svgNum(w)}" height="${svgNum(h)}" '
        'viewBox="${svgNum(b.left)} ${svgNum(b.top)} ${svgNum(w)} ${svgNum(h)}" font-family="$kSvgSans" font-size="13">')
    ..writeln('<title>${svgEsc(title)}</title>');
  if (!transparent) {
    out.writeln('<rect x="${svgNum(b.left)}" y="${svgNum(b.top)}" width="${svgNum(w)}" height="${svgNum(h)}" fill="${th.canvas}"/>');
  }

  for (final n in d.nodes) {
    final color = svgColor(sfNodeColor(n)).$1;
    final r = switch (n.kind) { SfKind.start || SfKind.end => n.h / 2, _ => 8.0 };
    final dash = n.kind == SfKind.external ? ' stroke-dasharray="7 4"' : '';
    final rect = 'x="${svgNum(n.x)}" y="${svgNum(n.y)}" width="${svgNum(n.w)}" height="${svgNum(n.h)}" rx="${svgNum(r)}"';
    out.writeln('<rect $rect fill="${th.surface}"/>');
    out.writeln('<rect $rect fill="$color" fill-opacity="${th.tint}" stroke="$color" stroke-width="1.7"$dash/>');
    final label = n.title.trim().isEmpty ? '' : n.title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.kind == SfKind.screen) {
      out.writeln('<line x1="${svgNum(n.x)}" y1="${svgNum(n.y + kSfTitleBar)}" x2="${svgNum(n.right)}" y2="${svgNum(n.y + kSfTitleBar)}" '
          'stroke="$color" stroke-opacity="0.5"/>');
      if (label.isNotEmpty) {
        final line = svgWrap(label, n.w - 16, 13 * 0.58, 1).first;
        out.writeln('<text x="${svgNum(n.x + 8)}" y="${svgNum(n.y + kSfTitleBar / 2 + 4.5)}" font-weight="600" fill="${th.text}">${svgEsc(line)}</text>');
      }
      final wf = n.wireframeId == null ? null : wireframeOf?.call(n.wireframeId!);
      final box = sfThumbBox(n);
      if (wf != null) {
        final f = sfThumbFit(box, wf.width, wf.height);
        out.writeln('<svg x="${svgNum(f.dx)}" y="${svgNum(f.dy)}" width="${svgNum(wf.width * f.scale)}" height="${svgNum(wf.height * f.scale)}" '
            'viewBox="0 0 ${svgNum(wf.width)} ${svgNum(wf.height)}">');
        out.write(wireframeSvgBody(wireframePrims(wf)));
        out.writeln('</svg>');
      } else {
        final note = n.wireframeId == null ? '—' : '?';
        out.writeln('<text x="${svgNum(box.left + box.width / 2)}" y="${svgNum(box.top + box.height / 2 + 4)}" text-anchor="middle" '
            'fill="${th.muted}">$note</text>');
      }
    } else if (label.isNotEmpty) {
      final lines = svgWrap(label, n.w - 20, 13 * 0.58, 2);
      final top = n.cy - lines.length * 16 / 2;
      out.write('<text text-anchor="middle" font-weight="600" fill="${th.text}">');
      for (var i = 0; i < lines.length; i++) {
        out.write('<tspan x="${svgNum(n.cx)}" y="${svgNum(top + 16 * i + 12.5)}">${svgEsc(lines[i])}</tspan>');
      }
      out.writeln('</text>');
    }
  }

  final routes = sfRoutes(d);
  for (final e in d.edges) {
    final r = routes[e.id];
    if (r == null) continue;
    out.writeln('<path d="${svgPathData(roundedRoute(r, radius: 6))}" fill="none" stroke="${th.text}" stroke-opacity="0.75" '
        'stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>');
    final (_, pts) = fcArrowHead(FcArrow.arrow, r[r.length - 2], r.last, size: 10.8);
    if (pts.isNotEmpty) {
      out.writeln('<polygon points="${pts.map((p) => '${svgNum(p.$1)},${svgNum(p.$2)}').join(' ')}" fill="${th.text}" fill-opacity="0.75"/>');
    }
  }
  for (final e in d.edges) {
    final r = routes[e.id];
    final cap = e.caption;
    if (r == null || cap.isEmpty) continue;
    final (ax, ay) = routeLabelAnchor(r);
    final label = svgWrap(cap, 220, 6.8, 1).first;
    final bw = label.length * 6.8 + 10;
    out.writeln('<rect x="${svgNum(ax - bw / 2)}" y="${svgNum(ay - 9)}" width="${svgNum(bw)}" height="18" rx="5" fill="${th.canvas}"/>');
    out.writeln('<text x="${svgNum(ax)}" y="${svgNum(ay + 4)}" text-anchor="middle" font-size="12" font-weight="500" fill="${th.text}">${svgEsc(label)}</text>');
  }
  out.writeln('</svg>');
  return out.toString();
}
