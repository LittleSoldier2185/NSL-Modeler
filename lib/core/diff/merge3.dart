import 'dart:convert';

import '../l10n/l10n.dart';
import '../models/project.dart';

/// การรวมโปรเจกต์แบบ 3 ทาง: [base] = ต้นฉบับร่วม, [mine] = ฉบับที่แก้อยู่ในโปรแกรม, [theirs] = ฉบับในไฟล์ที่ถูกแก้จากภายนอก
///
/// กติกา (ทำที่ระดับฟิลด์ของแต่ละวัตถุ จับคู่ด้วย id):
/// - ฝั่งเดียวที่เปลี่ยน → ใช้ฝั่งนั้น ; ทั้งสองเปลี่ยนเหมือนกัน → ใช้ค่านั้น
/// - ทั้งสองฝั่งเปลี่ยนฟิลด์เดียวกันเป็นคนละค่า → "ความขัดแย้ง" (ค่าเริ่มต้นเลือกของ [mine]) ผู้ใช้เลือกฝั่งได้ทีละรายการ
/// - ฝั่งหนึ่งลบ อีกฝั่งแก้ → ความขัดแย้ง ; ฝั่งหนึ่งลบ อีกฝั่งไม่แตะ → ลบ
/// - ตำแหน่ง/ขนาด/สี/ฟอนต์ที่แก้ต่างกันเป็นเรื่องรูปลักษณ์ → ใช้ของ [mine] ไม่ถามผู้ใช้
/// - ผลที่ได้จะถูกล้างของที่อ้างถึงสิ่งที่ถูกลบ (FK / INDEX ที่ชี้ไปคอลัมน์ที่ไม่มีแล้ว)
class MergeConflict {
  const MergeConflict(this.id, this.title, this.mine, this.theirs);

  /// กุญแจคงที่ของรายการ (ใช้เก็บว่าผู้ใช้เลือกฝั่งไหน)
  final String id;

  /// ชื่อที่อ่านง่าย เช่น `users.email › ชนิด`
  final String title;
  final String mine;
  final String theirs;
}

class MergeResult {
  MergeResult(this.merged, this.conflicts, this.notes);
  final Project merged;
  final List<MergeConflict> conflicts;

  /// สิ่งที่ระบบแก้ให้เองระหว่างรวม เช่น ลบ FK ที่ชี้ไปคอลัมน์ที่ถูกลบ
  final List<String> notes;
}

/// ฟิลด์ที่เป็นรูปลักษณ์ล้วน ๆ — ขัดแย้งกันเมื่อไหร่ใช้ของ mine เงียบ ๆ
const _cosmetic = {'x', 'y', 'width', 'height', 'color', 'fill', 'font', 'lineColor', 'board', 'colorIndex'};

/// รวม [mine] กับ [theirs] โดยใช้ [base] เป็นต้นฉบับร่วม
/// [useTheirs] = id ของความขัดแย้งที่ผู้ใช้เลือกใช้ค่าจากไฟล์ (ที่ไม่อยู่ในชุดนี้ใช้ของ mine)
MergeResult mergeProjects({
  required Project base,
  required Project mine,
  required Project theirs,
  Set<String> useTheirs = const {},
}) {
  final ctx = _Ctx(useTheirs);
  final merged = _mergeMap(base.toJson(), mine.toJson(), theirs.toJson(), const [], const [], ctx, top: true);
  var project = Project.fromJson(merged);
  final notes = _cleanup(project);
  // ล้างแล้วอาจเปลี่ยนโครงสร้าง : สร้างใหม่ผ่าน JSON เพื่อให้สอดคล้อง (เช่น แท็บ DFD)
  project = Project.fromJson(project.toJson());
  return MergeResult(project, ctx.conflicts, notes);
}

class _Ctx {
  _Ctx(this.useTheirs);
  final Set<String> useTheirs;
  final conflicts = <MergeConflict>[];

  void add(List<String> path, List<String> labels, Object? m, Object? t, {String? what}) {
    final id = path.join('/');
    if (conflicts.any((c) => c.id == id)) return;
    final title = [for (final l in labels) l].join(' › ');
    conflicts.add(MergeConflict(id, what == null ? title : '$title ($what)', _show(m), _show(t)));
  }

  bool theirsChosen(List<String> path) => useTheirs.contains(path.join('/'));
}

String _show(Object? v) {
  if (v == null) return tr('(ว่าง)');
  if (v is String) return v.isEmpty ? tr('(ว่าง)') : v;
  if (v is Map || v is List) {
    final s = jsonEncode(v);
    return s.length > 80 ? '${s.substring(0, 77)}…' : s;
  }
  return '$v';
}

