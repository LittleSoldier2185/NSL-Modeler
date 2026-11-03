/// ให้คะแนนความตรงของ [text] กับคำค้น [query] — มากกว่า = ตรงกว่า, null = ไม่ตรง
///
/// ลำดับความตรง: ตรงทั้งคำ > ขึ้นต้นด้วยคำค้น > ขึ้นต้นคำใดคำหนึ่ง (หลัง _ . ช่องว่าง) > มีคำค้นอยู่ในข้อความ
/// > ตัวอักษรของคำค้นเรียงตามลำดับในข้อความ (เช่น "usr" ตรง "users") ไม่สนตัวพิมพ์เล็กใหญ่
/// คำค้นหลายคำ (คั่นด้วยช่องว่าง) ต้องตรงทุกคำ คะแนนคือผลรวม
int? fuzzyScore(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;
  final t = text.toLowerCase();
  var total = 0;
  for (final word in q.split(RegExp(r'\s+'))) {
    final s = _wordScore(t, word);
    if (s == null) return null;
    total += s;
  }
  return total;
}

int? _wordScore(String t, String w) {
  if (t == w) return 1000;
  if (t.startsWith(w)) return 800 - (t.length - w.length).clamp(0, 100);
  final idx = t.indexOf(w);
  if (idx >= 0) {
    final atWordStart = idx > 0 && '_. -/'.contains(t[idx - 1]);
    return (atWordStart ? 600 : 400) - idx.clamp(0, 100);
  }
  // ตัวอักษรเรียงตามลำดับ (subsequence) — ยิ่งชิดกันยิ่งดี
  var ti = 0, first = -1, last = -1;
  for (final ch in w.split('')) {
    final found = t.indexOf(ch, ti);
    if (found < 0) return null;
    if (first < 0) first = found;
    last = found;
    ti = found + 1;
  }
  final span = last - first + 1;
  return 200 - (span - w.length).clamp(0, 150);
}

/// เรียง [items] ตามคะแนนจากมากไปน้อย (คะแนนเท่ากันคงลำดับเดิม) โดยตัดรายการที่ไม่ตรงทิ้ง
/// [textOf] คืนข้อความที่ใช้ค้นของรายการ
List<T> fuzzyRank<T>(Iterable<T> items, String query, String Function(T) textOf) {
  if (query.trim().isEmpty) return items.toList();
  final scored = <({T item, int score, int order})>[];
  var i = 0;
  for (final it in items) {
    final s = fuzzyScore(textOf(it), query);
    if (s != null) scored.add((item: it, score: s, order: i));
    i++;
  }
  scored.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  return [for (final s in scored) s.item];
}
