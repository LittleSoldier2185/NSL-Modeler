import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../state/app_settings.dart';
import '../state/project_controller.dart';
import 'app_actions.dart';
import 'canvas/canvas_controller.dart';
import 'file_actions.dart';
import 'shortcuts.dart';
import 'style_actions.dart';
import 'theme.dart';
import 'window_chrome.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final fileName = c.filePath == null
        ? '${c.project.name}.erd'
        : c.filePath!.split(RegExp(r'[\\/]')).last;

    // ใช้แถบของแอปเป็นแถบชื่อหน้าต่าง: ลากพื้นที่ว่างเพื่อย้ายหน้าต่าง ปุ่มควบคุมชิดมุมขวา
    final controls = WindowChrome.customControls;
    return Container(
      height: 52,
      padding: EdgeInsets.only(left: 16 + WindowChrome.leadingInset, right: controls ? 0 : 16),
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: C.primary,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(
                Icons.storage_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'NSL Modeler',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 22, color: C.border),
            const SizedBox(width: 8),
            ..._menus(context, c),
            const SizedBox(width: 8),
            // ชื่อไฟล์ยาว/หน้าต่างแคบ: ชื่อย่อด้วย … ส่วนปุ่มทางขวาคงขนาดเดิม
            // พื้นที่ว่างตรงกลางแถบ = ที่จับลากย้ายหน้าต่าง (ไม่ครอบทั้งแถบ เพราะ onDoubleTap ของตัวครอบ
            // จะทำให้ปุ่มข้างในรอ ~300ms ก่อนรับการกด)
            Expanded(
              child: WindowDragArea(
                child: SizedBox(
                  height: double.infinity,
                  child: Row(
                children: [
                  Flexible(
                    child: Text(
                      fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  // ช่องไฟเป็น Padding ในตัว Flexible (ไม่ใช่ SizedBox ตายตัว) เพื่อให้ยุบเหลือ 0 ได้เมื่อที่ไม่พอ
                  if (c.dirty)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          tr('● ยังไม่ได้บันทึก'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: C.muted),
                          maxLines: 1,
                        ),
                      ),
                    ),
                ],
              ),
                ),
              ),
            ),
            // กลุ่มปุ่มขวา: ได้พื้นที่ที่เหลือก่อนชื่อไฟล์ (flex สูง) ชิดขวาติดปุ่มควบคุมหน้าต่าง
            // ไม่เกิน 50% ของแถบ ถ้าที่ไม่พอจะย่อสัดส่วนลงแทนการล้น
            // ที่ว่างทางซ้ายของปุ่ม = ที่จับลากย้ายหน้าต่าง (วางเป็นชั้นล่างของ Stack: ปุ่มอยู่ชั้นบนจึงรับการกดทันที)
            Expanded(
              flex: 1000,
              child: Stack(children: [
            const Positioned.fill(child: WindowDragArea(child: SizedBox.expand())),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconBtn(
                        Icons.undo,
                        tr('ย้อนกลับ (Ctrl+Z)'),
                        c.canUndo ? c.undo : null,
                      ),
                      const SizedBox(width: 4),
                      _IconBtn(
                        Icons.redo,
                        tr('ทำซ้ำ (Ctrl+Shift+Z)'),
                        c.canRedo ? c.redo : null,
                      ),
                      const SizedBox(width: 4),
                      Builder(
                        builder: (context) {
                          final s = context.watch<AppSettings>();
                          return _IconBtn(
                            s.dark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            s.dark ? tr('ธีมสว่าง') : tr('ธีมมืด'),
                            s.toggleDark,
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 34,
                        child: OutlinedButton.icon(
                          onPressed: c.project.tables.isEmpty
                              ? null
                              : () {
                                  c.autoLayoutTables();
                                  context.read<CanvasController>().fit(
                                    c.project,
                                  );
                                },
                          icon: const Icon(Icons.grid_view_rounded, size: 16),
                          label: Text(tr('จัดวางอัตโนมัติ')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: C.text,
                            side: BorderSide(color: C.border),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(fontSize: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: C.primaryTint,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        alignment: Alignment.center,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Dialect  ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: C.primaryDark,
                                ),
                              ),
                              TextSpan(
                                text: c.project.dialect.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: C.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 34,
                        child: FilledButton.icon(
                          onPressed: () => FileActions.exportSql(context, c),
                          icon: const Icon(
                            Icons.file_download_outlined,
                            size: 16,
                          ),
                          label: const Text('Export .sql'),
                          style: FilledButton.styleFrom(
                            backgroundColor: C.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
              ]),
            ),
            if (controls) ...[
              const SizedBox(width: 12),
              const WindowControls(),
            ],
          ],
        ),
      ),
    );
  }

  /// เมนูหลัก: คีย์ลัดที่แสดงมาจาก [shortcutText] (ข้อมูลชุดเดียวกับตัวดักปุ่มจริง)
  static List<Widget> _menus(BuildContext context, ProjectController c) {
    final a = AppActions(context);
    final cv = a.cv;
    PopupMenuEntry<VoidCallback> cmd(
      String label,
      Cmd k, {
      bool enabled = true,
    }) => _item(label, shortcutText(k), enabled ? () => a.run(k) : null);
    const div = PopupMenuDivider();
    final hasSel = c.selectionCount > 0;

    return [
      _MenuButton(
        label: tr('ไฟล์'),
        items: [
          cmd(tr('โปรเจกต์ใหม่'), Cmd.newProject),
          cmd(tr('เปิด…'), Cmd.open),
          cmd(tr('บันทึก'), Cmd.save),
          cmd(tr('บันทึกเป็น…'), Cmd.saveAs),
          div,
          cmd(tr('นำเข้าจาก .sql…'), Cmd.importSql),
          cmd(tr('เปรียบเทียบกับไฟล์เก่า (Migration)…'), Cmd.compare),
          div,
          cmd(tr('Export ภาพ (PNG / SVG)…'), Cmd.exportImage),
          cmd(tr('Export เอกสาร / DBML / ข้อมูลตัวอย่าง…'), Cmd.exportText),
          cmd('Export .sql…', Cmd.exportSql),
        ],
      ),
      _MenuButton(
        label: tr('แก้ไข'),
        items: [
          cmd(tr('ย้อนกลับ'), Cmd.undo, enabled: c.canUndo),
          cmd(tr('ทำซ้ำ'), Cmd.redo, enabled: c.canRedo),
          div,
          cmd(tr('คัดลอกตาราง'), Cmd.copy, enabled: hasSel),
          cmd(tr('สร้างตารางแบบฟอร์ม…'), Cmd.createTableForm),
          cmd(tr('จัดกลุ่มตารางที่เลือก'), Cmd.groupSelected, enabled: hasSel),
          div,
          cmd(tr('วางตาราง'), Cmd.paste),
          cmd(tr('ทำสำเนาตาราง'), Cmd.duplicate, enabled: hasSel),
          cmd(
            tr('เลือกทุกตาราง'),
            Cmd.selectAll,
            enabled: c.project.tables.isNotEmpty,
          ),
          cmd(tr('เปลี่ยนชื่อ…'), Cmd.rename, enabled: c.selectedTable != null),
          cmd(tr('ลบที่เลือก'), Cmd.delete, enabled: hasSel),
          div,
          _item(
            tr('จัดวางอัตโนมัติ'),
            '',
            c.project.tables.isEmpty
                ? null
                : () {
                    c.autoLayoutTables();
                    cv.fit(c.project);
                  },
          ),
        ],
      ),
      _MenuButton(
        label: tr('มุมมอง'),
        items: [
          cmd(tr('พอดีหน้าจอ'), Cmd.fit),
          cmd(tr('ซูม 100%'), Cmd.zoom100),
          div,
          _item(tr('แสดง SQL Preview'), '', () => cv.showDock(DockTab.sql)),
          _item(
            tr('แสดงปัญหาที่ตรวจพบ'),
            '',
            () => cv.showDock(DockTab.issues),
          ),
          div,
          _item(
            tr('ขนาดกระดาน…'),
            '',
            () => FileActions.changeBoardSize(context, c),
          ),
          _item(tr('สีเส้นความสัมพันธ์…'), '', () => StyleActions.lineColor(context, c)),
          _item(
            '${context.read<AppSettings>().snapToGrid ? '✓ ' : '    '}${tr('จัดแนวตามตาราง (Snap)')}',
            '',
            () {
              final s = context.read<AppSettings>();
              s.setSnapToGrid(!s.snapToGrid);
            },
          ),
          div,
          cmd(tr('ค้นหาตาราง / คอลัมน์'), Cmd.find),
          cmd('Command palette', Cmd.palette),
        ],
      ),
      _MenuButton(
        label: tr('ช่วยเหลือ'),
        items: [
          cmd(tr('ดูคีย์ลัดทั้งหมด'), Cmd.help),
          div,
          for (final l in Lang.values)
            _item(
              '${l == currentLang ? '✓ ' : '    '}${l.label}',
              '',
              () => context.read<AppSettings>().setLang(l),
            ),
        ],
      ),
    ];
  }

  static PopupMenuEntry<VoidCallback> _item(
    String label,
    String shortcut,
    VoidCallback? onTap,
  ) => PopupMenuItem<VoidCallback>(
    value: onTap,
    enabled: onTap != null,
    height: 36,
    child: SizedBox(
      width: 400,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Text(shortcut, style: TextStyle(fontSize: 12, color: C.muted)),
        ],
      ),
    ),
  );
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.items});
  final String label;
  final List<PopupMenuEntry<VoidCallback>> items;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: '',
    offset: const Offset(0, 36),
    onSelected: (f) => f(),
    itemBuilder: (_) => items,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(this.icon, this.tip, this.onTap);
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: SizedBox(
      width: 34,
      height: 34,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: C.text,
          side: BorderSide(color: C.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 17),
      ),
    ),
  );
}
