import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

import '../core/l10n/l10n.dart';

/// คำสั่งที่ผูกกับคีย์ลัดได้ — การทำงานจริงอยู่ที่ [AppActions]
enum Cmd {
  newProject,
  open,
  save,
  saveAs,
  exportSql,
  exportImage,
  exportText,
  importSql,
  compare,
  connectDb,
  dfdEntity,
  dfdProcess,
  dfdStore,
  fcTerminator,
  fcIo,
  fcSubroutine,
  fcConnector,
  wfButton,
  wfContainer,
  wfImage,
  wfInput,
  undo,
  redo,
  copy,
  paste,
  duplicate,
  selectAll,
  delete,
  rename,
  toolSelect,
  toolTable,
  toolFk,
  toolNote,
  createTableForm,
  editTableStructure,
  groupSelected,
  escape,
  fit,
  zoom100,
  nudgeLeft,
  nudgeRight,
  nudgeUp,
  nudgeDown,
  nudgeLeftBig,
  nudgeRightBig,
  nudgeUpBig,
  nudgeDownBig,
  find,
  palette,
  dialectMysql,
  dialectPostgres,
  dialectSqlite,
  dialectMssql,
  help,
}

/// คีย์ลัดหนึ่งรายการ — เป็นแหล่งข้อมูลเดียวของทั้งตัวดักปุ่ม หน้า F1 และเมนู
/// [cmd] เป็น null = รายการอธิบายอย่างเดียว (เช่น Space+ลาก ซึ่งจัดการที่ท่าทางของเมาส์)
class ShortcutDef {
  const ShortcutDef(this.group, this.label, this.keys, {this.cmd, this.activator, this.character, this.global = false});

  final String group;
  final String label;

  /// ข้อความที่แสดง เช่น "Ctrl+Shift+S"
  final String keys;
  final Cmd? cmd;
  final SingleActivator? activator;

  /// จับตามตัวอักษรที่พิมพ์ได้ (เช่น "?" ที่ตำแหน่งต่างกันตามผังแป้นพิมพ์)
  final String? character;

  /// true = ทำงานแม้กำลังพิมพ์ในช่องข้อความ; false = ปล่อยให้ช่องข้อความจัดการก่อน
  /// (Ctrl+C/V/A/Z, ตัวอักษรเดี่ยว, ลูกศร, Delete ฯลฯ)
  final bool global;
}

const _ctrl = true;

