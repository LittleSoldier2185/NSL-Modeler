import 'dart:math' as math;

/// การจัดวางกล่องสี่เหลี่ยมที่ใช้ร่วมกันระหว่างแผนภาพแบบกล่อง (Wireframe, Screen Flow, …) — ฟังก์ชันล้วน
/// (Flowchart ยังใช้โค้ดเดิมของตัวเองซึ่งทำงานแบบเดียวกัน ย้ายมาใช้ภายหลังได้)

/// กล่องที่แก้ตำแหน่ง/ขนาดได้ (พิกัดแผนภาพ)
abstract interface class EditableBox {
  String get id;
  abstract double x;
  abstract double y;
  abstract double w;
  abstract double h;
}

/// วิธีจัดแนวกล่องที่เลือก
enum BoxAlign { left, centerH, right, top, middle, bottom }

/// กรอบที่ครอบกล่องทั้งหมด (left, top, right, bottom) ; ว่าง = null
({double left, double top, double right, double bottom})? boxesBounds(Iterable<EditableBox> boxes, {double pad = 0}) {
  var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  var any = false;
  for (final n in boxes) {
    any = true;
    l = math.min(l, n.x);
    t = math.min(t, n.y);
    r = math.max(r, n.x + n.w);
    b = math.max(b, n.y + n.h);
  }
  if (!any) return null;
  return (left: l - pad, top: t - pad, right: r + pad, bottom: b + pad);
}

/// ตำแหน่งใหม่ (x, y) ของกล่องแต่ละใบหลังจัดแนว [k] ตามกรอบที่ครอบทั้งหมด — ไม่แก้ข้อมูล
Map<String, (double, double)> alignBoxes(List<EditableBox> sel, BoxAlign k) {
  final out = <String, (double, double)>{};
  final b = boxesBounds(sel);
  if (b == null) return out;
  for (final n in sel) {
    out[n.id] = switch (k) {
      BoxAlign.left => (b.left, n.y),
      BoxAlign.centerH => ((b.left + b.right) / 2 - n.w / 2, n.y),
      BoxAlign.right => (b.right - n.w, n.y),
      BoxAlign.top => (n.x, b.top),
      BoxAlign.middle => (n.x, (b.top + b.bottom) / 2 - n.h / 2),
      BoxAlign.bottom => (n.x, b.bottom - n.h),
    };
  }
  return out;
}

/// ตำแหน่งใหม่ของกล่อง (อย่างน้อย 3 ใบ) ให้ช่องว่างระหว่างกันเท่ากัน — น้อยกว่า 3 = ว่าง
Map<String, (double, double)> distributeBoxes(List<EditableBox> sel, {required bool horizontal}) {
  final out = <String, (double, double)>{};
  if (sel.length < 3) return out;
  final list = List.of(sel)..sort((a, b) => horizontal ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  final first = list.first, last = list.last;
  final span = horizontal ? last.x + last.w - first.x : last.y + last.h - first.y;
  final total = list.fold<double>(0, (s, n) => s + (horizontal ? n.w : n.h));
  final gap = (span - total) / (list.length - 1);
  var p = horizontal ? first.x : first.y;
  for (final n in list) {
    out[n.id] = horizontal ? (p, n.y) : (n.x, p);
    p += (horizontal ? n.w : n.h) + gap;
  }
  return out;
}

/// กล่อง [inner] อยู่ภายในกล่อง [outer] ทั้งใบหรือไม่ (เผื่อขอบ [tol])
bool boxInside(EditableBox inner, EditableBox outer, {double tol = 0.5}) =>
    inner.x >= outer.x - tol &&
    inner.y >= outer.y - tol &&
    inner.x + inner.w <= outer.x + outer.w + tol &&
    inner.y + inner.h <= outer.y + outer.h + tol;

/// สองกล่องซ้อนทับกันเป็นพื้นที่ (ไม่นับแค่ขอบชนกัน)
bool boxesOverlap(EditableBox a, EditableBox b) =>
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
