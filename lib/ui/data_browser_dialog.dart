import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/db/data_access.dart';
import '../core/db/db_session.dart';
import '../core/l10n/l10n.dart';
import 'theme.dart';

/// เปิดเซสชันข้อมูล ([writable] = เปิดแบบเขียนได้) — ใช้สลับโหมดดู/แก้ โดยปิดอันเก่าแล้วเปิดใหม่
typedef DataSessionOpener = Future<DataSession> Function(bool writable);

Future<void> showDataBrowser(BuildContext context, {required String title, required DataSessionOpener opener}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DataBrowserDialog(title: title, opener: opener),
    );

String _rowId(Map<String, String?> key) => jsonEncode([for (final k in key.keys.toList()..sort()) [k, key[k]]]);

/// การแก้ไขที่เตรียมไว้ยังไม่บันทึก (ต่อหนึ่งตาราง)
class _Pending {
  final updates = <String, Map<String, String?>>{};
  final keys = <String, Map<String, String?>>{};
  final deletes = <String>{};
  final inserts = <Map<String, String?>>[];

  int get count => updates.length + deletes.length + inserts.length;
  bool get isEmpty => count == 0;

  void clear() {
    updates.clear();
    keys.clear();
    deletes.clear();
    inserts.clear();
  }

  List<RowEdit> toEdits() => [
        for (final i in inserts) RowInsert(i),
        for (final e in updates.entries) RowUpdate(keys[e.key]!, e.value),
        for (final id in deletes) RowDelete(keys[id]!),
      ];
}

/// เปิดดูข้อมูลของฐานข้อมูลที่เชื่อมต่อ : รายการตาราง กริดข้อมูล แบ่งหน้า เรียง ค้นหา
/// และ "โหมดแก้ไข" (ปิดเป็นค่าเริ่มต้น) ที่เตรียมการแก้ไขไว้ก่อน แล้วค่อยบันทึกทั้งชุดในทรานแซกชันเดียวหลังดูคำสั่งและยืนยัน
class DataBrowserDialog extends StatefulWidget {
  const DataBrowserDialog({super.key, required this.title, required this.opener});
  final String title;
  final DataSessionOpener opener;

  @override
  State<DataBrowserDialog> createState() => _DataBrowserDialogState();
}

class _DataBrowserDialogState extends State<DataBrowserDialog> {
  static const _pageSize = 100;
  static const _rowH = 32.0;

  DataSession? _session;
  List<String> _tables = const [];
  String? _selected;
  DbTable? _table;
  DbPage? _page;
  int _offset = 0;
  String? _orderBy;
  bool _desc = false;
  final _search = TextEditingController();
  String _searchApplied = '';
  final _pending = _Pending();