bool _eq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_eq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_eq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// ป้ายชื่อของแต่ละคีย์ใน JSON เพื่อทำชื่อความขัดแย้งให้อ่านรู้เรื่อง
String _keyLabel(String key) => switch (key) {
      'name' => tr('ชื่อ'),
      'type' => tr('ชนิด'),
      'length' => tr('ความยาว'),
      'scale' => tr('ทศนิยม'),
      'pk' => tr('คีย์หลัก'),
      'notNull' => 'NOT NULL',
      'unique' => 'UNIQUE',
      'autoIncrement' => 'AUTO INCREMENT',
      'default' => tr('ค่าเริ่มต้น'),
      'comment' => tr('หมายเหตุ'),
      'dialect' => 'Dialect',
      'onDelete' => 'ON DELETE',
      'onUpdate' => 'ON UPDATE',
      'text' => tr('ข้อความ'),
      'columns' => tr('คอลัมน์'),
      'seed' => tr('ข้อมูลตั้งต้น'),
      _ => key,
    };

/// รวมวัตถุ (Map) หนึ่งก้อน
Map<String, dynamic> _mergeMap(
  Map base,
  Map mine,
  Map theirs,
  List<String> path,
  List<String> labels,
  _Ctx ctx, {
  bool top = false,
}) {
  final out = <String, dynamic>{};
  final keys = <String>{...base.keys.cast<String>(), ...mine.keys.cast<String>(), ...theirs.keys.cast<String>()};
  // คงลำดับคีย์ตามของ mine ก่อน แล้วค่อยของ theirs (ผลลัพธ์คงที่ อ่านง่าย)
  final ordered = [
    ...mine.keys.cast<String>(),
    ...theirs.keys.cast<String>().where((k) => !mine.containsKey(k)),
    ...base.keys.cast<String>().where((k) => !mine.containsKey(k) && !theirs.containsKey(k)),
  ].where(keys.contains).toSet();

  for (final k in ordered) {
    final b = base[k], m = mine[k], t = theirs[k];
    final kp = [...path, k];
    final kl = [...labels, _keyLabel(k)];
    final v = _mergeValue(k, b, m, t, kp, labels, kl, ctx, top: top);
    if (v != _absent) out[k] = v;
  }
  return out;
}

const Object _absent = _Absent();

class _Absent {
  const _Absent();
}

Object? _mergeValue(
  String key,
  Object? b,
  Object? m,
  Object? t,
  List<String> kp,
  List<String> parentLabels,
  List<String> kl,
  _Ctx ctx, {
  bool top = false,
}) {
  // รายการวัตถุที่มี id → รวมแบบจับคู่ id
  if (key != 'seed' && (_isIdList(b) || _isIdList(m) || _isIdList(t))) {
    return _mergeIdList(b as List? ?? const [], m as List? ?? const [], t as List? ?? const [], kp, parentLabels, ctx,
        nameKey: key == 'notes' ? 'text' : 'name');
  }
  // แผนภาพ DFD: ถือเป็นก้อนเดียวต่อแท็บ (รวมละเอียดกว่านี้ไม่คุ้ม)
  if (key == 'dfd' && (m is Map || t is Map || b is Map)) {
    final bm = (b as Map?) ?? const {}, mm = (m as Map?) ?? const {}, tm = (t as Map?) ?? const {};
    final out = <String, dynamic>{};
    final ids = <String>{...mm.keys.cast<String>(), ...tm.keys.cast<String>()};
    for (final id in ids) {
      final p = [...kp, id];
      final v = _atomic(bm[id], mm[id], tm[id], p, [...parentLabels, 'DFD $id'], ctx, what: tr('แผนภาพ DFD'));
      if (v != _absent && v != null) out[id] = v;
    }
    return out.isEmpty ? _absent : out;
  }
  // Map ซ้อน (เช่น board) : รวมทีละฟิลด์
  if (m is Map && t is Map) {
    return _mergeMap((b as Map?) ?? const {}, m, t, kp, parentLabels, ctx);
  }
  return _atomic(b, m, t, kp, kl, ctx, cosmetic: _cosmetic.contains(key));
}

bool _isIdList(Object? v) =>
    v is List && v.isNotEmpty && v.every((e) => e is Map && e['id'] is String);

/// ค่าเดี่ยว (ข้อความ/ตัวเลข/รายการธรรมดา ฯลฯ) : รวมแบบ 3 ทางทั้งก้อน
Object? _atomic(Object? b, Object? m, Object? t, List<String> path, List<String> labels, _Ctx ctx,
    {bool cosmetic = false, String? what}) {
  if (_eq(m, t)) return m ?? _absent;
  if (_eq(m, b)) return t ?? _absent; // mine ไม่เปลี่ยน → ตาม theirs
  if (_eq(t, b)) return m ?? _absent; // theirs ไม่เปลี่ยน → ตาม mine
  if (cosmetic) return m ?? _absent;
  ctx.add(path, labels, m, t, what: what);
  return (ctx.theirsChosen(path) ? t : m) ?? _absent;
}

String _nameOf(Map? e, String nameKey) {
  final n = e?[nameKey];
  if (n is String && n.trim().isNotEmpty) {
    final s = n.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 28 ? '${s.substring(0, 27)}…' : s;
  }
  return '${e?['id'] ?? '?'}';
}

List<Map> _asMaps(List l) => [for (final e in l) e as Map];

