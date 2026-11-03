import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/layout/diagram_geometry.dart';
import '../../core/models/project.dart';
import '../../core/models/table_model.dart';
import '../canvas/relation_painter.dart';
import '../theme.dart';

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
Future<PngExport?> exportPng(Project p, {double scale = 2, bool includeNotes = true}) async {
  final b = diagramBounds(p, includeNotes: includeNotes);
  if (b == null) return null;

  final s = math.min(scale, kMaxPngSide / math.max(b.width, b.height));
  final w = (b.width * s).ceil();
  final h = (b.height * s).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(s);
  canvas.translate(-b.left, -b.top);
  final size = Size(b.width, b.height);

  canvas.drawRect(Rect.fromLTWH(b.left, b.top, b.width, b.height), Paint()..color = C.canvas);
  RelationPainter(p, null).paint(canvas, size);
  for (final t in p.tables) {
    _drawTable(canvas, p, t);
  }
  if (includeNotes) {
    for (final n in p.notes) {
      _drawNote(canvas, n.x, n.y, n.width, n.text);
    }
  }

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

TextStyle _sans(double size, Color color, {FontWeight weight = FontWeight.w400}) => TextStyle(
      fontFamily: kThai,
      fontFamilyFallback: const ['Leelawadee UI', 'Tahoma', 'Segoe UI'],
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

  canvas.drawRRect(rrect, Paint()..color = Colors.white);
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawRect(Rect.fromLTWH(t.x, t.y, w, kCardHeaderHeight), Paint()..color = C.tableHead);
  canvas.restore();
  canvas.drawRRect(
    rrect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFC9D1DC),
  );

  final count = '${t.columns.length}';
  _text(canvas, count, _sans(11, const Color(0xD9FFFFFF)), t.x + w - 10, t.y + 18, alignRight: true);
  _text(canvas, t.name, _sans(13, Colors.white, weight: FontWeight.w600), t.x + 10, t.y + 18,
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
            ? ('FK', const Color(0xFFD9F0EC), C.primaryDark)
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
    final typeTp = _tp(type, _mono(11, C.muted));
    final typeW = typeTp.width;
    typeTp.paint(canvas, Offset(t.x + w - 10 - typeW, y0 + 14 - typeTp.height / 2));
    typeTp.dispose();
    _text(canvas, c.name, _sans(12.5, C.text, weight: FontWeight.w500), t.x + 42, y0 + 14,
        maxWidth: math.max(10.0, w - 42 - 10 - typeW - 8));
  }
}

void _drawNote(Canvas canvas, double x, double y, double w, String text) {
  final lines = text.isEmpty ? <String>[''] : wrapNoteText(text, w);
  final h = kNoteChrome + kNoteLineHeight * lines.length;
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(6)),
    Paint()..color = C.warnBg,
  );
  _text(canvas, 'โน้ต', _sans(12, C.warnText, weight: FontWeight.w600), x + 12, y + 16);
  for (var i = 0; i < lines.length; i++) {
    _text(canvas, lines[i], _sans(12, C.warnText), x + 12, y + 34 + kNoteLineHeight * i - 4,
        maxWidth: w - 24);
  }
}
