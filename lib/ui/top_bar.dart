import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../state/app_settings.dart';
import '../state/project_controller.dart';
import '../state/workspace_controller.dart';
import 'app_actions.dart';
import '../state/dfd_controller.dart';
import 'canvas/canvas_controller.dart';
import 'file_actions.dart';
import 'line_settings_dialog.dart';
import 'palette/command_palette.dart';
import 'search_launcher.dart';
import 'shortcuts.dart';
import 'whats_new_dialog.dart';
import 'workspace_issues_dialog.dart';
import 'theme.dart';
import 'window_chrome.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final w = context.watch<WorkspaceController>();

    // ใช้แถบของแอปเป็นแถบชื่อหน้าต่าง: ลากพื้นที่ว่างเพื่อย้ายหน้าต่าง ปุ่มควบคุมชิดมุมขวา
    final controls = WindowChrome.customControls;
    final isEr = w.activeDocument.type == DocType.er;
    return Container(
      height: 52,
      padding: EdgeInsets.only(
        left: 16 + WindowChrome.leadingInset,
        right: controls ? 0 : 16,
      ),
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            // โลโก้แอป (ไฟล์เดียวกับไอคอนของโปรแกรม)
            Image.asset(
              'assets/icon/app_icon.png',
              key: const ValueKey('app-logo'),
              width: 34,
              height: 34,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(width: 10),
            const Text(
              'NSL Dev',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 22, color: C.border),
            const SizedBox(width: 8),
            ..._menus(context, c, w),
            const SizedBox(width: 8),
            // กลุ่มปุ่มขวา: ชิดขวาติดปุ่มควบคุมหน้าต่าง ได้ขนาดตามจริง (ย่อสัดส่วนลงถ้าที่ไม่พอ)
            // ที่ว่างทางซ้ายของกลุ่มปุ่ม = ช่องค้นหา + ที่จับลากย้ายหน้าต่าง
            Expanded(
              flex: 1000,
              child: _RightRegion(
                groupBuilder: (showSearchIcon) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSearchIcon) ...[
                      _IconBtn(
                        Icons.search_rounded,
                        tr('ค้นหา / สั่งงาน (Ctrl+K)'),
                        () => showCommandPalette(context),
                      ),
                      const SizedBox(width: 4),
                    ],
                    _IconBtn(
                      Icons.undo,
                      tr('ย้อนกลับ (Ctrl+Z)'),
                      w.canUndo ? w.undo : null,
                    ),
                    const SizedBox(width: 4),
                    _IconBtn(
                      Icons.redo,
                      tr('ทำซ้ำ (Ctrl+Shift+Z)'),
                      w.canRedo ? w.redo : null,
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
                    // ปุ่มที่เกี่ยวกับ ER/SQL ซ่อนบนแท็บ DFD
                    if (isEr) ...[
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
                  ],
                ),
              ),
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
  static List<Widget> _menus(BuildContext context, ProjectController c, WorkspaceController w) {
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
          cmd(tr('เชื่อมต่อฐานข้อมูล…'), Cmd.connectDb),
          div,
          cmd(tr('Export ภาพ (PNG / SVG)…'), Cmd.exportImage),
          cmd(tr('Export เอกสาร / DBML / ข้อมูลตัวอย่าง…'), Cmd.exportText),
          cmd('Export .sql…', Cmd.exportSql),
        ],
      ),
      _MenuButton(
        label: tr('แก้ไข'),
        items: [
          cmd(tr('ย้อนกลับ'), Cmd.undo, enabled: w.canUndo),
          cmd(tr('ทำซ้ำ'), Cmd.redo, enabled: w.canRedo),
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
            w.activeDocument.type == DocType.dfd
                ? (w.dfdOf(w.activeId).nodes.length < 2
                    ? null
                    : () {
                        final d = context.read<DfdController>();
                        if (d.autoLayout()) d.fit(d.viewport);
                      })
                : c.project.tables.isEmpty
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
          _item(tr('หน้า Project Home'), '', () => context.read<WorkspaceController>().showHome()),
          _item(tr('ปัญหาทั้งโปรเจกต์…'), '', () => showWorkspaceIssues(context)),
          _item(
            '${context.read<AppSettings>().showExplorer ? '✓ ' : '    '}${tr('แสดงตัวสำรวจโปรเจกต์')}',
            '',
            () {
              final s = context.read<AppSettings>();
              s.setShowExplorer(!s.showExplorer);
            },
          ),
          div,
          _item(
            tr('ขนาดกระดาน…'),
            '',
            () => FileActions.changeBoardSize(context, c),
          ),
          _item(
            '${context.read<AppSettings>().snapToGrid ? '✓ ' : '    '}${tr('จัดแนวตามตาราง (Snap)')}',
            '',
            () {
              final s = context.read<AppSettings>();
              s.setSnapToGrid(!s.snapToGrid);
            },
          ),
          _item(
            tr('เส้นความสัมพันธ์ (FK)…'),
            '',
            () => showLineSettingsDialog(context, c),
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
          _item(tr('มีอะไรใหม่ (Patch note)…'), '', () => showWhatsNew(context)),
          _item(tr('เกี่ยวกับ NSL Dev…'), '', () => showAbout(context)),
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

/// พื้นที่ขวาของแถบบน: [ที่ว่าง: ที่จับลากหน้าต่าง + ช่องค้นหา] [กลุ่มปุ่ม]
/// กลุ่มปุ่มได้ขนาดตามจริงก่อน ที่ว่างที่เหลือเป็นของช่องค้นหา (จึงไม่ทับกันไม่ว่าฟอนต์/ภาษาจะกว้างแค่ไหน)
/// ที่ว่างน้อยเกินไป = ซ่อนช่องค้นหา แล้วแสดงเป็นปุ่มแว่นขยายในกลุ่มปุ่มแทน
class _RightRegion extends StatefulWidget {
  const _RightRegion({required this.groupBuilder});

  /// สร้างกลุ่มปุ่ม ([showSearchIcon] = ใส่ปุ่มแว่นขยายด้วย)
  final Widget Function(bool showSearchIcon) groupBuilder;

  @override
  State<_RightRegion> createState() => _RightRegionState();
}

class _RightRegionState extends State<_RightRegion> {
  /// ที่ว่างอย่างน้อยเท่านี้จึงโชว์ช่องค้นหา (ตอนปุ่มแว่นขยายอยู่ในกลุ่มปุ่ม ที่ว่างจะแคบลงอีก จึงไม่สั่นไปมา)
  static const _minFieldArea = 220.0;
  bool _showIcon = false;

  /// ตำแหน่งซ้ายของพื้นที่ว่างบนหน้าจอ (วัดหลังวาง layout แล้ว) ใช้คำนวณให้ช่องค้นหาอยู่กลางแถบทั้งแถบ
  final _areaKey = GlobalKey();
  double? _areaLeft;

  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.attached || !box.hasSize) return;
      final left = box.localToGlobal(Offset.zero).dx;
      if (_areaLeft == null || (left - _areaLeft!).abs() > 0.5) {
        setState(() => _areaLeft = left);
      }
    });
  }

  void _report(bool fieldShown) {
    if (_showIcon == !fieldShown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _showIcon = !fieldShown);
    });
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    return _buildRegion(context);
  }

  Widget _buildRegion(BuildContext context) => LayoutBuilder(
    builder: (context, region) => Row(
      children: [
        Expanded(
          child: Stack(
            key: _areaKey,
            children: [
              const Positioned.fill(
                child: WindowDragArea(child: SizedBox.expand()),
              ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, area) {
                    final show = area.maxWidth >= _minFieldArea;
                    _report(show);
                    if (!show) return const SizedBox.shrink();
                    // อยู่กึ่งกลางของแถบชื่อหน้าต่างทั้งแถบ (ไม่ใช่กึ่งกลางของที่ว่างที่เหลือ) ถ้าที่ว่างไม่พอจะชิดเข้ามาในที่ว่าง
                    final w = math.min(420.0, area.maxWidth - 24);
                    final left = _areaLeft;
                    final screenW = MediaQuery.sizeOf(context).width;
                    var x = left == null
                        ? (area.maxWidth - w) / 2
                        : screenW / 2 - left - w / 2;
                    x = x.clamp(12.0, math.max(12.0, area.maxWidth - w - 12));
                    return Stack(
                      children: [
                        Positioned(
                          left: x,
                          top: 0,
                          bottom: 0,
                          width: w,
                          child: const Center(child: SearchLauncher()),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: region.maxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: widget.groupBuilder(_showIcon),
          ),
        ),
      ],
    ),
  );
}
