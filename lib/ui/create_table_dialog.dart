import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/column_model.dart';
import '../core/models/enums.dart';
import '../core/models/index_model.dart';
import '../core/models/table_model.dart';
import 'theme.dart';

/// ชนิดดัชนีของคอลัมน์ในฟอร์ม (เหมือนช่อง Index ของ phpMyAdmin)
enum ColumnIndex { none, primary, unique, plain }

String dataTypeName(DataType t) => switch (t) {
      DataType.integer => 'INT',
      _ => t.name.toUpperCase(),
    };

/// สถานะของคอลัมน์หนึ่งแถวในฟอร์ม
class ColumnDraft {
  ColumnDraft({
    String name = '',
    this.type = DataType.integer,
    String length = '',
    String defaultValue = '',
    this.allowNull = true,
    this.index = ColumnIndex.none,
    this.autoIncrement = false,
    String comment = '',
    this.id,
    this.plainIndexId,
  })  : originalIndex = index,
        name = TextEditingController(text: name),
        length = TextEditingController(text: length),
        defaultValue = TextEditingController(text: defaultValue),
        comment = TextEditingController(text: comment);

  final TextEditingController name, length, defaultValue, comment;

  /// id ของคอลัมน์เดิม (โหมดแก้ไข) — null = คอลัมน์ใหม่
  final String? id;

  /// id ของดัชนีธรรมดาคอลัมน์เดียวที่มีอยู่เดิม (โหมดแก้ไข)
  final String? plainIndexId;

  /// ชนิดดัชนีตอนเปิดฟอร์ม
  final ColumnIndex originalIndex;
  DataType type;
  bool allowNull;
  ColumnIndex index;
  bool autoIncrement;

  /// มีดัชนีธรรมดาอยู่เดิมแต่ฟอร์มแสดงเป็น PRIMARY/UNIQUE — ต้องคงดัชนีไว้ ไม่ให้หายเงียบ ๆ
  bool keepPlain = false;

  /// ร่างจากคอลัมน์เดิมของ [t] (โหมดแก้ไข)
  factory ColumnDraft.fromColumn(TableModel t, ColumnModel c) {
    IndexModel? plain;
    for (final i in t.indexes) {
      if (!i.unique && i.columnIds.length == 1 && i.columnIds.first == c.id) plain = i;
    }
    final idx = c.isPrimaryKey
        ? ColumnIndex.primary
        : c.unique
            ? ColumnIndex.unique
            : plain != null
                ? ColumnIndex.plain
                : ColumnIndex.none;
    final len = c.type == DataType.decimal && c.length != null
        ? '${c.length},${c.scale ?? 0}'
        : (c.length?.toString() ?? '');
    return ColumnDraft(
      name: c.name,
      type: c.type,
      length: len,
      defaultValue: c.defaultValue ?? '',
      allowNull: !c.notNull && !c.isPrimaryKey,
      index: idx,
      autoIncrement: c.autoIncrement,
      comment: c.comment,
      id: c.id,
      plainIndexId: plain?.id,
    )..keepPlain = plain != null && idx != ColumnIndex.plain;
  }

  bool get usesLength => type == DataType.varchar || type == DataType.decimal;
  bool get isIntegerType => type == DataType.integer || type == DataType.bigint || type == DataType.smallint;

  void dispose() {
    name.dispose();
    length.dispose();
    defaultValue.dispose();
    comment.dispose();
  }
}

/// ตรวจความยาว/precision ที่กรอก — คืนข้อความไทยต้นฉบับของปัญหา หรือ null ถ้าใช้ได้
/// varchar: จำนวนเต็ม >= 1 (ว่าง = 255) ; decimal: `p` หรือ `p,s` โดย s <= p (ว่าง = 10,2)
String? validateLengthText(DataType type, String text) {
  final t = text.trim();
  if (type == DataType.varchar) {
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return n == null || n < 1 ? 'ความยาวต้องเป็นจำนวนเต็มตั้งแต่ 1' : null;
  }
  if (type == DataType.decimal) {
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d+)(?:\s*,\s*(\d+))?$').firstMatch(t);
    if (m == null) return 'รูปแบบเป็น 10,2 (precision,scale)';
    final p = int.parse(m.group(1)!);
    final s = m.group(2) == null ? 0 : int.parse(m.group(2)!);
    return p < 1 || s > p ? 'scale ต้องไม่เกิน precision' : null;
  }
  return null;
}

