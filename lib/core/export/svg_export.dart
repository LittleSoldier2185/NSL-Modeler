import 'dart:math' as math;

import '../layout/diagram_geometry.dart';
import '../models/project.dart';
import '../models/table_model.dart';
import '../types/type_label.dart';

/// สร้างภาพแผนภาพ ER เป็น SVG (เวกเตอร์ ขยายได้ไม่แตก ใช้แปะใน README/รายงาน)
/// ผลลัพธ์คงที่ (ไม่มีเวลา/สุ่ม) — คืน null ถ้าไม่มีตารางหรือโน้ตให้วาด
String? exportSvg(Project p, {bool includeNotes = true}) {
  final b = diagramBounds(p, includeNotes: includeNotes);
  if (b == null) return null;
  return _Svg(p, b, includeNotes).build();
}

const _sans = "'IBM Plex Sans Thai','Leelawadee UI',Tahoma,'Segoe UI',sans-serif";
const _mono = "'JetBrains Mono',Consolas,'Courier New',monospace";

class _Svg {
  _Svg(this.p, this.b, this.includeNotes);
  final Project p;
  final DiagramBounds b;
  final bool includeNotes;
  final out = StringBuffer();

  String n(num v) {
    final s = v.toStringAsFixed(2);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  /// escape XML และตัดอักขระควบคุมที่ XML 1.0 ไม่อนุญาต
  static String esc(String s) => s
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// ตัดข้อความให้พอดีความกว้างโดยประมาณ ([charW] = ความกว้างต่อตัวอักษร)
  static String fit(String s, double width, double charW) {
    final max = math.max(1, (width / charW).floor());
    final chars = s.runes.toList();
    if (chars.length <= max) return s;
    return '${String.fromCharCodes(chars.take(math.max(1, max - 1)))}…';
  }

  String build() {
    final w = b.width, h = b.height;
    out.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    out.writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${n(w)}" height="${n(h)}" '
        'viewBox="${n(b.left)} ${n(b.top)} ${n(w)} ${n(h)}" font-family="$_sans" font-size="12.5">');
    out.writeln('<title>${esc(p.name)}</title>');
    out.writeln('<rect x="${n(b.left)}" y="${n(b.top)}" width="${n(w)}" height="${n(h)}" fill="#F6F8FB"/>');

    // เส้น FK อยู่ใต้การ์ด
    out.writeln('<g fill="none" stroke="#0F766E" stroke-width="1.6" stroke-linecap="round">');
    for (final r in p.relations) {
      final g = relationGeometry(p, r);
      if (g == null) continue;
      out.writeln('<path d="M${n(g.fx)} ${n(g.fy)} C${n(g.fx + g.d0 * g.k)} ${n(g.fy)} '
          '${n(g.tx + g.d1 * g.k)} ${n(g.ty)} ${n(g.tx)} ${n(g.ty)}"/>');
      if (g.oneToOne) {
        _bar(g.fx, g.fy, g.d0);
      } else {
        _crow(g.fx, g.fy, g.d0);
      }
      _bar(g.tx, g.ty, g.d1);
    }
    out.writeln('</g>');

    for (final t in p.tables) {
      _table(t);
    }
    if (includeNotes) {
      for (final nt in p.notes) {
        _note(nt.x, nt.y, nt.width, nt.text);
      }
    }
    out.writeln('</svg>');
    return out.toString();
  }

  void _crow(double x, double y, double dir) {
    final tip = x + dir * 14;
    out.writeln('<path d="M${n(tip)} ${n(y)} L${n(x)} ${n(y - 8)} M${n(tip)} ${n(y)} L${n(x)} ${n(y)} '
        'M${n(tip)} ${n(y)} L${n(x)} ${n(y + 8)}"/>');
  }

  void _bar(double x, double y, double dir) {
    final bx = x + dir * 8;
    out.writeln('<path d="M${n(bx)} ${n(y - 8)} L${n(bx)} ${n(y + 8)}"/>');
  }

  void _table(TableModel t) {
    final w = t.width;
    final h = tableHeight(t);
    final fkCols = {
      for (final r in p.relations)
        if (r.fromTableId == t.id) r.fromColumnId
    };
    out.writeln('<g transform="translate(${n(t.x)} ${n(t.y)})">');
    out.writeln('<rect width="${n(w)}" height="${n(h)}" rx="8" fill="#FFFFFF" stroke="#C9D1DC"/>');
    // หัวตาราง: มุมบนโค้ง มุมล่างตรง
    out.writeln('<path d="M0 8 A8 8 0 0 1 8 0 H${n(w - 8)} A8 8 0 0 1 ${n(w)} 8 V${n(kCardHeaderHeight)} H0 Z" '
        'fill="#1F2A37"/>');
    final countText = '${t.columns.length}';
    out.writeln('<text x="10" y="23" fill="#FFFFFF" font-weight="600" font-size="13">'
        '${esc(fit(t.name, w - 20 - countText.length * 7 - 8, 7.4))}</text>');
    out.writeln('<text x="${n(w - 10)}" y="23" fill="#FFFFFF" fill-opacity="0.85" font-size="11" '
        'text-anchor="end">$countText</text>');

    for (var i = 0; i < t.columns.length; i++) {
      final c = t.columns[i];
      final y0 = kCardHeaderHeight + kCardRowHeight * i;
      final type = typeLabel(c);
      out.writeln('<line x1="0" y1="${n(y0)}" x2="${n(w)}" y2="${n(y0)}" stroke="#E6EAF0"/>');

      final (flag, bg, fg) = c.isPrimaryKey
          ? ('PK', '#FDEBD3', '#8A4B08')
          : fkCols.contains(c.id)
              ? ('FK', '#D9F0EC', '#0B5A54')
              : c.unique
                  ? ('UQ', '#EDE9FE', '#5B21B6')
                  : ('', '', '');
      if (flag.isNotEmpty) {
        out.writeln('<rect x="10" y="${n(y0 + 6)}" width="24" height="16" rx="4" fill="$bg"/>');
        out.writeln('<text x="22" y="${n(y0 + 17.5)}" fill="$fg" font-family="$_mono" font-size="10" '
            'font-weight="700" text-anchor="middle">$flag</text>');
      }
      final nameW = w - 42 - 10 - type.length * 6.6 - 8;
      out.writeln('<text x="42" y="${n(y0 + 18)}" font-weight="500">${esc(fit(c.name, nameW, 7.0))}</text>');
      out.writeln('<text x="${n(w - 10)}" y="${n(y0 + 18)}" fill="#5B6778" font-family="$_mono" font-size="11" '
          'text-anchor="end">${esc(type)}</text>');
    }
    out.writeln('</g>');
  }

  void _note(double x, double y, double w, String text) {
    final lines = text.isEmpty ? <String>[''] : wrapNoteText(text, w);
    final h = kNoteChrome + kNoteLineHeight * lines.length;
    out.writeln('<g transform="translate(${n(x)} ${n(y)})">');
    out.writeln('<rect width="${n(w)}" height="${n(h)}" rx="6" fill="#FFF4D6"/>');
    out.writeln('<text x="12" y="20" fill="#5C3D00" font-weight="600" font-size="12">โน้ต</text>');
    for (var i = 0; i < lines.length; i++) {
      out.writeln('<text x="12" y="${n(38 + kNoteLineHeight * i)}" fill="#5C3D00" font-size="12" '
          'xml:space="preserve">${esc(lines[i])}</text>');
    }
    out.writeln('</g>');
  }
}
