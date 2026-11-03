import 'package:flutter/material.dart';

import '../core/export/seed_csv.dart';
import '../core/export/seed_data.dart';
import '../core/l10n/l10n.dart';
import '../core/models/column_model.dart';
import '../core/models/project.dart';
import '../core/models/table_model.dart';
import 'theme.dart';

/// แก้ข้อมูลตั้งต้นของตารางเป็นตาราง (หนึ่งแถว = หนึ่งแถวข้อมูล) คืนชุดแถวใหม่ หรือ null ถ้ายกเลิก
Future<List<Map<String, String?>>?> showSeedDataDialog(BuildContext context, {required Project project, required TableModel table}) =>
    showDialog<List<Map<String, String?>>>(context: context, builder: (_) => SeedDataDialog(project: project, table: table));

/// ช่องหนึ่งช่อง: ข้อความที่พิมพ์ (ว่าง = ปล่อยให้ใช้ DEFAULT/AUTO INCREMENT หรือ NULL แล้วแต่คอลัมน์)
class _Row {
  _Row(this.cells);
  final Map<String, TextEditingController> cells;
  void dispose() {
    for (final c in cells.values) {
      c.dispose();
    }
  }
}

class SeedDataDialog extends StatefulWidget {
  const SeedDataDialog({super.key, required this.project, required this.table});
  final Project project;
  final TableModel table;

  @override
  State<SeedDataDialog> createState() => _SeedDataDialogState();
}

class _SeedDataDialogState extends State<SeedDataDialog> {
  final _rows = <_Row>[];
  List<SeedProblem> _problems = const [];
  String? _notice;

  TableModel get t => widget.table;

