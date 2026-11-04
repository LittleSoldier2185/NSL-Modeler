import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/diagram_geometry.dart';
import '../../core/models/column_model.dart';
import '../../core/models/enums.dart';
import '../../core/models/group_model.dart';
import '../../core/models/note_model.dart';
import '../../core/models/table_model.dart';
import '../../state/app_settings.dart';
import '../../state/project_controller.dart';
import '../app_actions.dart';
import '../export/export_image_dialog.dart';
import '../file_actions.dart';
import '../style_actions.dart';
import '../right_panel.dart' show kTableColorNames;
import '../theme.dart';
import 'canvas_controller.dart';

/// รายการหนึ่งของเมนูคลิกขวา
class MenuSpec {
  const MenuSpec(
    this.label,
    this.icon,
    this.onTap, {
    this.shortcut = '',
    this.enabled = true,
    this.danger = false,
    this.checked,
    this.iconColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String shortcut;
  final bool enabled;
  final bool danger;

  /// ไม่ null = รายการแบบติ๊กถูก (แสดงเครื่องหมาย ✓ เมื่อ true)
  final bool? checked;

  /// สีของไอคอน (เช่นตัวอย่างสีของกลุ่ม)
  final Color? iconColor;
}

/// แสดงเมนูที่ตำแหน่งเมาส์ ([entries] ที่เป็น null คือเส้นคั่น) แล้วเรียก action ของรายการที่เลือก
Future<void> showContextMenu(BuildContext context, Offset global, List<MenuSpec?> entries) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final picked = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(Rect.fromLTWH(global.dx, global.dy, 0, 0), Offset.zero & overlay.size),
    items: [
      for (final e in entries)
        if (e == null)
          const PopupMenuDivider(height: 8)
        else
          PopupMenuItem<VoidCallback>(
            value: e.onTap,
            enabled: e.enabled,
            height: 34,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 230),
              child: Row(children: [
                SizedBox(
                  width: 18,
                  child: e.checked == true
                      ? Icon(Icons.check_rounded, size: 16, color: C.primary)
                      : Icon(e.icon, size: 16, color: e.iconColor ?? (e.danger ? C.danger : C.muted)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.label,
                    style: TextStyle(fontSize: 13, color: e.danger ? C.danger : null),
                  ),
                ),
                if (e.shortcut.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Text(e.shortcut, style: TextStyle(fontSize: 11.5, color: C.muted)),
                ],
              ]),
            ),
          ),
    ],
  );
  picked?.call();
}

/// เมนูบนพื้นที่ว่างของ canvas ([world] = ตำแหน่งที่คลิกในพิกัดโปรเจกต์)
List<MenuSpec?> backgroundMenuEntries(BuildContext context, Offset world) {
  final c = context.read<ProjectController>();
  final cv = context.read<CanvasController>();
  final settings = context.read<AppSettings>();
  final a = AppActions(context);
  final at = settings.snapToGrid ? Offset(snapToGrid(world.dx), snapToGrid(world.dy)) : world;
  return [
    MenuSpec(tr('เพิ่มตารางที่นี่'), Icons.table_rows_outlined, () => c.addTable(x: at.dx, y: at.dy), shortcut: 'T'),
    MenuSpec(tr('เพิ่มโน้ตที่นี่'), Icons.sticky_note_2_outlined, () {
      final n = c.addNote(x: at.dx, y: at.dy);
      cv.requestNoteEdit(n.id);
    }, shortcut: 'N'),
    MenuSpec(tr('สร้างตารางแบบฟอร์ม…'), Icons.view_list_outlined, a.createTableFromForm, shortcut: 'Ctrl+Shift+T'),
    MenuSpec(tr('เพิ่มกลุ่มที่นี่'), Icons.dashboard_customize_outlined, () {
      final g = c.addGroup(x: at.dx, y: at.dy);
      cv.requestGroupEdit(g.id);
    }),
    null,
    MenuSpec(tr('วางตาราง'), Icons.content_paste_rounded, a.paste, shortcut: 'Ctrl+V'),
    MenuSpec(tr('เลือกทุกตาราง'), Icons.select_all_rounded, c.selectAllTables,
        shortcut: 'Ctrl+A', enabled: c.project.tables.isNotEmpty),
    null,
    MenuSpec(tr('จัดวางอัตโนมัติ'), Icons.grid_view_rounded, () {
      c.autoLayoutTables();
      cv.fit(c.project);
    }, enabled: c.project.tables.isNotEmpty),
    MenuSpec(tr('พอดีหน้าจอ'), Icons.fit_screen_outlined, () => cv.fit(c.project), shortcut: 'Ctrl+0'),
    MenuSpec(tr('ซูม 100%'), Icons.zoom_in_map_outlined, cv.resetZoom, shortcut: 'Ctrl+1'),
    MenuSpec(tr('จัดแนวตามตาราง (Snap)'), Icons.grid_4x4_rounded, () => settings.setSnapToGrid(!settings.snapToGrid),
        checked: settings.snapToGrid),
    null,
    MenuSpec(tr('Export ภาพ PNG / SVG'), Icons.image_outlined, () => FileActions.exportImage(context, c),
        shortcut: 'Ctrl+Shift+E'),
  ];
}