/// แปลงฟอร์มเป็นตาราง (id ของคอลัมน์/ดัชนีสร้างจาก [newId])
/// PRIMARY หลายแถว = PK ผสม; INDEX = ดัชนีธรรมดาแยกต่อคอลัมน์
TableModel buildTableFromDrafts({
  required String Function(String prefix) newId,
  required String name,
  required String comment,
  required List<ColumnDraft> drafts,
  TableModel? existing,
}) {
  final cols = <ColumnModel>[];
  final indexes = <IndexModel>[];
  final tableName = name.trim();
  for (final d in drafts) {
    final isPk = d.index == ColumnIndex.primary;
    int? len;
    int? scale;
    final lt = d.length.text.trim();
    if (d.type == DataType.varchar && lt.isNotEmpty) len = int.parse(lt);
    if (d.type == DataType.decimal && lt.isNotEmpty) {
      final parts = lt.split(',').map((e) => int.parse(e.trim())).toList();
      len = parts[0];
      scale = parts.length > 1 ? parts[1] : 0;
    }
    final dv = d.defaultValue.text.trim();
    final col = ColumnModel(
      id: d.id ?? newId('c'),
      name: d.name.text.trim(),
      type: d.type,
      length: len,
      scale: scale,
      isPrimaryKey: isPk,
      notNull: isPk || !d.allowNull,
      unique: d.index == ColumnIndex.unique,
      autoIncrement: d.autoIncrement,
      defaultValue: dv.isEmpty ? null : dv,
      comment: d.comment.text.trim(),
    );
    cols.add(col);
    if (d.index == ColumnIndex.plain || (d.keepPlain && d.plainIndexId != null)) {
      indexes.add(IndexModel(id: d.plainIndexId ?? newId('i'), name: 'idx_${tableName}_${col.name}', columnIds: [col.id]));
    }
  }
  if (existing != null) {
    // ดัชนีหลายคอลัมน์ / UNIQUE index เดิมคงไว้ (ตัดคอลัมน์ที่ถูกลบออก) — ฟอร์มนี้แก้ได้เฉพาะดัชนีคอลัมน์เดียว
    final keptIds = {for (final c in cols) c.id};
    final plainIds = {for (final d in drafts) if (d.plainIndexId != null) d.plainIndexId};
    for (final i in existing.indexes) {
      if (plainIds.contains(i.id)) continue;
      final ids = [for (final id in i.columnIds) if (keptIds.contains(id)) id];
      if (ids.isEmpty) continue;
      indexes.add(IndexModel(id: i.id, name: i.name, columnIds: ids, unique: i.unique));
    }
  }
  return TableModel(id: existing?.id ?? newId('t'), name: tableName, comment: comment.trim(), columns: cols, indexes: indexes);
}

/// สร้างตารางแบบฟอร์ม เหมือนหน้า "Create table" ของ phpMyAdmin:
/// ตั้งชื่อ กำหนดจำนวนคอลัมน์ แล้วกรอกชื่อ/ชนิด/ความยาว/ค่าเริ่มต้น/Null/Index/A_I/หมายเหตุเป็นตารางเดียว
/// คืนตารางที่สร้างเสร็จ (ยังไม่ได้เพิ่มเข้าโปรเจกต์) หรือ null ถ้ายกเลิก
Future<TableModel?> showCreateTableDialog(BuildContext context, {required String Function(String) newId}) =>
    showDialog<TableModel>(context: context, builder: (_) => CreateTableDialog(newId: newId));

/// แก้โครงสร้างตารางที่มีอยู่ด้วยฟอร์มเดียวกัน คืนตารางใหม่ (id ตาราง/คอลัมน์เดิมคงไว้) หรือ null ถ้ายกเลิก
/// [relationCount] คืนจำนวนเส้น FK ที่ผูกกับคอลัมน์ ใช้เตือนก่อนลบคอลัมน์
Future<TableModel?> showEditTableDialog(
  BuildContext context, {
  required TableModel table,
  required String Function(String) newId,
  required int Function(String columnId) relationCount,
  List<String> otherTableNames = const [],
}) =>
    showDialog<TableModel>(
      context: context,
      builder: (_) => CreateTableDialog(
        newId: newId,
        editing: table,
        relationCount: relationCount,
        otherTableNames: otherTableNames,
      ),
    );

