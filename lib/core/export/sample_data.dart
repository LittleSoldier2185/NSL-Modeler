import 'dart:math' as math;

import '../ddl/ddl_generator.dart';
import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../l10n/l10n.dart';
import '../models/table_model.dart';
import '../types/type_map.dart';

/// สร้าง `INSERT` ข้อมูลตัวอย่างไว้ทดสอบ: ตารางแม่ก่อนลูก, ค่า FK ชี้แถวที่มีอยู่จริง,
/// เคารพ UNIQUE/PK (รวม PK หลายคอลัมน์) และกำหนดผลซ้ำได้ด้วย [seed]
///
/// คอลัมน์ AUTO INCREMENT ไม่ใส่ในคำสั่ง (ให้ DB ตั้งเอง 1,2,3…) จึงไม่ต้องเปิด IDENTITY_INSERT
String exportSampleData(Project p, {int rows = 10, int seed = 1}) {
  final n = rows.clamp(1, 1000);
  return _Sample(p, n, seed).build();
}

class _Rng {
  _Rng(int seed) : _s = (seed * 2654435761 + 1013904223) & 0x7FFFFFFF;
  int _s;

  /// LCG แบบคงที่ข้ามแพลตฟอร์ม (ไม่ใช้ dart:math Random)
  int next() {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return _s >> 8;
  }

  int below(int n) => n <= 0 ? 0 : next() % n;
  int range(int lo, int hi) => lo + below(hi - lo + 1);
  double unit() => (next() % 100000) / 100000;
}

const _names = [
  'สมชาย', 'สมหญิง', 'วิชัย', 'มาลี', 'ณัฐพล', 'กานต์', 'Alice', 'Bob', 'Carol', 'David', 'Emma', 'Frank', //
];
const _surnames = ['ใจดี', 'รักเรียน', 'สุขสันต์', 'Smith', 'Jones', 'Brown', 'Taylor'];
const _cities = ['กรุงเทพฯ', 'เชียงใหม่', 'ขอนแก่น', 'ภูเก็ต', 'Bangkok', 'Chiang Mai'];
const _statuses = ['active', 'pending', 'done', 'cancelled'];
const _sentences = [
  'ตัวอย่างข้อความสำหรับทดสอบระบบ',
  'Lorem ipsum dolor sit amet',
  'รายละเอียดเพิ่มเติมของรายการนี้',
  'Quick brown fox jumps over the lazy dog',
];

class _Sample {
  _Sample(this.p, this.rows, int seed)
      : gen = DdlGenerator.forDialect(p.dialect),
        rng = _Rng(seed);

  final Project p;
  final int rows;
  final DdlGenerator gen;
  final _Rng rng;

  /// ค่าที่สร้างแล้วของแต่ละคอลัมน์ ("tableId.columnId" -> ค่าตามแถว) ให้ตาราง FK ดึงไปใช้
  final values = <String, List<Object?>>{};

  String build() {
    final blocks = <String>[
      tr('-- ข้อมูลตัวอย่างไว้ทดสอบ ({0} แถวต่อตาราง) — {1}', [rows, p.dialect.label]),
    ];
    for (final t in _order()) {
      if (t.columns.isEmpty) continue;
      blocks.add(_table(t));
    }
    return '${blocks.join('\n\n')}\n';
  }

  /// เรียงให้ตารางแม่มาก่อนลูก (วงเป็นวงให้คงลำดับเดิมของที่เหลือ)
  List<TableModel> _order() {
    final remaining = [...p.tables];
    final out = <TableModel>[];
    final done = <String>{};
    while (remaining.isNotEmpty) {
      final ready = remaining.where((t) {
        return p.relations
            .where((r) => r.fromTableId == t.id && r.toTableId != t.id && p.tableById(r.toTableId) != null)
            .every((r) => done.contains(r.toTableId));
      }).toList();
      final pick = ready.isNotEmpty ? ready : [remaining.first]; // ติดวง -> ตัดวงที่ตารางแรก
      for (final t in pick) {
        out.add(t);
        done.add(t.id);
        remaining.remove(t);
      }
    }
    return out;
  }