  /// คอลัมน์ที่ฐานข้อมูลใส่ค่าให้เองได้เมื่อไม่ระบุ
  bool _hasDefault(ColumnModel c) => c.autoIncrement || (c.defaultValue != null && c.defaultValue!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    for (final r in t.seedRows) {
      _rows.add(_fromModel(r));
    }
    _revalidate();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  _Row _fromModel(Map<String, String?> r) => _Row({
        for (final c in t.columns)
          c.id: TextEditingController(
            // ไม่มี key = ว่าง (ใช้ DEFAULT) ; key เป็น NULL ในคอลัมน์ที่มี DEFAULT = พิมพ์ NULL ให้เห็นชัด
            text: !r.containsKey(c.id) ? '' : (r[c.id] ?? (_hasDefault(c) ? 'NULL' : '')),
          ),
      });

  /// ข้อความในช่องแปลงเป็นข้อมูลของแถว: ว่าง -> (มี DEFAULT/AI ? ไม่ระบุ : NULL), `NULL` -> NULL
  Map<String, String?> _toModel(_Row r) {
    final out = <String, String?>{};
    for (final c in t.columns) {
      final text = r.cells[c.id]!.text;
      if (text.trim().isEmpty) {
        if (!_hasDefault(c)) out[c.id] = null;
      } else if (text.trim() == 'NULL') {
        out[c.id] = null;
      } else {
        out[c.id] = text;
      }
    }
    return out;
  }

  List<Map<String, String?>> get _model => [for (final r in _rows) _toModel(r)];

  void _revalidate() {
    final copy = TableModel.fromJson(t.toJson())..seedRows = _model;
    final p = Project(
      name: widget.project.name,
      dialect: widget.project.dialect,
      tables: [for (final x in widget.project.tables) x.id == t.id ? copy : x],
      relations: widget.project.relations,
    );
    _problems = validateSeed(p).where((x) => x.tableId == t.id).toList();
  }

  void _changed() => setState(_revalidate);

  SeedProblem? _problemAt(int row, String colId) {
    for (final p in _problems) {
      if (p.row == row && p.columnId == colId) return p;
    }
    return null;
  }

  Future<void> _pasteCsv() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _CsvDialog());
    if (text == null || text.trim().isEmpty) return;
    final res = csvToSeedRows(t, text);
    setState(() {
      for (final r in res.rows) {
        _rows.add(_fromModel(r));
      }
      _notice = res.rows.isEmpty
          ? tr('ไม่พบแถวข้อมูลใน CSV')
          : tr('เพิ่ม {0} แถวจาก CSV{1}', [
              res.rows.length,
              res.unknownColumns.isEmpty ? '' : tr(' (ข้ามคอลัมน์ที่ไม่มีในตาราง: {0})', [res.unknownColumns.join(', ')]),
            ]);
      _revalidate();
    });
  }

  @override
  Widget build(BuildContext context) {
    const colW = 150.0;
    final width = 56.0 + t.columns.length * (colW + 8) + 44;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ข้อมูลตั้งต้นของตาราง {0}', [t.name]), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              tr('แถวเหล่านี้จะถูกสร้างเป็น INSERT ตอน Export .sql (ถ้าเลือกรวม) ช่องว่าง = ใช้ค่า DEFAULT/AUTO INCREMENT ของคอลัมน์ (ถ้าไม่มี = NULL), พิมพ์ NULL เพื่อบังคับเป็น NULL, พิมพ์ "" เพื่อสตริงว่าง'),
              style: TextStyle(fontSize: 12.5, color: C.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _header(colW),
                      Flexible(
                        child: _rows.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(tr('ยังไม่มีแถว กด "เพิ่มแถว" หรือ "วาง CSV…"'), style: TextStyle(color: C.muted)),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _rows.length,
                                itemBuilder: (_, i) => _rowWidget(i, colW),
                              ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_notice!, style: TextStyle(fontSize: 12.5, color: C.primaryDark)),
              ),
            if (_problems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  tr('พบ {0} ปัญหา (ช่องสีแดง) — แก้ก่อนจึงจะ Export พร้อมข้อมูลตั้งต้นได้', [_problems.length]),
                  key: const ValueKey('seed-problems'),
                  style: TextStyle(fontSize: 12.5, color: C.danger),
                ),
              ),
            Row(children: [
              TextButton.icon(
                key: const ValueKey('seed-add-row'),
                onPressed: () => setState(() {
                  _rows.add(_fromModel(const {}));
                  _revalidate();
                }),
                icon: const Icon(Icons.add, size: 16),
                label: Text(tr('เพิ่มแถว')),
              ),
              TextButton.icon(
                key: const ValueKey('seed-paste-csv'),
                onPressed: _pasteCsv,
                icon: const Icon(Icons.content_paste_rounded, size: 16),
                label: Text(tr('วาง CSV…')),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('seed-save'),
                onPressed: () => Navigator.pop(context, _model),
                child: Text(tr('บันทึก')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _header(double colW) => Container(
        color: C.field,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(children: [
          const SizedBox(width: 40),
          for (final c in t.columns) ...[
            SizedBox(
              width: colW,
              child: Text(
                '${c.name}${c.isPrimaryKey ? ' 🔑' : ''}',
                overflow: TextOverflow.ellipsis,
                style: monoStyle.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: C.muted),
              ),
            ),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 36),
        ]),
      );

  Widget _rowWidget(int i, double colW) {
    final row = _rows[i];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 40, child: Text('${i + 1}', style: TextStyle(fontSize: 12.5, color: C.muted))),
        for (final c in t.columns) ...[
          SizedBox(
            width: colW,
            child: Builder(builder: (context) {
              final problem = _problemAt(i, c.id);
              final field = TextField(
                key: ValueKey('seed-$i-${c.id}'),
                controller: row.cells[c.id],
                onChanged: (_) => _changed(),
                style: monoStyle.copyWith(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _hasDefault(c) ? (c.autoIncrement ? 'AUTO' : 'DEFAULT') : null,
                  hintStyle: TextStyle(fontSize: 11.5, color: C.muted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: problem == null ? C.inputBorder : C.danger, width: problem == null ? 1 : 1.6),
                  ),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: problem == null ? C.primary : C.danger, width: 1.6)),
                ),
              );
              return problem == null ? field : Tooltip(message: problem.message, child: field);
            }),
          ),
          const SizedBox(width: 8),
        ],
        SizedBox(
          width: 36,
          child: IconButton(
            key: ValueKey('seed-remove-$i'),
            tooltip: tr('ลบแถวนี้'),
            iconSize: 17,
            padding: EdgeInsets.zero,
            onPressed: () => setState(() {
              _rows.removeAt(i).dispose();
              _revalidate();
            }),
            icon: Icon(Icons.delete_outline, color: C.danger),
          ),
        ),
      ]),
    );
  }
}

class _CsvDialog extends StatefulWidget {
  const _CsvDialog();

  @override
  State<_CsvDialog> createState() => _CsvDialogState();
}

class _CsvDialogState extends State<_CsvDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('วาง CSV')),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              tr('วางข้อความ CSV หรือ TSV (คัดลอกจาก Excel ได้) ถ้าบรรทัดแรกเป็นชื่อคอลัมน์ของตารางจะจับคู่ตามชื่อ ไม่งั้นจับคู่ตามลำดับคอลัมน์'),
              style: TextStyle(fontSize: 12.5, color: C.muted, height: 1.4),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('csv-text'),
              controller: _ctl,
              minLines: 8,
              maxLines: 14,
              style: monoStyle.copyWith(fontSize: 12.5),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
          FilledButton(key: const ValueKey('csv-ok'), onPressed: () => Navigator.pop(context, _ctl.text), child: Text(tr('เพิ่มแถว'))),
        ],
      );
}