const List<ShortcutDef> kShortcuts = [
  // ---- ไฟล์ ----
  ShortcutDef('ไฟล์', 'โปรเจกต์ใหม่', 'Ctrl+N', cmd: Cmd.newProject, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyN, control: _ctrl, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'เปิดไฟล์โปรเจกต์', 'Ctrl+O', cmd: Cmd.open, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyO, control: _ctrl, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'บันทึก', 'Ctrl+S', cmd: Cmd.save, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyS, control: _ctrl, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'บันทึกเป็น…', 'Ctrl+Shift+S', cmd: Cmd.saveAs, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyS, control: _ctrl, shift: true, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'Export .sql', 'Ctrl+E', cmd: Cmd.exportSql, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyE, control: _ctrl, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'Export ภาพ PNG / SVG', 'Ctrl+Shift+E', cmd: Cmd.exportImage, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyE, control: _ctrl, shift: true, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'Export เอกสาร / DBML / ข้อมูลตัวอย่าง', 'Ctrl+Shift+D', cmd: Cmd.exportText, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyD, control: _ctrl, shift: true, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'นำเข้าจากไฟล์ .sql', 'Ctrl+I', cmd: Cmd.importSql, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyI, control: _ctrl, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'เชื่อมต่อฐานข้อมูล MySQL / SQLite (อ่านอย่างเดียว)', 'Ctrl+Shift+O', cmd: Cmd.connectDb, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyO, control: _ctrl, shift: true, includeRepeats: false)),
  ShortcutDef('ไฟล์', 'เปรียบเทียบกับไฟล์เก่า (Migration)', 'Ctrl+M', cmd: Cmd.compare, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyM, control: _ctrl, includeRepeats: false)),

  // ---- แก้ไข ----
  ShortcutDef('แก้ไข', 'ย้อนกลับ', 'Ctrl+Z', cmd: Cmd.undo,
      activator: SingleActivator(LogicalKeyboardKey.keyZ, control: _ctrl)),
  // ทำซ้ำ: ตามแบบ Adobe คือ Ctrl+Shift+Z (เมนู/ทูลทิปแสดงอันนี้เป็นหลัก — ต้องอยู่ก่อนรายการทางเลือก)
  ShortcutDef('แก้ไข', 'ทำซ้ำ', 'Ctrl+Shift+Z', cmd: Cmd.redo,
      activator: SingleActivator(LogicalKeyboardKey.keyZ, control: _ctrl, shift: true)),
  // คีย์ทางเลือกของ ทำซ้ำ
  ShortcutDef('แก้ไข', 'ทำซ้ำ (ทางเลือก)', 'Ctrl+Y', cmd: Cmd.redo,
      activator: SingleActivator(LogicalKeyboardKey.keyY, control: _ctrl)),
  ShortcutDef('แก้ไข', 'ทำซ้ำ (ทางเลือก)', 'Alt+Z', cmd: Cmd.redo,
      activator: SingleActivator(LogicalKeyboardKey.keyZ, alt: true)),
  ShortcutDef('แก้ไข', 'คัดลอกตาราง', 'Ctrl+C', cmd: Cmd.copy,
      activator: SingleActivator(LogicalKeyboardKey.keyC, control: _ctrl, includeRepeats: false)),
  ShortcutDef('แก้ไข', 'วางตาราง', 'Ctrl+V', cmd: Cmd.paste,
      activator: SingleActivator(LogicalKeyboardKey.keyV, control: _ctrl, includeRepeats: false)),
  ShortcutDef('แก้ไข', 'ทำสำเนาตาราง', 'Ctrl+D', cmd: Cmd.duplicate,
      activator: SingleActivator(LogicalKeyboardKey.keyD, control: _ctrl, includeRepeats: false)),
  ShortcutDef('แก้ไข', 'เลือกทุกตาราง', 'Ctrl+A', cmd: Cmd.selectAll,
      activator: SingleActivator(LogicalKeyboardKey.keyA, control: _ctrl, includeRepeats: false)),
  ShortcutDef('แก้ไข', 'ลบตาราง / คอลัมน์ที่เลือก', 'Delete', cmd: Cmd.delete,
      activator: SingleActivator(LogicalKeyboardKey.delete, includeRepeats: false)),
  ShortcutDef('แก้ไข', 'เปลี่ยนชื่อตาราง / คอลัมน์ที่เลือก', 'F2', cmd: Cmd.rename,
      activator: SingleActivator(LogicalKeyboardKey.f2, includeRepeats: false)),

  // ---- Canvas ----
  ShortcutDef('Canvas', 'โหมดเลือก', 'S', cmd: Cmd.toolSelect,
      activator: SingleActivator(LogicalKeyboardKey.keyS, includeRepeats: false)),
  ShortcutDef('Canvas', 'เพิ่มตารางใหม่', 'T', cmd: Cmd.toolTable,
      activator: SingleActivator(LogicalKeyboardKey.keyT, includeRepeats: false)),
  ShortcutDef('Canvas', 'โหมดเชื่อม FK', 'F', cmd: Cmd.toolFk,
      activator: SingleActivator(LogicalKeyboardKey.keyF, includeRepeats: false)),
  ShortcutDef('Canvas', 'สร้างตารางแบบฟอร์ม (เหมือน phpMyAdmin)', 'Ctrl+Shift+T', cmd: Cmd.createTableForm, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyT, control: _ctrl, shift: true, includeRepeats: false)),
  ShortcutDef('Canvas', 'แก้โครงสร้างตารางที่เลือก (ฟอร์ม)', 'Ctrl+Shift+M', cmd: Cmd.editTableStructure, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyM, control: _ctrl, shift: true, includeRepeats: false)),
  ShortcutDef('Canvas', 'จัดกลุ่มตารางที่เลือก', 'Ctrl+G', cmd: Cmd.groupSelected,
      activator: SingleActivator(LogicalKeyboardKey.keyG, control: _ctrl, includeRepeats: false)),
  ShortcutDef('Canvas', 'เพิ่มโน้ต', 'N', cmd: Cmd.toolNote,
      activator: SingleActivator(LogicalKeyboardKey.keyN, includeRepeats: false)),
  ShortcutDef('Canvas', 'กลับโหมดเลือก / ยกเลิก / ล้างการเลือก', 'Esc', cmd: Cmd.escape,
      activator: SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false), global: true),
  // ---- แผนภาพ DFD (ใช้เมื่อเปิดแท็บ DFD) ----
  ShortcutDef('DFD', 'วางผู้ใช้ภายนอก (External entity)', 'E', cmd: Cmd.dfdEntity,
      activator: SingleActivator(LogicalKeyboardKey.keyE, includeRepeats: false)),
  ShortcutDef('DFD', 'วางกระบวนการ (Process)', 'P', cmd: Cmd.dfdProcess,
      activator: SingleActivator(LogicalKeyboardKey.keyP, includeRepeats: false)),
  ShortcutDef('DFD', 'วางที่เก็บข้อมูล (Data store)', 'D', cmd: Cmd.dfdStore,
      activator: SingleActivator(LogicalKeyboardKey.keyD, includeRepeats: false)),
  // ---- Flowchart (ใช้เมื่อเปิดแท็บ Flowchart ; P/D/F/N/S ใช้คีย์เดียวกับ DFD/ER แต่ทำงานตามแท็บ) ----
  ShortcutDef('Flowchart', 'วางจุดเริ่มต้น / สิ้นสุด (Start / End)', 'O', cmd: Cmd.fcTerminator,
      activator: SingleActivator(LogicalKeyboardKey.keyO, includeRepeats: false)),
  ShortcutDef('Flowchart', 'วางกระบวนการ (Process)', 'P'),
  ShortcutDef('Flowchart', 'วางการตัดสินใจ (Decision)', 'D'),
  ShortcutDef('Flowchart', 'วางรับ/แสดงข้อมูล (Input / Output)', 'I', cmd: Cmd.fcIo,
      activator: SingleActivator(LogicalKeyboardKey.keyI, includeRepeats: false)),
  ShortcutDef('Flowchart', 'วางโปรแกรมย่อย (Subroutine)', 'U', cmd: Cmd.fcSubroutine,
      activator: SingleActivator(LogicalKeyboardKey.keyU, includeRepeats: false)),
  ShortcutDef('Flowchart', 'วางจุดต่อ (Connector)', 'C', cmd: Cmd.fcConnector,
      activator: SingleActivator(LogicalKeyboardKey.keyC, includeRepeats: false)),
  ShortcutDef('Flowchart', 'วางโน้ต', 'N'),
  ShortcutDef('Flowchart', 'ลากเส้นเชื่อม (คลิกต้นทาง แล้วคลิกปลายทาง)', 'F'),
  ShortcutDef('Flowchart', 'พิมพ์ข้อความในสัญลักษณ์ / ป้ายเส้น', 'F2 หรือ ดับเบิลคลิก'),
  // ---- Wireframe (ใช้เมื่อเปิดแท็บ Wireframe ; T/S ใช้คีย์เดียวกับ ER แต่ทำงานตามแท็บ) ----
  ShortcutDef('Wireframe', 'วางป้ายข้อความ (Label)', 'T'),
  ShortcutDef('Wireframe', 'วางปุ่ม (Button)', 'B', cmd: Cmd.wfButton,
      activator: SingleActivator(LogicalKeyboardKey.keyB, includeRepeats: false)),
  ShortcutDef('Wireframe', 'วางกล่อง / ภาชนะ (Container)', 'R', cmd: Cmd.wfContainer,
      activator: SingleActivator(LogicalKeyboardKey.keyR, includeRepeats: false)),
  ShortcutDef('Wireframe', 'วางรูปภาพ (Image)', 'G', cmd: Cmd.wfImage,
      activator: SingleActivator(LogicalKeyboardKey.keyG, includeRepeats: false)),
  ShortcutDef('Wireframe', 'วางช่องกรอกข้อความ (Input)', 'L', cmd: Cmd.wfInput,
      activator: SingleActivator(LogicalKeyboardKey.keyL, includeRepeats: false)),
  ShortcutDef('Wireframe', 'พิมพ์ข้อความในชิ้นส่วน (ตาราง = หัวคอลัมน์)', 'F2 หรือ ดับเบิลคลิก'),
  ShortcutDef('Wireframe', 'ย้ายภาชนะ = ชิ้นที่อยู่ข้างในย้ายตาม', 'ลาก'),
  // ---- Screen Flow (ใช้เมื่อเปิดแท็บ Screen Flow ; ใช้คีย์เดียวกับ DFD/Flowchart แต่ทำงานตามแท็บ) ----
  ShortcutDef('Screen Flow', 'วางจุดเริ่ม / จบ', 'O'),
  ShortcutDef('Screen Flow', 'วางหน้าจอ (Screen)', 'P'),
  ShortcutDef('Screen Flow', 'วางหน้าภายนอก / ป๊อปอัป', 'E'),
  ShortcutDef('Screen Flow', 'ลากเส้นการเปลี่ยนหน้า (คลิกต้นทาง แล้วคลิกปลายทาง)', 'F'),
  ShortcutDef('Screen Flow', 'เปิด Wireframe ของหน้าจอ', 'ดับเบิลคลิก'),
  ShortcutDef('Canvas', 'พอดีหน้าจอ', 'Ctrl+0', cmd: Cmd.fit, global: true,
      activator: SingleActivator(LogicalKeyboardKey.digit0, control: _ctrl, includeRepeats: false)),
  ShortcutDef('Canvas', 'ซูม 100%', 'Ctrl+1', cmd: Cmd.zoom100, global: true,
      activator: SingleActivator(LogicalKeyboardKey.digit1, control: _ctrl, includeRepeats: false)),
  ShortcutDef('Canvas', 'ขยับตารางที่เลือก (10 px)', '← ↑ → ↓', cmd: Cmd.nudgeLeft,
      activator: SingleActivator(LogicalKeyboardKey.arrowLeft)),
  ShortcutDef('Canvas', '', '', cmd: Cmd.nudgeRight, activator: SingleActivator(LogicalKeyboardKey.arrowRight)),
  ShortcutDef('Canvas', '', '', cmd: Cmd.nudgeUp, activator: SingleActivator(LogicalKeyboardKey.arrowUp)),
  ShortcutDef('Canvas', '', '', cmd: Cmd.nudgeDown, activator: SingleActivator(LogicalKeyboardKey.arrowDown)),
  ShortcutDef('Canvas', 'ขยับตารางที่เลือก (ก้าวใหญ่ 50 px)', 'Shift + ลูกศร', cmd: Cmd.nudgeLeftBig,
      activator: SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true)),
  ShortcutDef('Canvas', '', '', cmd: Cmd.nudgeRightBig,
      activator: SingleActivator(LogicalKeyboardKey.arrowRight, shift: true)),
  ShortcutDef('Canvas', '', '', cmd: Cmd.nudgeUpBig, activator: SingleActivator(LogicalKeyboardKey.arrowUp, shift: true)),
  ShortcutDef('Canvas', '', '', cmd: Cmd.nudgeDownBig,
      activator: SingleActivator(LogicalKeyboardKey.arrowDown, shift: true)),
  ShortcutDef('Canvas', 'เลือกหลายตาราง', 'Ctrl / Shift + คลิก'),
  ShortcutDef('Canvas', 'ซูม', 'Ctrl + ล้อเมาส์'),
  ShortcutDef('Canvas', 'เลื่อนมุมมอง (pan)', 'Space + ลาก'),

  // ---- ทั่วไป ----
  ShortcutDef('ทั่วไป', 'ค้นหาตาราง / คอลัมน์', 'Ctrl+F', cmd: Cmd.find, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyF, control: _ctrl, includeRepeats: false)),
  ShortcutDef('ทั่วไป', 'Command palette', 'Ctrl+K', cmd: Cmd.palette, global: true,
      activator: SingleActivator(LogicalKeyboardKey.keyK, control: _ctrl, includeRepeats: false)),
  ShortcutDef('ทั่วไป', 'สลับ dialect: MySQL / PostgreSQL / SQLite / SQL Server', 'Alt+1 … Alt+4',
      cmd: Cmd.dialectMysql, global: true,
      activator: SingleActivator(LogicalKeyboardKey.digit1, alt: true, includeRepeats: false)),
  ShortcutDef('ทั่วไป', '', '', cmd: Cmd.dialectPostgres, global: true,
      activator: SingleActivator(LogicalKeyboardKey.digit2, alt: true, includeRepeats: false)),
  ShortcutDef('ทั่วไป', '', '', cmd: Cmd.dialectSqlite, global: true,
      activator: SingleActivator(LogicalKeyboardKey.digit3, alt: true, includeRepeats: false)),
  ShortcutDef('ทั่วไป', '', '', cmd: Cmd.dialectMssql, global: true,
      activator: SingleActivator(LogicalKeyboardKey.digit4, alt: true, includeRepeats: false)),
  ShortcutDef('ทั่วไป', 'ดูคีย์ลัดทั้งหมด', 'F1 หรือ ?', cmd: Cmd.help, global: true,
      activator: SingleActivator(LogicalKeyboardKey.f1, includeRepeats: false)),
  ShortcutDef('ทั่วไป', '', '', cmd: Cmd.help, character: '?'),
];

