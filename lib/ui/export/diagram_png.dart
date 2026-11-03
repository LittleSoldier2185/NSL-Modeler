import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/layout/diagram_geometry.dart';
import '../../core/models/color_utils.dart';
import '../../core/models/group_model.dart';
import '../../core/models/project.dart';
import '../../core/models/table_model.dart';
import '../canvas/relation_painter.dart';
import '../theme.dart';
import '../../core/l10n/l10n.dart';

class PngExport {
  const PngExport(this.bytes, this.width, this.height, this.scale);
  final Uint8List bytes;
  final int width;
  final int height;

  /// สเกลที่ใช้จริง (อาจน้อยกว่าที่ขอถ้าภาพใหญ่เกินขีดจำกัด)
  final double scale;
}

/// ด้านที่ยาวที่สุดของภาพ PNG ไม่เกินนี้ (ภาพใหญ่กว่านี้ GPU/หน่วยความจำอาจไม่ไหว)
const int kMaxPngSide = 16000;

/// วาดแผนภาพทั้งหมดลงภาพ PNG — คืน null ถ้าไม่มีตารางหรือโน้ตให้วาด
///
/// [bounds] ระบุพื้นที่ที่จะส่งออกเอง (เช่นทั้งกระดาน) ถ้าไม่ระบุจะตัดเฉพาะส่วนที่มีตาราง/โน้ต
///
/// [dark] = ภาพธีมมืด (ค่าเริ่มต้นเป็นธีมสว่างเสมอไม่ว่าแอปอยู่ธีมไหน)
Future<PngExport?> exportPng(Project p,
    {double scale = 2, bool includeNotes = true, DiagramBounds? bounds, bool dark = false}) async {
  final content = diagramBounds(p, includeNotes: includeNotes);
  if (content == null) return null;
  final b = bounds ?? content;

  final s = math.min(scale, kMaxPngSide / math.max(b.width, b.height));
  final w = (b.width * s).ceil();
  final h = (b.height * s).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(s);
  canvas.translate(-b.left, -b.top);
  final size = Size(b.width, b.height);

  // ภาพที่ export ใช้ธีมที่เลือก (สว่างโดยค่าเริ่มต้น) ไม่ขึ้นกับธีมของแอป
  C.withPalette(dark ? kDarkPalette : kLightPalette, () {
    canvas.drawRect(Rect.fromLTWH(b.left, b.top, b.width, b.height), Paint()..color = C.canvas);
    for (final g in p.groups) {
      _drawGroup(canvas, g);
    }
    RelationPainter(p, null).paint(canvas, size);
    for (final t in p.tables) {
      _drawTable(canvas, p, t);
    }
    if (includeNotes) {
      for (final n in p.notes) {
        _drawNote(canvas, n.x, n.y, n.width, n.text);
      }
    }
  });

  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) return null;
  return PngExport(data.buffer.asUint8List(), w, h, s);
}

TextPainter _tp(String text, TextStyle style, {double? maxWidth}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
  return tp;
}

void _text(Canvas canvas, String text, TextStyle style, double x, double yCenter,
    {double? maxWidth, bool alignRight = false}) {
  final tp = _tp(text, style, maxWidth: maxWidth);
  final dx = alignRight ? x - tp.width : x;
  tp.paint(canvas, Offset(dx, yCenter - tp.height / 2));
  tp.dispose();
}

/// [family] = ฟอนต์ที่ผู้ใช้เลือกให้ตาราง (null = Noto Sans Thai) ฟอนต์ที่ไม่มีอักษรไทย/ไม่มีในเครื่องตกไปใช้ Noto Sans Thai
TextStyle _sans(double size, Color color, {FontWeight weight = FontWeight.w400, String? family}) => TextStyle(
      fontFamily: family ?? kThai,
      fontFamilyFallback: family == null ? kFontFallback : [kThai, ...kFontFallback],
      fontSize: size,
      color: color,
      fontWeight: weight,
    );

TextStyle _mono(double size, Color color, {FontWeight weight = FontWeight.w400}) =>
    monoStyle.copyWith(fontSize: size, color: color, fontWeight: weight);

