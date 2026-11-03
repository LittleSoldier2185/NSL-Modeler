import 'dart:math' as math;

import '../layout/diagram_geometry.dart';
import '../models/color_utils.dart';
import '../models/group_model.dart';
import '../models/project.dart';
import '../models/table_model.dart';
import '../types/type_label.dart';
import '../l10n/l10n.dart';

/// สร้างภาพแผนภาพ ER เป็น SVG (เวกเตอร์ ขยายได้ไม่แตก ใช้แปะใน README/รายงาน)
/// ผลลัพธ์คงที่ (ไม่มีเวลา/สุ่ม) — คืน null ถ้าไม่มีตารางหรือโน้ตให้วาด
///
/// [bounds] ระบุพื้นที่ที่จะส่งออกเอง (เช่นทั้งกระดาน) ถ้าไม่ระบุจะตัดเฉพาะส่วนที่มีตาราง/โน้ต
/// [dark] = ภาพธีมมืด (พื้น/การ์ด/ตัวอักษรใช้ชุดสีมืด) — ค่าเริ่มต้นเป็นธีมสว่างเสมอไม่ว่าแอปอยู่ธีมไหน
String? exportSvg(Project p, {bool includeNotes = true, DiagramBounds? bounds, bool dark = false, bool flowMarkers = false}) {
  final b = diagramBounds(p, includeNotes: includeNotes);
  if (b == null) return null;
  return _Svg(p, bounds ?? b, includeNotes, dark ? _dark : _light, flowMarkers).build();
}

/// ชุดสีของภาพ SVG (ฮีกซ์) — ธีมมืดตรงกับพาเลตต์มืดของแอป
class _SvgTheme {
  const _SvgTheme({
    required this.canvas,
    required this.card,
    required this.cardStroke,
    required this.rowLine,
    required this.text,
    required this.muted,
    required this.header,
    required this.line,
    required this.pk,
    required this.fk,
    required this.uq,
    required this.noteBg,
    required this.noteText,
    required this.tintOpacity,
  });
  final String canvas, card, cardStroke, rowLine, text, muted, header, line;
  final (String bg, String fg) pk, fk, uq;
  final String noteBg, noteText;
  final String tintOpacity;
}

const _light = _SvgTheme(
  canvas: '#F6F8FB',
  card: '#FFFFFF',
  cardStroke: '#C9D1DC',
  rowLine: '#E6EAF0',
  text: '#1B2430',
  muted: '#5B6778',
  header: '#1F2A37',
  line: '#0F766E',
  pk: ('#FDEBD3', '#8A4B08'),
  fk: ('#D9F0EC', '#0B5A54'),
  uq: ('#EDE9FE', '#5B21B6'),
  noteBg: '#FFF4D6',
  noteText: '#5C3D00',
  tintOpacity: '0.06',
);

const _dark = _SvgTheme(
  canvas: '#121820',
  card: '#19212B',
  cardStroke: '#3B4859',
  rowLine: '#242E3A',
  text: '#E6EBF2',
  muted: '#9AA7B8',
  header: '#2A3848',
  line: '#14958B',
  pk: ('#4A3213', '#F5B66B'),
  fk: ('#16403D', '#5ED0C4'),
  uq: ('#2E2552', '#C4B0FA'),
  noteBg: '#3A2E10',
  noteText: '#F4D58A',
  tintOpacity: '0.14',
);

const _sans = "'Noto Sans Thai','Leelawadee UI',Tahoma,'Segoe UI',sans-serif";
const _mono = "'JetBrains Mono',Consolas,'Courier New',monospace";

class _Svg {
  _Svg(this.p, this.b, this.includeNotes, this.th, this.flowMarkers);
  final bool flowMarkers;
  final Project p;
  final DiagramBounds b;
  final bool includeNotes;
  final _SvgTheme th;
  final out = StringBuffer();

  /// สีเส้นเริ่มต้นและสีพื้นกระดาน (ฮีกซ์) ของภาพ
  String get lineHex => p.lineColor != null ? hexRgb(p.lineColor!) : th.line;
  String get canvasHex => th.canvas;

  /// ชื่อฟอนต์ที่ผู้ใช้เลือก + ฟอนต์สำรองของแอป ใส่ในค่า font-family ของ SVG (ฟอนต์ที่ผู้เปิดไฟล์ไม่มีจะตกไปใช้ฟอนต์สำรอง)
  static String fontStack(String family) => "'${esc(family).replaceAll('&apos;', '')}',$_sans";

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
    out.writeln('<rect x="${n(b.left)}" y="${n(b.top)}" width="${n(w)}" height="${n(h)}" fill="${th.canvas}"/>');