/// รายการที่แสดงในหน้า F1: ตัดแถวต่อเนื่องที่ไม่มีข้อความ (ปุ่มลูกศรอีก 3 ทิศ ฯลฯ ซึ่งรวมอยู่ในแถวแรกแล้ว)
List<ShortcutDef> get visibleShortcuts => [for (final s in kShortcuts) if (s.label.isNotEmpty) s];

/// หาคีย์ลัดที่ตรงกับเหตุการณ์แป้นพิมพ์ — null ถ้าไม่มี
ShortcutDef? matchShortcut(KeyEvent e, HardwareKeyboard keyboard) {
  if (e is! KeyDownEvent && e is! KeyRepeatEvent) return null;
  for (final s in kShortcuts) {
    final a = s.activator;
    if (a != null && a.accepts(e, keyboard)) return s;
  }
  // ตัวอักษรที่ผังแป้นพิมพ์ต่างกัน เช่น "?" (ไม่ต้องมี Ctrl/Alt)
  final ch = e.character;
  if (ch != null &&
      !keyboard.isControlPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isMetaPressed) {
    for (final s in kShortcuts) {
      if (s.character != null && s.character == ch) return s;
    }
  }
  return null;
}

/// คีย์ลัดของคำสั่ง (สำหรับแสดงข้างเมนู/ปุ่ม) — "" ถ้าไม่มี
String shortcutText(Cmd cmd) {
  for (final s in kShortcuts) {
    if (s.cmd == cmd && s.keys.isNotEmpty) return tr(s.keys);
  }
  return '';
}
