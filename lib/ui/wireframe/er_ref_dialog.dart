import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/wireframe_model.dart';
import '../../core/models/workspace.dart';
import '../widgets.dart';

/// ผลของกล่องเลือกข้อมูล ER: [ref] null = เลิกผูก
class ErRefChoice {
  const ErRefChoice(this.ref);
  final WfDataRef? ref;
}

/// กล่องเลือก ER › ตาราง › คอลัมน์ (คอลัมน์ไม่บังคับ) — คืน null ถ้ายกเลิก
Future<ErRefChoice?> showErRefDialog(BuildContext context, Workspace w, {WfDataRef? current}) =>
    showDialog<ErRefChoice>(context: context, builder: (_) => _ErRefDialog(workspace: w, current: current));

class _ErRefDialog extends StatefulWidget {
  const _ErRefDialog({required this.workspace, this.current});
  final Workspace workspace;
  final WfDataRef? current;

  @override
  State<_ErRefDialog> createState() => _ErRefDialogState();
}

class _ErRefDialogState extends State<_ErRefDialog> {
  late List<ProjectDocument> _ers = widget.workspace.documentsOf(DocType.er).toList();
  String? _doc, _table, _column;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    final doc = c == null ? null : widget.workspace.documentById(c.docId);
    if (doc?.er != null) {
      _doc = doc!.id;
      final t = doc.er!.tableById(c!.tableId);
      if (t != null) {
        _table = t.id;
        if (c.columnId != null && t.columnById(c.columnId!) != null) _column = c.columnId;
      }
    } else if (_ers.isNotEmpty) {
      _doc = _ers.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    _ers = widget.workspace.documentsOf(DocType.er).toList();
    final er = _doc == null ? null : widget.workspace.documentById(_doc!)?.er;
    final tables = er?.tables ?? const [];
    final table = _table == null ? null : er?.tableById(_table!);
    const none = '';
    return AlertDialog(
      title: Text(tr('ผูกกับข้อมูลใน ER')),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_ers.isEmpty) Text(tr('ยังไม่มีเอกสาร ER ในโปรเจกต์')),
          if (_ers.isNotEmpty) ...[
            LabeledField(
              label: tr('เอกสาร ER'),
              child: KeyedSubtree(
                key: const ValueKey('wf-ref-doc'),
                child: Dropdown<String>(
                  value: _doc ?? _ers.first.id,
                  items: [for (final d in _ers) d.id],
                  labelOf: (id) => widget.workspace.documentById(id)?.name ?? id,
                  onChanged: (v) => setState(() {
                    _doc = v;
                    _table = null;
                    _column = null;
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: tr('ตาราง'),
              child: KeyedSubtree(
                key: const ValueKey('wf-ref-table'),
                child: Dropdown<String>(
                  value: _table ?? none,
                  items: [none, for (final t in tables) t.id],
                  labelOf: (id) => id == none ? tr('— เลือกตาราง —') : (er?.tableById(id)?.name ?? id),
                  onChanged: (v) => setState(() {
                    _table = v == none ? null : v;
                    _column = null;
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: tr('คอลัมน์ (ไม่บังคับ)'),
              child: KeyedSubtree(
                key: const ValueKey('wf-ref-column'),
                child: Dropdown<String>(
                  value: _column ?? none,
                  items: [none, for (final c in table?.columns ?? const []) c.id],
                  labelOf: (id) => id == none ? tr('— ทั้งตาราง —') : (table?.columnById(id)?.name ?? id),
                  onChanged: (v) => setState(() => _column = v == none ? null : v),
                ),
              ),
            ),
          ],
        ]),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            key: const ValueKey('wf-ref-unbind'),
            onPressed: () => Navigator.pop(context, const ErRefChoice(null)),
            child: Text(tr('เลิกผูก')),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        FilledButton(
          key: const ValueKey('wf-ref-ok'),
          onPressed: _doc == null || _table == null
              ? null
              : () => Navigator.pop(context, ErRefChoice(WfDataRef(docId: _doc!, tableId: _table!, columnId: _column))),
          child: Text(tr('ตกลง')),
        ),
      ],
    );
  }
}
