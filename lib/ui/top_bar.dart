import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/project_controller.dart';
import 'app_actions.dart';
import 'canvas/canvas_controller.dart';
import 'file_actions.dart';
import 'shortcuts.dart';
import 'theme.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final fileName = c.filePath == null
        ? '${c.project.name}.erd'
        : c.filePath!.split(RegExp(r'[\\/]')).last;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
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
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (c.dirty)
                    const Flexible(
                      child: Text(
                        '● ยังไม่ได้บันทึก',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: C.muted),
                        maxLines: 1,
                      ),
                    ),
                ],
              ),
            ),
            // กลุ่มปุ่มขวา: กินที่ไม่เกิน 50% ของแถบ ถ้าเกินจะย่อสัดส่วนลงแทนการล้น
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBtn(
                      Icons.undo,
                      'ย้อนกลับ (Ctrl+Z)',
                      c.canUndo ? c.undo : null,
                    ),
                    const SizedBox(width: 4),
                    _IconBtn(
                      Icons.redo,
                      'ทำซ้ำ (Ctrl+Y)',
                      c.canRedo ? c.redo : null,
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        onPressed: c.project.tables.isEmpty
                            ? null
                            : () {
                                c.autoLayoutTables();
                                context.read<CanvasController>().fit(c.project);
                              },
                        icon: const Icon(Icons.grid_view_rounded, size: 16),
                        label: const Text('จัดวางอัตโนมัติ'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: C.text,
                          side: const BorderSide(color: C.border),
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
                            const TextSpan(
                              text: 'Dialect  ',
                              style: TextStyle(
                                fontSize: 12,
                                color: C.primaryDark,
                              ),
                            ),
                            TextSpan(
                              text: c.project.dialect.label,
                              style: const TextStyle(
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
          ],
        ),
      ),
    );
  }

  /// เมนูหลัก: คีย์ลัดที่แสดงมาจาก [shortcutText] (ข้อมูลชุดเดียวกับตัวดักปุ่มจริง)
  static List<Widget> _menus(BuildContext context, ProjectController c) {
    final a = AppActions(context);
    final cv = a.cv;
    PopupMenuEntry<VoidCallback> cmd(String label, Cmd k, {bool enabled = true}) =>
        _item(label, shortcutText(k), enabled ? () => a.run(k) : null);
    const div = PopupMenuDivider();
    final hasSel = c.selectionCount > 0;

    return [
      _MenuButton(label: 'ไฟล์', items: [
        cmd('โปรเจกต์ใหม่', Cmd.newProject),
        cmd('เปิด…', Cmd.open),
        cmd('บันทึก', Cmd.save),
        cmd('บันทึกเป็น…', Cmd.saveAs),
        div,
        cmd('นำเข้าจาก .sql…', Cmd.importSql),
        cmd('เปรียบเทียบกับไฟล์เก่า (Migration)…', Cmd.compare),
        div,
        cmd('Export ภาพ (PNG / SVG)…', Cmd.exportImage),
        cmd('Export เอกสาร / DBML / ข้อมูลตัวอย่าง…', Cmd.exportText),
        cmd('Export .sql…', Cmd.exportSql),
      ]),
      _MenuButton(label: 'แก้ไข', items: [
        cmd('ย้อนกลับ', Cmd.undo, enabled: c.canUndo),
        cmd('ทำซ้ำ', Cmd.redo, enabled: c.canRedo),
        div,
        cmd('คัดลอกตาราง', Cmd.copy, enabled: hasSel),
        cmd('วางตาราง', Cmd.paste),
        cmd('ทำสำเนาตาราง', Cmd.duplicate, enabled: hasSel),
        cmd('เลือกทุกตาราง', Cmd.selectAll, enabled: c.project.tables.isNotEmpty),
        cmd('เปลี่ยนชื่อ…', Cmd.rename, enabled: c.selectedTable != null),
        cmd('ลบที่เลือก', Cmd.delete, enabled: hasSel),
        div,
        _item('จัดวางอัตโนมัติ', '', c.project.tables.isEmpty
            ? null
            : () {
                c.autoLayoutTables();
                cv.fit(c.project);
              }),
      ]),
      _MenuButton(label: 'มุมมอง', items: [
        cmd('พอดีหน้าจอ', Cmd.fit),
        cmd('ซูม 100%', Cmd.zoom100),
        div,
        _item('แสดง SQL Preview', '', () => cv.showDock(DockTab.sql)),
        _item('แสดงปัญหาที่ตรวจพบ', '', () => cv.showDock(DockTab.issues)),
        div,
        cmd('ค้นหาตาราง / คอลัมน์', Cmd.find),
        cmd('Command palette', Cmd.palette),
      ]),
      _MenuButton(label: 'ช่วยเหลือ', items: [
        cmd('ดูคีย์ลัดทั้งหมด', Cmd.help),
      ]),
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
            child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Text(shortcut, style: const TextStyle(fontSize: 12, color: C.muted)),
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
          side: const BorderSide(color: C.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 17),
      ),
    ),
  );
}