class CreateTableDialog extends StatefulWidget {
  const CreateTableDialog({
    super.key,
    required this.newId,
    this.initialColumns = 4,
    this.editing,
    this.relationCount,
    this.otherTableNames = const [],
  });
  final String Function(String prefix) newId;
  final int initialColumns;

  /// ตารางที่กำลังแก้ (null = สร้างใหม่)
  final TableModel? editing;
  final int Function(String columnId)? relationCount;
  final List<String> otherTableNames;

  @override
  State<CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<CreateTableDialog> {
  static const _maxColumns = 100;
  final _name = TextEditingController();
  final _comment = TextEditingController();
  final _count = TextEditingController();
  final _drafts = <ColumnDraft>[];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _name.text = e.name;
      _comment.text = e.comment;
      for (final c in e.columns) {
        _drafts.add(ColumnDraft.fromColumn(e, c));
      }
      if (_drafts.isEmpty) _drafts.add(ColumnDraft());
      _count.text = '${_drafts.length}';
      return;
    }
    _drafts.add(ColumnDraft(
      name: 'id',
      allowNull: false,
      index: ColumnIndex.primary,
      autoIncrement: true,
    ));
    _resize(widget.initialColumns);
  }

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    _count.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  /// ปรับจำนวนแถว: เพิ่มต่อท้าย / ตัดจากท้าย (ข้อมูลแถวที่เหลือคงเดิม)
  void _resize(int n) {
    n = n.clamp(1, _maxColumns);
    while (_drafts.length < n) {
      _drafts.add(ColumnDraft());
    }
    while (_drafts.length > n) {
      _drafts.removeLast().dispose();
    }
    _count.text = '$n';
  }

  void _applyCount() {
    final n = int.tryParse(_count.text.trim());
    if (n == null) return;
    setState(() => _resize(n));
  }

  void _remove(int i) {
    if (_drafts.length <= 1) return;
    setState(() {
      _drafts.removeAt(i).dispose();
      _count.text = '${_drafts.length}';
    });
  }

  // ---------- ตรวจความถูกต้อง ----------

  bool get _editing => widget.editing != null;

  String? get _nameError {
    final n = _name.text.trim();
    if (n.isEmpty) return tr('ต้องตั้งชื่อตาราง');
    final dup = widget.otherTableNames.any((o) => o.toLowerCase() == n.toLowerCase());
    return dup ? tr('ชื่อซ้ำกับตารางอื่น') : null;
  }

  String? _colNameError(int i) {
    final n = _drafts[i].name.text.trim();
    if (n.isEmpty) return tr('ต้องตั้งชื่อ');
    final dup = _drafts.indexed.any((e) => e.$1 != i && e.$2.name.text.trim().toLowerCase() == n.toLowerCase());
    return dup ? tr('ชื่อซ้ำ') : null;
  }

  String? _lengthError(int i) {
    final e = validateLengthText(_drafts[i].type, _drafts[i].length.text);
    return e == null ? null : tr(e);
  }

  String? _aiError(int i) {
    final d = _drafts[i];
    if (!d.autoIncrement) return null;
    return d.isIntegerType ? null : tr('A_I ใช้ได้กับชนิดจำนวนเต็มเท่านั้น');
  }

  bool get _valid =>
      _nameError == null &&
      _drafts.isNotEmpty &&
      [for (var i = 0; i < _drafts.length; i++) i].every(
        (i) => _colNameError(i) == null && _lengthError(i) == null && _aiError(i) == null,
      );

  Future<void> _save() async {
    if (!_valid) return;
    final e = widget.editing;
    if (e != null) {
      // คอลัมน์เดิมที่หายไปจากฟอร์ม = ถูกลบ ; เตือนถ้ามี FK ผูกอยู่
      final kept = {for (final d in _drafts) d.id};
      var rels = 0;
      final dropped = <String>[];
      for (final c in e.columns) {
        if (kept.contains(c.id)) continue;
        dropped.add(c.name);
        rels += widget.relationCount?.call(c.id) ?? 0;
      }
      if (dropped.isNotEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('ลบ {0} คอลัมน์?', [dropped.length])),
            content: Text(rels > 0
                ? tr('คอลัมน์ {0} จะถูกลบ พร้อมความสัมพันธ์ FK {1} เส้นที่ผูกอยู่ (ย้อนกลับได้ด้วย Undo)', [dropped.join(', '), rels])
                : tr('คอลัมน์ {0} จะถูกลบ (ย้อนกลับได้ด้วย Undo)', [dropped.join(', ')])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบและบันทึก'))),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
    }
    Navigator.pop(
      context,
      buildTableFromDrafts(newId: widget.newId, name: _name.text, comment: _comment.text, drafts: _drafts, existing: e),
    );
  }

  // ---------- UI ----------

  static const _wIdx = 34.0, _wName = 150.0, _wType = 118.0, _wLen = 84.0, _wDef = 112.0;
  static const _wNull = 52.0, _wIndex = 106.0, _wAi = 48.0, _wComment = 170.0, _wDel = 36.0;
  static const _rowWidth = _wIdx + _wName + _wType + _wLen + _wDef + _wNull + _wIndex + _wAi + _wComment + _wDel + 8 * 9;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_editing ? tr('แก้ไขโครงสร้างตาราง') : tr('สร้างตาราง'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
                _editing
                    ? tr('แก้ชื่อ ชนิด ความยาว ค่าเริ่มต้น Null Index A_I ของทุกคอลัมน์ในหน้าเดียว แล้วกดบันทึก')
                    : tr('กรอกชื่อตารางและรายละเอียดของทุกคอลัมน์ในครั้งเดียว แล้วกดสร้าง'),
                style: TextStyle(fontSize: 12.5, color: C.muted)),
            const SizedBox(height: 14),
            Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.start, children: [
              SizedBox(width: 260, child: _field(_name, tr('ชื่อตาราง'), 'ct-table-name', error: _nameError)),
              SizedBox(width: 300, child: _field(_comment, tr('หมายเหตุตาราง (ไม่บังคับ)'), 'ct-table-comment')),
              SizedBox(
                width: 210,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ct-count'),
                      controller: _count,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) => _applyCount(),
                      decoration: InputDecoration(
                        labelText: tr('จำนวนคอลัมน์'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    key: const ValueKey('ct-apply-count'),
                    onPressed: _applyCount,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: Text(tr('ตกลง')),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Flexible(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _rowWidth + 24,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _headerRow(),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _drafts.length,
                          itemBuilder: (_, i) => _columnRow(i),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              TextButton.icon(
                key: const ValueKey('ct-add'),
                onPressed: _drafts.length >= _maxColumns ? null : () => setState(() => _resize(_drafts.length + 1)),
                icon: const Icon(Icons.add, size: 16),
                label: Text(tr('เพิ่มคอลัมน์')),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('ct-save'),
                onPressed: _valid ? () => _save() : null,
                child: Text(_editing ? tr('บันทึก') : tr('สร้าง')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String key, {String? error}) => TextField(
        key: ValueKey(key),
        controller: c,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _headerRow() {
    Widget h(String t, double w) => SizedBox(
          width: w,
          child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.muted)),
        );
    return Container(
      color: C.field,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(children: [
        h('#', _wIdx),
        const SizedBox(width: 8),
        h(tr('ชื่อ'), _wName),
        const SizedBox(width: 8),
        h(tr('ชนิด'), _wType),
        const SizedBox(width: 8),
        h(tr('ความยาว'), _wLen),
        const SizedBox(width: 8),
        h(tr('ค่าเริ่มต้น'), _wDef),
        const SizedBox(width: 8),
        h('Null', _wNull),
        const SizedBox(width: 8),
        h('Index', _wIndex),
        const SizedBox(width: 8),
        h('A_I', _wAi),
        const SizedBox(width: 8),
        h(tr('หมายเหตุ'), _wComment),
        const SizedBox(width: 8),
        const SizedBox(width: _wDel),
      ]),
    );
  }

  InputDecoration _dec({String? error, String? hint}) => InputDecoration(
        isDense: true,
        hintText: hint,
        errorText: error,
        errorStyle: const TextStyle(fontSize: 10.5, height: 1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: const OutlineInputBorder(),
      );

  Widget _columnRow(int i) {
    final d = _drafts[i];
    const gap = SizedBox(width: 8);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: _wIdx,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('${i + 1}', style: TextStyle(fontSize: 12.5, color: C.muted)),
          ),
        ),
        gap,
        SizedBox(
          width: _wName,
          child: TextField(
            key: ValueKey('ct-name-$i'),
            controller: d.name,
            onChanged: (_) => setState(() {}),
            style: monoStyle.copyWith(fontSize: 12.5),
            decoration: _dec(error: _colNameError(i), hint: 'column_${i + 1}'),
          ),
        ),
        gap,
        SizedBox(
          width: _wType,
          child: DropdownButtonFormField<DataType>(
            key: ValueKey('ct-type-$i'),
            initialValue: d.type,
            isDense: true,
            isExpanded: true,
            decoration: _dec(),
            style: TextStyle(fontSize: 12.5, color: C.text, fontFamily: kThai),
            items: [
              for (final t in DataType.values) DropdownMenuItem(value: t, child: Text(dataTypeName(t))),
            ],
            onChanged: (t) => setState(() {
              if (t == null) return;
              d.type = t;
              if (!d.isIntegerType) d.autoIncrement = false;
              if (!d.usesLength) d.length.clear();
            }),
          ),
        ),
        gap,
        SizedBox(
          width: _wLen,
          child: TextField(
            key: ValueKey('ct-len-$i'),
            controller: d.length,
            enabled: d.usesLength,
            onChanged: (_) => setState(() {}),
            style: monoStyle.copyWith(fontSize: 12.5),
            decoration: _dec(
              error: _lengthError(i),
              hint: d.type == DataType.decimal ? '10,2' : (d.type == DataType.varchar ? '255' : '—'),
            ),
          ),
        ),
        gap,
        SizedBox(
          width: _wDef,
          child: TextField(
            key: ValueKey('ct-default-$i'),
            controller: d.defaultValue,
            style: monoStyle.copyWith(fontSize: 12.5),
            decoration: _dec(hint: tr('ไม่มี')),
          ),
        ),
        gap,
        SizedBox(
          width: _wNull,
          child: Checkbox(
            key: ValueKey('ct-null-$i'),
            value: d.allowNull && d.index != ColumnIndex.primary,
            // PRIMARY บังคับ NOT NULL
            onChanged: d.index == ColumnIndex.primary ? null : (v) => setState(() => d.allowNull = v ?? true),
          ),
        ),
        gap,
        SizedBox(
          width: _wIndex,
          child: DropdownButtonFormField<ColumnIndex>(
            key: ValueKey('ct-index-$i'),
            initialValue: d.index,
            isDense: true,
            isExpanded: true,
            decoration: _dec(),
            style: TextStyle(fontSize: 12.5, color: C.text, fontFamily: kThai),
            items: const [
              DropdownMenuItem(value: ColumnIndex.none, child: Text('—')),
              DropdownMenuItem(value: ColumnIndex.primary, child: Text('PRIMARY')),
              DropdownMenuItem(value: ColumnIndex.unique, child: Text('UNIQUE')),
              DropdownMenuItem(value: ColumnIndex.plain, child: Text('INDEX')),
            ],
            onChanged: (v) => setState(() {
              d.index = v ?? ColumnIndex.none;
              if (d.index == ColumnIndex.primary) d.allowNull = false;
            }),
          ),
        ),
        gap,
        SizedBox(
          width: _wAi,
          child: Column(children: [
            Checkbox(
              key: ValueKey('ct-ai-$i'),
              value: d.autoIncrement,
              onChanged: d.isIntegerType ? (v) => setState(() => d.autoIncrement = v ?? false) : null,
            ),
          ]),
        ),
        gap,
        SizedBox(
          width: _wComment,
          child: TextField(
            key: ValueKey('ct-comment-$i'),
            controller: d.comment,
            decoration: _dec(),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        gap,
        SizedBox(
          width: _wDel,
          child: IconButton(
            key: ValueKey('ct-remove-$i'),
            tooltip: tr('ลบคอลัมน์นี้'),
            iconSize: 17,
            padding: EdgeInsets.zero,
            onPressed: _drafts.length <= 1 ? null : () => _remove(i),
            icon: Icon(Icons.delete_outline, color: C.danger),
          ),
        ),
      ]),
    );
  }
}
