import 'package:flutter/material.dart';

import '../core/fonts/system_fonts.dart';
import '../core/l10n/l10n.dart';
import 'theme.dart';

/// ผลของกล่องเลือกฟอนต์: [family] = null หมายถึงกลับไปใช้ฟอนต์หลัก (Noto Sans Thai)
class FontChoice {
  const FontChoice(this.family);
  final String? family;
}

/// เลือกฟอนต์ที่ติดตั้งในเครื่อง (ค้นหาได้ พรีวิวด้วยฟอนต์นั้นเอง) — คืน null ถ้ายกเลิก
Future<FontChoice?> showFontPickerDialog(BuildContext context, {String? current}) =>
    showDialog<FontChoice>(context: context, builder: (_) => _FontPickerDialog(current: current));

const _sample = 'Aa กขค ABC 0123 customer_id';

class _FontPickerDialog extends StatefulWidget {
  const _FontPickerDialog({this.current});
  final String? current;

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  List<String>? _fonts;
  String _q = '';

  @override
  void initState() {
    super.initState();
    SystemFonts.list().then((f) {
      if (mounted) setState(() => _fonts = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fonts = _fonts;
    final shown = fonts == null ? const <String>[] : [for (final f in fonts) if (f.toLowerCase().contains(_q.toLowerCase())) f];
    return AlertDialog(
      title: Text(tr('ฟอนต์ของตาราง')),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const ValueKey('font-search'),
            autofocus: true,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: tr('ค้นหาฟอนต์ในเครื่อง'),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('font-default'),
            dense: true,
            selected: widget.current == null,
            title: Text(tr('ค่าเริ่มต้น (Noto Sans Thai)'), style: const TextStyle(fontSize: 13.5)),
            onTap: () => Navigator.pop(context, const FontChoice(null)),
          ),
          Divider(height: 1, color: C.border),
          Expanded(
            child: fonts == null
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? Center(child: Text(tr('ไม่พบฟอนต์'), style: TextStyle(color: C.muted)))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemExtent: 54,
                        itemBuilder: (_, i) {
                          final f = shown[i];
                          return ListTile(
                            key: ValueKey('font-$f'),
                            dense: true,
                            selected: f == widget.current,
                            title: Text(f, style: TextStyle(fontSize: 11.5, color: C.muted)),
                            subtitle: Text(_sample,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: tableFont(const TextStyle(fontSize: 15), f)),
                            onTap: () => Navigator.pop(context, FontChoice(f)),
                          );
                        },
                      ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก')))],
    );
  }
}