    // กลุ่มอยู่ล่างสุด (ใต้เส้น FK และการ์ด)
    for (final g in p.groups) {
      final hex = hexRgb(g.colorValue);
      out.writeln('<rect x="${n(g.x)}" y="${n(g.y)}" width="${n(g.width)}" height="${n(g.height)}" rx="14" '
          'fill="$hex" fill-opacity="0.07" stroke="$hex" stroke-opacity="0.9" stroke-width="1.6" stroke-dasharray="8 6"/>');
      out.writeln('<path d="M${n(g.x)} ${n(g.y + kGroupHeader)} V${n(g.y + 14)} A14 14 0 0 1 ${n(g.x + 14)} ${n(g.y)} '
          'H${n(g.x + g.width - 14)} A14 14 0 0 1 ${n(g.x + g.width)} ${n(g.y + 14)} V${n(g.y + kGroupHeader)} Z" '
          'fill="$hex" fill-opacity="0.14"/>');
      out.writeln('<text x="${n(g.x + 14)}" y="${n(g.y + kGroupHeader / 2 + 4.5)}" font-size="13" font-weight="600" fill="$hex">'
          '${esc(fit(g.name, g.width - 28, 7.6))}</text>');
    }

    // เส้น FK อยู่ใต้การ์ด
    out.writeln('<g fill="none" stroke="$lineHex" stroke-width="1.6" stroke-linecap="round">');
    final routes = relationRoutes(p);
    final slots = parentEndSlots(p);
    for (final r in p.relations) {
      final g = relationGeometry(p, r);
      final route = routes[r.id];
      if (g == null || route == null) continue;
      // สีเส้นของความสัมพันธ์นี้ ก่อน สีเริ่มต้นของโปรเจกต์ (เส้นที่ใช้สีเดียวกับกลุ่มไม่ต้องห่อซ้ำ)
      final own = r.color ?? p.lineColor;
      final ownHex = own == null ? lineHex : hexRgb(own);
      if (ownHex != lineHex) out.writeln('<g stroke="$ownHex">');
      final d = StringBuffer();
      for (final (op, pts) in roundedRoute(route)) {
        if (d.isNotEmpty) d.write(' ');
        d.write(op);
        d.write(pts.map((q) => '${n(q.$1)} ${n(q.$2)}').join(' '));
      }
      out.writeln('<path d="$d"/>');
      if (g.oneToOne) {
        _bar(g.fx, g.fy, g.d0);
      } else {
        _crow(g.fx, g.fy, g.d0);
      }
      // ปลายฝั่งแม่ของเส้นนี้เอง (เส้นที่เข้าคอลัมน์เดียวกันเข้าคนละระดับ ย่อสัญลักษณ์ไม่ให้ซ้อนกัน)
      final end = route.last;
      final s = (slots[r.id]?.count ?? 1) > 1 ? 0.6 : 1.0;
      _bar(end.$1, end.$2, g.d1, half: 8 * s);
      if (g.mandatory) {
        _bar(end.$1 + g.d1 * 5, end.$2, g.d1, half: 8 * s);
      } else {
        out.writeln('<circle cx="${n(end.$1 + g.d1 * (s < 1 ? 13 : 17))}" cy="${n(end.$2)}" r="${n(4.5 * s)}" fill="$canvasHex"/>');
      }
      // เครื่องหมายทิศทางข้อมูล: วงกลมลูกศรกลางเส้น ชี้จากตารางแม่ไปหาตารางลูก (ตรงกับที่วาดบนจอ)
      final m = flowMarkers ? relationFlowMarker(route) : null;
      if (m != null) {
        out.writeln('<circle cx="${n(m.x)}" cy="${n(m.y)}" r="9.5" fill="$canvasHex"/>');
        final tx = m.x + m.dx * 3.6, ty = m.y + m.dy * 3.6;
        final nx = -m.dy, ny = m.dx;
        out.writeln('<path d="M${n(tx - m.dx * 5 + nx * 4.6)} ${n(ty - m.dy * 5 + ny * 4.6)} L${n(tx)} ${n(ty)} '
            'L${n(tx - m.dx * 5 - nx * 4.6)} ${n(ty - m.dy * 5 - ny * 4.6)}" stroke-width="1.8" stroke-linejoin="round"/>');
        out.writeln('<circle cx="${n(m.x)}" cy="${n(m.y)}" r="9.5"/>');
      }
      if (ownHex != lineHex) out.writeln('</g>');
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

  void _bar(double x, double y, double dir, {double half = 8}) {
    final bx = x + dir * 8;
    out.writeln('<path d="M${n(bx)} ${n(y - half)} L${n(bx)} ${n(y + half)}"/>');
  }

  void _table(TableModel t) {
    final w = t.width;
    final h = tableHeight(t);
    final fkCols = {
      for (final r in p.relations)
        if (r.fromTableId == t.id) r.fromColumnId
    };
    final font = t.fontFamily == null ? '' : ' font-family="${fontStack(t.fontFamily!)}"';
    out.writeln('<g transform="translate(${n(t.x)} ${n(t.y)})"$font>');
    out.writeln('<rect width="${n(w)}" height="${n(h)}" rx="8" fill="${th.card}" stroke="${th.cardStroke}"/>');
    final custom = t.colorValue;
    final hex = custom == null ? th.header : hexRgb(custom);
    // สีตัวอักษรบนหัวตารางตามความสว่างของสีพื้น (สีกำหนดเองอาจอ่อนมาก)
    final headFg = custom == null ? '#FFFFFF' : hexRgb(onColor(custom));
    if (custom != null) {
      out.writeln('<rect width="${n(w)}" height="${n(h)}" rx="8" fill="$hex" fill-opacity="${th.tintOpacity}"/>');
    }
    // หัวตาราง: มุมบนโค้ง มุมล่างตรง
    out.writeln('<path d="M0 8 A8 8 0 0 1 8 0 H${n(w - 8)} A8 8 0 0 1 ${n(w)} 8 V${n(kCardHeaderHeight)} H0 Z" '
        'fill="$hex"/>');
    final countText = '${t.columns.length}';
    out.writeln('<text x="10" y="23" fill="$headFg" font-weight="600" font-size="13">'
        '${esc(fit(t.name, w - 20 - countText.length * 7 - 8, 7.4))}</text>');
    out.writeln('<text x="${n(w - 10)}" y="23" fill="$headFg" fill-opacity="0.85" font-size="11" '
        'text-anchor="end">$countText</text>');

    for (var i = 0; i < t.columns.length; i++) {
      final c = t.columns[i];
      final y0 = kCardHeaderHeight + kCardRowHeight * i;
      final type = typeLabel(c);
      out.writeln('<line x1="0" y1="${n(y0)}" x2="${n(w)}" y2="${n(y0)}" stroke="${th.rowLine}"/>');

      final (flag, (bg, fg)) = c.isPrimaryKey
          ? ('PK', th.pk)
          : fkCols.contains(c.id)
              ? ('FK', th.fk)
              : c.unique
                  ? ('UQ', th.uq)
                  : ('', ('', ''));
      if (flag.isNotEmpty) {
        out.writeln('<rect x="10" y="${n(y0 + 6)}" width="24" height="16" rx="4" fill="$bg"/>');
        out.writeln('<text x="22" y="${n(y0 + 17.5)}" fill="$fg" font-family="$_mono" font-size="10" '
            'font-weight="700" text-anchor="middle">$flag</text>');
      }
      final nameW = w - 42 - 10 - type.length * 6.6 - 8;
      out.writeln('<text x="42" y="${n(y0 + 18)}" font-weight="500" fill="${th.text}">${esc(fit(c.name, nameW, 7.0))}</text>');
      // ชนิดข้อมูล: ถ้าผู้ใช้เลือกฟอนต์ให้ตาราง ใช้ฟอนต์นั้น (ไม่งั้นฟอนต์เว้นระยะเท่ากัน)
      final typeFont = t.fontFamily == null ? ' font-family="$_mono"' : '';
      out.writeln('<text x="${n(w - 10)}" y="${n(y0 + 18)}" fill="${th.muted}"$typeFont font-size="11" '
          'text-anchor="end">${esc(type)}</text>');
    }
    out.writeln('</g>');
  }

  void _note(double x, double y, double w, String text) {
    final lines = text.isEmpty ? <String>[''] : wrapNoteText(text, w);
    final h = kNoteChrome + kNoteLineHeight * lines.length;
    out.writeln('<g transform="translate(${n(x)} ${n(y)})">');
    out.writeln('<rect width="${n(w)}" height="${n(h)}" rx="6" fill="${th.noteBg}"/>');
    out.writeln('<text x="12" y="20" fill="${th.noteText}" font-weight="600" font-size="12">${esc(tr('โน้ต'))}</text>');
    for (var i = 0; i < lines.length; i++) {
      out.writeln('<text x="12" y="${n(38 + kNoteLineHeight * i)}" fill="${th.noteText}" font-size="12" '
          'xml:space="preserve">${esc(lines[i])}</text>');
    }
    out.writeln('</g>');
  }
}