  String _table(TableModel t) {
    final pkCols = t.columns.where((c) => c.isPrimaryKey).toList();
    final fkByCol = {
      for (final r in p.relations)
        if (r.fromTableId == t.id) r.fromColumnId: r
    };
    final insertCols = [for (final c in t.columns) if (!_isAuto(c)) c];

    // PK/UNIQUE ที่ FK ชี้ไปตารางแม่ -> จำนวนแถวไม่เกินจำนวนค่าที่ใช้ได้
    final seenPk = <String>{};
    final seenUnique = {for (final c in t.columns) if (c.unique && !c.isPrimaryKey) c.id: <String>{}};
    final accepted = <List<Object?>>[]; // เฉพาะคอลัมน์ที่ INSERT
    final all = {for (final c in t.columns) c.id: <Object?>[]};

    for (var i = 1; accepted.length < rows && i <= rows * 6; i++) {
      final rowNo = accepted.length + 1;
      final row = <String, Object?>{};
      for (final c in t.columns) {
        row[c.id] = _value(t, c, rowNo, fkByCol[c.id], i);
      }
      // ตรวจความไม่ซ้ำ
      if (pkCols.isNotEmpty) {
        final key = pkCols.map((c) => '${row[c.id]}').join('\u0001');
        if (!seenPk.add(key)) continue;
      }
      var clash = false;
      for (final e in seenUnique.entries) {
        final v = row[e.key];
        if (v != null && !e.value.add('$v')) clash = true;
      }
      if (clash) continue;
      accepted.add([for (final c in insertCols) row[c.id]]);
      for (final c in t.columns) {
        all[c.id]!.add(row[c.id]);
      }
    }
    for (final c in t.columns) {
      values['${t.id}.${c.id}'] = all[c.id]!;
    }

    final name = gen.quote(t.name);
    if (accepted.isEmpty) return tr('-- ข้ามตาราง {0}: สร้างแถวที่ไม่ซ้ำไม่ได้', [DdlGenerator.flat(t.name)]);
    if (insertCols.isEmpty) {
      // ทุกคอลัมน์เป็น AUTO INCREMENT -> ให้ DB ตั้งเองทั้งหมด
      final stmt = switch (p.dialect) {
        Dialect.mysql => 'INSERT INTO $name () VALUES ();',
        _ => 'INSERT INTO $name DEFAULT VALUES;',
      };
      return List.filled(accepted.length, stmt).join('\n');
    }
    final cols = insertCols.map((c) => gen.quote(c.name)).join(', ');
    final lines = [
      for (final r in accepted)
        '  (${[for (var k = 0; k < insertCols.length; k++) _literal(insertCols[k], r[k])].join(', ')})'
    ];
    return 'INSERT INTO $name ($cols) VALUES\n${lines.join(',\n')};';
  }

  bool _isAuto(ColumnModel c) => c.autoIncrement && isIntegerType(c.type);

  Object? _value(TableModel t, ColumnModel c, int rowNo, dynamic fk, int attempt) {
    if (fk != null) {
      final parent = values['${fk.toTableId}.${fk.toColumnId}'];
      final nullable = !(c.notNull || c.isPrimaryKey);
      if (parent == null || parent.isEmpty) return nullable ? null : 1;
      if (nullable && rng.below(8) == 0) return null;
      // FK ที่ต้องไม่ซ้ำ (PK/UNIQUE) ไล่ตามลำดับ นอกนั้นสุ่ม
      return (c.unique || (c.isPrimaryKey && t.columns.where((x) => x.isPrimaryKey).length == 1))
          ? parent[(rowNo - 1) % parent.length]
          : parent[rng.below(parent.length)];
    }
    if (_isAuto(c)) return rowNo;
    final nullable = !(c.notNull || c.isPrimaryKey || c.unique);
    if (nullable && rng.below(8) == 0) return null;
    return _byType(c, rowNo);
  }