  bool _busy = true;
  String? _error;
  String? _notice;
  bool get _editMode => _session?.writable ?? false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    _session?.close();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final s = await widget.opener(false);
      final names = await s.tableNames();
      if (!mounted) {
        await s.close();
        return;
      }
      setState(() {
        _session = s;
        _tables = names;
        _busy = false;
      });
      if (names.isNotEmpty) await _selectTable(names.first, force: true);
    } on DbException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = tr('เกิดข้อผิดพลาด: {0}', [e]);
          _busy = false;
        });
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_pending.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ทิ้งการแก้ไขที่ยังไม่บันทึก?')),
        content: Text(tr('มี {0} รายการที่เตรียมไว้แต่ยังไม่ได้บันทึก จะหายไป', [_pending.count])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('กลับไปแก้ต่อ'))),
          FilledButton(key: const ValueKey('discard-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ทิ้ง'))),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _selectTable(String name, {bool force = false}) async {
    if (!force && name == _selected) return;
    if (!force && !await _confirmDiscard()) return;
    _pending.clear();
    setState(() {
      _selected = name;
      _offset = 0;
      _orderBy = null;
      _desc = false;
      _search.clear();
      _searchApplied = '';
      _table = null;
      _page = null;
    });
    await _load(reloadTable: true);
  }

  Future<void> _load({bool reloadTable = false}) async {
    final s = _session, name = _selected;
    if (s == null || name == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = reloadTable || _table == null ? await s.table(name) : _table!;
      final page = await s.fetch(t, offset: _offset, limit: _pageSize, orderBy: _orderBy, descending: _desc, search: _searchApplied);
      if (!mounted) return;
      setState(() {
        _table = t;
        _page = page;
      });
    } on DbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = tr('เกิดข้อผิดพลาด: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// สลับระหว่างโหมดดูอย่างเดียว กับโหมดแก้ไข : เปิดเซสชันใหม่ (ของโหมดดูเขียนไม่ได้จริงที่ระดับการเชื่อมต่อ)
  Future<void> _setEditMode(bool on) async {
    if (on == _editMode) return;
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('เปิดโหมดแก้ไขข้อมูล?')),
          content: Text(tr('การแก้ไขจะถูกเตรียมไว้ก่อน แล้วบันทึกลงฐานข้อมูลจริงเมื่อคุณกด "บันทึก" และยืนยันคำสั่งที่จะรัน (ไฟล์ SQLite จะถูกสำรองก่อนเขียน)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
            FilledButton(key: const ValueKey('edit-mode-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('เปิดโหมดแก้ไข'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    } else if (!await _confirmDiscard()) {
      return;
    }
    _pending.clear();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final old = _session;
      final s = await widget.opener(on);
      await old?.close();
      if (!mounted) {
        await s.close();
        return;
      }
      setState(() => _session = s);
      await _load(reloadTable: true);
    } on DbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = tr('เกิดข้อผิดพลาด: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sortBy(String col) {
    setState(() {
      if (_orderBy != col) {
        _orderBy = col;
        _desc = false;
      } else if (!_desc) {
        _desc = true;
      } else {
        _orderBy = null;
        _desc = false;
      }
      _offset = 0;
    });
    _load();
  }

  Future<void> _go(int offset) async {
    if (!await _confirmDiscard()) return;
    _pending.clear();
    setState(() => _offset = offset);
    await _load();
  }

  // ---------- เตรียมการแก้ไข ----------

  String _shown(DbRow row, int i) {
    final col = _table!.columns[i].name;
    final id = _rowId(row.key);
    final u = _pending.updates[id];
    final v = u != null && u.containsKey(col) ? u[col] : row.cells[i];
    return v ?? '\u0000NULL';
  }

  Future<void> _editCell(DbRow row, int i) async {
    final t = _table!;
    final col = t.columns[i];
    if (!_editMode || !t.canEditRows || col.isBinary) return;
    final id = _rowId(row.key);
    final current = _pending.updates[id]?.containsKey(col.name) == true ? _pending.updates[id]![col.name] : row.cells[i];
    final r = await showDialog<_CellResult>(
      context: context,
      builder: (_) => _CellEditDialog(column: col, initial: current),
    );
    if (r == null || !mounted) return;
    setState(() {
      final changes = _pending.updates.putIfAbsent(id, () => {});
      _pending.keys[id] = row.key;
      if (r.value == row.cells[i]) {
        changes.remove(col.name); // กลับเป็นค่าเดิม = ไม่นับเป็นการแก้ไข
      } else {
        changes[col.name] = r.value;
      }
      if (changes.isEmpty) {
        _pending.updates.remove(id);
        if (!_pending.deletes.contains(id)) _pending.keys.remove(id);
      }
    });
  }

  void _toggleDelete(DbRow row) {
    final id = _rowId(row.key);
    setState(() {
      if (_pending.deletes.remove(id)) {
        if (!_pending.updates.containsKey(id)) _pending.keys.remove(id);
      } else {
        _pending.deletes.add(id);
        _pending.keys[id] = row.key;
        _pending.updates.remove(id); // แถวที่จะลบ ไม่ต้องแก้
      }
    });
  }

  Future<void> _addRow() async {
    final t = _table!;
    final r = await showDialog<Map<String, String?>>(context: context, builder: (_) => _InsertDialog(table: t));
    if (r == null || !mounted) return;
    setState(() => _pending.inserts.add(r));
  }

  Future<void> _save() async {
    final s = _session, t = _table;
    if (s == null || t == null || _pending.isEmpty) return;
    final edits = _pending.toEdits();
    final List<String> preview;
    try {
      preview = [for (final e in edits) buildEditStatement(s.dialect, t, e).preview()];
    } on DataSqlException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('save-confirm'),
        title: Text(tr('บันทึก {0} การเปลี่ยนแปลงลงฐานข้อมูลจริง?', [edits.length])),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s.dialect.name == 'sqlite'
                  ? tr('จะสำรองไฟล์ก่อน แล้วรันคำสั่งต่อไปนี้ในทรานแซกชันเดียว ผิดพลาดข้อเดียวจะยกเลิกทั้งหมด')
                  : tr('จะรันคำสั่งต่อไปนี้ในทรานแซกชันเดียว ผิดพลาดข้อเดียวจะยกเลิกทั้งหมด'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(8)),
                child: SingleChildScrollView(
                  child: SelectableText(preview.map((p) => '$p;').join('\n'), style: monoStyle.copyWith(fontSize: 12)),
                ),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(key: const ValueKey('save-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('บันทึกลงฐานข้อมูล'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final r = await s.apply(t, edits);
      _pending.clear();
      if (!mounted) return;
      setState(() => _notice = r.backupPath == null
          ? tr('บันทึกแล้ว {0} คำสั่ง', [r.statements])
          : tr('บันทึกแล้ว {0} คำสั่ง · ไฟล์สำรอง: {1}', [r.statements, r.backupPath!]));
      await _load();
    } on DbException catch (e) {
      if (mounted) setState(() => _error = e.message); // ค้างการแก้ไขไว้ให้แก้ต่อ/ลองใหม่
    } catch (e) {
      if (mounted) setState(() => _error = tr('เกิดข้อผิดพลาด: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- หน้าจอ ----------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return PopScope(
      canPop: _pending.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        final nav = Navigator.of(context);
        if (!didPop && await _confirmDiscard()) nav.pop();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(children: [
            _header(),
            if (_editMode) _banner(tr('โหมดแก้ไข : การเปลี่ยนแปลงจะถูกเตรียมไว้ก่อน (ไฮไลต์) แล้วบันทึกเมื่อกด "บันทึก"'), C.warnBg, C.warnText),
            if (_error != null) _banner(_error!, C.dangerBg, C.danger, key: const ValueKey('data-error')),
            if (_notice != null) _banner(_notice!, C.primaryTint, C.primaryDark, key: const ValueKey('data-notice')),
            const Divider(height: 1),
            Expanded(
              child: _session == null && _error == null
                  ? const Center(child: CircularProgressIndicator())
                  : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: 220, child: _tableList()),
                      VerticalDivider(width: 1, color: C.border),
                      Expanded(child: _content()),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _banner(String text, Color bg, Color fg, {Key? key}) => Container(
        key: key,
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: SelectableText(text, style: TextStyle(fontSize: 12.5, color: fg)),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          Icon(Icons.table_rows_outlined, size: 20, color: C.primaryDark),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          Text(tr('โหมดแก้ไข'), style: TextStyle(fontSize: 13, color: C.muted)),
          Switch(
            key: const ValueKey('edit-mode'),
            value: _editMode,
            onChanged: _busy || _session == null ? null : _setEditMode,
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('data-close'),
            tooltip: tr('ปิด'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (await _confirmDiscard()) nav.pop();
            },
          ),
        ]),
      );

  Widget _tableList() => _tables.isEmpty
      ? Center(child: Text(_busy ? '' : tr('ไม่มีตาราง'), style: TextStyle(color: C.muted)))
      : ListView.builder(
          key: const ValueKey('data-tables'),
          itemCount: _tables.length,
          itemBuilder: (_, i) {
            final n = _tables[i];
            final on = n == _selected;
            return InkWell(
              key: ValueKey('data-table-$n'),
              onTap: _busy ? null : () => _selectTable(n),
              child: Container(
                color: on ? C.primaryTint : null,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(children: [
                  Icon(Icons.table_chart_outlined, size: 15, color: on ? C.primaryDark : C.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(n, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w400))),
                ]),
              ),
            );
          },
        );

  Widget _content() {
    final t = _table, p = _page;
    if (_selected == null) return Center(child: Text(tr('เลือกตารางทางซ้าย'), style: TextStyle(color: C.muted)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toolbar(t, p),
      const Divider(height: 1),
      Expanded(child: t == null || p == null ? Center(child: _busy ? const CircularProgressIndicator() : const SizedBox()) : _grid(t, p)),
    ]);
  }

  Widget _toolbar(DbTable? t, DbPage? p) {
    final total = p?.total ?? 0;
    final from = total == 0 ? 0 : _offset + 1;
    final to = (_offset + (p?.rows.length ?? 0));
    final canEdit = _editMode && t != null && t.canEditRows;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 240,
          height: 34,
          child: TextField(
            key: const ValueKey('data-search'),
            controller: _search,
            onSubmitted: (v) async {
              if (!await _confirmDiscard()) return;
              _pending.clear();
              setState(() {
                _searchApplied = v;
                _offset = 0;
              });
              await _load();
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: tr('ค้นหาในทุกคอลัมน์ (กด Enter)'),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('data-prev'),
          tooltip: tr('หน้าก่อนหน้า'),
          onPressed: _busy || _offset == 0 ? null : () => _go((_offset - _pageSize).clamp(0, 1 << 30)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text('$from–$to / $total', key: const ValueKey('data-range'), style: const TextStyle(fontSize: 13)),
        IconButton(
          key: const ValueKey('data-next'),
          tooltip: tr('หน้าถัดไป'),
          onPressed: _busy || p == null || _offset + _pageSize >= total ? null : () => _go(_offset + _pageSize),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        IconButton(
          key: const ValueKey('data-refresh'),
          tooltip: tr('โหลดใหม่'),
          onPressed: _busy ? null : () => _go(_offset),
          icon: const Icon(Icons.refresh_rounded),
        ),
        if (_editMode && t != null && !t.canEditRows)
          Text(tr('ตารางนี้ไม่มีคีย์หลัก ดูได้อย่างเดียว'), style: TextStyle(fontSize: 12.5, color: C.warnText)),
        if (canEdit) ...[
          OutlinedButton.icon(
            key: const ValueKey('data-add'),
            onPressed: _busy ? null : _addRow,
            icon: const Icon(Icons.add, size: 16),
            label: Text(tr('เพิ่มแถว')),
          ),
          if (!_pending.isEmpty) ...[
            TextButton(
              key: const ValueKey('data-revert'),
              onPressed: _busy ? null : () => setState(_pending.clear),
              child: Text(tr('ยกเลิกที่เตรียมไว้')),
            ),
            FilledButton(
              key: const ValueKey('data-save'),
              onPressed: _busy ? null : _save,
              child: Text(tr('บันทึก ({0})', [_pending.count])),
            ),
          ],
        ],
      ]),
    );
  }

  double _colW(DbColumn c) => (c.name.length * 9.0 + 44).clamp(120.0, 260.0);

  Widget _grid(DbTable t, DbPage p) {
    final widths = [for (final c in t.columns) _colW(c)];
    const actionW = 44.0;
    final total = widths.fold<double>(0, (a, b) => a + b) + (_editMode ? actionW : 0) + 24;
    return LayoutBuilder(builder: (context, box) {
      return Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: total < box.maxWidth ? box.maxWidth : total,
            child: Column(children: [
              Container(
                height: 34,
                color: C.field,
                child: Row(children: [
                  if (_editMode) const SizedBox(width: actionW),
                  for (var i = 0; i < t.columns.length; i++)
                    SizedBox(
                      width: widths[i],
                      child: InkWell(
                        key: ValueKey('data-head-${t.columns[i].name}'),
                        onTap: _busy ? null : () => _sortBy(t.columns[i].name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(children: [
                            if (t.columns[i].isPk) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.key_rounded, size: 13, color: C.warnText)),
                            Flexible(child: Text(t.columns[i].name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                            if (_orderBy == t.columns[i].name) Icon(_desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 13),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              Expanded(
                child: p.rows.isEmpty && _pending.inserts.isEmpty
                    ? Center(child: Text(tr('ไม่มีข้อมูล'), style: TextStyle(color: C.muted)))
                    : ListView.builder(
                        itemExtent: _rowH,
                        itemCount: _pending.inserts.length + p.rows.length,
                        itemBuilder: (_, i) => i < _pending.inserts.length ? _insertRow(t, widths, i, actionW) : _dataRow(t, p.rows[i - _pending.inserts.length], widths, actionW),
                      ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _cell(String? text, double w, {Color? bg, bool strike = false, VoidCallback? onDouble, Key? key}) {
    final isNull = text == null || text == '\u0000NULL';
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onDouble,
      child: Container(
        width: w,
        height: _rowH,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          isNull ? 'NULL' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: monoStyle.copyWith(
            fontSize: 12.5,
            color: isNull ? C.muted : C.text,
            fontStyle: isNull ? FontStyle.italic : FontStyle.normal,
            decoration: strike ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }

  Widget _dataRow(DbTable t, DbRow row, List<double> widths, double actionW) {
    final id = _rowId(row.key);
    final deleted = _pending.deletes.contains(id);
    final edits = _pending.updates[id];
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.borderSoft)), color: deleted ? C.dangerBg : null),
      child: Row(children: [
        if (_editMode)
          SizedBox(
            width: actionW,
            child: t.canEditRows
                ? IconButton(
                    key: ValueKey('data-del-$id'),
                    tooltip: deleted ? tr('ไม่ลบแล้ว') : tr('ลบแถวนี้'),
                    iconSize: 17,
                    padding: EdgeInsets.zero,
                    onPressed: _busy ? null : () => _toggleDelete(row),
                    icon: Icon(deleted ? Icons.undo_rounded : Icons.delete_outline, color: C.danger),
                  )
                : null,
          ),
        for (var i = 0; i < t.columns.length; i++)
          _cell(
            _shown(row, i),
            widths[i],
            key: ValueKey('cell-${row.key.values.join('|')}-${t.columns[i].name}'),
            bg: !deleted && edits != null && edits.containsKey(t.columns[i].name) ? C.warnBg : null,
            strike: deleted,
            onDouble: deleted ? null : () => _editCell(row, i),
          ),
      ]),
    );
  }

  Widget _insertRow(DbTable t, List<double> widths, int index, double actionW) {
    final v = _pending.inserts[index];
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.borderSoft)), color: C.primaryTint),
      child: Row(children: [
        if (_editMode)
          SizedBox(
            width: actionW,
            child: IconButton(
              key: ValueKey('data-insert-remove-$index'),
              tooltip: tr('เอาแถวใหม่นี้ออก'),
              iconSize: 17,
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _pending.inserts.removeAt(index)),
              icon: Icon(Icons.close_rounded, color: C.danger),
            ),
          ),
        for (var i = 0; i < t.columns.length; i++)
          _cell(
            v.containsKey(t.columns[i].name) ? (v[t.columns[i].name] ?? '\u0000NULL') : tr('(ค่าเริ่มต้น)'),
            widths[i],
          ),
      ]),
    );
  }
}

class _CellResult {
  const _CellResult(this.value);
  final String? value;
}

/// แก้ค่าของเซลล์หนึ่งช่อง : ข้อความ หรือ NULL (ไม่เสนอ NULL ให้คอลัมน์ NOT NULL)
class _CellEditDialog extends StatefulWidget {
  const _CellEditDialog({required this.column, required this.initial});
  final DbColumn column;
  final String? initial;

  @override
  State<_CellEditDialog> createState() => _CellEditDialogState();
}

class _CellEditDialogState extends State<_CellEditDialog> {
  late final _c = TextEditingController(text: widget.initial ?? '');
  late bool _null = widget.initial == null;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final col = widget.column;
    return AlertDialog(
      title: Text(tr('แก้ค่า {0}', [col.name])),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${col.type}${col.notNull ? ' · NOT NULL' : ''}${col.isPk ? ' · PRIMARY KEY' : ''}', style: TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('cell-value'),
            controller: _c,
            enabled: !_null,
            autofocus: true,
            minLines: 1,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
          if (!col.notNull)
            CheckboxListTile(
              key: const ValueKey('cell-null'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _null,
              onChanged: (v) => setState(() => _null = v ?? false),
              title: const Text('NULL', style: TextStyle(fontSize: 13)),
            ),
          if (col.isPk)
            Text(tr('⚠ กำลังแก้คีย์หลัก — ตารางอื่นที่อ้างถึงแถวนี้อาจเสียหาย'), style: TextStyle(fontSize: 12, color: C.warnText)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        FilledButton(
          key: const ValueKey('cell-ok'),
          onPressed: () => Navigator.pop(context, _CellResult(_null ? null : _c.text)),
          child: Text(tr('ตกลง')),
        ),
      ],
    );
  }
}

enum _InsertMode { omit, value, nullValue }

/// ฟอร์มเพิ่มแถวใหม่ : ทุกคอลัมน์ "ใช้ค่าเริ่มต้น" ไว้ก่อน (ให้ฐานข้อมูลใส่ DEFAULT / AUTO INCREMENT เอง) พิมพ์ค่าหรือเลือก NULL เมื่อต้องการ
class _InsertDialog extends StatefulWidget {
  const _InsertDialog({required this.table});
  final DbTable table;

  @override
  State<_InsertDialog> createState() => _InsertDialogState();
}

class _InsertDialogState extends State<_InsertDialog> {
  late final _ctl = {for (final c in widget.table.columns) c.name: TextEditingController()};
  late final _mode = {for (final c in widget.table.columns) c.name: _InsertMode.omit};

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String?> _result() => {
        for (final c in widget.table.columns)
          if (_mode[c.name] == _InsertMode.value)
            c.name: _ctl[c.name]!.text
          else if (_mode[c.name] == _InsertMode.nullValue)
            c.name: null,
      };

  @override
  Widget build(BuildContext context) {
    final cols = widget.table.columns.where((c) => !c.isBinary).toList();
    return AlertDialog(
      title: Text(tr('เพิ่มแถวใหม่ใน {0}', [widget.table.name])),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final c in cols)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(
                    width: 150,
                    child: Text('${c.name}${c.notNull ? ' *' : ''}', overflow: TextOverflow.ellipsis, style: monoStyle.copyWith(fontSize: 12.5)),
                  ),
                  Expanded(
                    child: TextField(
                      key: ValueKey('ins-${c.name}'),
                      controller: _ctl[c.name],
                      enabled: _mode[c.name] != _InsertMode.nullValue,
                      onChanged: (_) => setState(() => _mode[c.name] = _InsertMode.value),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _mode[c.name] == _InsertMode.omit ? (c.autoIncrement ? tr('อัตโนมัติ') : tr('ค่าเริ่มต้น')) : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: tr('ใช้ค่าเริ่มต้นของฐานข้อมูล'),
                    child: ChoiceChip(
                      key: ValueKey('ins-default-${c.name}'),
                      label: Text(tr('เริ่มต้น'), style: const TextStyle(fontSize: 11.5)),
                      selected: _mode[c.name] == _InsertMode.omit,
                      onSelected: (_) => setState(() {
                        _mode[c.name] = _InsertMode.omit;
                        _ctl[c.name]!.clear();
                      }),
                    ),
                  ),
                  if (!c.notNull) ...[
                    const SizedBox(width: 4),
                    ChoiceChip(
                      key: ValueKey('ins-null-${c.name}'),
                      label: const Text('NULL', style: TextStyle(fontSize: 11.5)),
                      selected: _mode[c.name] == _InsertMode.nullValue,
                      onSelected: (_) => setState(() => _mode[c.name] = _InsertMode.nullValue),
                    ),
                  ],
                ]),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        FilledButton(key: const ValueKey('ins-ok'), onPressed: () => Navigator.pop(context, _result()), child: Text(tr('เพิ่มเข้ารายการที่เตรียมไว้'))),
      ],
    );
  }
}