/// รวมรายการวัตถุที่มี `id` : เพิ่ม/ลบ/แก้ ทีละวัตถุ
List<dynamic> _mergeIdList(List b, List m, List t, List<String> path, List<String> labels, _Ctx ctx,
    {required String nameKey}) {
  final bm = {for (final e in _asMaps(b)) e['id'] as String: e};
  final mm = {for (final e in _asMaps(m)) e['id'] as String: e};
  final tm = {for (final e in _asMaps(t)) e['id'] as String: e};
  final survivors = <String, dynamic>{};
  final ids = <String>{...mm.keys, ...tm.keys, ...bm.keys};

  for (final id in ids) {
    final inB = bm.containsKey(id), inM = mm.containsKey(id), inT = tm.containsKey(id);
    final label = _nameOf(mm[id] ?? tm[id] ?? bm[id], nameKey);
    final p = [...path, id];
    final l = [...labels, label];
    if (!inB) {
      if (inM && inT) {
        survivors[id] = _mergeMap(const {}, mm[id]!, tm[id]!, p, l, ctx);
      } else {
        survivors[id] = (mm[id] ?? tm[id])!;
      }
      continue;
    }
    if (!inM && !inT) continue; // ลบทั้งสองฝั่ง
    if (inM && inT) {
      survivors[id] = _mergeMap(bm[id]!, mm[id]!, tm[id]!, p, l, ctx);
      continue;
    }
    // ฝั่งหนึ่งลบ
    final remaining = inM ? mm[id]! : tm[id]!;
    if (_eq(remaining, bm[id])) continue; // อีกฝั่งไม่แตะ → ลบจริง
    final delP = [...p, '#delete'];
    ctx.add(delP, l, inM ? tr('(แก้ไข)') : tr('(ลบแล้ว)'), inM ? tr('(ลบแล้ว)') : tr('(แก้ไข)'), what: tr('ลบ/แก้ขัดกัน'));
    final theirsWins = ctx.theirsChosen(delP);
    // mine = ฝั่งที่ถืออยู่ ; ถ้าเลือก theirs → ทำตามที่ theirs ทำ (ลบ หรือ คงฉบับที่แก้)
    final keep = inM ? !theirsWins : theirsWins;
    if (keep) survivors[id] = remaining;
  }

  // ลำดับ: ใช้ลำดับของฝั่งที่จัดเรียงใหม่ (เทียบกับ base) ไม่เช่นนั้นตาม mine แล้วเติมของใหม่จาก theirs ต่อท้าย
  List<String> orderOf(Map<String, Map> side) => [for (final id in side.keys) if (survivors.containsKey(id)) id];
  final baseCommon = [for (final id in bm.keys) if (survivors.containsKey(id)) id];
  final mOrder = orderOf(mm), tOrder = orderOf(tm);
  bool sameAsBase(List<String> o) {
    final common = [for (final id in o) if (bm.containsKey(id)) id];
    return _eq(common, [for (final id in baseCommon) if (o.contains(id)) id]);
  }

  final primary = sameAsBase(mOrder) && !sameAsBase(tOrder) ? tOrder : mOrder;
  final secondary = identical(primary, mOrder) ? tOrder : mOrder;
  final order = <String>[...primary, ...secondary.where((id) => !primary.contains(id))];
  for (final id in survivors.keys) {
    if (!order.contains(id)) order.add(id); // เช่น วัตถุที่คงไว้จากการเลือกขัดแย้ง
  }
  return [for (final id in order) survivors[id]];
}

/// ล้างสิ่งที่อ้างถึงของที่ไม่มีแล้ว คืนข้อความบอกผู้ใช้
List<String> _cleanup(Project p) {
  final notes = <String>[];
  p.relations.removeWhere((r) {
    final from = p.tableById(r.fromTableId), to = p.tableById(r.toTableId);
    final ok = from != null &&
        to != null &&
        from.columnById(r.fromColumnId) != null &&
        to.columnById(r.toColumnId) != null;
    if (!ok) {
      notes.add(tr('ตัด FK {0} ออก เพราะตาราง/คอลัมน์ที่อ้างถึงไม่มีแล้ว', [r.name ?? r.id]));
    }
    return !ok;
  });
  for (final t in p.tables) {
    for (final i in t.indexes.toList()) {
      final before = i.columnIds.length;
      i.columnIds.removeWhere((id) => t.columnById(id) == null);
      if (i.columnIds.isEmpty) {
        t.indexes.remove(i);
        notes.add(tr('ตัด INDEX {0}.{1} ออก เพราะคอลัมน์ถูกลบ', [t.name, i.name]));
      } else if (i.columnIds.length != before) {
        notes.add(tr('INDEX {0}.{1} เหลือคอลัมน์น้อยลง เพราะบางคอลัมน์ถูกลบ', [t.name, i.name]));
      }
    }
    // ข้อมูลตั้งต้นที่ชี้คอลัมน์ที่ไม่มีแล้ว
    for (final r in t.seedRows) {
      r.removeWhere((k, _) => t.columnById(k) == null);
    }
    t.seedRows.removeWhere((r) => r.isEmpty);
  }
  // PK ซ้ำ/ชื่อซ้ำไม่แตะ — ปล่อยให้ตัวตรวจ schema รายงานตามปกติ
  return notes;
}