/// เมนูบนเส้นความสัมพันธ์: เปลี่ยนสีเส้น, กลับเป็นสีเริ่มต้น, ลบ FK
List<MenuSpec?> relationMenuEntries(BuildContext context, String relationId) {
  final c = context.read<ProjectController>();
  final r = c.project.relations.where((r) => r.id == relationId).firstOrNull;
  if (r == null) return const [];
  return [
    MenuSpec(tr('เปลี่ยนสีเส้นนี้…'), Icons.colorize_rounded,
        () => StyleActions.relationColor(context, c, relationId, current: r.color)),
    MenuSpec(tr('ใช้สีเส้นเริ่มต้น'), Icons.format_color_reset_outlined, () => c.setRelationColor(relationId, null),
        enabled: r.color != null),
    MenuSpec(tr('สีเส้นทั้งหมด…'), Icons.palette_outlined, () => StyleActions.lineColor(context, c)),
    null,
    MenuSpec(tr('ลบ FK นี้'), Icons.delete_outline, () => c.removeRelation(relationId), danger: true),
  ];
}

/// เมนูบนตาราง (หรือบนคอลัมน์ถ้าส่ง [column])
/// คลิกขวาที่ตารางที่ยังไม่ได้เลือก = เลือกมันก่อน; ถ้าอยู่ในกลุ่มที่เลือกอยู่ คำสั่งใช้กับทั้งกลุ่ม
/// [at] = ตำแหน่งเมาส์ (ใช้เปิดเมนูย่อยเลือกสีตรงที่เดิม)
List<MenuSpec?> tableMenuEntries(BuildContext context, TableModel t, {ColumnModel? column, required Offset at}) {
  final c = context.read<ProjectController>();
  final cv = context.read<CanvasController>();
  final a = AppActions(context);

  if (column != null) {
    c.selectTable(t.id, columnId: column.id);
    void edit(void Function(ColumnModel x) f) => c.updateColumn(t.id, column.id, f);
    final isInt = column.type == DataType.integer || column.type == DataType.bigint || column.type == DataType.smallint;
    return [
      MenuSpec(tr('เปลี่ยนชื่อคอลัมน์'), Icons.drive_file_rename_outline, a.rename, shortcut: 'F2'),
      null,
      MenuSpec('Primary Key', Icons.key_rounded, () => edit((x) {
            x.isPrimaryKey = !x.isPrimaryKey;
            if (x.isPrimaryKey) x.notNull = true;
          }), checked: column.isPrimaryKey),
      MenuSpec('NOT NULL', Icons.block_outlined, () => edit((x) => x.notNull = !x.notNull),
          checked: column.notNull, enabled: !column.isPrimaryKey),
      MenuSpec('UNIQUE', Icons.fingerprint_rounded, () => edit((x) => x.unique = !x.unique), checked: column.unique),
      MenuSpec('AUTO INCREMENT', Icons.exposure_plus_1_rounded, () => edit((x) => x.autoIncrement = !x.autoIncrement),
          checked: column.autoIncrement, enabled: isInt),
      null,
      MenuSpec(tr('เริ่มเชื่อม FK จากคอลัมน์นี้'), Icons.share_outlined, () {
        cv.setTool(CanvasTool.fk);
        cv.setFkSource(t.id, column.id);
      }),
      MenuSpec(tr('เพิ่มคอลัมน์'), Icons.add_rounded, () => c.addColumn(t.id)),
      null,
      MenuSpec(tr('ลบคอลัมน์นี้'), Icons.delete_outline, () => c.removeColumn(t.id, column.id), shortcut: 'Del', danger: true),
    ];
  }

  if (!c.isTableSelected(t.id)) c.selectTable(t.id);
  final many = c.selectionCount > 1;
  return [
    MenuSpec(tr('เปลี่ยนชื่อ…'), Icons.drive_file_rename_outline, a.rename, shortcut: 'F2', enabled: !many),
    MenuSpec(tr('แก้ไขโครงสร้าง…'), Icons.table_chart_outlined, () => a.editTableStructure(t.id),
        shortcut: 'Ctrl+Shift+M', enabled: !many),
    MenuSpec(tr('เพิ่มคอลัมน์'), Icons.add_rounded, () => c.addColumn(t.id), enabled: !many),
    null,
    MenuSpec(tr('คัดลอกตาราง'), Icons.copy_rounded, a.copy, shortcut: 'Ctrl+C'),
    MenuSpec(tr('ทำสำเนาตาราง'), Icons.file_copy_outlined, a.duplicate, shortcut: 'Ctrl+D'),
    MenuSpec(tr('สีตาราง…'), Icons.palette_outlined, () {
      final tables = c.selectedTableIds;
      showContextMenu(context, at, [
        MenuSpec(tr('ไม่มีสี (ค่าเริ่มต้น)'), Icons.block_rounded, () => c.setTablesColor(tables, null),
            checked: t.colorIndex == null ? true : null),
        for (var i = 0; i < kTableColors.length; i++)
          MenuSpec(tr(kTableColorNames[i]), Icons.circle, () => c.setTablesColor(tables, i),
              iconColor: Color(kTableColors[i]), checked: t.colorIndex == i && t.customColor == null ? true : null),
        MenuSpec(tr('กำหนดเอง…'), Icons.colorize_rounded, () => StyleActions.tableColor(context, c, tables, current: t.colorValue),
            checked: t.customColor != null ? true : null),
      ]);
    }),
    MenuSpec(tr('ฟอนต์ตาราง…'), Icons.font_download_outlined,
        () => StyleActions.tableFont(context, c, c.selectedTableIds, current: t.fontFamily)),
    MenuSpec(tr('จัดกลุ่มตารางที่เลือก'), Icons.dashboard_customize_outlined, a.groupSelected, shortcut: 'Ctrl+G'),
    MenuSpec(tr('Export ภาพเฉพาะตารางที่เลือก…'), Icons.crop_outlined,
        () => FileActions.exportImage(context, c, initialArea: ImageArea.selection)),
    null,
    MenuSpec(many ? tr('ลบ {0} ตาราง', [c.selectionCount]) : tr('ลบตาราง'), Icons.delete_outline, a.deleteSelection,
        shortcut: 'Del', danger: true),
  ];
}

