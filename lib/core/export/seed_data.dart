import 'dart:convert';

import '../ddl/ddl_generator.dart';
import '../l10n/l10n.dart';
import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/table_model.dart';

/// ข้อมูลตั้งต้น (seed data): แถวที่ผู้ใช้กรอกไว้ล่วงหน้าในตาราง เช่น roles, statuses
/// เก็บใน [TableModel.seedRows] เป็นข้อความต่อคอลัมน์ (id คอลัมน์ -> ข้อความ)
///
/// กติกาค่าในช่อง:
/// - ช่องว่าง = NULL
/// - `""` (เครื่องหมายคำพูดคู่สองตัว) = สตริงว่าง (เฉพาะคอลัมน์ข้อความ)
/// - คอลัมน์ที่ไม่ได้กรอก (ไม่มี key) ใช้ DEFAULT/AUTO INCREMENT ของฐานข้อมูล
class SeedProblem {
  const SeedProblem(this.tableId, this.row, this.columnId, this.key, [this.args = const []]);
  final String tableId;

  /// ลำดับแถว (เริ่ม 0) — null = ปัญหาระดับตาราง
  final int? row;
  final String? columnId;

  /// ข้อความไทยต้นฉบับ (คีย์ของ `tr`) พร้อมค่าที่แทรก
  final String key;
  final List<Object?> args;

  String get message => tr(key, args);

  @override
  String toString() => 'SeedProblem($tableId, row=$row, col=$columnId, $message)';
}

final _intRe = RegExp(r'^[+-]?\d+$');
final _numRe = RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$');
final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _dateTimeRe = RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?$');
final _uuidRe = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final _hexRe = RegExp(r'^(0x)?([0-9a-fA-F]{2})+$');

/// ค่าที่แปลงแล้วของหนึ่งช่อง: null = NULL
class _Parsed {
  const _Parsed(this.ok, this.value, [this.problem]);
  final bool ok;
  final String? value; // ข้อความมาตรฐาน (ยังไม่ quote) หรือ null = NULL
  final String? problem;
}

String? _raw(Map<String, String?> row, ColumnModel c) => row[c.id];

/// ค่ามาตรฐานของช่อง (ใช้เทียบข้อมูลระหว่างเวอร์ชัน): null = NULL หรือค่าที่อ่านไม่ได้
String? seedNormalized(ColumnModel c, String? raw) => _parse(c, raw).value;

/// ตรวจและทำให้เป็นข้อความมาตรฐานของค่าในช่อง ([raw] ว่าง = NULL)
_Parsed _parse(ColumnModel c, String? raw) {
  if (raw == null || raw.trim().isEmpty) return const _Parsed(true, null);
  final s = raw.trim();
  switch (c.type) {
    case DataType.integer:
    case DataType.bigint:
    case DataType.smallint:
      return _intRe.hasMatch(s) ? _Parsed(true, s.startsWith('+') ? s.substring(1) : s) : const _Parsed(false, null, 'ต้องเป็นจำนวนเต็ม');
    case DataType.decimal:
    case DataType.float:
      return _numRe.hasMatch(s) ? _Parsed(true, s) : const _Parsed(false, null, 'ต้องเป็นตัวเลข');
    case DataType.boolean:
      final l = s.toLowerCase();
      if (const {'true', 't', '1', 'yes', 'y'}.contains(l)) return const _Parsed(true, 'true');
      if (const {'false', 'f', '0', 'no', 'n'}.contains(l)) return const _Parsed(true, 'false');
      return const _Parsed(false, null, 'ต้องเป็น true / false / 0 / 1');
    case DataType.date:
      return _dateRe.hasMatch(s) ? _Parsed(true, s) : const _Parsed(false, null, 'วันที่ต้องเป็น YYYY-MM-DD');
    case DataType.datetime:
    case DataType.timestamp:
      return _dateTimeRe.hasMatch(s) ? _Parsed(true, s) : const _Parsed(false, null, 'วันเวลาต้องเป็น YYYY-MM-DD HH:MM[:SS]');
    case DataType.uuid:
      return _uuidRe.hasMatch(s) ? _Parsed(true, s.toLowerCase()) : const _Parsed(false, null, 'รูปแบบ UUID ไม่ถูกต้อง');
    case DataType.json:
      try {
        jsonDecode(raw);
        return _Parsed(true, raw.trim());
      } catch (_) {
        return const _Parsed(false, null, 'JSON ไม่ถูกต้อง');
      }
    case DataType.blob:
      return _hexRe.hasMatch(s) ? _Parsed(true, s.startsWith('0x') ? s.substring(2) : s) : const _Parsed(false, null, 'BLOB ต้องเป็นเลขฐานสิบหก (เช่น 0A1B)');
    case DataType.varchar:
    case DataType.text:
      // ใช้ข้อความตามที่พิมพ์ (ไม่ trim) ยกเว้น "" = สตริงว่าง
      final text = raw == '""' ? '' : raw;
      final max = c.type == DataType.varchar ? (c.length ?? 255) : null;
      if (max != null && text.length > max) return _Parsed(false, null, 'ยาวเกิน {0} ตัวอักษร', );
      return _Parsed(true, text);
  }
}