void _drawTable(Canvas canvas, Project p, TableModel t) {
  final w = t.width;
  final h = tableHeight(t);
  final rect = Rect.fromLTWH(t.x, t.y, w, h);
  final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

  final custom = t.colorValue == null ? null : Color(t.colorValue!);
  final font = t.fontFamily;
  canvas.drawRRect(rrect, Paint()..color = C.surface);
  if (custom != null) canvas.drawRRect(rrect, Paint()..color = custom.withValues(alpha: C.isDark ? 0.14 : 0.06));
  canvas.save();
  canvas.clipRRect(rrect);
  final headBg = custom ?? C.tableHead;
  canvas.drawRect(Rect.fromLTWH(t.x, t.y, w, kCardHeaderHeight), Paint()..color = headBg);
  canvas.restore();
  canvas.drawRRect(
    rrect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = C.isDark ? const Color(0xFF3B4859) : const Color(0xFFC9D1DC),
  );

  // สีตัวอักษรบนหัวตารางตามความสว่างของสีพื้น (สีกำหนดเองอาจอ่อนมาก)
  final headFg = Color(onColor(headBg.toARGB32()));
  final count = '${t.columns.length}';
  _text(canvas, count, _sans(11, headFg.withValues(alpha: 0.85), family: font), t.x + w - 10, t.y + 18, alignRight: true);
  _text(canvas, t.name, _sans(13, headFg, weight: FontWeight.w600, family: font), t.x + 10, t.y + 18,
      maxWidth: w - 20 - count.length * 7 - 8);

  final fkCols = {
    for (final r in p.relations)
      if (r.fromTableId == t.id) r.fromColumnId
  };
  final line = Paint()
    ..color = C.borderSoft
    ..strokeWidth = 1;
  for (var i = 0; i < t.columns.length; i++) {
    final c = t.columns[i];
    final y0 = t.y + kCardHeaderHeight + kCardRowHeight * i;
    canvas.drawLine(Offset(t.x, y0), Offset(t.x + w, y0), line);

    final (flag, bg, fg) = c.isPrimaryKey
        ? ('PK', C.pkBg, C.pkText)
        : fkCols.contains(c.id)
            ? ('FK', C.fkChip, C.primaryDark)
            : c.unique
                ? ('UQ', C.uqBg, C.uqText)
                : ('', Colors.transparent, Colors.transparent);
    if (flag.isNotEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(t.x + 10, y0 + 6, 24, 16), const Radius.circular(4)),
        Paint()..color = bg,
      );
      final tp = _tp(flag, _mono(10, fg, weight: FontWeight.w700));
      tp.paint(canvas, Offset(t.x + 22 - tp.width / 2, y0 + 14 - tp.height / 2));
      tp.dispose();
    }

    final type = typeLabel(c);
    final typeTp = _tp(type, font == null ? _mono(11, C.muted) : _sans(11, C.muted, family: font));
    final typeW = typeTp.width;
    typeTp.paint(canvas, Offset(t.x + w - 10 - typeW, y0 + 14 - typeTp.height / 2));
    typeTp.dispose();
    _text(canvas, c.name, _sans(12.5, C.text, weight: FontWeight.w500, family: font), t.x + 42, y0 + 14,
        maxWidth: math.max(10.0, w - 42 - 10 - typeW - 8));
  }
}

void _drawGroup(Canvas canvas, GroupModel g) {
  final color = Color(g.colorValue);
  final rect = Rect.fromLTWH(g.x, g.y, g.width, g.height);
  final r = RRect.fromRectAndRadius(rect, const Radius.circular(14));
  canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.07));
  canvas.drawRRect(
    RRect.fromRectAndCorners(Rect.fromLTWH(g.x, g.y, g.width, kGroupHeader),
        topLeft: const Radius.circular(14), topRight: const Radius.circular(14)),
    Paint()..color = color.withValues(alpha: 0.14),
  );
  final border = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = color.withValues(alpha: 0.9);
  for (final m in (Path()..addRRect(r.deflate(0.8))).computeMetrics()) {
    for (var d = 0.0; d < m.length; d += 14) {
      canvas.drawPath(m.extractPath(d, math.min(d + 8, m.length)), border);
    }
  }
  _text(canvas, g.name, _sans(13, C.isDark ? color : Color.lerp(color, Colors.black, 0.35)!, weight: FontWeight.w600), g.x + 14,
      g.y + kGroupHeader / 2, maxWidth: g.width - 28);
}

void _drawNote(Canvas canvas, double x, double y, double w, String text) {
  final lines = text.isEmpty ? <String>[''] : wrapNoteText(text, w);
  final h = kNoteChrome + kNoteLineHeight * lines.length;
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(6)),
    Paint()..color = C.warnBg,
  );
  _text(canvas, tr('โน้ต'), _sans(12, C.warnText, weight: FontWeight.w600), x + 12, y + 16);
  for (var i = 0; i < lines.length; i++) {
    _text(canvas, lines[i], _sans(12, C.warnText), x + 12, y + 34 + kNoteLineHeight * i - 4,
        maxWidth: w - 24);
  }
}