  Object? _byType(ColumnModel c, int i) {
    final name = c.name.toLowerCase();
    bool has(List<String> keys) => keys.any(name.contains);
    final unique = c.unique || c.isPrimaryKey;

    switch (c.type) {
      case DataType.integer:
      case DataType.bigint:
      case DataType.smallint:
        if (c.isPrimaryKey) return i;
        if (has(['age', 'อายุ'])) return rng.range(18, 70);
        if (has(['qty', 'quantity', 'count', 'amount_items'])) return rng.range(1, 10);
        if (has(['year'])) return rng.range(2000, 2025);
        final max = c.type == DataType.smallint ? 100 : 1000;
        return unique ? i : rng.range(1, max);
      case DataType.decimal:
        final prec = c.length ?? 10, scale = c.scale ?? 2;
        final intDigits = math.max(0, math.min(prec - scale, 4));
        final limit = intDigits == 0 ? 0.99 : math.pow(10, intDigits) - 1;
        var v = (has(['price', 'amount', 'total', 'cost']) ? 10 + rng.unit() * math.min(limit - 10, 4990) : rng.unit() * limit);
        if (v < 0) v = 0;
        return num.parse(v.toStringAsFixed(scale));
      case DataType.float:
        return num.parse((rng.unit() * 100).toStringAsFixed(2));
      case DataType.boolean:
        return i % 2 == 0;
      case DataType.date:
        return _date(i);
      case DataType.datetime:
      case DataType.timestamp:
        final h = rng.range(8, 20), m = rng.range(0, 59);
        return '${_date(i)} ${pad2(h)}:${pad2(m)}:00';
      case DataType.uuid:
        return _uuid();
      case DataType.json:
        return '{"id": $i}';
      case DataType.blob:
        return c.notNull ? #blob : null;
      case DataType.varchar:
      case DataType.text:
        return _text(c, name, i, unique);
    }
  }

  String _text(ColumnModel c, String name, int i, bool unique) {
    bool has(List<String> keys) => keys.any(name.contains);
    String s;
    if (has(['email', 'mail'])) {
      s = 'user$i@example.com';
    } else if (has(['phone', 'tel', 'mobile', 'เบอร์'])) {
      s = '08${rng.range(10000000, 99999999)}';
    } else if (has(['url', 'link', 'website', 'site'])) {
      s = 'https://example.com/$i';
    } else if (has(['first_name', 'firstname', 'fname'])) {
      s = _names[(i - 1 + rng.below(3)) % _names.length];
    } else if (has(['last_name', 'lastname', 'surname', 'lname'])) {
      s = _surnames[rng.below(_surnames.length)];
    } else if (has(['name', 'ชื่อ'])) {
      s = '${_names[(i - 1) % _names.length]} ${_surnames[rng.below(_surnames.length)]}';
    } else if (has(['title', 'subject', 'หัวข้อ'])) {
      s = 'หัวข้อ $i';
    } else if (has(['desc', 'detail', 'note', 'comment', 'bio', 'remark', 'message', 'content'])) {
      s = _sentences[rng.below(_sentences.length)];
    } else if (has(['address'])) {
      s = '$i หมู่ ${rng.range(1, 9)} ${_cities[rng.below(_cities.length)]}';
    } else if (has(['city', 'province', 'จังหวัด'])) {
      s = _cities[rng.below(_cities.length)];
    } else if (has(['status', 'state'])) {
      s = _statuses[rng.below(_statuses.length)];
    } else if (has(['code', 'sku', 'ref'])) {
      s = 'CODE-${i.toString().padLeft(4, '0')}';
    } else if (has(['password', 'hash', 'token'])) {
      s = 'x${rng.range(100000, 999999)}';
    } else {
      s = '${c.name} $i';
    }
    final max = c.type == DataType.varchar ? (c.length ?? 255) : 100000;
    if (s.runes.length <= max) return s;
    // ยาวเกิน: ตัดแต่ถ้าต้องไม่ซ้ำให้คงเลขลำดับท้ายไว้
    final suffix = unique ? '$i' : '';
    final keep = math.max(0, max - suffix.length);
    return '${String.fromCharCodes(s.runes.take(keep))}$suffix';
  }

  static String pad2(int v) => v.toString().padLeft(2, '0');

  String _date(int i) {
    final d = DateTime.utc(2024, 1, 1).add(Duration(days: (i - 1) % 700));
    return '${d.year}-${pad2(d.month)}-${pad2(d.day)}';
  }

  String _uuid() {
    String hex(int n) => List.generate(n, (_) => rng.below(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${'89ab'[rng.below(4)]}${hex(3)}-${hex(12)}';
  }

  String _literal(ColumnModel c, Object? v) {
    if (v == null) return 'NULL';
    if (v is bool) return gen.booleanLiteral(v);
    if (v is num) return '$v';
    if (identical(v, #blob)) {
      return switch (p.dialect) {
        Dialect.postgres => r"'\x00'",
        Dialect.mssql => '0x00',
        _ => "X'00'",
      };
    }
    return gen.stringLiteral(v as String);
  }
}