/// ตรวจข้อมูลตั้งต้นทั้งโปรเจกต์ — คืนปัญหาทั้งหมด (ว่าง = ใช้ได้)
/// ตรวจ: ชนิดของค่า, NOT NULL ที่ไม่มีค่า/DEFAULT, PK/UNIQUE ซ้ำ, FK ที่ชี้ไปค่าที่ไม่มีในตารางแม่ (เมื่อแม่มีข้อมูลตั้งต้น)
List<SeedProblem> validateSeed(Project p) {
  final out = <SeedProblem>[];
  // ค่าที่มีในแต่ละคอลัมน์ของตารางที่มีข้อมูลตั้งต้น (ใช้ตรวจ FK)
  final present = <String, Set<String>>{};
  for (final t in p.tables) {
    if (t.seedRows.isEmpty) continue;
    for (final c in t.columns) {
      present['${t.id}.${c.id}'] = {
        for (final r in t.seedRows)
          if (_parse(c, _raw(r, c)).value != null) _parse(c, _raw(r, c)).value!,
      };
    }
  }

  for (final t in p.tables) {
    if (t.seedRows.isEmpty) continue;
    final known = t.columns.map((c) => c.id).toSet();
    final pk = t.columns.where((c) => c.isPrimaryKey).toList();
    final seenPk = <String>{};
    final seenUnique = {for (final c in t.columns) if (c.unique && !c.isPrimaryKey) c.id: <String>{}};
    final fks = [for (final r in p.relations) if (r.fromTableId == t.id) r];

    for (var i = 0; i < t.seedRows.length; i++) {
      final row = t.seedRows[i];
      for (final k in row.keys) {
        if (!known.contains(k)) out.add(SeedProblem(t.id, i, k, 'แถวมีคอลัมน์ที่ไม่มีอยู่แล้ว'));
      }
      for (final c in t.columns) {
        final hasKey = row.containsKey(c.id);
        final parsed = _parse(c, _raw(row, c));
        if (!parsed.ok) {
          final maxLen = c.type == DataType.varchar ? (c.length ?? 255) : null;
          out.add(SeedProblem(t.id, i, c.id, parsed.problem!, maxLen != null ? [maxLen] : const []));
          continue;
        }
        final isNull = parsed.value == null;
        final auto = c.autoIncrement;
        // NOT NULL ที่ไม่ได้ให้ค่า: ใช้ได้ถ้ามี DEFAULT หรือเป็น AUTO INCREMENT (ฐานข้อมูลใส่ให้)
        final mustHave = (c.notNull || c.isPrimaryKey) && !auto && (c.defaultValue == null || c.defaultValue!.isEmpty);
        if (isNull && mustHave) {
          out.add(SeedProblem(t.id, i, c.id, 'คอลัมน์ NOT NULL ต้องมีค่า'));
        } else if (isNull && hasKey && (c.notNull || c.isPrimaryKey) && !auto) {
          // กรอกเป็น NULL ตรง ๆ ในคอลัมน์ NOT NULL (ไม่ปล่อยให้ใช้ DEFAULT)
          out.add(SeedProblem(t.id, i, c.id, 'คอลัมน์ NOT NULL ต้องมีค่า'));
        }
      }
      if (pk.isNotEmpty) {
        final key = pk.map((c) => _parse(c, _raw(row, c)).value ?? '\u0000').join('\u0001');
        if (pk.every((c) => _parse(c, _raw(row, c)).value != null) && !seenPk.add(key)) {
          out.add(SeedProblem(t.id, i, pk.first.id, 'Primary Key ซ้ำกับแถวก่อนหน้า'));
        }
      }
      for (final c in t.columns) {
        final set = seenUnique[c.id];
        final v = _parse(c, _raw(row, c)).value;
        if (set != null && v != null && !set.add(v)) {
          out.add(SeedProblem(t.id, i, c.id, 'ค่า UNIQUE ซ้ำกับแถวก่อนหน้า'));
        }
      }
      for (final r in fks) {
        final child = t.columnById(r.fromColumnId);
        final parentSet = present['${r.toTableId}.${r.toColumnId}'];
        if (child == null || parentSet == null) continue; // แม่ไม่มีข้อมูลตั้งต้น = ตรวจไม่ได้
        final v = _parse(child, _raw(row, child)).value;
        if (v != null && !parentSet.contains(v)) {
          out.add(SeedProblem(t.id, i, child.id, 'FK ชี้ไปค่า {0} ที่ไม่มีในตารางแม่', [v]));
        }
      }
    }
  }
  return out;
}

