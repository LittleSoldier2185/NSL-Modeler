import 'dart:math' as math;

import '../layout/wireframe_render.dart';
import '../models/wireframe_model.dart';
import 'svg_util.dart';

/// เขียนชิ้นวาดของ Wireframe ([wireframePrims]) เป็นองค์ประกอบ SVG (ไม่มีแท็ก svg ครอบ) — ใช้ทั้งไฟล์ภาพและภาพย่อใน Screen Flow
String wireframeSvgBody(List<WfPrim> prims) {
  final out = StringBuffer();
  for (final p in prims) {
    switch (p) {
      case WfPathPrim():
        final fill = p.fill == null ? 'fill="none"' : svgPaint('fill', p.fill!);
        final stroke = p.stroke == null
            ? ''
            : ' ${svgPaint('stroke', p.stroke!)} stroke-width="${svgNum(p.width)}" stroke-linejoin="round" stroke-linecap="round"'
                '${p.dashed ? ' stroke-dasharray="6 4"' : ''}';
        out.writeln('<path d="${svgPathData(p.cmds)}" $fill$stroke/>');
      case WfTextPrim():
        final lineH = p.size * 1.3;
        final maxLines = p.maxLines ?? math.max(1, (p.h / lineH).floor());
        final lines = svgWrap(p.text, p.w, p.size * 0.58, maxLines);
        final (anchor, tx) = switch (p.align) {
          1 => ('middle', p.x + p.w / 2),
          2 => ('end', p.x + p.w),
          _ => ('start', p.x),
        };
        final top = p.top ? p.y : p.y + (p.h - lines.length * lineH) / 2;
        out.write('<text text-anchor="$anchor" font-size="${svgNum(p.size)}" font-weight="${p.bold ? 700 : 400}" '
            '${svgPaint('fill', p.color)}>');
        for (var i = 0; i < lines.length; i++) {
          out.write('<tspan x="${svgNum(tx)}" y="${svgNum(top + lineH * i + p.size * 0.98)}">${svgEsc(lines[i])}</tspan>');
        }
        out.writeln('</text>');
    }
  }
  return out.toString();
}

/// ภาพ SVG ของหน้าจอ Wireframe ทั้งกรอบ (ตามรูปแบบการแสดงผลของเอกสาร) ; [transparent] = ไม่มีพื้นหลังรอบกรอบ
String exportWireframeSvg(WireframeDiagram d, {String title = 'Wireframe', bool transparent = false}) {
  const pad = 24.0;
  // ชิ้นที่ล้นออกนอกกรอบก็อยู่ในภาพ
  var l = 0.0, t = 0.0, r = d.width, b = d.height;
  for (final c in d.components) {
    l = math.min(l, c.x);
    t = math.min(t, c.y);
    r = math.max(r, c.right);
    b = math.max(b, c.bottom);
  }
  l -= pad;
  t -= pad;
  r += pad;
  b += pad;
  final w = r - l, h = b - t;
  final out = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${svgNum(w)}" height="${svgNum(h)}" '
        'viewBox="${svgNum(l)} ${svgNum(t)} ${svgNum(w)} ${svgNum(h)}" font-family="$kSvgSans" font-size="14">')
    ..writeln('<title>${svgEsc(title)}</title>');
  if (!transparent) {
    out.writeln('<rect x="${svgNum(l)}" y="${svgNum(t)}" width="${svgNum(w)}" height="${svgNum(h)}" '
        'fill="${d.style == WfStyle.sketch ? '#F4F4F2' : '#EEF1F5'}"/>');
  }
  out.write(wireframeSvgBody(wireframePrims(d)));
  out.writeln('</svg>');
  return out.toString();
}
