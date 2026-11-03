import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import 'palette/command_palette.dart';
import 'shortcuts.dart';
import 'theme.dart';

/// ช่องค้นหากลางแถบบน: คลิก (หรือ Ctrl+K) เปิดหน้าค้นหา/สั่งงาน ซึ่งค้นได้ทั้งคำสั่ง ตาราง คอลัมน์ วัตถุ DFD โน้ต กลุ่ม และปัญหาที่ตรวจพบ
/// เป็นปุ่มหน้าตาเป็นช่อง (ไม่ใช่ TextField) เพื่อให้หน้าค้นหาเป็นที่พิมพ์ที่เดียว
class SearchLauncher extends StatefulWidget {
  const SearchLauncher({super.key});

  @override
  State<SearchLauncher> createState() => _SearchLauncherState();
}

class _SearchLauncherState extends State<SearchLauncher> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final key = shortcutText(Cmd.palette);
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const ValueKey('top-search'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showCommandPalette(context),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: C.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _hover ? C.primary.withValues(alpha: 0.6) : C.border),
          ),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 16, color: C.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('ค้นหาตาราง คำสั่ง วัตถุ DFD…'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: C.muted),
              ),
            ),
            if (key.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: C.border)),
                child: Text(key, style: monoStyle.copyWith(fontSize: 10.5, color: C.muted)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
