import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ddl/sql_highlight.dart';
import 'theme.dart';

Color sqlTokenColor(SqlTokenKind k) => switch (k) {
  SqlTokenKind.comment => const Color(0xFF8A99AE),
  SqlTokenKind.identifier => const Color(0xFF7DD3C0),
  SqlTokenKind.string => const Color(0xFFFCD34D),
  SqlTokenKind.keyword => const Color(0xFFC4B5FD),
  SqlTokenKind.type => const Color(0xFF93C5FD),
  SqlTokenKind.number => const Color(0xFFFDBA74),
  SqlTokenKind.punct => const Color(0xFF94A3B8),
  _ => const Color(0xFFE2E8F0),
};

/// ตัวแสดง SQL มีเลขบรรทัด + ไฮไลต์ + เลื่อนแนวนอน/แนวตั้ง + เลือกข้อความได้ (พื้นหลังเข้มกำหนดจากภายนอก)
class SqlCodeView extends StatelessWidget {
  const SqlCodeView({super.key, required this.lines, this.highlight = true});
  final List<String> lines;

  /// false = แสดงเป็นข้อความธรรมดา (ใช้กับ Markdown/DBML/Mermaid ที่ไม่ใช่ SQL)
  final bool highlight;

  static const _lineHeight = 19.0;
  static const _gutter = 48.0;

  /// แยกข้อความ SQL เป็นบรรทัด (ตัดบรรทัดว่างท้ายสุดที่เกิดจาก '\n' ปิดท้าย)
  static List<String> splitLines(String sql) => sql.endsWith('\n')
      ? sql.substring(0, sql.length - 1).split('\n')
      : sql.split('\n');

  /// ความกว้างของบรรทัดที่ยาวที่สุด วัดด้วยฟอนต์จริง (ภาษาไทย/ฟอนต์สำรองกว้างไม่เท่า monospace)
  double _textWidth() {
    if (lines.isEmpty) return 0;
    // บรรทัดที่ยาวที่สุดตามจำนวนตัวอักษร + บรรทัดที่มีอักขระนอก ASCII (ไทย/ฟอนต์สำรอง กว้างกว่า monospace
    // จึงบรรทัดสั้นกว่าอาจกว้างกว่า) — จำกัดจำนวนผู้เข้าชิงไว้ไม่ให้ช้าเมื่อไฟล์ใหญ่
    final longest = lines.reduce((a, b) => b.length > a.length ? b : a);
    final candidates = <String>{longest};
    for (final l in lines) {
      if (candidates.length >= 60) break;
      if (l.runes.any((r) => r > 0x7e)) candidates.add(l);
    }
    var w = 0.0;
    for (final text in candidates) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: monoStyle.copyWith(fontSize: 12.5, height: 1.0)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (tp.width > w) w = tp.width;
      tp.dispose();
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final textW = _textWidth();
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(box.maxWidth, _gutter + textW + 32);
        return SelectionArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: box.maxHeight,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemExtent: _lineHeight,
                itemCount: lines.length,
                itemBuilder: (_, i) => Row(
                  children: [
                    SizedBox(
                      width: _gutter,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.right,
                          style: monoStyle.copyWith(
                            fontSize: 12.5,
                            height: 1.0,
                            color: const Color(0xFF8A99AE),
                          ),
                        ),
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (!highlight)
                            TextSpan(text: lines[i])
                          else
                            for (final t in tokenizeSqlLine(lines[i]))
                              TextSpan(
                                text: t.text,
                                style: TextStyle(color: sqlTokenColor(t.kind)),
                              ),
                        ],
                      ),
                      style: monoStyle.copyWith(
                        fontSize: 12.5,
                        height: 1.0,
                        color: sqlTokenColor(SqlTokenKind.plain),
                      ),
                      softWrap: false,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