/// ตารางที่มีข้อมูลตั้งต้นอย่างน้อยหนึ่งแถว
List<TableModel> tablesWithSeed(Project p) => [for (final t in p.tables) if (t.seedRows.isNotEmpty) t];

/// เรียงตารางให้แม่มาก่อนลูก (FK วนเป็นวงคงลำดับเดิมของที่เหลือ)
List<TableModel> seedOrder(Project p) {
  final remaining = [...p.tables];
  final out = <TableModel>[];
  final done = <String>{};
  while (remaining.isNotEmpty) {
    final ready = remaining.where((t) {
      return p.relations
          .where((r) => r.fromTableId == t.id && r.toTableId != t.id && p.tableById(r.toTableId) != null)
          .every((r) => done.contains(r.toTableId));
    }).toList();
    final pick = ready.isNotEmpty ? ready : [remaining.first];
    for (final t in pick) {
      out.add(t);
      done.add(t.id);
      remaining.remove(t);
    }
  }
  return out;
}

/// สร้าง `INSERT` ของข้อมูลตั้งต้นทั้งโปรเจกต์ตาม dialect (ตารางแม่ก่อนลูก)
/// ถ้ามีปัญหาในข้อมูล ([validateSeed] ไม่ว่าง) จะโยน [SeedException] — ไม่สร้าง SQL จากข้อมูลที่ไม่ถูกต้อง
String generateSeedSql(Project p) {
  final problems = validateSeed(p);
  if (problems.isNotEmpty) throw SeedException(problems);
  final blocks = <String>[
    tr('-- ข้อมูลตั้งต้น (seed data) — {0}', [p.dialect.label]),
  ];
  for (final t in seedOrder(p)) {
    if (t.seedRows.isEmpty) continue;
    blocks.add(seedInsertSql(p, t, t.seedRows));
  }
  return blocks.length == 1 ? '' : '${blocks.join('\n\n')}\n';
}

class SeedException implements Exception {
  SeedException(this.problems);
  final List<SeedProblem> problems;
  @override
  String toString() => 'SeedException(${problems.length} problems)';
}

