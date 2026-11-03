import '../models/table_model.dart';

/// แยกข้อความ CSV/TSV เป็นแถว (รองรับเครื่องหมายคำพูดคู่ ช่องที่มีตัวคั่น/ขึ้นบรรทัดใหม่ และ `""` แทน `"`)
/// ตัวคั่นเลือกเองจากบรรทัดแรกที่พบ: แท็บ > เซมิโคลอน > จุลภาค
List<List<String>> parseCsv(String text) {
  final src = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final firstLine = src.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final delim = firstLine.contains('\t')
      ? '\t'
      : firstLine.contains(';') && !firstLine.contains(',')
          ? ';'
          : ',';

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var wasQuoted = false;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
    wasQuoted = false;
  }

  void endRow() {
    endCell();
    // ข้ามบรรทัดว่างล้วน
    if (!(row.length == 1 && row.first.trim().isEmpty && !wasQuoted)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < src.length; i++) {
    final ch = src[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < src.length && src[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.isEmpty) {
      inQuotes = true;
      wasQuoted = true;
    } else if (ch == delim) {
      endCell();
    } else if (ch == '\n') {
      endRow();
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// ผลการแปลง CSV เป็นแถวข้อมูลตั้งต้นของตาราง
class CsvSeedResult {
  const CsvSeedResult(this.rows, {this.usedHeader = false, this.unknownColumns = const [], this.skippedRows = 0});

  /// แถวพร้อมใช้ (id คอลัมน์ -> ข้อความ)
  final List<Map<String, String?>> rows;

  /// บรรทัดแรกเป็นหัวคอลัมน์ที่จับคู่ได้
  final bool usedHeader;

  /// หัวคอลัมน์ใน CSV ที่ไม่มีในตาราง (ข้ามค่าของคอลัมน์เหล่านี้)
  final List<String> unknownColumns;

  /// แถวที่ว่างทั้งแถวหรือคอลัมน์เกินจำนวนจึงถูกข้าม
  final int skippedRows;
}

/// แปลง CSV เป็นแถวของ [table]: ถ้าบรรทัดแรกเป็นชื่อคอลัมน์ของตาราง (ไม่สนตัวพิมพ์) ใช้จับคู่ตามชื่อ
/// ไม่งั้นจับคู่ตามลำดับคอลัมน์ของตาราง ช่องว่างหรือ `NULL` = NULL
CsvSeedResult csvToSeedRows(TableModel table, String text) {
  final all = parseCsv(text);
  if (all.isEmpty) return const CsvSeedResult([]);
  final byName = {for (final c in table.columns) c.name.toLowerCase(): c};
  final first = all.first.map((h) => h.trim().toLowerCase()).toList();
  final header = first.isNotEmpty && first.every((h) => h.isNotEmpty) && first.any(byName.containsKey);

  final cols = header ? [for (final h in first) byName[h]] : [...table.columns.take(all.first.length)];
  final unknown = header ? [for (var i = 0; i < first.length; i++) if (byName[first[i]] == null) all.first[i].trim()] : <String>[];
  final data = header ? all.skip(1) : all;

  final out = <Map<String, String?>>[];
  var skipped = 0;
  for (final r in data) {
    if (r.every((v) => v.trim().isEmpty)) {
      skipped++;
      continue;
    }
    final row = <String, String?>{};
    for (var i = 0; i < cols.length && i < r.length; i++) {
      final c = cols[i];
      if (c == null) continue;
      final v = r[i];
      row[c.id] = v.trim().isEmpty || v.trim() == 'NULL' ? null : v;
    }
    out.add(row);
  }
  return CsvSeedResult(out, usedHeader: header, unknownColumns: unknown, skippedRows: skipped);
}