/// เมนูบนกลุ่ม: เปลี่ยนชื่อ, เปลี่ยนสี, เลือกตารางในกลุ่ม, ลบกลุ่ม (ไม่ลบตาราง)
List<MenuSpec?> groupMenuEntries(BuildContext context, GroupModel g) {
  final c = context.read<ProjectController>();
  final cv = context.read<CanvasController>();
  const names = ['เขียวน้ำทะเล', 'ม่วง', 'น้ำเงิน', 'ส้ม', 'ชมพู', 'เขียว'];
  return [
    MenuSpec(tr('เปลี่ยนชื่อกลุ่ม'), Icons.drive_file_rename_outline, () => cv.requestGroupEdit(g.id)),
    MenuSpec(tr('เลือกตารางทั้งหมดในกลุ่ม'), Icons.select_all_rounded, () => c.selectGroupMembers(g.id)),
    MenuSpec(tr('Export ภาพเฉพาะกลุ่มนี้…'), Icons.crop_outlined, () {
      c.selectGroup(g.id);
      FileActions.exportImage(context, c, initialArea: ImageArea.selection);
    }),
    null,
    for (var i = 0; i < kGroupColors.length; i++)
      MenuSpec(tr(names[i]), Icons.circle, () => c.setGroupColor(g.id, i),
          iconColor: Color(kGroupColors[i]), checked: g.colorIndex == i && g.customColor == null ? true : null),
    MenuSpec(tr('กำหนดสีเอง…'), Icons.colorize_rounded, () => StyleActions.groupColor(context, c, g.id, current: g.colorValue),
        checked: g.customColor != null ? true : null),
    null,
    MenuSpec(tr('ลบกลุ่ม (ไม่ลบตาราง)'), Icons.delete_outline, () => c.removeGroup(g.id), danger: true),
  ];
}

/// เมนูบนโน้ต
List<MenuSpec?> noteMenuEntries(BuildContext context, NoteModel n) {
  final c = context.read<ProjectController>();
  final cv = context.read<CanvasController>();
  return [
    MenuSpec(tr('แก้ไขข้อความ'), Icons.edit_outlined, () => cv.requestNoteEdit(n.id)),
    MenuSpec(tr('ทำสำเนาโน้ต'), Icons.file_copy_outlined, () {
      final copy = c.addNote(x: n.x + 30, y: n.y + 30, text: n.text);
      cv.pendingNoteEditId = null;
      c.updateNote(copy.id, (x) => x.width = n.width);
    }),
    null,
    MenuSpec(tr('ลบโน้ต'), Icons.delete_outline, () => c.removeNote(n.id), danger: true),
  ];
}
