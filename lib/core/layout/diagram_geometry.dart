import 'dart:math' as math;

import '../models/column_model.dart';
import '../models/note_model.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';

/// เรขาคณิตของแผนภาพที่ canvas / SVG / PNG ใช้ร่วมกัน เพื่อให้วาดตรงกันทุกที่
const double kCardHeaderHeight = 36;
const double kCardRowHeight = 28;

/// คอลัมน์นี้ไม่ซ้ำกันด้วยตัวเอง (UNIQUE หรือ PK คอลัมน์เดียว) — ใช้ตัดสินว่า FK เป็น 1:1 หรือ หลาย:1
/// คอลัมน์ที่เป็นเพียงส่วนหนึ่งของ PK หลายคอลัมน์ (ตารางเชื่อม) ไม่นับ
bool isUniqueAlone(TableModel t, ColumnModel c) =>
    c.unique || (c.isPrimaryKey && t.columns.where((x) => x.isPrimaryKey).length == 1);

double tableHeight(TableModel t) => kCardHeaderHeight + kCardRowHeight * t.columns.length;

/// จุดกึ่งกลางแนวตั้งของแถวคอลัมน์ที่ [index]
double rowCenterY(double tableY, int index) =>
    tableY + kCardHeaderHeight + kCardRowHeight * index + kCardRowHeight / 2;

/// เส้น FK หนึ่งเส้น: เริ่มที่คอลัมน์ลูก (fx,fy) จบที่คอลัมน์แม่ (tx,ty)
/// d0/d1 = ทิศที่เส้นออก/เข้า (+1 ขวา, -1 ซ้าย), k = ระยะดึงโค้ง
class RelationGeometry {
  const RelationGeometry({
    required this.fx,
    required this.fy,
    required this.tx,
    required this.ty,
    required this.d0,
    required this.d1,
    required this.k,
    required this.oneToOne,
  });
  final double fx, fy, tx, ty, d0, d1, k;

  /// คอลัมน์ FK เป็น PK/UNIQUE -> ปลายลูกเป็นขีดแทนตีนกา
  final bool oneToOne;
}

RelationGeometry? relationGeometry(Project p, RelationModel r) {
  final ft = p.tableById(r.fromTableId);
  final tt = p.tableById(r.toTableId);
  if (ft == null || tt == null) return null;
  final fi = ft.columns.indexWhere((c) => c.id == r.fromColumnId);
  final ti = tt.columns.indexWhere((c) => c.id == r.toColumnId);
  if (fi < 0 || ti < 0) return null;
  final fcol = ft.columns[fi];

  final double fx, tx, d0, d1;
  if (ft.x + ft.width <= tt.x) {
    fx = ft.x + ft.width;
    tx = tt.x;
    d0 = 1;
    d1 = -1;
  } else if (tt.x + tt.width <= ft.x) {
    fx = ft.x;
    tx = tt.x + tt.width;
    d0 = -1;
    d1 = 1;
  } else {
    // การ์ดซ้อนกันในแนวนอน (หรือตารางเดียวกัน): ออกด้านขวาทั้งคู่
    fx = ft.x + ft.width;
    tx = tt.x + tt.width;
    d0 = 1;
    d1 = 1;
  }
  return RelationGeometry(
    fx: fx,
    fy: rowCenterY(ft.y, fi),
    tx: tx,
    ty: rowCenterY(tt.y, ti),
    d0: d0,
    d1: d1,
    k: d0 == d1 ? 60.0 : math.max(40.0, (tx - fx).abs() / 2),
    oneToOne: isUniqueAlone(ft, fcol),
  );
}

/// ตัดข้อความโน้ตเป็นบรรทัดโดยประมาณ (ไม่รู้ความกว้างฟอนต์จริง) — ใช้ร่วมกันทั้ง SVG และ PNG
List<String> wrapNoteText(String text, double width) {
  final perLine = math.max(8, ((width - 24) / 6.8).floor());
  final out = <String>[];
  for (final raw in text.split('\n')) {
    var line = raw;
    if (line.isEmpty) {
      out.add('');
      continue;
    }
    while (line.length > perLine) {
      var cut = line.lastIndexOf(' ', perLine);
      if (cut <= 0) cut = perLine;
      out.add(line.substring(0, cut).trimRight());
      line = line.substring(cut).trimLeft();
    }
    out.add(line);
  }
  return out;
}

const double kNoteLineHeight = 16;
const double kNoteChrome = 34; // หัว "โน้ต" + ช่องว่างบนล่าง

double noteHeight(NoteModel n) {
  final lines = n.text.isEmpty ? 1 : wrapNoteText(n.text, n.width).length;
  return kNoteChrome + kNoteLineHeight * lines;
}

class DiagramBounds {
  const DiagramBounds(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  double get width => right - left;
  double get height => bottom - top;
}

/// กรอบที่ครอบตาราง (และโน้ต) ทั้งหมด — null ถ้าไม่มีอะไรเลย
DiagramBounds? diagramBounds(Project p, {bool includeNotes = true}) {
  double? l, t, r, b;
  void add(double x, double y, double w, double h) {
    l = l == null ? x : math.min(l!, x);
    t = t == null ? y : math.min(t!, y);
    r = r == null ? x + w : math.max(r!, x + w);
    b = b == null ? y + h : math.max(b!, y + h);
  }

  for (final tb in p.tables) {
    add(tb.x, tb.y, tb.width, tableHeight(tb));
  }
  if (includeNotes) {
    for (final n in p.notes) {
      add(n.x, n.y, n.width, noteHeight(n));
    }
  }
  if (l == null) return null;
  // เส้น FK ที่โค้งออกนอกการ์ดสุดขอบ (ตีนกา 14 + โค้ง ~ 60)
  return DiagramBounds(l! - 24, t! - 24, r! + 24 + (p.relations.isEmpty ? 0 : 40), b! + 24);
}