/// `INSERT` ของแถว [rows] ในตาราง [t] (ค่าต้องผ่าน [validateSeed] แล้ว)
/// [idempotent] = รันซ้ำได้ ไม่ error และไม่แตะแถวเดิมที่ซ้ำ (ใช้กับ migration)
///   MySQL: INSERT IGNORE · PostgreSQL: ON CONFLICT DO NOTHING · SQLite: INSERT OR IGNORE
///   SQL Server: IF NOT EXISTS (… PK …) ต่อแถว — ตารางที่ไม่มี PK จะข้ามพร้อมคอมเมนต์เตือน
String seedInsertSql(Project p, TableModel t, List<Map<String, String?>> rows, {bool idempotent = false}) {
  final gen = DdlGenerator.forDialect(p.dialect);
  final d = p.dialect;
  String q(String s) => gen.quote(s);

  // คอลัมน์ที่ใส่ค่า = คอลัมน์ที่มี key ในแถวใดแถวหนึ่ง (คงลำดับตามตาราง)
  final used = [for (final c in t.columns) if (rows.any((r) => r.containsKey(c.id))) c];
  if (used.isEmpty) {
    return '-- ${DdlGenerator.flat(t.name)}: ${tr('ไม่มีคอลัมน์ที่ใส่ค่า')}';
  }

  String literal(ColumnModel c, String? raw) {
    final v = _parse(c, raw).value;
    if (v == null) return 'NULL';
    switch (c.type) {
      case DataType.integer:
      case DataType.bigint:
      case DataType.smallint:
      case DataType.decimal:
      case DataType.float:
        return v;
      case DataType.boolean:
        return switch (d) {
          Dialect.mssql || Dialect.sqlite => v == 'true' ? '1' : '0',
          _ => gen.booleanLiteral(v == 'true'),
        };
      case DataType.blob:
        return switch (d) {
          Dialect.mysql || Dialect.sqlite => "X'$v'",
          Dialect.postgres => "'\\x$v'",
          Dialect.mssql => '0x$v',
        };
      case DataType.date:
      case DataType.datetime:
      case DataType.timestamp:
      case DataType.uuid:
        return gen.stringLiteral(v);
      case DataType.json:
      case DataType.varchar:
      case DataType.text:
        // SQL Server: ข้อความ Unicode ต้องนำหน้า N (ไม่งั้นภาษาไทยกลายเป็น ?)
        return d == Dialect.mssql ? "N'${v.replaceAll("'", "''")}'" : gen.stringLiteral(v);
    }
  }

  final table = q(t.name);
  final cols = used.map((c) => q(c.name)).join(', ');
  List<String> tuples = [
    for (final r in rows) '(${used.map((c) => r.containsKey(c.id) ? literal(c, _raw(r, c)) : 'DEFAULT').join(', ')})',
  ];
  // มีแถวที่ไม่ได้ให้ค่าบางคอลัมน์ (ใช้ DEFAULT ของฐานข้อมูล)
  final mixed = rows.any((r) => used.any((c) => !r.containsKey(c.id)));

  final pk = t.columns.where((c) => c.isPrimaryKey).toList();

  // โหมดรันซ้ำได้: ต้องระบุตัวตนของแถวด้วย PK เสมอ ไม่งั้นรันซ้ำแล้วเกิดแถวซ้ำ จึงข้ามแถว/ตารางที่ทำไม่ได้พร้อมคอมเมนต์เตือน
  if (idempotent) {
    if (pk.isEmpty) {
      return tr('-- ข้ามข้อมูลตั้งต้นของ {0}: ไม่มี Primary Key จึงรันซ้ำอย่างปลอดภัยไม่ได้', [DdlGenerator.flat(t.name)]);
    }
    bool hasPk(Map<String, String?> r) => pk.every((c) => r.containsKey(c.id) && _parse(c, _raw(r, c)).value != null);
    final skipped = rows.where((r) => !hasPk(r)).length;
    if (skipped > 0) {
      final kept = [for (final r in rows) if (hasPk(r)) r];
      final warn = tr('-- ข้าม {0} แถวของ {1} ที่ไม่ระบุค่า Primary Key (รันซ้ำอย่างปลอดภัยไม่ได้)', [skipped, DdlGenerator.flat(t.name)]);
      if (kept.isEmpty) return warn;
      return '$warn\n${seedInsertSql(p, t, kept, idempotent: true)}';
    }
  }

  final identityCols = [for (final c in used) if (c.autoIncrement) c];
  final explicitIdentity = identityCols.any((c) => rows.any((r) => r.containsKey(c.id) && (_parse(c, _raw(r, c)).value != null)));

  final buf = StringBuffer();
  void rowInserts(String keyword, {String suffix = ''}) {
    if (d == Dialect.sqlite && mixed) {
      // SQLite ไม่รับ DEFAULT ในรายการค่า: ทำคำสั่งต่อแถวให้คอลัมน์ตรงกับที่ให้ค่าจริง
      for (final r in rows) {
        final cs = [for (final c in used) if (r.containsKey(c.id)) c];
        if (cs.isEmpty) continue;
        buf.writeln('$keyword $table (${cs.map((c) => q(c.name)).join(', ')}) VALUES (${cs.map((c) => literal(c, _raw(r, c))).join(', ')})$suffix;');
      }
      return;
    }
    // แบ่งเป็นก้อนละ 500 แถว (SQL Server รับ VALUES ได้ไม่เกิน 1000 แถวต่อคำสั่ง)
    for (var i = 0; i < tuples.length; i += 500) {
      final chunk = tuples.sublist(i, i + 500 > tuples.length ? tuples.length : i + 500);
      buf.writeln('$keyword $table ($cols) VALUES\n  ${chunk.join(',\n  ')}$suffix;');
    }
  }

  if (d == Dialect.mssql && explicitIdentity) buf.writeln('SET IDENTITY_INSERT $table ON;');

  if (!idempotent) {
    rowInserts('INSERT INTO');
  } else {
    switch (d) {
      case Dialect.mysql:
        rowInserts('INSERT IGNORE INTO');
      case Dialect.sqlite:
        rowInserts('INSERT OR IGNORE INTO');
      case Dialect.postgres:
        rowInserts('INSERT INTO', suffix: '\nON CONFLICT DO NOTHING');
      case Dialect.mssql:
        // ต่อแถว: ใส่เมื่อยังไม่มีแถวที่ PK ตรงกัน (ทุกแถวมี PK ครบแล้วจากการกรองข้างบน)
        for (final r in rows) {
          final cs = [for (final c in used) if (r.containsKey(c.id)) c];
          final values = cs.map((c) => literal(c, _raw(r, c))).join(', ');
          final insert = 'INSERT INTO $table (${cs.map((c) => q(c.name)).join(', ')}) VALUES ($values);';
          final where = pk.map((c) => '${q(c.name)} = ${literal(c, _raw(r, c))}').join(' AND ');
          buf.writeln('IF NOT EXISTS (SELECT 1 FROM $table WHERE $where) $insert');
        }
    }
  }

  if (d == Dialect.mssql && explicitIdentity) buf.writeln('SET IDENTITY_INSERT $table OFF;');
  if (d == Dialect.postgres && explicitIdentity) {
    // ค่าที่ใส่เองไม่เลื่อน sequence: ตั้งต่อจากค่าสูงสุดกัน AUTO INCREMENT ครั้งถัดไปชนค่าที่มีอยู่
    for (final c in identityCols) {
      final tn = '"${t.name.replaceAll('"', '""')}"';
      buf.writeln("SELECT setval(pg_get_serial_sequence('${tn.replaceAll("'", "''")}', '${c.name.replaceAll("'", "''")}'), "
          'COALESCE((SELECT MAX(${q(c.name)}) FROM $table), 1));');
    }
  }
  return buf.toString().trimRight();
}
